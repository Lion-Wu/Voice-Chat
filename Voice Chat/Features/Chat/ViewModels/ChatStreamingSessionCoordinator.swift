//
//  ChatStreamingSessionCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

enum ChatStreamingConfigurationUpdate: Equatable {
    case unchanged
    case deferred
    case applied

    var didApply: Bool {
        self == .applied
    }
}

@MainActor
final class ChatStreamingSessionCoordinator {
    typealias ServiceFactory = (ChatServiceConfiguring) -> ChatStreamingService

    private var service: ChatStreamingService
    private var serviceGeneration: UInt64 = 0
    private let serviceFactory: ServiceFactory
    private(set) var configuration: ChatServiceConfiguration
    private var deferredConfiguration: ChatServiceConfiguration?

    private var onDelta: ((String) -> Void)?
    private var onSegment: ((AssistantStreamSegment) -> Void)?
    private var onOpenAIResponsesConversationItems: (([JSONValue]) -> Void)?
    private var onError: ((Error) -> Void)?
    private var onResponseMetadata: ((ChatResponseMetadata) -> Void)?
    private var onToolActivity: ((ChatToolActivity) -> Void)?
    private var onStreamFinished: (() -> Void)?

    init(
        configuration: ChatServiceConfiguration,
        service: ChatStreamingService?,
        serviceFactory: @escaping ServiceFactory
    ) {
        self.configuration = configuration
        self.serviceFactory = serviceFactory
        self.service = service ?? serviceFactory(configuration)
    }

    func bindHandlers(
        onDelta: @escaping (String) -> Void,
        onSegment: @escaping (AssistantStreamSegment) -> Void,
        onOpenAIResponsesConversationItems: @escaping ([JSONValue]) -> Void,
        onError: @escaping (Error) -> Void,
        onResponseMetadata: @escaping (ChatResponseMetadata) -> Void,
        onToolActivity: @escaping (ChatToolActivity) -> Void,
        onStreamFinished: @escaping () -> Void
    ) {
        self.onDelta = onDelta
        self.onSegment = onSegment
        self.onOpenAIResponsesConversationItems = onOpenAIResponsesConversationItems
        self.onError = onError
        self.onResponseMetadata = onResponseMetadata
        self.onToolActivity = onToolActivity
        self.onStreamFinished = onStreamFinished
        bindCurrentService()
    }

    func updateConfiguration(
        _ newConfiguration: ChatServiceConfiguration,
        isActiveTextRequest: Bool
    ) -> ChatStreamingConfigurationUpdate {
        guard newConfiguration != configuration else {
            deferredConfiguration = nil
            return .unchanged
        }

        if isActiveTextRequest {
            deferredConfiguration = newConfiguration
            return .deferred
        }

        applyConfiguration(newConfiguration)
        return .applied
    }

    func applyDeferredConfigurationIfIdle(isActiveTextRequest: Bool) -> ChatStreamingConfigurationUpdate {
        guard !isActiveTextRequest else { return .unchanged }
        guard let deferred = deferredConfiguration else { return .unchanged }
        guard deferred != configuration else {
            deferredConfiguration = nil
            return .unchanged
        }

        applyConfiguration(deferred)
        return .applied
    }

    func fetchStreamedData(
        messages: [ChatMessage],
        developerPrompt: String?,
        includeImagesInUserContent: Bool
    ) {
        service.fetchStreamedData(
            messages: messages,
            developerPrompt: developerPrompt,
            includeImagesInUserContent: includeImagesInUserContent
        )
    }

    func retryLastFailedStreamRequest() -> Bool {
        service.retryLastFailedStreamRequest()
    }

    func cancelStreaming() {
        service.cancelStreaming()
    }

    func resolveToolAuthorization(requestID: String, allowed: Bool) {
        service.resolveToolAuthorization(requestID: requestID, allowed: allowed)
    }

    private func applyConfiguration(_ newConfiguration: ChatServiceConfiguration) {
        deferredConfiguration = nil
        configuration = newConfiguration
        service = serviceFactory(newConfiguration)
        bindCurrentService()
    }

    private func bindCurrentService() {
        serviceGeneration &+= 1
        let generation = serviceGeneration
        service.onDelta = { [weak self] piece in
            guard self?.serviceGeneration == generation else { return }
            self?.onDelta?(piece)
        }
        service.onSegment = { [weak self] segment in
            guard self?.serviceGeneration == generation else { return }
            self?.onSegment?(segment)
        }
        service.onOpenAIResponsesConversationItems = { [weak self] items in
            guard self?.serviceGeneration == generation else { return }
            self?.onOpenAIResponsesConversationItems?(items)
        }
        service.onError = { [weak self] error in
            guard self?.serviceGeneration == generation else { return }
            self?.onError?(error)
        }
        service.onResponseMetadata = { [weak self] metadata in
            guard self?.serviceGeneration == generation else { return }
            self?.onResponseMetadata?(metadata)
        }
        service.onToolActivity = { [weak self] activity in
            guard self?.serviceGeneration == generation else { return }
            self?.onToolActivity?(activity)
        }
        service.onStreamFinished = { [weak self] in
            guard self?.serviceGeneration == generation else { return }
            self?.onStreamFinished?()
        }
    }
}
