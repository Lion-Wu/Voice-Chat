//
//  SettingsPresetApplyController.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

@MainActor
final class SettingsPresetApplyController {
    typealias StatusPublisher = @MainActor @Sendable (TTSPresetApplyStatus) -> Void
    typealias ApplyOperation = @MainActor (TTSPresetApplyRequest, @escaping StatusPublisher) async -> Void

    var onStatusChange: ((TTSPresetApplyStatus) -> Void)?

    private let applyOperation: ApplyOperation
    private(set) var status: TTSPresetApplyStatus
    private var didApplyOnLaunch = false

    init(
        initialStatus: TTSPresetApplyStatus = .idle,
        applyOperation: ApplyOperation? = nil
    ) {
        let coordinator = TTSPresetApplyCoordinator(initialStatus: initialStatus)
        self.status = initialStatus
        self.applyOperation = applyOperation ?? { request, publish in
            await coordinator.apply(request, publish: publish)
        }
    }

    func applyOnLaunchIfNeeded(makeRequest: () -> TTSPresetApplyRequest?) async {
        guard !didApplyOnLaunch else { return }
        didApplyOnLaunch = true
        await apply(makeRequest())
    }

    func apply(_ request: TTSPresetApplyRequest?) async {
        guard let request else { return }

        await applyOperation(request) { [weak self] status in
            self?.update(status)
        }
    }

    private func update(_ nextStatus: TTSPresetApplyStatus) {
        status = nextStatus
        onStatusChange?(nextStatus)
    }
}
