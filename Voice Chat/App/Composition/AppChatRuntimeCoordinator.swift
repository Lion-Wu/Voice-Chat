//
//  AppChatRuntimeCoordinator.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2026/06/13.
//

import Combine
import Foundation

@MainActor
final class AppChatRuntimeCoordinator {
    private struct ChatEndpointSignature: Equatable {
        let apiURL: String
        let apiKey: String
    }

    private let settingsManager: SettingsManager
    private let chatSessionsViewModel: ChatSessionsViewModel
    private let reachabilityMonitor: ServerReachabilityMonitor
    private var cancellables: Set<AnyCancellable> = []
    private var reachabilityTask: Task<Void, Never>?
    private var didStart = false

    init(
        settingsManager: SettingsManager,
        chatSessionsViewModel: ChatSessionsViewModel,
        reachabilityMonitor: ServerReachabilityMonitor
    ) {
        self.settingsManager = settingsManager
        self.chatSessionsViewModel = chatSessionsViewModel
        self.reachabilityMonitor = reachabilityMonitor
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        observeSettingsChanges()
        startReachabilityMonitoring()
        startLaunchTasks()
    }

    private func startLaunchTasks() {
        Task { [settingsManager] in
            await settingsManager.applyPresetOnLaunchIfNeeded()
            await settingsManager.prefetchChatModelsOnLaunchIfNeeded()
        }
    }

    private func observeSettingsChanges() {
        settingsManager.$chatSettings
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.chatSessionsViewModel.refreshChatConfigurationIfNeeded()
                self.kickReachabilityCheck()
            }
            .store(in: &cancellables)

        settingsManager.$chatSettings
            .map { settings in
                ChatEndpointSignature(
                    apiURL: settings.apiURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    apiKey: settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(650), scheduler: RunLoop.main)
            .sink { [settingsManager] _ in
                Task { [settingsManager] in
                    await settingsManager.refreshChatProviderHintsAndModels()
                }
            }
            .store(in: &cancellables)

        settingsManager.$apiAdvancedSettings
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.chatSessionsViewModel.refreshChatConfigurationIfNeeded()
            }
            .store(in: &cancellables)

        settingsManager.$developerModeEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.chatSessionsViewModel.refreshChatConfigurationIfNeeded()
            }
            .store(in: &cancellables)

        settingsManager.chatModelCapabilityChanges
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.chatSessionsViewModel.refreshChatConfigurationIfNeeded()
            }
            .store(in: &cancellables)

        settingsManager.$chatServerPresets
            .combineLatest(settingsManager.$selectedChatServerPresetID.removeDuplicates())
            .map { presets, selectedID in
                guard let selectedID,
                      let preset = presets.first(where: { $0.id == selectedID }) else {
                    return ""
                }
                let normalizedBase = ChatAPIEndpointResolver.normalizedAPIBaseKey(preset.apiURL)
                    ?? preset.apiURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let format = (preset.apiFormatPreferenceRaw ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(selectedID.uuidString)|\(normalizedBase)|\(format)"
            }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.chatSessionsViewModel.refreshChatConfigurationIfNeeded()
            }
            .store(in: &cancellables)

        settingsManager.$serverSettings
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.kickReachabilityCheck()
            }
            .store(in: &cancellables)
    }

    private func startReachabilityMonitoring() {
        kickReachabilityCheck()
        reachabilityMonitor.startMonitoring { [settingsManager] in
            settingsManager.serverReachabilitySnapshot
        }
    }

    private func kickReachabilityCheck() {
        reachabilityTask?.cancel()
        reachabilityTask = Task { [settingsManager, reachabilityMonitor] in
            await reachabilityMonitor.checkAll(snapshot: settingsManager.serverReachabilitySnapshot)
        }
    }
}
