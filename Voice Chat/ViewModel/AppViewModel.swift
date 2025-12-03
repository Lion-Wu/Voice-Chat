//
//  AppViewModel.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2025/03/12.
//

import Foundation
import SwiftData

@MainActor
final class AppViewModel: ObservableObject {
    private let reachabilityMonitor: ServerReachabilityMonitor
    private var connectivityTask: Task<Void, Never>?

    init(reachabilityMonitor: ServerReachabilityMonitor? = nil) {
        self.reachabilityMonitor = reachabilityMonitor ?? .shared
    }

    func handleAppear(
        context: ModelContext,
        settingsManager: SettingsManager,
        chatSessionsViewModel: ChatSessionsViewModel
    ) {
        chatSessionsViewModel.attach(context: context)
        settingsManager.attach(context: context)
        chatSessionsViewModel.refreshChatConfigurationIfNeeded()
        ensureAtLeastOneSession(chatSessionsViewModel)
        runConnectivityChecks(settings: settingsManager)
    }

    func handleServerChange(settingsManager: SettingsManager,
                            chatSessionsViewModel: ChatSessionsViewModel) {
        chatSessionsViewModel.refreshChatConfigurationIfNeeded()
        runConnectivityChecks(settings: settingsManager)
    }

    func selectConversation(_ session: ChatSession, store: ChatSessionsViewModel) {
        store.selectedSession = session
    }

    func startNewConversation(store: ChatSessionsViewModel) {
        store.startNewSession()
    }

    var monitor: ServerReachabilityMonitor { reachabilityMonitor }

    // MARK: - Internal helpers

    private func ensureAtLeastOneSession(_ store: ChatSessionsViewModel) {
        if store.chatSessions.isEmpty {
            store.startNewSession()
        }
    }

    private func runConnectivityChecks(settings: SettingsManager) {
        connectivityTask?.cancel()
        connectivityTask = Task {
            await reachabilityMonitor.checkAll(settings: settings)
            reachabilityMonitor.startMonitoring(settings: settings)
        }
    }

    deinit {
        connectivityTask?.cancel()
    }
}
