import SwiftData
import XCTest
@testable import Voice_Chat

@MainActor
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
        XCTAssertFalse(
            store.isImageInputSupportUnknown(
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
                provider: .openAI,
                requestStyle: .openAIChatCompletions
            ),
            explicitCapability
        )
        XCTAssertNil(
            store.thinkingCapability(
                for: "custom-model",
                apiBaseURL: "http://other-host:1234",
                provider: .openAI,
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

        let capability = ModelThinkingCapability(options: [.low, .high], defaultOption: .low)
        store.setSelectedThinkingOption(
            .high,
            for: "reasoning-model",
            apiBaseURL: "https://api.example.com/v1",
            capability: capability
        )
        let container = try ModelContainer(for: AppSettings.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let settings = AppSettings()
        context.insert(settings)
        try store.savePreferences(to: settings)
        try context.save()
        let reloaded = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<AppSettings>()).first)
        let restored = ChatModelCapabilityStore.restoringPreferences(from: reloaded)
        XCTAssertEqual(restored.detectedProviderHints, store.detectedProviderHints)
        XCTAssertEqual(restored.detectedRequestStyleHints, store.detectedRequestStyleHints)
        XCTAssertEqual(restored.thinkingPreferences, store.thinkingPreferences)
    }
}
