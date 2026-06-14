import XCTest
@testable import Voice_Chat

@MainActor
final class SettingsPresetBindingControllerTests: XCTestCase {
    func testVoicePresetBindingProjectsSelectedFieldsAndResetsMissingSelection() {
        let first = VoicePreset(
            name: "Narrator",
            refAudioPath: "/tmp/ref.wav",
            promptText: "calm voice",
            promptLang: "en",
            gptWeightsPath: "/tmp/gpt.ckpt",
            sovitsWeightsPath: "/tmp/sovits.pth"
        )
        let second = VoicePreset(name: "Backup")

        let selected = SettingsPresetBindingProjector.voicePresetBinding(
            presets: [first, second],
            selectedID: first.id
        )

        XCTAssertEqual(selected.presets.map(\.name), ["Narrator", "Backup"])
        XCTAssertEqual(selected.selectedID, first.id)
        XCTAssertEqual(selected.name, "Narrator")
        XCTAssertEqual(selected.refAudioPath, "/tmp/ref.wav")
        XCTAssertEqual(selected.promptText, "calm voice")
        XCTAssertEqual(selected.promptLang, "en")
        XCTAssertEqual(selected.gptWeightsPath, "/tmp/gpt.ckpt")
        XCTAssertEqual(selected.sovitsWeightsPath, "/tmp/sovits.pth")

        let missing = SettingsPresetBindingProjector.voicePresetBinding(
            presets: [first, second],
            selectedID: UUID()
        )

        XCTAssertEqual(missing.presets.map(\.name), ["Narrator", "Backup"])
        XCTAssertEqual(missing.name, "")
        XCTAssertEqual(missing.refAudioPath, "")
        XCTAssertEqual(missing.promptText, "")
        XCTAssertEqual(missing.promptLang, "auto")
        XCTAssertEqual(missing.gptWeightsPath, "")
        XCTAssertEqual(missing.sovitsWeightsPath, "")
    }

    func testChatServerBindingKeepsSelectedFormatPreference() {
        let automatic = ChatServerPreset(name: "Auto")
        let responses = ChatServerPreset(
            name: "Responses",
            apiFormatPreferenceRaw: ChatAPIFormatPreference.openAICompatible.rawValue
        )

        let binding = SettingsPresetBindingProjector.chatServerBinding(
            presets: [automatic, responses],
            selectedID: responses.id
        )

        XCTAssertEqual(binding.presets.map(\.name), ["Auto", "Responses"])
        XCTAssertEqual(binding.selectedID, responses.id)
        XCTAssertEqual(binding.name, "Responses")
        XCTAssertEqual(binding.formatPreference, .openAICompatible)

        let missing = SettingsPresetBindingProjector.chatServerBinding(
            presets: [automatic, responses],
            selectedID: UUID()
        )

        XCTAssertEqual(missing.name, "")
        XCTAssertEqual(missing.formatPreference, .automatic)
    }

    func testSystemPromptBindingsKeepNormalAndVoicePromptsSeparate() {
        let normal = SystemPromptPreset(
            name: "Normal",
            mode: SystemPromptPresetStore.normalMode,
            normalPrompt: "normal instructions",
            voicePrompt: "ignored voice"
        )
        let voice = SystemPromptPreset(
            name: "Voice",
            mode: SystemPromptPresetStore.voiceMode,
            normalPrompt: "ignored normal",
            voicePrompt: "voice instructions"
        )

        let bindings = SettingsPresetBindingProjector.systemPromptBindings(
            normalPresets: [normal],
            selectedNormalID: normal.id,
            voicePresets: [voice],
            selectedVoiceID: voice.id
        )

        XCTAssertEqual(bindings.normal.presets.map(\.name), ["Normal"])
        XCTAssertEqual(bindings.normal.name, "Normal")
        XCTAssertEqual(bindings.normal.prompt, "normal instructions")
        XCTAssertEqual(bindings.voice.presets.map(\.name), ["Voice"])
        XCTAssertEqual(bindings.voice.name, "Voice")
        XCTAssertEqual(bindings.voice.prompt, "voice instructions")
    }
}
