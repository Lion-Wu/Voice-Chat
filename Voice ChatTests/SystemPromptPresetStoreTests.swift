import XCTest
@testable import Voice_Chat

final class SystemPromptPresetStoreTests: XCTestCase {
    func testFiltersPresetsByModeAndBuildsMissingDefaults() {
        let normal = SystemPromptPreset(name: "Normal", mode: SystemPromptPresetStore.normalMode)
        let voice = SystemPromptPreset(name: "Voice", mode: SystemPromptPresetStore.voiceMode)

        XCTAssertEqual(SystemPromptPresetStore.normalPresets(from: [normal, voice]).map(\.id), [normal.id])
        XCTAssertEqual(SystemPromptPresetStore.voicePresets(from: [normal, voice]).map(\.id), [voice.id])
        XCTAssertTrue(SystemPromptPresetStore.missingDefaultPresets(for: [normal, voice]).isEmpty)

        let defaults = SystemPromptPresetStore.missingDefaultPresets(for: [normal])

        XCTAssertEqual(defaults.count, 1)
        XCTAssertEqual(defaults.first?.mode, SystemPromptPresetStore.voiceMode)
    }

    func testRepairedSelectionKeepsValidModeSpecificSelections() throws {
        let normal = SystemPromptPreset(name: "Normal", mode: SystemPromptPresetStore.normalMode)
        let voice = SystemPromptPreset(name: "Voice", mode: SystemPromptPresetStore.voiceMode)

        let repair = try XCTUnwrap(SystemPromptPresetStore.repairedSelection(
            in: [normal, voice],
            selectedNormalID: normal.id,
            persistedNormalID: nil,
            selectedVoiceID: voice.id,
            persistedVoiceID: nil
        ))

        XCTAssertEqual(repair.normalID, normal.id)
        XCTAssertEqual(repair.voiceID, voice.id)
        XCTAssertFalse(repair.didRepairPersistedSelection)
    }

    func testRepairedSelectionFallsBackWhenModeDoesNotMatch() throws {
        let normal = SystemPromptPreset(name: "Normal", mode: SystemPromptPresetStore.normalMode)
        let voice = SystemPromptPreset(name: "Voice", mode: SystemPromptPresetStore.voiceMode)

        let repair = try XCTUnwrap(SystemPromptPresetStore.repairedSelection(
            in: [normal, voice],
            selectedNormalID: voice.id,
            persistedNormalID: nil,
            selectedVoiceID: normal.id,
            persistedVoiceID: nil
        ))

        XCTAssertEqual(repair.normalID, normal.id)
        XCTAssertEqual(repair.voiceID, voice.id)
        XCTAssertTrue(repair.didRepairPersistedSelection)
    }

    func testModeSpecificUpdatesClearOppositePrompt() {
        let preset = SystemPromptPreset(name: "Draft", mode: nil, normalPrompt: "old normal", voicePrompt: "old voice")

        SystemPromptPresetStore.updateNormalPreset(preset, name: "Normal", prompt: "normal prompt")

        XCTAssertEqual(preset.mode, SystemPromptPresetStore.normalMode)
        XCTAssertEqual(preset.name, "Normal")
        XCTAssertEqual(preset.normalPrompt, "normal prompt")
        XCTAssertEqual(preset.voicePrompt, "")

        SystemPromptPresetStore.updateVoicePreset(preset, name: "Voice", prompt: "voice prompt")

        XCTAssertEqual(preset.mode, SystemPromptPresetStore.voiceMode)
        XCTAssertEqual(preset.name, "Voice")
        XCTAssertEqual(preset.normalPrompt, "")
        XCTAssertEqual(preset.voicePrompt, "voice prompt")
    }
}
