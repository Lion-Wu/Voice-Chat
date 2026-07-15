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
        store.noteDetectedProvider(.openAI, for: "http://localhost:1234/v1")
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
        store.noteDetectedProvider(.openAI, for: "http://localhost:1234/v1")
        let facade = ChatModelCapabilityFacade(
            store: store,
            chatSettings: ChatSettings(apiURL: "http://localhost:1234/v1", selectedModel: "local", apiKey: ""),
            chatServerPresets: [preset],
            selectedChatServerPresetID: preset.id
        )

        XCTAssertEqual(facade.resolvedProvider(for: "http://localhost:1234/v1"), .openAI)
    }

    func testModelCatalogDoesNotTreatSharedModelsEndpointAsGenerationStyleProbe() throws {
        let baseURL = "https://compatible.example.com/v1"
        var staleStore = ChatModelCapabilityStore()
        staleStore.noteDetectedRequestStyle(.openAIResponses, for: baseURL)
        var facade = ChatModelCapabilityFacade(
            store: staleStore,
            chatSettings: ChatSettings(apiURL: baseURL, selectedModel: "model", apiKey: ""),
            chatServerPresets: [],
            selectedChatServerPresetID: nil
        )
        let endpoint = ChatAPIEndpointCandidate(
            provider: .unknown,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://compatible.example.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://compatible.example.com/v1/models"))
        )

        facade.noteDetectedEndpoint(endpoint, for: baseURL)

        XCTAssertNil(facade.detectedRequestStyle(for: baseURL))
    }

    func testModelCatalogKeepsStyleProvenByExplicitGenerationPath() throws {
        let baseURL = "https://compatible.example.com/v1/chat/completions"
        var facade = ChatModelCapabilityFacade(
            store: ChatModelCapabilityStore(),
            chatSettings: ChatSettings(apiURL: baseURL, selectedModel: "model", apiKey: ""),
            chatServerPresets: [],
            selectedChatServerPresetID: nil
        )
        let endpoint = ChatAPIEndpointCandidate(
            provider: .unknown,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: baseURL)),
            modelsURL: try XCTUnwrap(URL(string: "https://compatible.example.com/v1/models"))
        )

        facade.noteDetectedEndpoint(endpoint, for: baseURL)

        XCTAssertEqual(facade.detectedRequestStyle(for: baseURL), .openAIChatCompletions)
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
