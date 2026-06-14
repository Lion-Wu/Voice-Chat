import XCTest
@testable import Voice_Chat

final class ChatModelCapabilityStoreTests: XCTestCase {
    func testProviderReportedImageSupportOverridesManualAndIsScopedByEndpoint() {
        var store = ChatModelCapabilityStore(
            imageInputOverrides: ["plain-text-model": true]
        )

        XCTAssertTrue(
            store.supportsImageInput(
                for: "plain-text-model",
                apiBaseURL: "http://localhost:1234"
            )
        )

        store.updateImageInputSupport(["plain-text-model": false], for: "http://localhost:1234")

        XCTAssertFalse(
            store.supportsImageInput(
                for: "plain-text-model",
                apiBaseURL: "http://localhost:1234"
            )
        )
        XCTAssertTrue(
            store.supportsImageInput(
                for: "plain-text-model",
                apiBaseURL: "http://other-host:1234"
            )
        )
    }

    func testThinkingCapabilityAndSelectionUseScopedEndpointState() {
        var store = ChatModelCapabilityStore()
        let explicitCapability = ModelThinkingCapability(
            options: [.off, .high],
            defaultOption: .off
        )

        store.updateThinkingCapabilities(["custom-model": explicitCapability], for: "http://localhost:1234")

        XCTAssertEqual(
            store.thinkingCapability(
                for: "custom-model",
                apiBaseURL: "http://localhost:1234",
                provider: .openAICompatible,
                requestStyle: .openAIChatCompletions
            ),
            explicitCapability
        )
        XCTAssertNil(
            store.thinkingCapability(
                for: "custom-model",
                apiBaseURL: "http://other-host:1234",
                provider: .openAICompatible,
                requestStyle: .openAIChatCompletions
            )
        )

        store.setSelectedThinkingOption(
            .high,
            for: "custom-model",
            apiBaseURL: "http://localhost:1234",
            capability: explicitCapability
        )

        XCTAssertEqual(
            store.selectedThinkingOption(
                for: "custom-model",
                apiBaseURL: "http://localhost:1234",
                capability: explicitCapability
            ),
            .high
        )
    }

    func testDetectionHintsAndThinkingPreferencesPersistThroughDedicatedStore() throws {
        var store = ChatModelCapabilityStore()
        store.noteDetectedProvider(.anthropic, for: "https://api.anthropic.com")
        store.noteDetectedRequestStyle(.anthropicMessages, for: "https://api.anthropic.com")
        store.noteDetectedProvider(.unknown, for: "https://ignored.example")

        XCTAssertEqual(store.detectedProvider(for: "https://api.anthropic.com"), .anthropic)
        XCTAssertEqual(store.detectedRequestStyle(for: "https://api.anthropic.com"), .anthropicMessages)
        XCTAssertNil(store.detectedProvider(for: "https://ignored.example"))

        let suiteName = "ChatModelCapabilityStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let capability = ModelThinkingCapability(options: [.low, .high], defaultOption: .low)
        store.setSelectedThinkingOption(
            .high,
            for: "reasoning-model",
            apiBaseURL: "https://api.example.com/v1",
            capability: capability
        )
        store.saveThinkingPreferences(to: defaults, key: "thinking.preferences")

        XCTAssertEqual(
            ChatModelCapabilityStore.decodeThinkingPreferences(from: defaults, key: "thinking.preferences"),
            store.thinkingPreferences
        )
    }
}
