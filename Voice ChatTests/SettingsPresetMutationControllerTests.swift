import SwiftData
import XCTest
@testable import Voice_Chat

@MainActor
final class SettingsPresetMutationControllerTests: XCTestCase {
    func testChatServerCreatePersistsAPIKeyAndDeleteClearsSelectedKey() throws {
        let harness = try makeHarness()
        var savedKeys: [(String, UUID)] = []
        var deletedKeys: [UUID] = []
        var selectedID: UUID?

        let preset = SettingsPresetMutationController.createChatServerPreset(
            name: "Local",
            apiURL: "http://localhost:1234",
            selectedModel: "model-a",
            apiFormatPreference: .openAIResponses,
            apiKey: "secret",
            context: harness.context,
            saveAPIKey: { savedKeys.append(($0, $1)) },
            save: harness.save
        )
        selectedID = preset.id
        harness.appSettings.selectedChatServerPresetID = preset.id

        XCTAssertEqual(savedKeys.first?.0, "secret")
        XCTAssertEqual(savedKeys.first?.1, preset.id)

        let didDelete = SettingsPresetMutationController.deleteChatServerPreset(
            id: preset.id,
            presets: [preset],
            selectedID: &selectedID,
            appSettings: harness.appSettings,
            context: harness.context,
            deleteAPIKey: { deletedKeys.append($0) },
            save: harness.save
        )

        XCTAssertTrue(didDelete)
        XCTAssertNil(selectedID)
        XCTAssertNil(harness.appSettings.selectedChatServerPresetID)
        XCTAssertEqual(deletedKeys, [preset.id])
    }

    func testVoicePresetSelectAndUpdateUseStoreRules() throws {
        let harness = try makeHarness()
        let preset = SettingsPresetMutationController.createVoicePreset(
            name: "Narrator",
            promptLang: "en",
            context: harness.context,
            save: harness.save
        )
        var selectedID: UUID?

        XCTAssertTrue(SettingsPresetMutationController.selectVoicePreset(
            id: preset.id,
            selectedID: &selectedID,
            appSettings: harness.appSettings,
            save: harness.save
        ))
        XCTAssertEqual(selectedID, preset.id)
        XCTAssertEqual(harness.appSettings.selectedPresetID, preset.id)

        XCTAssertTrue(SettingsPresetMutationController.updateVoicePreset(
            id: preset.id,
            name: "Updated",
            refAudioPath: "/tmp/ref.wav",
            promptText: "calm",
            promptLang: nil,
            gptWeightsPath: nil,
            sovitsWeightsPath: nil,
            presets: [preset],
            save: harness.save
        ))
        XCTAssertEqual(preset.name, "Updated")
        XCTAssertEqual(preset.refAudioPath, "/tmp/ref.wav")
        XCTAssertEqual(preset.promptText, "calm")
        XCTAssertEqual(preset.promptLang, "en")
    }

    func testSystemPromptSelectAndModeSpecificUpdateStaySeparated() throws {
        let harness = try makeHarness()
        let normal = SettingsPresetMutationController.createSystemPromptPreset(
            mode: SystemPromptPresetStore.normalMode,
            name: "Normal",
            context: harness.context,
            save: harness.save
        )
        var selectedNormalID: UUID?

        XCTAssertTrue(SettingsPresetMutationController.selectNormalSystemPromptPreset(
            id: normal.id,
            selectedID: &selectedNormalID,
            appSettings: harness.appSettings,
            save: harness.save
        ))
        XCTAssertEqual(harness.appSettings.selectedNormalSystemPromptPresetID, normal.id)

        XCTAssertTrue(SettingsPresetMutationController.updateNormalSystemPromptPreset(
            id: normal.id,
            name: "Normal Updated",
            prompt: "normal prompt",
            presets: [normal],
            save: harness.save
        ))
        XCTAssertEqual(normal.mode, SystemPromptPresetStore.normalMode)
        XCTAssertEqual(normal.normalPrompt, "normal prompt")
        XCTAssertEqual(normal.voicePrompt, "")
    }

    private func makeHarness() throws -> PresetMutationHarness {
        let container = try ModelContainer(
            for: AppSettings.self,
            VoiceServerPreset.self,
            ChatServerPreset.self,
            VoicePreset.self,
            SystemPromptPreset.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let appSettings = AppSettings()
        context.insert(appSettings)
        try context.save()
        return PresetMutationHarness(context: context, appSettings: appSettings)
    }
}

@MainActor
private struct PresetMutationHarness {
    let context: ModelContext
    let appSettings: AppSettings

    func save(_ label: String) {
        try? context.save()
    }
}
