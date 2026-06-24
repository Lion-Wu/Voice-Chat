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
    let requestBodyBuilder: ChatRequestBodyBuilding
    let requestFactory: ChatStreamingRequestBuilding
    private let responseTextExtractor: ChatResponseTextExtracting
    let bufferedResponseParser: ChatBufferedResponseParsing
    let streamPayloadExtractor: ChatStreamPayloadExtracting
    let openAICompatibleStreamReducer: OpenAICompatibleStreamEventReducer
    let anthropicStreamReducer = AnthropicStreamEventReducer()
    let lmStudioStreamReducer: LMStudioStreamEventReducer
    let toolExecutor: ChatToolExecuting

    let stateQueue: DispatchQueue
    private let sessionQueue: OperationQueue
    private let delegateProxy: ChatServiceDelegateProxy

    var session: URLSession?
    var dataTask: URLSessionDataTask?

    /// Callbacks are explicitly constrained to run on the main actor.
    @MainActor var onDelta: (@MainActor (String) -> Void)?
    @MainActor var onError: (@MainActor (Error) -> Void)?
    @MainActor var onResponseMetadata: (@MainActor (ChatResponseMetadata) -> Void)?
    @MainActor var onToolActivity: (@MainActor (ChatToolActivity) -> Void)?
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
    var toolCallAccumulator = ChatToolCallAccumulator()
    var pendingToolCalls: [ChatToolCallEnvelope] = []
    var activeToolLoopContext: ChatToolLoopContext?
    var lmStudioPromptToolBufferedDeltas: [LMStudioPromptToolBufferedDelta] = []
    var lmStudioPromptToolPrimaryText = ""
    var lmStudioPromptToolStreamDecision = LMStudioPromptToolStreamDecision.undecided
    var lmStudioPromptToolPendingThinkClose: String?
    var lmStudioPromptToolKeepsThinkOpen = false

    init(
        configurationProvider: ChatServiceConfiguring,
        endpointResolver: ChatEndpointResolving = DefaultChatEndpointResolver(),
        requestPayloadProjector: ChatRequestPayloadProjecting = ChatRequestPayloadProjector(),
        requestBodyBuilder: ChatRequestBodyBuilding = ChatRequestBodyBuilder(),
        requestFactory: ChatStreamingRequestBuilding = ChatStreamingRequestFactory(),
        responseMetadataExtractor: ChatResponseMetadataExtracting = ChatResponseMetadataExtractor(),
        responseTextExtractor: ChatResponseTextExtracting = ChatResponseTextExtractor(),
        bufferedResponseParser: ChatBufferedResponseParsing? = nil,
        streamPayloadExtractor: ChatStreamPayloadExtracting? = nil,
        toolExecutor: ChatToolExecuting = ChatToolExecutor()
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
        self.toolExecutor = toolExecutor
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

        let sourceMessages = Self.messagesThroughLatestUser(messages.map {
            ChatRequestSourceMessage(
                content: $0.content,
                isUser: $0.isUser,
                imageAttachments: $0.imageAttachments,
                providerResponseID: $0.providerResponseID,
                createdAt: $0.createdAt
            )
        })
        let previousResponseID = Self.previousLMStudioResponseID(
            in: sourceMessages,
            endpoint: firstEndpoint
        )
        let payload = requestPayloadProjector.transformedMessagesForRequest(
            messages: sourceMessages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent
        )
        let toolContext = ChatToolLoopContext(
            sourceMessages: sourceMessages,
            originalPayload: ChatToolLoopPayload(messages: payload),
            currentPayload: ChatToolLoopPayload(messages: payload),
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent,
            model: model,
            endpoint: firstEndpoint,
            iteration: 0,
            previousResponseID: previousResponseID,
            didRetryWithoutPreviousResponseID: false
        )

        let requestBodyData: Data
        do {
            requestBodyData = try requestBodyBuilder.buildRequestBodyData(
                model: model,
                messagePayload: payload,
                developerPrompt: developerPrompt,
                endpoint: firstEndpoint,
                apiAdvancedSettings: configurationProvider.apiAdvancedSettings,
                toolUseSettings: configurationProvider.toolUseSettings,
                previousResponseID: previousResponseID,
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
            self.activeToolLoopContext = toolContext
            self.isCancelled = false
            self.activeEndpointCandidate = firstEndpoint
            self.startStreaming(endpoint: firstEndpoint, requestBodyData: requestBodyData)
        }
    }

    static func previousLMStudioResponseID(
        in sourceMessages: [ChatRequestSourceMessage],
        endpoint: ChatAPIEndpointCandidate,
        now: Date = Date()
    ) -> String? {
        switch endpoint.style {
        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            break
        case .openAIChatCompletions, .anthropicMessages:
            return nil
        }

        guard let latestUserIndex = sourceMessages.lastIndex(where: \.isUser),
              latestUserIndex > sourceMessages.startIndex else {
            return nil
        }

        let previousIndex = sourceMessages.index(before: latestUserIndex)
        let previousMessage = sourceMessages[previousIndex]
        guard !previousMessage.isUser,
              !previousMessage.content.hasPrefix("!error:"),
              now.timeIntervalSince(previousMessage.createdAt) <= Self.lmStudioPreviousResponseIDMaxAge,
              let responseID = previousMessage.providerResponseID?.trimmingCharacters(in: .whitespacesAndNewlines),
              responseID.hasPrefix("resp_") else {
            return nil
        }
        return responseID
    }

    static let lmStudioPreviousResponseIDMaxAge: TimeInterval = 30 * 24 * 60 * 60

    static func messagesThroughLatestUser(
        _ sourceMessages: [ChatRequestSourceMessage]
    ) -> [ChatRequestSourceMessage] {
        guard let latestUserIndex = sourceMessages.lastIndex(where: \.isUser) else {
            return sourceMessages
        }
        return Array(sourceMessages[...latestUserIndex])
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

struct LMStudioPromptToolBufferedDelta: Equatable {
    let piece: String
    let marksPrimaryOutput: Bool
}

enum LMStudioPromptToolStreamDecision: Equatable {
    case undecided
    case normalAnswer
    case toolCall
}

struct ChatToolLoopContext: Sendable {
    let sourceMessages: [ChatRequestSourceMessage]
    let originalPayload: ChatToolLoopPayload
    var currentPayload: ChatToolLoopPayload
    let developerPrompt: String?
    let includeImagesInUserContent: Bool
    let model: String
    let endpoint: ChatAPIEndpointCandidate
    var iteration: Int
    var previousResponseID: String?
    var didRetryWithoutPreviousResponseID: Bool
}

struct ChatToolLoopPayload: @unchecked Sendable {
    let messages: [[String: Any]]
}

// MARK: - Protocol Conformance

extension ChatService: ChatStreamingService {}
