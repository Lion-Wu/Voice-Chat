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
    let openAIResponsesStreamItemReducer: OpenAIResponsesStreamItemReducer
    let anthropicStreamReducer = AnthropicStreamEventReducer()
    let lmStudioStreamReducer: LMStudioStreamEventReducer
    let toolExecutor: ChatToolExecuting
    let toolAuthorizationCoordinator = ChatToolAuthorizationCoordinator()

    let stateQueue: DispatchQueue
    private let sessionQueue: OperationQueue
    private let delegateProxy: ChatServiceDelegateProxy

    var session: URLSession?
    var dataTask: URLSessionDataTask?

    /// Callbacks are explicitly constrained to run on the main actor.
    @MainActor var onDelta: (@MainActor (String) -> Void)?
    @MainActor var onSegment: (@MainActor (AssistantStreamSegment) -> Void)?
    @MainActor var onOpenAIResponsesConversationItems: (@MainActor ([JSONValue]) -> Void)?
    @MainActor var onError: (@MainActor (Error) -> Void)?
    @MainActor var onResponseMetadata: (@MainActor (ChatResponseMetadata) -> Void)?
    @MainActor var onToolActivity: (@MainActor (ChatToolActivity) -> Void)?
    @MainActor var onStreamFinished: (@MainActor () -> Void)?

    // Reasoning / body state tracking
    var isLegacyThinkStream = false
    var sawAnyAssistantToken = false
    var sawAnyPrimaryAssistantToken = false
    var lmStudioSawAnyReasoningToken = false
    var newFormatActive = false
    var sentThinkOpen = false
    var sentThinkClose = false
    var isInsideLegacyThinkTag = false
    var shouldTrimNextLegacyThinkLeadingNewline = false
    var legacyThinkTagBuffer = ""
    var streamFinishedEmitted = false
    var lastProcessedSSESequenceNumber: Int?
    var reasoningDeltaItemIDs = Set<String>()
    var outputTextDeltaItemIDs = Set<String>()
    var openAIResponsesStreamItemState = OpenAIResponsesStreamItemState()

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
    var anthropicAssistantContentAccumulator = AnthropicAssistantContentAccumulator()
    var pendingLMStudioStreamErrorMessage: String?
    var activeEndpointCandidate: ChatAPIEndpointCandidate?
    var pendingResponseMetadata = ChatResponseMetadata.empty
    var backgroundExecutionCoordinator: ChatServiceBackgroundExecutionCoordinator?
    var activeStreamRequestBodyData: Data?
    var lastRetryableStreamRequest: ChatRetryableStreamRequest?
    var toolCallAccumulator = ChatToolCallAccumulator()
    var openAIResponsesOutputItems: [[String: Any]] = []
    var openAIResponsesConversationItems: [JSONValue] = []
    var openAIChatCompletionsReasoningDetails: [JSONValue] = []
    var openAIChatCompletionsReasoningText = ""
    var pendingToolCalls: [ChatToolCallEnvelope] = []
    var generatingToolActivities: [String: ChatToolActivity] = [:]
    var activeToolLoopContext: ChatToolLoopContext?
    var activeToolExecutionID: UUID?
    var activeToolExecutionTask: Task<Void, Never>?
    var isToolContinuationStarting = false
    var requestGeneration: UInt64 = 0
    var streamCallbackEpoch: UInt64 = 0
    var streamCallbackAttempt: UInt64 = 0
    var invalidatedStreamCallbackAttempts = Set<UInt64>()
    var promptToolBufferedDeltas: [PromptToolBufferedDelta] = []
    var promptToolPrimaryText = ""
    var promptToolStreamDecision = PromptToolStreamDecision.undecided
    var promptToolPendingThinkClose: String?
    var promptToolKeepsThinkOpen = false
    var promptToolPreviewActivityID: String?

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
        self.openAIResponsesStreamItemReducer = OpenAIResponsesStreamItemReducer(
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
        activeToolExecutionTask?.cancel()
        session?.invalidateAndCancel()
        stopConnectionWatchdog()
        stopWatchdog()
        let authorizationCoordinator = toolAuthorizationCoordinator
        Task { await authorizationCoordinator.cancelAll() }
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
        guard messages.last?.isUser == true else {
            onError?(ChatNetworkError.invalidRequestHistory)
            return
        }

        let sourceMessages = messages.map {
            ChatRequestSourceMessage(
                content: $0.content,
                isUser: $0.isUser,
                imageAttachments: $0.imageAttachments,
                providerResponseID: $0.providerResponseID,
                requestContextFingerprint: $0.requestContextFingerprint,
                requestContentSnapshot: $0.requestContentSnapshot,
                assistantSegments: $0.assistantSegments,
                openAIResponsesConversationItems: $0.openAIResponsesConversationItems,
                toolActivityPlacements: $0.toolActivityPlacements,
                createdAt: $0.createdAt
            )
        }
        let requestContext = ChatRequestContextBuilder.make(
            model: model,
            endpoint: firstEndpoint,
            developerPrompt: developerPrompt,
            toolUseSettings: configurationProvider.toolUseSettings,
            apiAdvancedSettings: configurationProvider.apiAdvancedSettings,
            thinkingOption: configurationProvider.thinkingOption,
            sourceMessages: sourceMessages,
            includeImagesInUserContent: includeImagesInUserContent
        )
        let previousResponseID = Self.previousResponseID(
            in: sourceMessages,
            endpoint: firstEndpoint,
            currentRequestFingerprint: requestContext.fingerprint,
            useProviderContinuationIDs: configurationProvider.toolUseSettings.useProviderContinuationIDs(for: firstEndpoint)
        )
        let initialPayload = projectedRequestPayload(
            sourceMessages: sourceMessages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent,
            endpoint: firstEndpoint
        )
        let payload = initialPayload.messages
        let toolContext = ChatToolLoopContext(
            currentPayload: initialPayload,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent,
            model: model,
            endpoint: firstEndpoint,
            iteration: 0,
            previousResponseID: previousResponseID
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
        onResponseMetadata?(ChatResponseMetadata(
            requestContext: requestContext.snapshot,
            requestUsedPreviousResponseID: previousResponseID != nil,
            requestPreviousResponseID: previousResponseID
        ))
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.dataTask?.cancel()
            self.dataTask = nil
            self.cancelActiveToolExecution()
            self.stopWatchdog()
            self.resetStreamState()
            self.advanceRequestGeneration()
            var activeContext = toolContext
            activeContext.requestGeneration = self.requestGeneration
            self.activeToolLoopContext = activeContext
            self.isCancelled = false
            self.activeEndpointCandidate = firstEndpoint
            self.startStreaming(endpoint: firstEndpoint, requestBodyData: requestBodyData)
        }
    }

    static func previousResponseID(
        in sourceMessages: [ChatRequestSourceMessage],
        endpoint: ChatAPIEndpointCandidate,
        currentRequestFingerprint: String? = nil,
        useProviderContinuationIDs: Bool = true,
        now: Date = Date()
    ) -> String? {
        guard useProviderContinuationIDs else {
            return nil
        }
        guard ChatRequestBodyProviderEncoder.supportsPreviousResponseContinuation(endpoint) else {
            return nil
        }

        guard let latestUserIndex = sourceMessages.indices.last,
              sourceMessages[latestUserIndex].isUser,
              latestUserIndex > sourceMessages.startIndex else {
            return nil
        }

        let previousIndex = sourceMessages.index(before: latestUserIndex)
        let previousMessage = sourceMessages[previousIndex]
        let currentRequestFingerprint = currentRequestFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousFingerprint = previousMessage.requestContextFingerprint?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previousMessage.isUser,
              !previousMessage.content.hasPrefix("!error:"),
              now.timeIntervalSince(previousMessage.createdAt) <= Self.previousResponseIDMaxAge,
              let currentRequestFingerprint,
              !currentRequestFingerprint.isEmpty,
              previousFingerprint == currentRequestFingerprint,
              let responseID = ChatRequestBodyProviderEncoder.normalizedPreviousResponseID(
                previousMessage.providerResponseID,
                endpoint: endpoint
              ) else {
            return nil
        }
        return responseID
    }

    static let previousResponseIDMaxAge: TimeInterval = 30 * 24 * 60 * 60

    func projectedRequestPayload(
        sourceMessages: [ChatRequestSourceMessage],
        developerPrompt: String?,
        includeImagesInUserContent: Bool,
        endpoint: ChatAPIEndpointCandidate
    ) -> ChatToolLoopPayload {
        ChatToolLoopPayload(messages: requestPayloadProjector.transformedMessagesForRequest(
            messages: sourceMessages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent,
            requestStyle: endpoint.style
        ))
    }

    /// Cancels the current streaming request.
    @MainActor
    func cancelStreaming() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.isCancelled = true
            self.advanceRequestGeneration()
            self.dataTask?.cancel()
            self.dataTask = nil
            self.stopWatchdog()
            Task { await self.toolAuthorizationCoordinator.cancelAll() }
            self.resetStreamState()
            self.activeToolLoopContext = nil
            self.clearActiveEndpointCandidate()
        }
    }

}

struct PromptToolBufferedDelta: Equatable {
    let piece: String
    let marksPrimaryOutput: Bool
}

enum PromptToolStreamDecision: Equatable {
    case undecided
    case normalAnswer
    case toolCall
}

struct ChatToolLoopContext: Sendable {
    var currentPayload: ChatToolLoopPayload
    let developerPrompt: String?
    let includeImagesInUserContent: Bool
    let model: String
    var endpoint: ChatAPIEndpointCandidate
    var iteration: Int
    var previousResponseID: String?
    var requestGeneration: UInt64 = 0
    var didRetryWithoutPreviousResponseID = false
}

struct ChatToolLoopPayload: @unchecked Sendable {
    let messages: [[String: Any]]
}

struct ChatRetryableStreamRequest: Sendable {
    let endpoint: ChatAPIEndpointCandidate
    let body: Data
    let toolLoopContext: ChatToolLoopContext?
}

struct ChatStreamCallbackToken: Hashable, Sendable {
    let epoch: UInt64
    let attempt: UInt64
}

// MARK: - Protocol Conformance

extension ChatService: ChatStreamingService {}
