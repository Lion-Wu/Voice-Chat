//
//  ChatService.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

final class ChatService: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let configurationProvider: ChatServiceConfiguring

    private let stateQueue: DispatchQueue
    private let sessionQueue: OperationQueue
    private let delegateProxy: DelegateProxy

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?

    /// Callbacks are explicitly constrained to run on the main actor.
    @MainActor var onDelta: (@MainActor (String) -> Void)?
    @MainActor var onError: (@MainActor (Error) -> Void)?
    @MainActor var onResponseMetadata: (@MainActor (ChatResponseMetadata) -> Void)?
    @MainActor var onStreamFinished: (@MainActor () -> Void)?

    // Reasoning / body state tracking
    private var isLegacyThinkStream = false
    private var sawAnyAssistantToken = false
    private var sawAnyPrimaryAssistantToken = false
    private var newFormatActive = false
    private var sentThinkOpen = false
    private var sentThinkClose = false
    private var streamFinishedEmitted = false
    private var lastProcessedSSESequenceNumber: Int?
    private var reasoningDeltaItemIDs = Set<String>()
    private var outputTextDeltaItemIDs = Set<String>()

    // SSE parsing buffer
    private var ssePartialLine: String = ""
    private var ssePendingEventType: String?
    private let maxBufferedSSEBytes = 512 * 1024
    private let thinkOpenLine = "<think>\n"
    private let thinkCloseLine = "\n</think>\n"
    private let decoder = JSONDecoder()

    // Watchdog configuration to cover long-running sessions (up to ~1 hour).
    private let connectTimeout: TimeInterval = 8             // Fail fast if we can't establish a connection.
    private let firstTokenTimeout: TimeInterval = 3600        // Wait up to one hour for the first token.
    private let silentGapTimeout: TimeInterval  = 3600        // Allow up to one hour of silence between tokens.
    private var streamStartAt: Date?
    private var didEstablishConnection: Bool = false
    private var lastDeltaAt: Date?
    private var watchdog: DispatchSourceTimer?
    private var connectionWatchdog: DispatchSourceTimer?

    // Cancel flag to ignore any residual deltas after stopping.
    private var isCancelled: Bool = false

    // HTTP status/error accumulation for non-2xx responses.
    private var httpStatusCode: Int?
    private let errorBodyCaptureLimit = 32 * 1024
    private var errorResponseData = Data()
    private let successBodyCaptureLimit = 2 * 1024 * 1024
    private var successResponseData = Data()
    private var anthropicThinkingActive = false
    private var pendingLMStudioStreamErrorMessage: String?
    private var activeEndpointCandidate: ChatAPIEndpointCandidate?
    private var pendingResponseMetadata = ChatResponseMetadata.empty
#if canImport(UIKit)
    // UIKit background tasks only provide a finite grace period for in-flight work.
    private let backgroundTaskName = "VoiceChat.TextStreaming"
    private var backgroundTaskGeneration: UInt64 = 0
    @MainActor private var backgroundTaskGenerationOnMain: UInt64 = 0
    @MainActor private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
#endif

    private final class DelegateProxy: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        weak var owner: ChatService?

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            owner?.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            owner?.urlSession(session, dataTask: dataTask, didReceive: data)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didSendBodyData bytesSent: Int64,
            totalBytesSent: Int64,
            totalBytesExpectedToSend: Int64
        ) {
            owner?.urlSession(
                session,
                task: task,
                didSendBodyData: bytesSent,
                totalBytesSent: totalBytesSent,
                totalBytesExpectedToSend: totalBytesExpectedToSend
            )
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            owner?.urlSession(session, task: task, didCompleteWithError: error)
        }
    }

    init(configurationProvider: ChatServiceConfiguring) {
        self.configurationProvider = configurationProvider
        self.stateQueue = DispatchQueue(label: "VoiceChat.ChatService.state", qos: .userInitiated)
        let queue = OperationQueue()
        queue.name = "VoiceChat.ChatService.session"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        queue.underlyingQueue = self.stateQueue
        self.sessionQueue = queue
        self.delegateProxy = DelegateProxy()
        super.init()
        self.delegateProxy.owner = self
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest  = 3900   // Adds a few minutes of headroom beyond one hour.
        configuration.timeoutIntervalForResource = 3900
        configuration.httpMaximumConnectionsPerHost = 1
        self.session = URLSession(configuration: configuration, delegate: delegateProxy, delegateQueue: sessionQueue)
    }

    deinit {
        session?.invalidateAndCancel()
        stopConnectionWatchdog()
        stopWatchdog()
#if canImport(UIKit)
        let teardownBackgroundTask = {
            MainActor.assumeIsolated {
                self.endBackgroundExecutionOnMain(for: UInt64.max)
            }
        }
        if Thread.isMainThread {
            teardownBackgroundTask()
        } else {
            DispatchQueue.main.sync(execute: teardownBackgroundTask)
        }
#endif
    }

    /// Called on the main actor to avoid crossing actor boundaries with SwiftData models.
    @MainActor
    func fetchStreamedData(messages: [ChatMessage], developerPrompt: String?, includeImagesInUserContent: Bool) {
        let base = configurationProvider.apiBaseURL
        let model = configurationProvider.modelIdentifier
        var endpointCandidates = ChatAPIEndpointResolver.endpointCandidates(
            for: base,
            preferredProvider: configurationProvider.providerHint
        )
        if let providerHint = configurationProvider.providerHint, providerHint != .unknown {
            let providerMatched = endpointCandidates.filter { $0.provider == providerHint }
            if !providerMatched.isEmpty {
                endpointCandidates = providerMatched
            }
        }
        if let styleHint = configurationProvider.requestStyleHint {
            let styleMatched = endpointCandidates.filter { $0.style == styleHint }
            if !styleMatched.isEmpty {
                endpointCandidates = styleMatched
            }
        }
        endpointCandidates = prioritizeEndpointCandidates(
            endpointCandidates,
            preferredStyle: configurationProvider.requestStyleHint
        )
        guard let firstEndpoint = endpointCandidates.first else {
            onError?(ChatNetworkError.invalidURL)
            return
        }

        let payload = transformedMessagesForRequest(
            messages: messages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent
        )

        let requestBodyData: Data
        do {
            requestBodyData = try buildRequestBodyData(
                model: model,
                messagePayload: payload,
                developerPrompt: developerPrompt,
                endpoint: firstEndpoint
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

    /// Builds the request and starts the URLSession stream (non-async helper).
    private func startStreaming(endpoint: ChatAPIEndpointCandidate, requestBodyData: Data) {
        var request = URLRequest(url: endpoint.chatURL)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 3900 // Individual request timeout with extra buffer beyond one hour.
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.addValue("keep-alive", forHTTPHeaderField: "Connection")
        request.addValue("no-cache", forHTTPHeaderField: "Cache-Control")

        applyAuthHeaders(to: &request, for: endpoint)

        request.httpBody = requestBodyData

        streamStartAt = Date()
        didEstablishConnection = false
        lastDeltaAt = nil
        beginBackgroundExecutionForCurrentRequest()
        startWatchdog()
        startConnectionWatchdog()

        dataTask = session?.dataTask(with: request)
        dataTask?.resume()
    }

    private func normalizedAPIKeyForXAPIKeyHeader(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.lowercased().hasPrefix("bearer ") {
            return String(trimmed.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func applyAuthHeaders(to request: inout URLRequest, for endpoint: ChatAPIEndpointCandidate) {
        let rawKey = configurationProvider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch endpoint.style {
        case .anthropicMessages:
            let keyForHeader = normalizedAPIKeyForXAPIKeyHeader(rawKey)
            if !keyForHeader.isEmpty {
                request.setValue(keyForHeader, forHTTPHeaderField: "x-api-key")
            }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        case .openAIChatCompletions, .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            if !rawKey.isEmpty {
                let headerValue = rawKey.lowercased().hasPrefix("bearer ") ? rawKey : "Bearer \(rawKey)"
                request.setValue(headerValue, forHTTPHeaderField: "Authorization")
            }
        }
    }

    private func buildRequestBodyData(
        model: String,
        messagePayload: [[String: Any]],
        developerPrompt: String?,
        endpoint: ChatAPIEndpointCandidate
    ) throws -> Data {
        let style = endpoint.style
        switch style {
        case .openAIChatCompletions:
            if isOpenAIResponsesEndpoint(endpoint.chatURL) {
                var requestBody: [String: Any] = [
                    "model": model,
                    "stream": true,
                    "input": openAIResponsesInput(from: messagePayload)
                ]
                applyAdvancedAPIConfiguration(to: &requestBody, model: model, endpoint: endpoint)
                applyThinkingConfiguration(to: &requestBody, model: model, endpoint: endpoint)
                return try JSONSerialization.data(withJSONObject: requestBody, options: [])
            }

            var requestBody: [String: Any] = [
                "model": model,
                "stream": true,
                "messages": messagePayload
            ]
            applyAdvancedAPIConfiguration(to: &requestBody, model: model, endpoint: endpoint)
            applyThinkingConfiguration(to: &requestBody, model: model, endpoint: endpoint)
            return try JSONSerialization.data(withJSONObject: requestBody, options: [])

        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            let lmStudioInput = lmStudioRESTInput(
                from: messagePayload,
                textDiscriminator: style == .lmStudioRESTV1LegacyMessage ? "message" : "text"
            )
            var requestBody: [String: Any] = [
                "model": model,
                "stream": true,
                "input": lmStudioInput
            ]
            if let prompt = developerPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
               !prompt.isEmpty {
                requestBody["system_prompt"] = prompt
            }
            applyAdvancedAPIConfiguration(to: &requestBody, model: model, endpoint: endpoint)
            applyThinkingConfiguration(to: &requestBody, model: model, endpoint: endpoint)
            return try JSONSerialization.data(withJSONObject: requestBody, options: [])

        case .anthropicMessages:
            let advancedSettings = configurationProvider.apiAdvancedSettings.sanitized
            var requestBody: [String: Any] = [
                "model": model,
                "stream": true,
                "max_tokens": advancedSettings.anthropicMaxTokens,
                "messages": anthropicMessagesInput(from: messagePayload)
            ]
            if let prompt = developerPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
               !prompt.isEmpty {
                requestBody["system"] = prompt
            }
            applyAdvancedAPIConfiguration(to: &requestBody, model: model, endpoint: endpoint)
            applyThinkingConfiguration(to: &requestBody, model: model, endpoint: endpoint)
            return try JSONSerialization.data(withJSONObject: requestBody, options: [])
        }
    }

    private func applyAdvancedAPIConfiguration(
        to requestBody: inout [String: Any],
        model: String,
        endpoint: ChatAPIEndpointCandidate
    ) {
        let settings = configurationProvider.apiAdvancedSettings.sanitized
        switch endpoint.style {
        case .openAIChatCompletions:
            if isOpenAIResponsesEndpoint(endpoint.chatURL) {
                applyPositiveInteger(settings.openAIResponsesMaxOutputTokens, key: "max_output_tokens", to: &requestBody)
                applyOpenAIResponsesSamplingConfiguration(settings.openAIResponsesSampling, to: &requestBody)
                return
            }

            switch endpoint.provider {
            case .openAI:
                applyPositiveInteger(settings.openAIChatMaxCompletionTokens, key: "max_completion_tokens", to: &requestBody)
                applyOpenAIChatSamplingConfiguration(settings.openAIChatSampling, to: &requestBody)
            case .gemini:
                applyPositiveInteger(settings.geminiMaxTokens, key: "max_tokens", to: &requestBody)
                applyGeminiSamplingConfiguration(settings.geminiSampling, to: &requestBody)
            case .deepSeek:
                applyPositiveInteger(settings.deepSeekMaxTokens, key: "max_tokens", to: &requestBody)
                applyDeepSeekSamplingConfiguration(settings.deepSeekSampling, model: model, to: &requestBody)
            case .xAI:
                applyPositiveInteger(settings.xAIMaxTokens, key: "max_tokens", to: &requestBody)
                applyOpenAIChatSamplingConfiguration(settings.xAISampling, to: &requestBody, topLogprobsLimit: 8)
            case .openRouter:
                applyPositiveInteger(settings.openRouterMaxTokens, key: "max_tokens", to: &requestBody)
                applyPositiveInteger(settings.openRouterMaxCompletionTokens, key: "max_completion_tokens", to: &requestBody)
                applyOpenRouterSamplingConfiguration(settings.openRouterSampling, to: &requestBody)
            case .lmStudio:
                applyPositiveInteger(settings.lmStudioOpenAICompatibleMaxTokens, key: "max_tokens", to: &requestBody)
                applyLMStudioOpenAICompatibleSamplingConfiguration(settings.lmStudioOpenAICompatibleSampling, to: &requestBody)
            case .llamaCpp:
                applyPositiveInteger(settings.llamaCppMaxTokens, key: "max_tokens", to: &requestBody)
                applyLlamaCppSamplingConfiguration(settings.llamaCppSampling, to: &requestBody)
            case .openAICompatible, .unknown, .anthropic:
                applyPositiveInteger(settings.openAICompatibleMaxTokens, key: "max_tokens", to: &requestBody)
                applyOpenAIChatSamplingConfiguration(settings.openAICompatibleSampling, to: &requestBody)
            }

        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            applyPositiveInteger(settings.lmStudioMaxTokens, key: "max_output_tokens", to: &requestBody)
            applyLMStudioRESTSamplingConfiguration(settings.lmStudioSampling, to: &requestBody)

        case .anthropicMessages:
            applyAnthropicSamplingConfiguration(settings.anthropicSampling, to: &requestBody)
        }
    }

    private func applyPositiveInteger(_ value: Int, key: String, to requestBody: inout [String: Any]) {
        guard value > 0 else { return }
        requestBody[key] = value
    }

    private func applyIntegerOverride(_ isEnabled: Bool, _ value: Int, key: String, to requestBody: inout [String: Any]) {
        guard isEnabled else { return }
        requestBody[key] = max(0, value)
    }

    private func applyOpenAIChatSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any],
        includeSeed: Bool = true,
        includeJSONMode: Bool = true,
        includeLogprobs: Bool = true,
        topLogprobsLimit: Int = 20
    ) {
        if sampling.temperatureEnabled {
            requestBody["temperature"] = sampling.temperature
        }
        if sampling.topPEnabled {
            requestBody["top_p"] = sampling.topP
        }
        if sampling.presencePenaltyEnabled {
            requestBody["presence_penalty"] = sampling.presencePenalty
        }
        if sampling.frequencyPenaltyEnabled {
            requestBody["frequency_penalty"] = sampling.frequencyPenalty
        }
        if includeJSONMode, sampling.jsonModeEnabled {
            requestBody["response_format"] = ["type": "json_object"]
        }
        if includeLogprobs, sampling.logprobsEnabled {
            requestBody["logprobs"] = true
            applyIntegerOverride(
                sampling.topLogprobsEnabled,
                min(sampling.topLogprobs, topLogprobsLimit),
                key: "top_logprobs",
                to: &requestBody
            )
        }
        if includeSeed {
            applyIntegerOverride(sampling.seedEnabled, sampling.seed, key: "seed", to: &requestBody)
        }
    }

    private func applyAnthropicSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any]
    ) {
        if sampling.temperatureEnabled {
            requestBody["temperature"] = min(sampling.temperature, 1)
        }
        if sampling.topPEnabled {
            requestBody["top_p"] = sampling.topP
        }
        applyIntegerOverride(sampling.topKEnabled, sampling.topK, key: "top_k", to: &requestBody)
    }

    private func applyOpenAIResponsesSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any]
    ) {
        if sampling.temperatureEnabled {
            requestBody["temperature"] = sampling.temperature
        }
        if sampling.topPEnabled {
            requestBody["top_p"] = sampling.topP
        }
        if sampling.jsonModeEnabled {
            mergeOpenAIResponsesTextOptions(["format": ["type": "json_object"]], into: &requestBody)
        }
        if sampling.verbosityEnabled {
            mergeOpenAIResponsesTextOptions(["verbosity": openAIResponsesVerbosity(sampling.verbosity)], into: &requestBody)
        }
    }

    private func mergeOpenAIResponsesTextOptions(_ options: [String: Any], into requestBody: inout [String: Any]) {
        var textOptions = requestBody["text"] as? [String: Any] ?? [:]
        for (key, value) in options {
            textOptions[key] = value
        }
        requestBody["text"] = textOptions
    }

    private func openAIResponsesVerbosity(_ verbosity: String) -> String {
        switch verbosity {
        case "low", "high":
            return verbosity
        default:
            return "medium"
        }
    }

    private func applyGeminiSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any]
    ) {
        if sampling.temperatureEnabled {
            requestBody["temperature"] = sampling.temperature
        }
        if sampling.topPEnabled {
            requestBody["top_p"] = sampling.topP
        }
    }

    private func applyDeepSeekSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        model: String,
        to requestBody: inout [String: Any]
    ) {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isReasoner = normalizedModel.contains("reasoner")
        if !isReasoner {
            if sampling.temperatureEnabled {
                requestBody["temperature"] = sampling.temperature
            }
            if sampling.topPEnabled {
                requestBody["top_p"] = sampling.topP
            }
            if sampling.presencePenaltyEnabled {
                requestBody["presence_penalty"] = sampling.presencePenalty
            }
            if sampling.frequencyPenaltyEnabled {
                requestBody["frequency_penalty"] = sampling.frequencyPenalty
            }
            if sampling.logprobsEnabled {
                requestBody["logprobs"] = true
                applyIntegerOverride(sampling.topLogprobsEnabled, sampling.topLogprobs, key: "top_logprobs", to: &requestBody)
            }
        }
        if sampling.jsonModeEnabled {
            requestBody["response_format"] = ["type": "json_object"]
        }
    }

    private func applyOpenRouterSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any]
    ) {
        applyOpenAIChatSamplingConfiguration(sampling, to: &requestBody)
        applyIntegerOverride(sampling.topKEnabled, sampling.topK, key: "top_k", to: &requestBody)
        if sampling.minPEnabled {
            requestBody["min_p"] = sampling.minP
        }
        if sampling.topAEnabled {
            requestBody["top_a"] = sampling.topA
        }
        if sampling.repetitionPenaltyEnabled {
            requestBody["repetition_penalty"] = sampling.repetitionPenalty
        }
        if sampling.structuredOutputsEnabled {
            requestBody["structured_outputs"] = true
        }
        if sampling.verbosityEnabled {
            requestBody["verbosity"] = sampling.verbosity
        }
    }

    private func applyLMStudioRESTSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any]
    ) {
        if sampling.temperatureEnabled {
            requestBody["temperature"] = min(sampling.temperature, 1)
        }
        if sampling.topPEnabled {
            requestBody["top_p"] = sampling.topP
        }
        applyIntegerOverride(sampling.topKEnabled, sampling.topK, key: "top_k", to: &requestBody)
        if sampling.minPEnabled {
            requestBody["min_p"] = sampling.minP
        }
        if sampling.repetitionPenaltyEnabled {
            requestBody["repeat_penalty"] = sampling.repetitionPenalty
        }
        applyIntegerOverride(sampling.contextLengthEnabled, sampling.contextLength, key: "context_length", to: &requestBody)
    }

    private func applyLMStudioOpenAICompatibleSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any]
    ) {
        applyOpenAIChatSamplingConfiguration(sampling, to: &requestBody, includeLogprobs: false)
        applyIntegerOverride(sampling.topKEnabled, sampling.topK, key: "top_k", to: &requestBody)
        if sampling.repetitionPenaltyEnabled {
            requestBody["repeat_penalty"] = sampling.repetitionPenalty
        }
    }

    private func applyLlamaCppSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any]
    ) {
        applyOpenAIChatSamplingConfiguration(sampling, to: &requestBody)
        applyIntegerOverride(sampling.topKEnabled, sampling.topK, key: "top_k", to: &requestBody)
        if sampling.minPEnabled {
            requestBody["min_p"] = sampling.minP
        }
        if sampling.repetitionPenaltyEnabled {
            requestBody["repeat_penalty"] = sampling.repetitionPenalty
        }
    }

    private func applyThinkingConfiguration(
        to requestBody: inout [String: Any],
        model: String,
        endpoint: ChatAPIEndpointCandidate
    ) {
        guard let option = configurationProvider.thinkingOption else { return }
        if let capability = configurationProvider.thinkingCapability,
           !capability.isConfigurable {
            return
        }
        let requestParameter = configurationProvider.thinkingCapability?.requestParameter

        switch endpoint.style {
        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            requestBody["reasoning"] = lmStudioReasoningValue(for: option)

        case .anthropicMessages:
            guard !option.isDisabled else { return }
            if isAnthropicAdaptiveThinkingModel(model) {
                requestBody["thinking"] = [
                    "type": "adaptive",
                    "display": "summarized"
                ]
                requestBody["output_config"] = [
                    "effort": anthropicAdaptiveEffort(for: option, model: model)
                ]
                return
            }

            let budget = anthropicThinkingBudget(for: option)
            requestBody["thinking"] = [
                "type": "enabled",
                "budget_tokens": budget
            ]
            let settings = configurationProvider.apiAdvancedSettings.sanitized
            let currentMaxTokens = (requestBody["max_tokens"] as? Int) ?? settings.anthropicMaxTokens
            requestBody["max_tokens"] = max(currentMaxTokens, budget + settings.anthropicThinkingResponseReserve)

        case .openAIChatCompletions:
            if endpoint.provider == .deepSeek {
                applyDeepSeekThinkingConfiguration(to: &requestBody, option: option)
                return
            }

            if isOpenAIResponsesEndpoint(endpoint.chatURL) {
                requestBody["reasoning"] = ["effort": openAIReasoningEffort(for: option)]
                return
            }

            if let requestParameter {
                switch requestParameter {
                case .reasoningEffort:
                    requestBody["reasoning_effort"] = reasoningEffortValue(for: option, endpoint: endpoint)
                case .reasoning:
                    requestBody["reasoning"] = ["effort": reasoningEffortValue(for: option, endpoint: endpoint)]
                case .thinking:
                    requestBody["thinking"] = ["type": option.isDisabled ? "disabled" : "enabled"]
                }
                return
            }

            switch endpoint.provider {
            case .deepSeek:
                if !option.isDisabled {
                    requestBody["thinking"] = ["type": "enabled"]
                }
            case .gemini:
                requestBody["reasoning_effort"] = geminiReasoningEffort(for: option)
            case .openRouter:
                requestBody["reasoning"] = ["effort": openRouterReasoningEffort(for: option)]
            case .openAI, .lmStudio, .openAICompatible, .llamaCpp, .unknown:
                requestBody["reasoning_effort"] = openAIReasoningEffort(for: option)
            case .xAI, .anthropic:
                break
            }
        }
    }

    private func reasoningEffortValue(for option: ModelThinkingOption, endpoint: ChatAPIEndpointCandidate) -> String {
        switch endpoint.provider {
        case .gemini:
            return geminiReasoningEffort(for: option)
        case .openRouter:
            return openRouterReasoningEffort(for: option)
        case .openAI, .lmStudio, .openAICompatible, .llamaCpp, .unknown, .deepSeek, .anthropic, .xAI:
            return openAIReasoningEffort(for: option)
        }
    }

    private func lmStudioReasoningValue(for option: ModelThinkingOption) -> String {
        switch option {
        case .none:
            return "off"
        case .minimal:
            return "low"
        case .xhigh, .max:
            return "high"
        default:
            return option.rawValue
        }
    }

    private func openAIReasoningEffort(for option: ModelThinkingOption) -> String {
        switch option {
        case .off:
            return "none"
        case .on:
            return "medium"
        case .max:
            return "xhigh"
        default:
            return option.rawValue
        }
    }

    private func geminiReasoningEffort(for option: ModelThinkingOption) -> String {
        switch option {
        case .off:
            return "none"
        case .on:
            return "medium"
        case .xhigh, .max:
            return "high"
        default:
            return option.rawValue
        }
    }

    private func openRouterReasoningEffort(for option: ModelThinkingOption) -> String {
        switch option {
        case .off:
            return "none"
        case .on:
            return "medium"
        case .max:
            return "xhigh"
        default:
            return option.rawValue
        }
    }

    private func applyDeepSeekThinkingConfiguration(to requestBody: inout [String: Any], option: ModelThinkingOption) {
        requestBody["thinking"] = ["type": option.isDisabled ? "disabled" : "enabled"]
        guard !option.isDisabled else { return }
        requestBody["reasoning_effort"] = deepSeekReasoningEffort(for: option)
    }

    private func deepSeekReasoningEffort(for option: ModelThinkingOption) -> String {
        switch option {
        case .xhigh, .max:
            return "max"
        case .off, .none:
            return "high"
        case .minimal, .low, .medium, .high, .on:
            return "high"
        }
    }

    private func anthropicThinkingBudget(for option: ModelThinkingOption) -> Int {
        let settings = configurationProvider.apiAdvancedSettings.sanitized
        switch option {
        case .minimal, .low, .on:
            return settings.anthropicLowThinkingBudget
        case .medium:
            return settings.anthropicMediumThinkingBudget
        case .high, .xhigh, .max:
            return settings.anthropicHighThinkingBudget
        case .off, .none:
            return 0
        }
    }

    private func isAnthropicAdaptiveThinkingModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("claude-opus-4-7") ||
            normalized.contains("claude-opus-4-6") ||
            normalized.contains("claude-sonnet-4-6") ||
            normalized.contains("claude-mythos")
    }

    private func anthropicAdaptiveEffort(for option: ModelThinkingOption, model: String) -> String {
        switch option {
        case .xhigh:
            let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.contains("claude-opus-4-7") ? "xhigh" : "max"
        case .max:
            return "max"
        case .minimal, .low, .on:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .off, .none:
            return "low"
        }
    }

    private func isOpenAIResponsesEndpoint(_ url: URL) -> Bool {
        let canonicalPath = url.path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return canonicalPath.hasSuffix("responses")
    }

    private func openAIResponsesInput(from messagePayload: [[String: Any]]) -> [[String: Any]] {
        var input: [[String: Any]] = []
        input.reserveCapacity(messagePayload.count)

        for item in messagePayload {
            let rawRole = ((item["role"] as? String) ?? "user").lowercased()
            let role: String
            switch rawRole {
            case "assistant", "system", "developer":
                role = rawRole
            default:
                role = "user"
            }

            var parts: [[String: Any]] = []
            if let text = item["content"] as? String {
                parts.append([
                    "type": "input_text",
                    "text": text
                ])
            } else if let content = item["content"] as? [[String: Any]] {
                for part in content {
                    let partType = ((part["type"] as? String) ?? "").lowercased()
                    if partType == "text", let text = part["text"] as? String {
                        parts.append([
                            "type": "input_text",
                            "text": text
                        ])
                    } else if let dataURL = lmStudioRESTImageDataURL(from: part) {
                        parts.append([
                            "type": "input_image",
                            "image_url": dataURL
                        ])
                    }
                }
            }

            if parts.isEmpty { continue }
            input.append([
                "role": role,
                "content": parts
            ])
        }

        if input.isEmpty {
            input.append([
                "role": "user",
                "content": [
                    ["type": "input_text", "text": ""]
                ]
            ])
        }
        return input
    }

    private func resetStreamState() {
        isLegacyThinkStream = false
        sawAnyAssistantToken = false
        sawAnyPrimaryAssistantToken = false
        newFormatActive = false
        sentThinkOpen = false
        sentThinkClose = false
        streamFinishedEmitted = false
        lastProcessedSSESequenceNumber = nil
        reasoningDeltaItemIDs.removeAll(keepingCapacity: true)
        outputTextDeltaItemIDs.removeAll(keepingCapacity: true)
        anthropicThinkingActive = false
        ssePartialLine = ""
        ssePendingEventType = nil
        streamStartAt = nil
        didEstablishConnection = false
        lastDeltaAt = nil
        httpStatusCode = nil
        errorResponseData.removeAll(keepingCapacity: true)
        successResponseData.removeAll(keepingCapacity: true)
        pendingLMStudioStreamErrorMessage = nil
        pendingResponseMetadata = .empty
        stopConnectionWatchdog()
        endBackgroundExecutionForCurrentRequest()
    }

    private func clearActiveEndpointCandidate() {
        activeEndpointCandidate = nil
    }

    private func transformedMessagesForRequest(
        messages: [ChatMessage],
        developerPrompt: String?,
        includeImagesInUserContent: Bool
    ) -> [[String: Any]] {
        var payload: [[String: Any]] = []
        if let prompt = developerPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            payload.append([
                "role": "developer",
                "content": prompt
            ])
        }

        for message in messages where !message.content.hasPrefix("!error:") {
            let role = message.isUser ? "user" : "assistant"
            let textContent = message.content
            let imageAttachments = includeImagesInUserContent ? message.imageAttachments : []

            if message.isUser, !imageAttachments.isEmpty {
                var parts: [[String: Any]] = []
                if !textContent.isEmpty {
                    parts.append([
                        "type": "text",
                        "text": textContent
                    ])
                }

                for attachment in imageAttachments where !attachment.data.isEmpty {
                    parts.append([
                        "type": "image_url",
                        "image_url": [
                            "url": attachment.dataURLString
                        ]
                    ])
                }

                if !parts.isEmpty {
                    payload.append([
                        "role": role,
                        "content": parts
                    ])
                    continue
                }
            }

            payload.append([
                "role": role,
                "content": textContent
            ])
        }
        return payload
    }

    private func lmStudioRESTInput(
        from messagePayload: [[String: Any]],
        textDiscriminator: String
    ) -> Any {
        var transcriptLines: [String] = []
        transcriptLines.reserveCapacity(messagePayload.count)

        var lastUserPayloadIndex: Int?
        for (index, item) in messagePayload.enumerated() {
            if (item["role"] as? String)?.lowercased() == "user" {
                lastUserPayloadIndex = index
            }
        }

        var latestUserImages: [[String: Any]] = []
        for (index, item) in messagePayload.enumerated() {
            let role = ((item["role"] as? String) ?? "user").lowercased()
            if role == "developer" || role == "system" {
                continue
            }

            var collectedText = ""
            var collectedImages: [[String: Any]] = []

            if let text = item["content"] as? String {
                collectedText = text
            } else if let parts = item["content"] as? [[String: Any]] {
                for part in parts {
                    let partType = ((part["type"] as? String) ?? "").lowercased()
                    if partType == "text" {
                        if let text = part["text"] as? String {
                            collectedText += text
                        }
                    } else if let dataURL = lmStudioRESTImageDataURL(from: part) {
                        collectedImages.append([
                            "type": "image",
                            "data_url": dataURL
                        ])
                    }
                }
            }

            let trimmedText = collectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                let speaker = role == "assistant" ? "Assistant" : "User"
                transcriptLines.append("\(speaker): \(trimmedText)")
            }

            if role == "user", index == lastUserPayloadIndex, !collectedImages.isEmpty {
                latestUserImages = collectedImages
            }
        }

        let transcript = transcriptLines.joined(separator: "\n\n")
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        // LM Studio `/api/v1/chat` accepts plain strings, which avoids discriminator mismatches
        // when a text-only request is sent to different server versions.
        if latestUserImages.isEmpty {
            return trimmedTranscript.isEmpty ? "" : transcript
        }

        var input: [[String: Any]] = []
        if !trimmedTranscript.isEmpty {
            input.append([
                "type": textDiscriminator,
                "content": transcript
            ])
        }
        input.append(contentsOf: latestUserImages)
        return input
    }

    private func lmStudioRESTImageDataURL(from part: [String: Any]) -> String? {
        if let dataURL = part["data_url"] as? String,
           !dataURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return dataURL
        }

        let partType = ((part["type"] as? String) ?? "").lowercased()
        guard partType == "image_url" else { return nil }

        guard let imageURL = part["image_url"] as? [String: Any],
              let urlString = imageURL["url"] as? String else {
            return nil
        }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseDataURL(_ raw: String) -> (mimeType: String, base64Data: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("data:"),
              let separator = trimmed.firstIndex(of: ",") else {
            return nil
        }
        let header = String(trimmed[..<separator])
        let payload = String(trimmed[trimmed.index(after: separator)...])
        guard !payload.isEmpty else { return nil }

        let mediaAndEncoding = String(header.dropFirst("data:".count))
        let parts = mediaAndEncoding.split(separator: ";")
        guard let media = parts.first, !media.isEmpty else { return nil }
        let isBase64 = parts.dropFirst().contains { $0.caseInsensitiveCompare("base64") == .orderedSame }
        guard isBase64 else { return nil }
        return (mimeType: String(media), base64Data: payload)
    }

    private func anthropicMessagesInput(from messagePayload: [[String: Any]]) -> [[String: Any]] {
        var output: [[String: Any]] = []
        output.reserveCapacity(messagePayload.count)

        for item in messagePayload {
            let rawRole = ((item["role"] as? String) ?? "").lowercased()
            guard rawRole == "user" || rawRole == "assistant" else { continue }

            var contentParts: [[String: Any]] = []
            if let text = item["content"] as? String {
                if !text.isEmpty {
                    contentParts.append(["type": "text", "text": text])
                }
            } else if let parts = item["content"] as? [[String: Any]] {
                for part in parts {
                    let partType = ((part["type"] as? String) ?? "").lowercased()
                    if partType == "text" {
                        if let text = part["text"] as? String, !text.isEmpty {
                            contentParts.append(["type": "text", "text": text])
                        }
                        continue
                    }

                    guard let dataURL = lmStudioRESTImageDataURL(from: part),
                          let parsed = parseDataURL(dataURL) else {
                        continue
                    }
                    contentParts.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": parsed.mimeType,
                            "data": parsed.base64Data
                        ]
                    ])
                }
            }

            if contentParts.isEmpty {
                continue
            }
            output.append([
                "role": rawRole,
                "content": contentParts
            ])
        }

        if output.isEmpty {
            output.append([
                "role": "user",
                "content": [
                    ["type": "text", "text": ""]
                ]
            ])
        }
        return output
    }

    private func prioritizeEndpointCandidates(
        _ candidates: [ChatAPIEndpointCandidate],
        preferredStyle: ChatRequestStyle?
    ) -> [ChatAPIEndpointCandidate] {
        guard let preferredStyle else { return candidates }
        return candidates.enumerated().sorted { lhs, rhs in
            let lhsPreferred = lhs.element.style == preferredStyle
            let rhsPreferred = rhs.element.style == preferredStyle
            if lhsPreferred != rhsPreferred {
                return lhsPreferred && !rhsPreferred
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func normalizedTokenCount(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return Int(value.rounded())
    }

    private func mergeResponseMetadata(_ update: ChatResponseMetadata) {
        pendingResponseMetadata.merge(update)
        let snapshot = pendingResponseMetadata
        Task { @MainActor in self.onResponseMetadata?(snapshot) }
    }

    private func extractResponseMetadata(from dictionary: [String: Any], style: ChatRequestStyle) -> ChatResponseMetadata {
        switch style {
        case .openAIChatCompletions:
            var metadata = ChatResponseMetadata.empty
            if let responseID = dictionary["id"] as? String,
               !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.providerResponseID = responseID
            }
            if metadata.providerResponseID == nil,
               let responseID = dictionary["response_id"] as? String,
               !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.providerResponseID = responseID
            }
            if let usage = dictionary["usage"] as? [String: Any] {
                if let output = usage["completion_tokens"] as? NSNumber {
                    metadata.outputTokenCount = output.intValue
                }
                if metadata.outputTokenCount == nil,
                   let output = usage["output_tokens"] as? NSNumber {
                    metadata.outputTokenCount = output.intValue
                }
                if let details = usage["completion_tokens_details"] as? [String: Any],
                   let reasoning = details["reasoning_tokens"] as? NSNumber {
                    metadata.reasoningOutputTokenCount = reasoning.intValue
                }
                if metadata.reasoningOutputTokenCount == nil,
                   let details = usage["output_tokens_details"] as? [String: Any],
                   let reasoning = details["reasoning_tokens"] as? NSNumber {
                    metadata.reasoningOutputTokenCount = reasoning.intValue
                }
            }
            if let timings = dictionary["timings"] as? [String: Any] {
                if metadata.outputTokenCount == nil,
                   let predictedN = timings["predicted_n"] as? NSNumber {
                    metadata.outputTokenCount = predictedN.intValue
                }
                if metadata.tokensPerSecond == nil,
                   let predictedPerSecond = timings["predicted_per_second"] as? NSNumber {
                    metadata.tokensPerSecond = predictedPerSecond.doubleValue
                }
                if metadata.timeToFirstTokenSeconds == nil,
                   let ttf = timings["time_to_first_token_seconds"] as? NSNumber {
                    metadata.timeToFirstTokenSeconds = ttf.doubleValue
                }
            }
            if let choices = dictionary["choices"] as? [[String: Any]],
               let first = choices.first,
               let finish = first["finish_reason"] as? String,
               !finish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.finishReason = finish
            }

            if let response = dictionary["response"] as? [String: Any] {
                if metadata.providerResponseID == nil,
                   let responseID = response["id"] as? String,
                   !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    metadata.providerResponseID = responseID
                }
                if let usage = response["usage"] as? [String: Any] {
                    if metadata.outputTokenCount == nil {
                        if let output = usage["completion_tokens"] as? NSNumber {
                            metadata.outputTokenCount = output.intValue
                        } else if let output = usage["output_tokens"] as? NSNumber {
                            metadata.outputTokenCount = output.intValue
                        }
                    }
                    if metadata.reasoningOutputTokenCount == nil {
                        if let details = usage["completion_tokens_details"] as? [String: Any],
                           let reasoning = details["reasoning_tokens"] as? NSNumber {
                            metadata.reasoningOutputTokenCount = reasoning.intValue
                        } else if let details = usage["output_tokens_details"] as? [String: Any],
                                  let reasoning = details["reasoning_tokens"] as? NSNumber {
                            metadata.reasoningOutputTokenCount = reasoning.intValue
                        }
                    }
                }
                if metadata.finishReason == nil,
                   let status = response["status"] as? String,
                   !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    metadata.finishReason = status
                }
            }
            return metadata

        case .anthropicMessages:
            var metadata = ChatResponseMetadata.empty
            if let responseID = dictionary["id"] as? String,
               !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.providerResponseID = responseID
            } else if let message = dictionary["message"] as? [String: Any],
                      let responseID = message["id"] as? String,
                      !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.providerResponseID = responseID
            }
            if let usage = dictionary["usage"] as? [String: Any] {
                if let output = usage["output_tokens"] as? NSNumber {
                    metadata.outputTokenCount = output.intValue
                }
            } else if let message = dictionary["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] {
                if let output = usage["output_tokens"] as? NSNumber {
                    metadata.outputTokenCount = output.intValue
                }
            }
            if let stopReason = dictionary["stop_reason"] as? String,
               !stopReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.finishReason = stopReason
            } else if let message = dictionary["message"] as? [String: Any],
                      let stopReason = message["stop_reason"] as? String,
                      !stopReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.finishReason = stopReason
            }
            return metadata

        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            var metadata = ChatResponseMetadata.empty
            if let responseID = dictionary["response_id"] as? String,
               !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.providerResponseID = responseID
            }

            if let stats = dictionary["stats"] as? [String: Any] {
                if let output = stats["total_output_tokens"] as? NSNumber {
                    metadata.outputTokenCount = output.intValue
                }
                if let reasoning = stats["reasoning_output_tokens"] as? NSNumber {
                    metadata.reasoningOutputTokenCount = reasoning.intValue
                }
                if let tps = stats["tokens_per_second"] as? NSNumber {
                    metadata.tokensPerSecond = tps.doubleValue
                }
                if let ttf = stats["time_to_first_token_seconds"] as? NSNumber {
                    metadata.timeToFirstTokenSeconds = ttf.doubleValue
                }
            }

            if let result = dictionary["result"] as? [String: Any] {
                if metadata.providerResponseID == nil,
                   let responseID = result["response_id"] as? String,
                   !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    metadata.providerResponseID = responseID
                }
                if let stats = result["stats"] as? [String: Any] {
                    if metadata.outputTokenCount == nil, let output = stats["total_output_tokens"] as? NSNumber {
                        metadata.outputTokenCount = output.intValue
                    }
                    if metadata.reasoningOutputTokenCount == nil, let reasoning = stats["reasoning_output_tokens"] as? NSNumber {
                        metadata.reasoningOutputTokenCount = reasoning.intValue
                    }
                    if metadata.tokensPerSecond == nil, let tps = stats["tokens_per_second"] as? NSNumber {
                        metadata.tokensPerSecond = tps.doubleValue
                    }
                    if metadata.timeToFirstTokenSeconds == nil, let ttf = stats["time_to_first_token_seconds"] as? NSNumber {
                        metadata.timeToFirstTokenSeconds = ttf.doubleValue
                    }
                }
            }

            if let response = dictionary["response"] as? [String: Any] {
                if metadata.providerResponseID == nil,
                   let responseID = response["response_id"] as? String,
                   !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    metadata.providerResponseID = responseID
                }
                if let stats = response["stats"] as? [String: Any] {
                    if metadata.outputTokenCount == nil, let output = stats["total_output_tokens"] as? NSNumber {
                        metadata.outputTokenCount = output.intValue
                    }
                    if metadata.reasoningOutputTokenCount == nil, let reasoning = stats["reasoning_output_tokens"] as? NSNumber {
                        metadata.reasoningOutputTokenCount = reasoning.intValue
                    }
                    if metadata.tokensPerSecond == nil, let tps = stats["tokens_per_second"] as? NSNumber {
                        metadata.tokensPerSecond = tps.doubleValue
                    }
                    if metadata.timeToFirstTokenSeconds == nil, let ttf = stats["time_to_first_token_seconds"] as? NSNumber {
                        metadata.timeToFirstTokenSeconds = ttf.doubleValue
                    }
                }
            }
            return metadata
        }
    }

    private func parseBufferedSuccessResponse(_ data: Data, style: ChatRequestStyle) -> (text: String?, errorMessage: String?, metadata: ChatResponseMetadata) {
        guard !data.isEmpty else { return (nil, nil, .empty) }
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty else {
            return (nil, nil, .empty)
        }
        guard let first = raw.first, first == "{" || first == "[" else {
            // Likely SSE frames (`event:` / `data:`), not a plain JSON response body.
            return (nil, nil, .empty)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any] else {
            return (nil, nil, .empty)
        }
        let metadata = extractResponseMetadata(from: dictionary, style: style)

        if let errorObject = dictionary["error"] as? [String: Any],
           let message = errorObject["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return (nil, trimmed, metadata)
            }
        }
        if let directMessage = dictionary["message"] as? String {
            let trimmed = directMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, dictionary["output"] == nil, dictionary["choices"] == nil {
                return (nil, trimmed, metadata)
            }
        }

        let recoveredText: String?
        switch style {
        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            recoveredText = extractLMStudioAssistantText(from: dictionary)
        case .openAIChatCompletions:
            recoveredText = extractOpenAIAssistantText(from: dictionary)
        case .anthropicMessages:
            recoveredText = extractAnthropicAssistantText(from: dictionary)
        }

        if let text = recoveredText {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return (trimmed, nil, metadata)
            }
        }

        return (nil, nil, metadata)
    }

    private func extractLMStudioAssistantText(from dictionary: [String: Any]) -> String? {
        if let output = dictionary["output"] as? [[String: Any]],
           let text = extractLMStudioOutputText(output) {
            return text
        }

        if let result = dictionary["result"] as? [String: Any],
           let output = result["output"] as? [[String: Any]],
           let text = extractLMStudioOutputText(output) {
            return text
        }

        if let response = dictionary["response"] as? [String: Any],
           let output = response["output"] as? [[String: Any]],
           let text = extractLMStudioOutputText(output) {
            return text
        }

        return nil
    }

    private func extractOpenAIAssistantText(from dictionary: [String: Any]) -> String? {
        if let output = dictionary["output"] as? [[String: Any]],
           let text = extractOpenAIResponseOutputText(output) {
            return text
        }

        if let response = dictionary["response"] as? [String: Any] {
            if let output = response["output"] as? [[String: Any]],
               let text = extractOpenAIResponseOutputText(output) {
                return text
            }
            if let outputText = response["output_text"] {
                let text = flattenedText(from: outputText).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
            if let textValue = response["text"] {
                let text = flattenedText(from: textValue).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }

        if let item = dictionary["item"] as? [String: Any] {
            let itemType = ((item["type"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if itemType == "reasoning" || itemType.contains("tool") {
                return nil
            }
            if let content = item["content"] {
                let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
            if let textValue = item["text"] {
                let text = flattenedText(from: textValue).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }

        if let choices = dictionary["choices"] as? [[String: Any]] {
            for choice in choices {
                if let message = choice["message"] as? [String: Any],
                   let content = message["content"] {
                    let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        return text
                    }
                }
                if let delta = choice["delta"] as? [String: Any],
                   let content = delta["content"] {
                    let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        return text
                    }
                }
            }
        }

        if let outputText = dictionary["output_text"] {
            let text = flattenedText(from: outputText).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }

        if let textValue = dictionary["text"] {
            let text = flattenedText(from: textValue).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }

        if let content = dictionary["content"] {
            let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }

        if let message = dictionary["message"] as? [String: Any],
           let content = message["content"] {
            let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }

        return nil
    }

    private func extractOpenAIResponseOutputText(_ output: [[String: Any]]) -> String? {
        for item in output {
            let itemType = ((item["type"] as? String) ?? "").lowercased()

            if itemType == "message" || itemType.isEmpty {
                if let content = item["content"] as? [[String: Any]] {
                    let merged = content.compactMap { part -> String? in
                        let partType = ((part["type"] as? String) ?? "").lowercased()
                        guard partType == "output_text" || partType == "text" || partType.isEmpty else {
                            return nil
                        }
                        if let text = part["text"] as? String, !text.isEmpty {
                            return text
                        }
                        if let content = part["content"] as? String, !content.isEmpty {
                            return content
                        }
                        return nil
                    }
                        .joined()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !merged.isEmpty {
                        return merged
                    }
                }

                if let content = item["content"] {
                    let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        return text
                    }
                }
            }

            if itemType == "output_text" || itemType == "text" {
                if let text = item["text"] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
                if let content = item["content"] {
                    let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        return text
                    }
                }
            }
        }
        return nil
    }

    private func extractAnthropicAssistantText(from dictionary: [String: Any]) -> String? {
        if let content = dictionary["content"] as? [[String: Any]] {
            let merged = content
                .compactMap { part -> String? in
                    let partType = ((part["type"] as? String) ?? "").lowercased()
                    guard partType == "text" || partType.isEmpty else { return nil }
                    if let text = part["text"] as? String, !text.isEmpty {
                        return text
                    }
                    if let text = part["content"] as? String, !text.isEmpty {
                        return text
                    }
                    return nil
                }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !merged.isEmpty {
                return merged
            }
        }

        if let message = dictionary["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            let merged = content
                .compactMap { part -> String? in
                    let partType = ((part["type"] as? String) ?? "").lowercased()
                    guard partType == "text" || partType.isEmpty else { return nil }
                    if let text = part["text"] as? String, !text.isEmpty {
                        return text
                    }
                    if let text = part["content"] as? String, !text.isEmpty {
                        return text
                    }
                    return nil
                }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !merged.isEmpty {
                return merged
            }
        }

        return nil
    }

    private func extractLMStudioOutputText(_ output: [[String: Any]]) -> String? {
        for item in output {
            let type = ((item["type"] as? String) ?? "").lowercased()
            if type == "reasoning" || type == "tool_call" || type == "invalid_tool_call" {
                continue
            }
            if let content = item["content"] {
                let text = flattenedText(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
            if let text = item["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            if let message = item["message"] {
                let text = flattenedText(from: message).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private func flattenedText(from value: Any) -> String {
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let array = value as? [Any] {
            return array.map(flattenedText(from:)).joined()
        }
        if let dictionary = value as? [String: Any] {
            if let text = dictionary["text"] as? String, !text.isEmpty {
                return text
            }
            if let content = dictionary["content"] as? String, !content.isEmpty {
                return content
            }
            return dictionary.values.map(flattenedText(from:)).joined()
        }
        return ""
    }

    // MARK: - URLSession Data Delegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let currentTask = self.dataTask, dataTask === currentTask else {
            completionHandler(.cancel)
            return
        }
        markConnectionEstablishedIfNeeded()
        if let http = response as? HTTPURLResponse {
            httpStatusCode = http.statusCode
            if !(200...299).contains(http.statusCode) {
                errorResponseData.removeAll(keepingCapacity: true)
            }
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData _: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend _: Int64
    ) {
        guard let currentTask = self.dataTask, task === currentTask else { return }
        guard totalBytesSent > 0 else { return }
        markConnectionEstablishedIfNeeded()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let currentTask = self.dataTask, dataTask === currentTask else { return }
        guard !isCancelled else { return }
        markConnectionEstablishedIfNeeded()

        if let status = httpStatusCode, !(200...299).contains(status) {
            if errorResponseData.count < errorBodyCaptureLimit {
                let remaining = errorBodyCaptureLimit - errorResponseData.count
                errorResponseData.append(data.prefix(remaining))
            }
            return
        }

        if successResponseData.count < successBodyCaptureLimit {
            let remaining = successBodyCaptureLimit - successResponseData.count
            successResponseData.append(data.prefix(remaining))
        }

        let chunk = String(decoding: data, as: UTF8.self)
        ssePartialLine += chunk

        if ssePartialLine.utf8.count > maxBufferedSSEBytes {
            isCancelled = true
            dataTask.cancel()
            stopWatchdog()
            Task { @MainActor in
                self.onError?(ChatNetworkError.serverError(
                    statusCode: nil,
                    message: NSLocalizedString("Stream payload exceeded safety limit", comment: "Shown when streamed SSE data exceeds the configured memory safety cap")
                ))
            }
            return
        }

        let lines = ssePartialLine.split(
            maxSplits: Int.max,
            omittingEmptySubsequences: false,
            whereSeparator: { $0.isNewline }
        )

        var processCount = lines.count
        if let last = ssePartialLine.last, last != "\n" && last != "\r" {
            processCount -= 1
        }

        for i in 0..<max(0, processCount) {
            guard !isCancelled else { return }
            let line = String(lines[i]).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                ssePendingEventType = nil
                continue
            }
            if line.hasPrefix("event:") {
                let eventType = String(line.dropFirst("event:".count))
                    .trimmingCharacters(in: .whitespaces)
                ssePendingEventType = eventType.isEmpty ? nil : eventType
                continue
            }
            guard line.hasPrefix("data:") else { continue }

            let payloadString = String(line.dropFirst("data:".count))
                .trimmingCharacters(in: CharacterSet.whitespaces)

            if payloadString == "[DONE]" {
                ssePendingEventType = nil
                if self.newFormatActive && self.sentThinkOpen && !self.sentThinkClose && !self.isLegacyThinkStream {
                    self.emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                    self.sentThinkClose = true
                }
                if self.sawAnyPrimaryAssistantToken {
                    emitStreamFinishedOnce()
                    stopWatchdog()
                }
                return
            }

            guard let jsonData = payloadString.data(using: String.Encoding.utf8) else { continue }
            let activeStyle = activeEndpointCandidate?.style ?? .openAIChatCompletions

            switch activeStyle {
            case .openAIChatCompletions:
                if self.handleOpenAICompatibleStreamPayload(jsonData, fallbackType: ssePendingEventType) {
                    ssePendingEventType = nil
                }

            case .anthropicMessages:
                if let anthropicEvent = try? decoder.decode(AnthropicStreamEvent.self, from: jsonData),
                   anthropicEvent.type != nil {
                    ssePendingEventType = nil
                    self.handleAnthropicStreamEvent(anthropicEvent)
                }

            case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
                if let lmStudioEvent = try? decoder.decode(LMStudioChatStreamEvent.self, from: jsonData) {
                    self.handleLMStudioStreamEvent(lmStudioEvent, fallbackType: ssePendingEventType)
                    ssePendingEventType = nil
                }
            }
        }

        if processCount >= 0 {
            let remainder = lines.suffix(from: max(0, processCount)).joined(separator: "\n")
            ssePartialLine = remainder
        }
    }

    private func handleOpenAICompatibleStreamPayload(_ jsonData: Data, fallbackType: String?) -> Bool {
        if let decoded = try? decoder.decode(ChatCompletionChunk.self, from: jsonData),
           decoded.choices != nil || decoded.usage != nil || decoded.id != nil || decoded.timings != nil {
            handleDecodedChunk(decoded)
            return true
        }

        guard let object = try? JSONSerialization.jsonObject(with: jsonData, options: []),
              let dictionary = object as? [String: Any] else {
            return false
        }

        if let sequenceNumber = extractSSESequenceNumber(from: dictionary) {
            if let lastProcessed = lastProcessedSSESequenceNumber, sequenceNumber <= lastProcessed {
                return true
            }
            lastProcessedSSESequenceNumber = sequenceNumber
        }

        if let streamError = extractSSEStreamErrorMessage(from: dictionary) {
            failCurrentStreamWithServerError(streamError)
            return true
        }

        let metadata = extractResponseMetadata(from: dictionary, style: .openAIChatCompletions)
        if metadata.hasAnyValue {
            mergeResponseMetadata(metadata)
        }

        let rawType = (dictionary["type"] as? String) ?? fallbackType ?? ""
        let eventType = rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if eventType.isEmpty {
            if let chunk = extractOpenAICompatibleStreamDeltaText(from: dictionary), !chunk.isEmpty {
                emitDelta(chunk)
                return true
            }
            return metadata.hasAnyValue
        }

        switch eventType {
        case "response.created", "response.in_progress", "response.output_item.added", "response.content_part.added":
            return true

        case "response.reasoning_text.delta":
            newFormatActive = true
            if !isLegacyThinkStream && !sentThinkOpen {
                emitDelta(thinkOpenLine, marksPrimaryOutput: false)
                sentThinkOpen = true
            }
            if let itemID = extractSSEItemID(from: dictionary) {
                reasoningDeltaItemIDs.insert(itemID)
            }
            if let chunk = extractOpenAICompatibleStreamDeltaText(from: dictionary), !chunk.isEmpty {
                emitDelta(chunk, marksPrimaryOutput: false)
            }
            return true

        case "response.reasoning_text.done":
            newFormatActive = true
            if !isLegacyThinkStream && !sentThinkOpen {
                emitDelta(thinkOpenLine, marksPrimaryOutput: false)
                sentThinkOpen = true
            }
            let itemID = extractSSEItemID(from: dictionary)
            let sawReasoningDeltaForItem: Bool
            if let itemID {
                sawReasoningDeltaForItem = reasoningDeltaItemIDs.contains(itemID)
            } else {
                sawReasoningDeltaForItem = !reasoningDeltaItemIDs.isEmpty
            }
            if !sawReasoningDeltaForItem,
               let chunk = extractOpenAICompatibleStreamDeltaText(from: dictionary),
               !chunk.isEmpty {
                emitDelta(chunk, marksPrimaryOutput: false)
            }
            return true

        case "response.output_text.delta", "response.content_part.delta", "response.delta", "message.delta":
            if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                sentThinkClose = true
            }
            if let itemID = extractSSEItemID(from: dictionary) {
                outputTextDeltaItemIDs.insert(itemID)
            }
            if let chunk = extractOpenAICompatibleStreamDeltaText(from: dictionary), !chunk.isEmpty {
                emitDelta(chunk)
            }
            return true

        case "response.output_text.done", "response.content_part.done":
            if eventType == "response.content_part.done",
               let partType = extractSSEPartType(from: dictionary),
               partType.contains("reasoning") {
                return true
            }
            if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                sentThinkClose = true
            }
            let itemID = extractSSEItemID(from: dictionary)
            let sawOutputDeltaForItem: Bool
            if let itemID {
                sawOutputDeltaForItem = outputTextDeltaItemIDs.contains(itemID)
            } else {
                sawOutputDeltaForItem = false
            }
            if !sawOutputDeltaForItem,
               !sawAnyPrimaryAssistantToken,
               let chunk = extractOpenAICompatibleStreamDeltaText(from: dictionary),
               !chunk.isEmpty {
                emitDelta(chunk)
            }
            return true

        case "response.output_item.done":
            if let itemType = extractSSEItemType(from: dictionary),
               (itemType.contains("reasoning") || itemType.contains("tool")) {
                return true
            }
            if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                sentThinkClose = true
            }
            if !sawAnyPrimaryAssistantToken {
                if let chunk = extractOpenAICompatibleStreamDeltaText(from: dictionary),
                   !chunk.isEmpty {
                    emitDelta(chunk)
                } else if let recovered = extractOpenAIAssistantText(from: dictionary),
                          !recovered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emitDelta(recovered)
                }
            }
            return true

        case "response.completed", "response.done":
            if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                sentThinkClose = true
            }
            if !sawAnyPrimaryAssistantToken {
                if let response = dictionary["response"] as? [String: Any],
                   let recovered = extractOpenAIAssistantText(from: response),
                   !recovered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emitDelta(recovered)
                } else if let recovered = extractOpenAIAssistantText(from: dictionary),
                          !recovered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emitDelta(recovered)
                }
            }
            if sawAnyPrimaryAssistantToken || sawAnyAssistantToken {
                emitStreamFinishedOnce()
                stopWatchdog()
            }
            return true

        case "response.failed", "error":
            let message = extractOpenAICompatibleStreamErrorMessage(from: dictionary) ?? NSLocalizedString(
                "OpenAI Compatible API error",
                comment: "Fallback error shown when OpenAI-compatible stream returns an error event without a message"
            )
            failCurrentStreamWithServerError(message)
            return true

        default:
            if let chunk = extractOpenAICompatibleStreamDeltaText(from: dictionary), !chunk.isEmpty {
                if eventType.contains("reasoning") {
                    newFormatActive = true
                    if !isLegacyThinkStream && !sentThinkOpen {
                        emitDelta(thinkOpenLine, marksPrimaryOutput: false)
                        sentThinkOpen = true
                    }
                    emitDelta(chunk, marksPrimaryOutput: false)
                } else {
                    if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                        emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                        sentThinkClose = true
                    }
                    emitDelta(chunk)
                }
                return true
            }
            if !sawAnyPrimaryAssistantToken,
               let recovered = extractOpenAIAssistantText(from: dictionary),
               !recovered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                    emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                    sentThinkClose = true
                }
                emitDelta(recovered)
                return true
            }
            return metadata.hasAnyValue
        }
    }

    private func extractSSESequenceNumber(from dictionary: [String: Any]) -> Int? {
        if let number = dictionary["sequence_number"] as? NSNumber {
            return number.intValue
        }
        if let number = dictionary["sequence_number"] as? Int {
            return number
        }
        if let raw = dictionary["sequence_number"] as? String {
            return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func extractSSEItemID(from dictionary: [String: Any]) -> String? {
        if let itemID = dictionary["item_id"] as? String {
            let trimmed = itemID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        if let item = dictionary["item"] as? [String: Any],
           let itemID = item["id"] as? String {
            let trimmed = itemID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func extractSSEItemType(from dictionary: [String: Any]) -> String? {
        guard let item = dictionary["item"] as? [String: Any],
              let type = item["type"] as? String else {
            return nil
        }
        let normalized = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func extractSSEPartType(from dictionary: [String: Any]) -> String? {
        guard let part = dictionary["part"] as? [String: Any],
              let type = part["type"] as? String else {
            return nil
        }
        let normalized = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func extractOpenAICompatibleStreamDeltaText(from dictionary: [String: Any]) -> String? {
        func extract(_ value: Any?) -> String? {
            guard let value else { return nil }
            let text = flattenedText(from: value)
            return text.isEmpty ? nil : text
        }

        let itemCandidate: [String: Any]? = {
            guard let item = dictionary["item"] as? [String: Any] else { return nil }
            let itemType = ((item["type"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if itemType == "reasoning" || itemType.contains("tool") {
                return nil
            }
            return item
        }()

        let directCandidates: [Any?] = [
            dictionary["delta"],
            dictionary["text"],
            dictionary["output_text"],
            dictionary["content"],
            itemCandidate?["text"],
            itemCandidate?["output_text"],
            itemCandidate?["content"],
            (dictionary["part"] as? [String: Any])?["text"],
            (dictionary["part"] as? [String: Any])?["content"]
        ]
        for candidate in directCandidates {
            if let text = extract(candidate) {
                return text
            }
        }

        if let choices = dictionary["choices"] as? [[String: Any]] {
            for choice in choices {
                if let delta = choice["delta"] as? [String: Any],
                   let text = extract(delta["content"]) {
                    return text
                }
                if let message = choice["message"] as? [String: Any],
                   let text = extract(message["content"]) {
                    return text
                }
                if let text = extract(choice["text"]) {
                    return text
                }
                if let text = extract(choice["content"]) {
                    return text
                }
            }
        }

        if let response = dictionary["response"] as? [String: Any] {
            if let text = extract(response["output_text"]) {
                return text
            }
            if let text = extract(response["text"]) {
                return text
            }
            if let output = response["output"] as? [[String: Any]],
               let text = extractOpenAIResponseOutputText(output) {
                return text
            }
        }
        return nil
    }

    private func extractOpenAICompatibleStreamErrorMessage(from dictionary: [String: Any]) -> String? {
        if let error = dictionary["error"] as? [String: Any],
           let message = error["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let message = dictionary["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private func extractSSEStreamErrorMessage(from dictionary: [String: Any]) -> String? {
        if let errorObject = dictionary["error"] as? [String: Any],
           let message = errorObject["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        if let type = dictionary["type"] as? String,
           type.lowercased().contains("error"),
           let message = dictionary["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        return nil
    }

    private func extractSSEStreamErrorMessage(from rawBodyData: Data) -> String? {
        guard !rawBodyData.isEmpty,
              let rawBody = String(data: rawBodyData, encoding: .utf8),
              !rawBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let lines = rawBody.split(whereSeparator: \.isNewline)
        for rawLine in lines {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, payload != "[DONE]",
                  let payloadData = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: payloadData, options: []),
                  let dictionary = object as? [String: Any] else {
                continue
            }
            if let message = extractSSEStreamErrorMessage(from: dictionary) {
                return message
            }
        }

        return nil
    }

    private func failCurrentStreamWithServerError(_ message: String) {
        isCancelled = true
        dataTask?.cancel()
        dataTask = nil
        stopConnectionWatchdog()
        stopWatchdog()
        clearActiveEndpointCandidate()
        endBackgroundExecutionForCurrentRequest()
        Task { @MainActor in
            self.onError?(ChatNetworkError.serverError(statusCode: httpStatusCode, message: message))
        }
    }

    private func handleDecodedChunk(_ chunk: ChatCompletionChunk) {
        guard !isCancelled else { return }
        var metadata = ChatResponseMetadata.empty
        if let responseID = chunk.id,
           !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata.providerResponseID = responseID
        }
        if let usage = chunk.usage {
            metadata.outputTokenCount = usage.completion_tokens
            metadata.reasoningOutputTokenCount = usage.completion_tokens_details?.reasoning_tokens
        }
        if let timings = chunk.timings {
            if metadata.outputTokenCount == nil, let predictedN = timings.predicted_n {
                metadata.outputTokenCount = predictedN
            }
            if metadata.tokensPerSecond == nil, let predictedPerSecond = timings.predicted_per_second {
                metadata.tokensPerSecond = predictedPerSecond
            }
        }

        for choice in chunk.choices ?? [] {
            guard !isCancelled else { return }
            if metadata.finishReason == nil,
               let finishReason = choice.finish_reason,
               !finishReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.finishReason = finishReason
            }
            guard let delta = choice.delta else { continue }

            let deltaText = delta.content ?? ""

            if deltaText.contains("<think>") || deltaText.contains("</think>") {
                isLegacyThinkStream = true
            }

            var reasoningText = delta.reasoning?.text ?? ""
            if reasoningText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reasoningText = delta.reasoning_content ?? ""
            }
            if !reasoningText.isEmpty {
                newFormatActive = true
                if !isLegacyThinkStream && !sentThinkOpen {
                    emitDelta(thinkOpenLine, marksPrimaryOutput: false)
                    sentThinkOpen = true
                }
                emitDelta(reasoningText, marksPrimaryOutput: false)
            }

            if !deltaText.isEmpty {
                if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                    emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                    sentThinkClose = true
                }
                emitDelta(deltaText)
            }
        }

        if metadata.hasAnyValue {
            mergeResponseMetadata(metadata)
        }
    }

    private func handleAnthropicStreamEvent(_ event: AnthropicStreamEvent) {
        guard !isCancelled else { return }
        guard let rawType = event.type?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawType.isEmpty else {
            return
        }

        var metadata = ChatResponseMetadata.empty
        if let responseID = event.message?.id,
           !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata.providerResponseID = responseID
        }
        let usage = event.usage ?? event.message?.usage
        if let usage {
            metadata.outputTokenCount = usage.output_tokens
        }
        if let stopReason = event.delta?.stop_reason ?? event.message?.stop_reason,
           !stopReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata.finishReason = stopReason
        }
        if metadata.hasAnyValue {
            mergeResponseMetadata(metadata)
        }

        switch rawType.lowercased() {
        case "content_block_start":
            let blockType = (event.content_block?.type ?? "").lowercased()
            if blockType.contains("thinking") {
                if !sentThinkOpen {
                    emitDelta(thinkOpenLine, marksPrimaryOutput: false)
                    sentThinkOpen = true
                }
                anthropicThinkingActive = true
                if let thinking = event.content_block?.thinking, !thinking.isEmpty {
                    emitDelta(thinking, marksPrimaryOutput: false)
                }
            } else if blockType == "text" {
                if anthropicThinkingActive && sentThinkOpen && !sentThinkClose {
                    emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                    sentThinkClose = true
                    anthropicThinkingActive = false
                }
                if let text = event.content_block?.text, !text.isEmpty {
                    emitDelta(text)
                }
            }

        case "content_block_delta":
            let deltaType = (event.delta?.type ?? "").lowercased()
            if deltaType.contains("thinking") {
                if !sentThinkOpen {
                    emitDelta(thinkOpenLine, marksPrimaryOutput: false)
                    sentThinkOpen = true
                }
                anthropicThinkingActive = true
                let thinking = event.delta?.thinking ?? event.delta?.text ?? ""
                if !thinking.isEmpty {
                    emitDelta(thinking, marksPrimaryOutput: false)
                }
            } else {
                if anthropicThinkingActive && sentThinkOpen && !sentThinkClose {
                    emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                    sentThinkClose = true
                    anthropicThinkingActive = false
                }
                if let text = event.delta?.text, !text.isEmpty {
                    emitDelta(text)
                }
            }

        case "content_block_stop":
            if anthropicThinkingActive && sentThinkOpen && !sentThinkClose {
                emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                sentThinkClose = true
                anthropicThinkingActive = false
            }

        case "message_stop":
            if anthropicThinkingActive && sentThinkOpen && !sentThinkClose {
                emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                sentThinkClose = true
                anthropicThinkingActive = false
            }
            emitStreamFinishedOnce()
            stopWatchdog()

        case "error":
            let message = event.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = (message?.isEmpty == false) ? message! : NSLocalizedString(
                "Anthropic API error",
                comment: "Fallback error shown when Anthropic stream returns an error event without a message"
            )
            isCancelled = true
            dataTask?.cancel()
            dataTask = nil
            stopConnectionWatchdog()
            stopWatchdog()
            clearActiveEndpointCandidate()
            endBackgroundExecutionForCurrentRequest()
            Task { @MainActor in
                self.onError?(ChatNetworkError.serverError(statusCode: nil, message: resolved))
            }

        default:
            break
        }
    }

    private func handleLMStudioStreamEvent(_ event: LMStudioChatStreamEvent, fallbackType: String? = nil) {
        guard !isCancelled else { return }
        let resolvedType = event.type ?? fallbackType
        guard let rawType = resolvedType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawType.isEmpty else { return }

        var metadata = ChatResponseMetadata.empty
        if let responseID = event.response_id ?? event.result?.response_id ?? event.response?.response_id,
           !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata.providerResponseID = responseID
        }
        if let stats = event.stats ?? event.result?.stats ?? event.response?.stats {
            metadata.outputTokenCount = normalizedTokenCount(stats.total_output_tokens)
            metadata.reasoningOutputTokenCount = normalizedTokenCount(stats.reasoning_output_tokens)
            metadata.tokensPerSecond = stats.tokens_per_second
            metadata.timeToFirstTokenSeconds = stats.time_to_first_token_seconds
        }
        if metadata.hasAnyValue {
            mergeResponseMetadata(metadata)
        }

        switch rawType.lowercased() {
        case "reasoning.start":
            newFormatActive = true
            if !isLegacyThinkStream && !sentThinkOpen {
                emitDelta(thinkOpenLine, marksPrimaryOutput: false)
                sentThinkOpen = true
            }

        case "reasoning.delta":
            newFormatActive = true
            if !isLegacyThinkStream && !sentThinkOpen {
                emitDelta(thinkOpenLine, marksPrimaryOutput: false)
                sentThinkOpen = true
            }
            if let content = event.content, !content.isEmpty {
                emitDelta(content, marksPrimaryOutput: false)
            }

        case "reasoning.end":
            if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                sentThinkClose = true
            }

        case "message", "message.delta", "response.output_text.delta", "response.content":
            if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                sentThinkClose = true
            }
            let chunk = [
                event.content,
                event.delta,
                event.text,
                event.output_text,
                event.response?.output_text,
                event.response?.text,
                event.response?.content
            ]
                .compactMap { $0 }
                // Preserve whitespace-only deltas (for example a standalone " " token),
                // otherwise streamed output can lose spacing between words.
                .first(where: { !$0.isEmpty })
            if let chunk {
                emitDelta(chunk)
            }

        case "chat.end", "response.completed":
            if newFormatActive && !isLegacyThinkStream && sentThinkOpen && !sentThinkClose {
                emitDelta(thinkCloseLine, marksPrimaryOutput: false)
                sentThinkClose = true
            }
            if !sawAnyPrimaryAssistantToken {
                let fullText = [
                    event.result?.primaryMessageText,
                    event.response?.primaryMessageText,
                    event.output_text,
                    event.content,
                    event.text,
                    event.delta
                ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty }) ?? ""
                if !fullText.isEmpty {
                    emitDelta(fullText)
                }
            }
            if !sawAnyPrimaryAssistantToken {
                if let pendingLMStudioStreamErrorMessage,
                   !pendingLMStudioStreamErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    isCancelled = true
                    dataTask?.cancel()
                    dataTask = nil
                    stopConnectionWatchdog()
                    clearActiveEndpointCandidate()
                    endBackgroundExecutionForCurrentRequest()
                    Task { @MainActor in
                        self.onError?(ChatNetworkError.serverError(statusCode: httpStatusCode, message: pendingLMStudioStreamErrorMessage))
                    }
                }
                stopWatchdog()
                return
            }
            emitStreamFinishedOnce()
            stopWatchdog()

        case "chat.error", "error":
            let message = event.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                pendingLMStudioStreamErrorMessage = message
            }

        default:
            break
        }
    }

    private func emitDelta(_ piece: String, marksPrimaryOutput: Bool = true) {
        guard !isCancelled else { return }
        lastDeltaAt = Date()
        Task { @MainActor in self.onDelta?(piece) }
        sawAnyAssistantToken = true
        if marksPrimaryOutput {
            sawAnyPrimaryAssistantToken = true
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let currentTask = self.dataTask, task === currentTask else { return }
        stopConnectionWatchdog()
        stopWatchdog()
        dataTask = nil
        endBackgroundExecutionForCurrentRequest()

        if isCancelled {
            return
        }
        if let status = httpStatusCode, !(200...299).contains(status) {
            let preview = String(data: errorResponseData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message: String
            if preview.isEmpty {
                message = "HTTP \(status)"
            } else {
                let snippet = preview.prefix(400)
                message = "HTTP \(status): \(snippet)"
            }
            clearActiveEndpointCandidate()
            Task { @MainActor in self.onError?(ChatNetworkError.serverError(statusCode: status, message: message)) }
            return
        }

        if let nsError = error as NSError?,
           nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            return
        }

        if let error = error {
            clearActiveEndpointCandidate()
            Task { @MainActor in self.onError?(error) }
            return
        }

        if !sawAnyPrimaryAssistantToken {
            let activeStyle = activeEndpointCandidate?.style ?? .openAIChatCompletions
            let parsedBufferedResponse = parseBufferedSuccessResponse(successResponseData, style: activeStyle)
            if parsedBufferedResponse.metadata.hasAnyValue {
                mergeResponseMetadata(parsedBufferedResponse.metadata)
            }
            if let recoveredText = parsedBufferedResponse.text,
               !recoveredText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emitDelta(recoveredText)
                emitStreamFinishedOnce()
                return
            }
            if let recoveredError = parsedBufferedResponse.errorMessage,
               !recoveredError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clearActiveEndpointCandidate()
                Task { @MainActor in
                    self.onError?(ChatNetworkError.serverError(statusCode: httpStatusCode, message: recoveredError))
                }
                return
            }
            if let recoveredSSEError = extractSSEStreamErrorMessage(from: successResponseData),
               !recoveredSSEError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clearActiveEndpointCandidate()
                Task { @MainActor in
                    self.onError?(ChatNetworkError.serverError(statusCode: httpStatusCode, message: recoveredSSEError))
                }
                return
            }
            if let pendingLMStudioStreamErrorMessage,
               !pendingLMStudioStreamErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clearActiveEndpointCandidate()
                Task { @MainActor in
                    self.onError?(ChatNetworkError.serverError(statusCode: httpStatusCode, message: pendingLMStudioStreamErrorMessage))
                }
                return
            }
            clearActiveEndpointCandidate()
            Task { @MainActor in self.onError?(ChatNetworkError.emptyResponse) }
            return
        }

        emitStreamFinishedOnce()
    }

// MARK: - Watchdog (reports errors after long waits)

    private func startWatchdog() {
        stopWatchdog()
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + 5.0, repeating: 5.0, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard !self.isCancelled else { return }
            let now = Date()

            if let start = self.streamStartAt, self.lastDeltaAt == nil {
                if now.timeIntervalSince(start) > self.firstTokenTimeout {
                    self.dataTask?.cancel()
                    self.dataTask = nil
                    self.stopConnectionWatchdog()
                    self.stopWatchdog()
                    self.endBackgroundExecutionForCurrentRequest()
                    Task { @MainActor in
                        self.onError?(ChatNetworkError.timeout(NSLocalizedString("Connection timed out", comment: "Shown when the chat server request exceeds the timeout")))
                    }
                }
                return
            }

            if let last = self.lastDeltaAt {
                if now.timeIntervalSince(last) > self.silentGapTimeout {
                    self.dataTask?.cancel()
                    self.dataTask = nil
                    self.stopConnectionWatchdog()
                    self.stopWatchdog()
                    self.endBackgroundExecutionForCurrentRequest()
                    Task { @MainActor in
                        self.onError?(ChatNetworkError.timeout(NSLocalizedString("Connection timed out", comment: "Shown when the chat server request exceeds the timeout")))
                    }
                }
            }
        }
        watchdog = timer
        timer.resume()
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    private func startConnectionWatchdog() {
        stopConnectionWatchdog()
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + connectTimeout, repeating: .never, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard !self.isCancelled else { return }
            guard let task = self.dataTask else { return }
            guard !self.didEstablishConnection else {
                self.stopConnectionWatchdog()
                return
            }
            if task.countOfBytesSent > 0 {
                self.markConnectionEstablishedIfNeeded()
                return
            }
            task.cancel()
            self.dataTask = nil
            self.stopWatchdog()
            self.stopConnectionWatchdog()
            self.endBackgroundExecutionForCurrentRequest()
            Task { @MainActor in
                self.onError?(ChatNetworkError.timeout(NSLocalizedString("Connection timed out", comment: "Shown when connecting to the chat server takes too long")))
            }
        }
        connectionWatchdog = timer
        timer.resume()
    }

    private func stopConnectionWatchdog() {
        connectionWatchdog?.cancel()
        connectionWatchdog = nil
    }

    private func beginBackgroundExecutionForCurrentRequest() {
#if canImport(UIKit)
        backgroundTaskGeneration &+= 1
        let generation = backgroundTaskGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.beginBackgroundExecutionOnMain(for: generation)
        }
#endif
    }

    private func endBackgroundExecutionForCurrentRequest() {
#if canImport(UIKit)
        backgroundTaskGeneration &+= 1
        let generation = backgroundTaskGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.endBackgroundExecutionOnMain(for: generation)
        }
#endif
    }

#if canImport(UIKit)
    @MainActor
    private func beginBackgroundExecutionOnMain(for generation: UInt64) {
        guard generation >= backgroundTaskGenerationOnMain else { return }
        backgroundTaskGenerationOnMain = generation
        endBackgroundExecutionOnMainInternal()

        var identifier: UIBackgroundTaskIdentifier = .invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: backgroundTaskName) { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleBackgroundExecutionExpirationOnMain(taskIdentifier: identifier, generation: generation)
            }
        }
        backgroundTaskIdentifier = identifier

        guard identifier != .invalid else {
            guard UIApplication.shared.applicationState == .background else { return }
            handleBackgroundExecutionUnavailableOnMain(for: generation)
            return
        }
    }

    @MainActor
    private func endBackgroundExecutionOnMain(for generation: UInt64) {
        guard generation >= backgroundTaskGenerationOnMain else { return }
        backgroundTaskGenerationOnMain = generation
        endBackgroundExecutionOnMainInternal()
    }

    @MainActor
    private func endBackgroundExecutionOnMainInternal() {
        guard backgroundTaskIdentifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
    }

    @MainActor
    private func handleBackgroundExecutionUnavailableOnMain(for generation: UInt64) {
        guard generation >= backgroundTaskGenerationOnMain else { return }
        let shouldReportError = stateQueue.sync { [self] in
            cancelCurrentStreamForBackgroundInterruption()
        }
        guard shouldReportError else { return }
        onError?(ChatNetworkError.timeout(
            NSLocalizedString(
                "Background execution unavailable",
                comment: "Shown when iOS cannot grant background runtime for an active text generation stream"
            )
        ))
    }

    @MainActor
    private func handleBackgroundExecutionExpirationOnMain(
        taskIdentifier: UIBackgroundTaskIdentifier,
        generation: UInt64
    ) {
        guard taskIdentifier != .invalid else { return }
        guard generation >= backgroundTaskGenerationOnMain else { return }
        guard backgroundTaskIdentifier == taskIdentifier else { return }

        backgroundTaskGenerationOnMain = generation
        let shouldReportError = stateQueue.sync { [self] in
            cancelCurrentStreamForBackgroundInterruption()
        }
        UIApplication.shared.endBackgroundTask(taskIdentifier)
        if backgroundTaskIdentifier == taskIdentifier {
            backgroundTaskIdentifier = .invalid
        }

        guard shouldReportError else { return }
        onError?(ChatNetworkError.timeout(
            NSLocalizedString(
                "Background execution time expired",
                comment: "Shown when iOS ends background time for an active text generation stream"
            )
        ))
    }
#endif

    private func cancelCurrentStreamForBackgroundInterruption() -> Bool {
        guard dataTask != nil else { return false }
        isCancelled = true
        dataTask?.cancel()
        dataTask = nil
        stopConnectionWatchdog()
        stopWatchdog()
        clearActiveEndpointCandidate()
        return true
    }

    private func markConnectionEstablishedIfNeeded() {
        guard !didEstablishConnection else { return }
        didEstablishConnection = true
        stopConnectionWatchdog()
    }

    private func emitStreamFinishedOnce() {
        guard !streamFinishedEmitted else { return }
        streamFinishedEmitted = true
        clearActiveEndpointCandidate()
        Task { @MainActor in self.onStreamFinished?() }
    }
}

// MARK: - Protocol Conformance

extension ChatService: ChatStreamingService {}
