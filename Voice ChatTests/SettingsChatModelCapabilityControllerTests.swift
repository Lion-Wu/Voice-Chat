import XCTest
@testable import Voice_Chat

@MainActor
final class SettingsChatModelCapabilityControllerTests: XCTestCase {
    func testImageInputOverrideMutatesStoreAndRequestsPersistence() {
        var store = ChatModelCapabilityStore()
        var saveCount = 0
        let controller = SettingsChatModelCapabilityController(
            getStore: { store },
            setStore: { store = $0 },
            context: { Self.context() },
            savePreferences: { saveCount += 1 }
        )

        controller.setImageInputManualOverride(true, for: "local-model")

        XCTAssertEqual(store.imageInputManualOverride(for: "local-model"), true)
        XCTAssertEqual(saveCount, 1)
        XCTAssertTrue(controller.supportsImageInput(for: "local-model"))
    }

    func testSelectedFormatPreferenceUsesCurrentChatPresetContext() throws {
        var store = ChatModelCapabilityStore()
        let selectedID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000201"))
        let preset = ChatServerPreset(
            name: "Anthropic",
            apiURL: "https://api.anthropic.com",
            selectedModel: "claude",
            apiFormatPreferenceRaw: ChatAPIFormatPreference.anthropic.rawValue
        )
        preset.id = selectedID
        let controller = SettingsChatModelCapabilityController(
            getStore: { store },
            setStore: { store = $0 },
            context: {
                Self.context(
                    selectedID: selectedID,
                    presets: [preset]
                )
            },
            savePreferences: {}
        )

        XCTAssertEqual(controller.selectedChatAPIFormatPreference(), ChatAPIFormatPreference.anthropic)
        XCTAssertEqual(controller.resolvedProvider(for: "https://api.anthropic.com"), ChatProvider.anthropic)
    }

    func testDetectedProviderHintsAreScopedByEndpoint() {
        var store = ChatModelCapabilityStore()
        let controller = SettingsChatModelCapabilityController(
            getStore: { store },
            setStore: { store = $0 },
            context: { Self.context(apiURL: "https://models.example.com/v1") },
            savePreferences: {}
        )

        controller.noteDetectedProvider(.openAI, for: "https://models.example.com/v1")

        XCTAssertEqual(controller.detectedProvider(for: "https://models.example.com/v1"), .openAI)
        XCTAssertNil(controller.detectedProvider(for: "https://other.example.com/v1"))
    }

    func testEndpointAndThinkingChangesRequestSettingsPersistence() throws {
        var store = ChatModelCapabilityStore()
        var saveCount = 0
        let controller = SettingsChatModelCapabilityController(
            getStore: { store }, setStore: { store = $0 }, context: { Self.context() },
            savePreferences: { saveCount += 1 }
        )
        controller.noteDetectedEndpoint(ChatAPIEndpointCandidate(
            provider: .openAI, style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/v1/models"))
        ), for: "http://localhost:1234/v1")
        XCTAssertEqual(saveCount, 1)
        controller.updateThinkingCapabilities(["local-model": ModelThinkingCapability(options: [.low, .high], defaultOption: .low)], for: "http://localhost:1234/v1")
        controller.setSelectedThinkingOption(.high)
        XCTAssertEqual(saveCount, 2)
        XCTAssertEqual(controller.selectedThinkingOption(), .high)
    }

    private static func context(
        apiURL: String = "http://localhost:1234/v1",
        selectedID: UUID? = nil,
        presets: [ChatServerPreset] = []
    ) -> SettingsChatModelCapabilityContext {
        SettingsChatModelCapabilityContext(
            chatSettings: ChatSettings(
                apiURL: apiURL,
                selectedModel: "local-model",
                apiKey: ""
            ),
            chatServerPresets: presets,
            selectedChatServerPresetID: selectedID
        )
    }
}
