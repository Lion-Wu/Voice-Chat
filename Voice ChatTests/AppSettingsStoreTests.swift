import XCTest
@testable import Voice_Chat

final class AppSettingsStoreTests: XCTestCase {
    @MainActor
    func testLoadedStateMapsPersistedEntityAndBackfillsFallbacks() {
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
            hapticFeedbackEnabled: nil,
            selectedPresetID: UUID(),
            selectedNormalSystemPromptPresetID: normalID,
            selectedVoiceSystemPromptPresetID: voiceID,
            modelImageInputOverrideJSON: "{\"vision\":true}",
            apiAdvancedSettingsJSON: nil
        )

        let state = AppSettingsStore.loadedState(
            from: settings,
            chatAPIKey: "key",
            defaultHapticFeedbackEnabled: true,
            defaultAPIAdvancedSettings: .defaults
        )

        XCTAssertEqual(state.serverSettings.serverAddress, "http://voice.local")
        XCTAssertEqual(state.chatSettings.apiKey, "key")
        XCTAssertFalse(state.voiceSettings.enableStreaming)
        XCTAssertTrue(state.developerModeEnabled)
        XCTAssertTrue(state.hapticFeedbackEnabled)
        XCTAssertEqual(state.selectedNormalSystemPromptPresetID, normalID)
        XCTAssertEqual(state.selectedVoiceSystemPromptPresetID, voiceID)
        XCTAssertEqual(state.modelImageInputOverrides, ["vision": true])

        var labels: [String] = []
        AppSettingsStore.backfillMissingValues(in: settings, loadedState: state) { label in
            labels.append(label)
        }

        XCTAssertEqual(settings.hapticFeedbackEnabled, true)
        XCTAssertNotNil(settings.apiAdvancedSettingsJSON)
        XCTAssertEqual(labels, ["backfill haptic feedback setting", "backfill API advanced settings"])
    }
}
