import XCTest
@testable import Voice_Chat

@MainActor
final class ChatModelCapabilityFacadeTests: XCTestCase {
    func testManualFormatPreferenceOverridesDetectedProviderForMatchingPresetBase() {
        let preset = ChatServerPreset(
            name: "Local",
            apiURL: "http://localhost:1234/v1",
            selectedModel: "local",
            apiFormatPreferenceRaw: ChatAPIFormatPreference.lmStudio.rawValue
        )
        var store = ChatModelCapabilityStore()
        store.noteDetectedProvider(.openAICompatible, for: "http://localhost:1234/v1")
        let facade = ChatModelCapabilityFacade(
            store: store,
            chatSettings: ChatSettings(apiURL: "http://localhost:1234/v1", selectedModel: "local", apiKey: ""),
            chatServerPresets: [preset],
            selectedChatServerPresetID: preset.id
        )

        XCTAssertEqual(facade.resolvedProvider(for: "http://localhost:1234/v1"), .lmStudio)
        XCTAssertEqual(facade.resolvedRequestStyle(for: "http://localhost:1234/v1"), .lmStudioRESTV1)
    }

    func testDetectedProviderIsUsedWhenManualPresetDoesNotMatchRequestedBase() {
        let preset = ChatServerPreset(
            name: "Other",
            apiURL: "http://other.example.com/v1",
            selectedModel: "local",
            apiFormatPreferenceRaw: ChatAPIFormatPreference.lmStudio.rawValue
        )
        var store = ChatModelCapabilityStore()
        store.noteDetectedProvider(.openAICompatible, for: "http://localhost:1234/v1")
        let facade = ChatModelCapabilityFacade(
            store: store,
            chatSettings: ChatSettings(apiURL: "http://localhost:1234/v1", selectedModel: "local", apiKey: ""),
            chatServerPresets: [preset],
            selectedChatServerPresetID: preset.id
        )

        XCTAssertEqual(facade.resolvedProvider(for: "http://localhost:1234/v1"), .openAICompatible)
    }

    func testThinkingSelectionMutatesUnderlyingStore() throws {
        let capability = ModelThinkingCapability(
            options: [.off, .high],
            defaultOption: .off,
            requestParameter: .reasoning
        )
        var facade = ChatModelCapabilityFacade(
            store: ChatModelCapabilityStore(thinkingCapabilities: [
                try XCTUnwrap(ChatModelCapabilityStore.scopedKey(apiBaseURL: "http://localhost:1234/v1", modelIdentifier: "reasoner")): capability
            ]),
            chatSettings: ChatSettings(apiURL: "http://localhost:1234/v1", selectedModel: "reasoner", apiKey: ""),
            chatServerPresets: [],
            selectedChatServerPresetID: nil
        )

        XCTAssertTrue(facade.setSelectedThinkingOption(.high))
        XCTAssertEqual(facade.selectedThinkingOption(), .high)
        XCTAssertTrue(facade.toggleSelectedThinking())
        XCTAssertEqual(facade.selectedThinkingOption(), .off)
    }
}
