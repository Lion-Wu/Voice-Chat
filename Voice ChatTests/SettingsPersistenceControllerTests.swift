import SwiftData
import XCTest
@testable import Voice_Chat

final class SettingsPersistenceControllerTests: XCTestCase {
    @MainActor
    func testAttachLoadsBackfillsAndKeepsSingleBinding() throws {
        let presetID = UUID()
        let container = try ModelContainer(
            for: AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let settings = AppSettings(
            apiURL: "https://chat.example.com",
            selectedModel: "model-a",
            selectedChatServerPresetID: presetID,
            developerModeEnabled: true,
            hapticFeedbackEnabled: nil,
            apiAdvancedSettingsJSON: nil
        )
        context.insert(settings)
        try context.save()

        let controller = SettingsPersistenceController()
        let load = controller.attach(
            context: context,
            chatAPIKeyForPreset: { id in id == presetID ? "secret-key" : "" },
            defaultHapticFeedbackEnabled: true,
            defaultAPIAdvancedSettings: .defaults
        )

        XCTAssertNotNil(load)
        XCTAssertTrue(controller.entity === settings)
        XCTAssertEqual(load?.loadedState.chatSettings.apiKey, "secret-key")
        XCTAssertTrue(load?.loadedState.hapticFeedbackEnabled == true)
        XCTAssertEqual(settings.hapticFeedbackEnabled, true)
        XCTAssertNotNil(settings.apiAdvancedSettingsJSON)

        let secondAttach = controller.attach(
            context: context,
            chatAPIKeyForPreset: { _ in "other-key" },
            defaultHapticFeedbackEnabled: false,
            defaultAPIAdvancedSettings: .defaults
        )
        XCTAssertNil(secondAttach)
        XCTAssertEqual(controller.entity?.selectedChatServerPresetID, presetID)
    }
}
