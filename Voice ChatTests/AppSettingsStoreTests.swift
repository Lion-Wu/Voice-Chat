import XCTest
@testable import Voice_Chat

final class AppSettingsStoreTests: XCTestCase {
    @MainActor
    func testLoadedStateMapsPersistedEntity() {
        let normalID = UUID()
        let voiceID = UUID()
        let settings = AppSettings(
            serverAddress: "http://voice.local",
            textLang: "zh",
            modelId: "voice-model",
            language: "en",
            autoSplit: "cut5",
            apiURL: "https://api.example.com",
            selectedModel: "chat-model",
            selectedChatServerPresetID: UUID(),
            selectedVoiceServerPresetID: UUID(),
            enableStreaming: false,
            developerModeEnabled: true,
            hapticFeedbackEnabled: true,
            selectedPresetID: UUID(),
            selectedNormalSystemPromptPresetID: normalID,
            selectedVoiceSystemPromptPresetID: voiceID,
            modelImageInputOverrideJSON: "{\"vision\":true}",
            ttsProviderRawValue: TTSProvider.appleSpeech.rawValue,
            appleSpeechVoiceIdentifier: "com.apple.voice.test",
            personalVoiceIdentifier: "com.apple.personalvoice.test"
        )

        let state = AppSettingsStore.loadedState(
            from: settings,
            chatAPIKey: "key",
            defaultAPIAdvancedSettings: .defaults
        )

        XCTAssertEqual(state.serverSettings.serverAddress, "http://voice.local")
        XCTAssertEqual(state.chatSettings.apiKey, "key")
        XCTAssertFalse(state.voiceSettings.enableStreaming)
        XCTAssertEqual(state.voiceSettings.provider, .appleSpeech)
        XCTAssertEqual(state.voiceSettings.appleSpeechVoiceIdentifier, "com.apple.voice.test")
        XCTAssertEqual(state.voiceSettings.personalVoiceIdentifier, "com.apple.personalvoice.test")
        XCTAssertTrue(state.developerModeEnabled)
        XCTAssertTrue(state.hapticFeedbackEnabled)
        XCTAssertEqual(state.selectedNormalSystemPromptPresetID, normalID)
        XCTAssertEqual(state.selectedVoiceSystemPromptPresetID, voiceID)
        XCTAssertEqual(state.modelImageInputOverrides, ["vision": true])
    }
}
