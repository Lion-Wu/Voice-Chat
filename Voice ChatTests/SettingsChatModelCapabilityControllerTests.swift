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
            saveImageInputOverrides: { saveCount += 1 }
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
            saveImageInputOverrides: {}
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
            saveImageInputOverrides: {}
        )

        controller.noteDetectedProvider(.openRouter, for: "https://models.example.com/v1")

        XCTAssertEqual(controller.detectedProvider(for: "https://models.example.com/v1"), .openRouter)
        XCTAssertNil(controller.detectedProvider(for: "https://other.example.com/v1"))
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
