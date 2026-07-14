//
//  ChatServiceConfiguration.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import Foundation

// MARK: - Configuration

/// Provides chat API configuration without tying the service to a global singleton.
protocol ChatServiceConfiguring {
    var apiBaseURL: String { get }
    var modelIdentifier: String { get }
    var apiKey: String { get }
    var providerHint: ChatProvider? { get }
    var requestStyleHint: ChatRequestStyle? { get }
    var thinkingCapability: ModelThinkingCapability? { get }
    var thinkingOption: ModelThinkingOption? { get }
    var apiAdvancedSettings: APIAdvancedSettings { get }
    var toolUseSettings: ToolUseSettings { get }
}

/// Lightweight snapshot of chat configuration to avoid actor-hopping from main-actor singletons.
struct ChatServiceConfiguration: ChatServiceConfiguring, Equatable {
    let apiBaseURL: String
    let modelIdentifier: String
    let apiKey: String
    let providerHint: ChatProvider?
    let requestStyleHint: ChatRequestStyle?
    let thinkingCapability: ModelThinkingCapability?
    let thinkingOption: ModelThinkingOption?
    let apiAdvancedSettings: APIAdvancedSettings
    let toolUseSettings: ToolUseSettings

    init(
        apiBaseURL: String,
        modelIdentifier: String,
        apiKey: String,
        providerHint: ChatProvider? = nil,
        requestStyleHint: ChatRequestStyle? = nil,
        thinkingCapability: ModelThinkingCapability? = nil,
        thinkingOption: ModelThinkingOption? = nil,
        apiAdvancedSettings: APIAdvancedSettings = .defaults,
        toolUseSettings: ToolUseSettings = .defaults
    ) {
        self.apiBaseURL = apiBaseURL
        self.modelIdentifier = modelIdentifier
        self.apiKey = apiKey
        self.providerHint = providerHint
        self.requestStyleHint = requestStyleHint
        self.thinkingCapability = thinkingCapability
        self.thinkingOption = thinkingOption
        self.apiAdvancedSettings = apiAdvancedSettings.sanitized
        self.toolUseSettings = toolUseSettings
    }
}

// MARK: - Service Contracts

@MainActor
protocol ChatStreamingService: AnyObject {
    var onDelta: (@MainActor (String) -> Void)? { get set }
    var onSegment: (@MainActor (AssistantStreamSegment) -> Void)? { get set }
    var onOpenAIResponsesConversationItems: (@MainActor ([JSONValue]) -> Void)? { get set }
    var onError: (@MainActor (Error) -> Void)? { get set }
    var onResponseMetadata: (@MainActor (ChatResponseMetadata) -> Void)? { get set }
    var onToolActivity: (@MainActor (ChatToolActivity) -> Void)? { get set }
    var onStreamFinished: (@MainActor () -> Void)? { get set }

    func fetchStreamedData(messages: [ChatMessage], developerPrompt: String?, includeImagesInUserContent: Bool)
    func retryLastFailedStreamRequest() -> Bool
    func cancelStreaming()
    func resolveToolAuthorization(requestID: String, allowed: Bool)
}

// MARK: - ChatService (Streaming)
