//
//  ChatService.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import Foundation

final class ChatService: NSObject, @unchecked Sendable {
    let configurationProvider: ChatServiceConfiguring
    private let endpointResolver: ChatEndpointResolving
    private let requestPayloadProjector: ChatRequestPayloadProjecting
    private let requestBodyBuilder: ChatRequestBodyBuilding
    let requestFactory: ChatStreamingRequestBuilding
    private let responseTextExtractor: ChatResponseTextExtracting
    let bufferedResponseParser: ChatBufferedResponseParsing
    let streamPayloadExtractor: ChatStreamPayloadExtracting
    let openAICompatibleStreamReducer: OpenAICompatibleStreamEventReducer
    let anthropicStreamReducer = AnthropicStreamEventReducer()
    let lmStudioStreamReducer: LMStudioStreamEventReducer

    let stateQueue: DispatchQueue
    private let sessionQueue: OperationQueue
    private let delegateProxy: ChatServiceDelegateProxy

    var session: URLSession?
    var dataTask: URLSessionDataTask?

    /// Callbacks are explicitly constrained to run on the main actor.
    @MainActor var onDelta: (@MainActor (String) -> Void)?
    @MainActor var onError: (@MainActor (Error) -> Void)?
    @MainActor var onResponseMetadata: (@MainActor (ChatResponseMetadata) -> Void)?
    @MainActor var onStreamFinished: (@MainActor () -> Void)?

    // Reasoning / body state tracking
    var isLegacyThinkStream = false
    var sawAnyAssistantToken = false
    var sawAnyPrimaryAssistantToken = false
    var newFormatActive = false
    var sentThinkOpen = false
    var sentThinkClose = false
    var streamFinishedEmitted = false
    var lastProcessedSSESequenceNumber: Int?
    var reasoningDeltaItemIDs = Set<String>()
    var outputTextDeltaItemIDs = Set<String>()

    var sseParser = ChatSSEStreamParser()
    let thinkCloseLine = "\n</think>\n"
    let decoder = JSONDecoder()

    // Watchdog configuration to cover long-running sessions (up to ~1 hour).
    let connectTimeout: TimeInterval = 8             // Fail fast if we can't establish a connection.
    let firstTokenTimeout: TimeInterval = 3600        // Wait up to one hour for the first token.
    let silentGapTimeout: TimeInterval  = 3600        // Allow up to one hour of silence between tokens.
    var streamStartAt: Date?
    var didEstablishConnection: Bool = false
    var lastDeltaAt: Date?
    var watchdog: DispatchSourceTimer?
    var connectionWatchdog: DispatchSourceTimer?

    // Cancel flag to ignore any residual deltas after stopping.
    var isCancelled: Bool = false

    // HTTP status/error accumulation for non-2xx responses.
    var httpStatusCode: Int?
    let errorBodyCaptureLimit = 32 * 1024
    var errorResponseData = Data()
    let successBodyCaptureLimit = 2 * 1024 * 1024
    var successResponseData = Data()
    var anthropicStreamState = AnthropicStreamEventState()
    var pendingLMStudioStreamErrorMessage: String?
    var activeEndpointCandidate: ChatAPIEndpointCandidate?
    var pendingResponseMetadata = ChatResponseMetadata.empty
    var backgroundExecutionCoordinator: ChatServiceBackgroundExecutionCoordinator?

    init(
        configurationProvider: ChatServiceConfiguring,
        endpointResolver: ChatEndpointResolving = DefaultChatEndpointResolver(),
        requestPayloadProjector: ChatRequestPayloadProjecting = ChatRequestPayloadProjector(),
        requestBodyBuilder: ChatRequestBodyBuilding = ChatRequestBodyBuilder(),
        requestFactory: ChatStreamingRequestBuilding = ChatStreamingRequestFactory(),
        responseMetadataExtractor: ChatResponseMetadataExtracting = ChatResponseMetadataExtractor(),
        responseTextExtractor: ChatResponseTextExtracting = ChatResponseTextExtractor(),
        bufferedResponseParser: ChatBufferedResponseParsing? = nil,
        streamPayloadExtractor: ChatStreamPayloadExtracting? = nil
    ) {
        self.configurationProvider = configurationProvider
        self.endpointResolver = endpointResolver
        self.requestPayloadProjector = requestPayloadProjector
        self.requestBodyBuilder = requestBodyBuilder
        self.requestFactory = requestFactory
        self.responseTextExtractor = responseTextExtractor
        self.bufferedResponseParser = bufferedResponseParser ?? ChatBufferedResponseParser(
            metadataExtractor: responseMetadataExtractor,
            textExtractor: responseTextExtractor
        )
        let resolvedStreamPayloadExtractor = streamPayloadExtractor ?? ChatStreamPayloadExtractor(textExtractor: responseTextExtractor)
        self.streamPayloadExtractor = resolvedStreamPayloadExtractor
        self.openAICompatibleStreamReducer = OpenAICompatibleStreamEventReducer(
            metadataExtractor: responseMetadataExtractor,
            textExtractor: responseTextExtractor,
            payloadExtractor: resolvedStreamPayloadExtractor
        )
        self.lmStudioStreamReducer = LMStudioStreamEventReducer(metadataExtractor: responseMetadataExtractor)
        self.stateQueue = DispatchQueue(label: "VoiceChat.ChatService.state", qos: .userInitiated)
        let queue = OperationQueue()
        queue.name = "VoiceChat.ChatService.session"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        queue.underlyingQueue = self.stateQueue
        self.sessionQueue = queue
        self.delegateProxy = ChatServiceDelegateProxy()
        super.init()
        self.delegateProxy.owner = self
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest  = 3900   // Adds a few minutes of headroom beyond one hour.
        configuration.timeoutIntervalForResource = 3900
        configuration.httpMaximumConnectionsPerHost = 1
        self.session = URLSession(configuration: configuration, delegate: delegateProxy, delegateQueue: sessionQueue)
        self.backgroundExecutionCoordinator = ChatServiceBackgroundExecutionCoordinator { [weak self] message in
            self?.handleBackgroundExecutionInterruption(message)
        }
    }

    deinit {
        session?.invalidateAndCancel()
        stopConnectionWatchdog()
        stopWatchdog()
        backgroundExecutionCoordinator?.endSynchronouslyIfNeeded()
    }

    /// Called on the main actor to avoid crossing actor boundaries with SwiftData models.
    @MainActor
    func fetchStreamedData(messages: [ChatMessage], developerPrompt: String?, includeImagesInUserContent: Bool) {
        let base = configurationProvider.apiBaseURL
        let model = configurationProvider.modelIdentifier
        let endpointCandidates = endpointResolver.streamingCandidates(
            for: base,
            providerHint: configurationProvider.providerHint,
            styleHint: configurationProvider.requestStyleHint
        )
        guard let firstEndpoint = endpointCandidates.first else {
            onError?(ChatNetworkError.invalidURL)
            return
        }

        let sourceMessages = messages.map {
            ChatRequestSourceMessage(
                content: $0.content,
                isUser: $0.isUser,
                imageAttachments: $0.imageAttachments
            )
        }
        let payload = requestPayloadProjector.transformedMessagesForRequest(
            messages: sourceMessages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent
        )

        let requestBodyData: Data
        do {
            requestBodyData = try requestBodyBuilder.buildRequestBodyData(
                model: model,
                messagePayload: payload,
                developerPrompt: developerPrompt,
                endpoint: firstEndpoint,
                apiAdvancedSettings: configurationProvider.apiAdvancedSettings,
                thinkingCapability: configurationProvider.thinkingCapability,
                thinkingOption: configurationProvider.thinkingOption
            )
        } catch {
            onError?(error)
            return
        }
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.dataTask?.cancel()
            self.dataTask = nil
            self.stopWatchdog()
            self.resetStreamState()
            self.isCancelled = false
            self.activeEndpointCandidate = firstEndpoint
            self.startStreaming(endpoint: firstEndpoint, requestBodyData: requestBodyData)
        }
    }

    /// Cancels the current streaming request.
    @MainActor
    func cancelStreaming() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.isCancelled = true
            self.dataTask?.cancel()
            self.dataTask = nil
            self.stopWatchdog()
            self.resetStreamState()
            self.clearActiveEndpointCandidate()
        }
    }

}

// MARK: - Protocol Conformance

extension ChatService: ChatStreamingService {}
