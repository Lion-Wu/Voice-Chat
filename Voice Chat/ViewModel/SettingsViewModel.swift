//
//  SettingsViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.10.09.
//

import Foundation
import Combine

class SettingsViewModel: ObservableObject {
    @Published var serverAddress: String
    @Published var textLang: String
    @Published var refAudioPath: String
    @Published var promptText: String
    @Published var promptLang: String

    @Published var apiURL: String
    @Published var selectedModel: String

    private var cancellables = Set<AnyCancellable>()
    private let settingsManager = SettingsManager.shared

    init() {
        let serverSettings = settingsManager.serverSettings
        self.serverAddress = serverSettings.serverAddress
        self.textLang = serverSettings.textLang
        self.refAudioPath = serverSettings.refAudioPath
        self.promptText = serverSettings.promptText
        self.promptLang = serverSettings.promptLang

        let chatSettings = settingsManager.chatSettings
        self.apiURL = chatSettings.apiURL
        self.selectedModel = chatSettings.selectedModel

        setupBindings()
    }

    private func setupBindings() {
        $serverAddress
            .sink { [weak self] _ in self?.saveServerSettings() }
            .store(in: &cancellables)

        $textLang
            .sink { [weak self] _ in self?.saveServerSettings() }
            .store(in: &cancellables)

        $refAudioPath
            .sink { [weak self] _ in self?.saveServerSettings() }
            .store(in: &cancellables)

        $promptText
            .sink { [weak self] _ in self?.saveServerSettings() }
            .store(in: &cancellables)

        $promptLang
            .sink { [weak self] _ in self?.saveServerSettings() }
            .store(in: &cancellables)

        $apiURL
            .sink { [weak self] _ in self?.saveChatSettings() }
            .store(in: &cancellables)

        $selectedModel
            .sink { [weak self] _ in self?.saveChatSettings() }
            .store(in: &cancellables)
    }

    func saveServerSettings() {
        settingsManager.updateServerSettings(
            serverAddress: serverAddress,
            textLang: textLang,
            refAudioPath: refAudioPath,
            promptText: promptText,
            promptLang: promptLang
        )
    }

    func saveChatSettings() {
        settingsManager.updateChatSettings(
            apiURL: apiURL,
            selectedModel: selectedModel
        )
    }
}
