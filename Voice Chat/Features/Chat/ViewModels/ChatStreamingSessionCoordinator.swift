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
    private let serviceFactory: ServiceFactory
    private(set) var configuration: ChatServiceConfiguration
    private var deferredConfiguration: ChatServiceConfiguration?

    private var onDelta: ((String) -> Void)?
    private var onError: ((Error) -> Void)?
    private var onResponseMetadata: ((ChatResponseMetadata) -> Void)?
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
        onError: @escaping (Error) -> Void,
        onResponseMetadata: @escaping (ChatResponseMetadata) -> Void,
        onStreamFinished: @escaping () -> Void
    ) {
        self.onDelta = onDelta
        self.onError = onError
        self.onResponseMetadata = onResponseMetadata
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

    func cancelStreaming() {
        service.cancelStreaming()
    }

    private func applyConfiguration(_ newConfiguration: ChatServiceConfiguration) {
        deferredConfiguration = nil
        configuration = newConfiguration
        service = serviceFactory(newConfiguration)
        bindCurrentService()
    }

    private func bindCurrentService() {
        service.onDelta = { [weak self] piece in
            self?.onDelta?(piece)
        }
        service.onError = { [weak self] error in
            self?.onError?(error)
        }
        service.onResponseMetadata = { [weak self] metadata in
            self?.onResponseMetadata?(metadata)
        }
        service.onStreamFinished = { [weak self] in
            self?.onStreamFinished?()
        }
    }
}
