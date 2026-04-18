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
}

/// Lightweight snapshot of chat configuration to avoid actor-hopping from main-actor singletons.
struct ChatServiceConfiguration: ChatServiceConfiguring, Equatable {
    let apiBaseURL: String
    let modelIdentifier: String
    let apiKey: String
    let providerHint: ChatProvider?
    let requestStyleHint: ChatRequestStyle?

    init(
        apiBaseURL: String,
        modelIdentifier: String,
        apiKey: String,
        providerHint: ChatProvider? = nil,
        requestStyleHint: ChatRequestStyle? = nil
    ) {
        self.apiBaseURL = apiBaseURL
        self.modelIdentifier = modelIdentifier
        self.apiKey = apiKey
        self.providerHint = providerHint
        self.requestStyleHint = requestStyleHint
    }
}

// MARK: - Service Contracts

@MainActor
protocol ChatStreamingService: AnyObject {
    var onDelta: (@MainActor (String) -> Void)? { get set }
    var onError: (@MainActor (Error) -> Void)? { get set }
    var onResponseMetadata: (@MainActor (ChatResponseMetadata) -> Void)? { get set }
    var onStreamFinished: (@MainActor () -> Void)? { get set }

    func fetchStreamedData(messages: [ChatMessage], developerPrompt: String?, includeImagesInUserContent: Bool)
    func cancelStreaming()
}

// MARK: - ChatService (Streaming)
