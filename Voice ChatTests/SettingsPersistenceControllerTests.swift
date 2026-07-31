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
        let load = try controller.attach(
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

        let secondAttach = try controller.attach(
            context: context,
            chatAPIKeyForPreset: { _ in "other-key" },
            defaultHapticFeedbackEnabled: false,
            defaultAPIAdvancedSettings: .defaults
        )
        XCTAssertNil(secondAttach)
        XCTAssertEqual(controller.entity?.selectedChatServerPresetID, presetID)
    }

    @MainActor
    func testAttachReloadsStateWhenResetProvidesNewContext() throws {
        let firstContainer = try ModelContainer(
            for: AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let firstContext = ModelContext(firstContainer)
        firstContext.insert(AppSettings(apiURL: "https://old.example.com"))
        try firstContext.save()

        let secondContainer = try ModelContainer(
            for: AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let secondContext = ModelContext(secondContainer)
        secondContext.insert(AppSettings(apiURL: "https://new.example.com"))
        try secondContext.save()

        let controller = SettingsPersistenceController()
        _ = try controller.attach(
            context: firstContext,
            chatAPIKeyForPreset: { _ in "" },
            defaultHapticFeedbackEnabled: true,
            defaultAPIAdvancedSettings: .defaults
        )
        let reloaded = try controller.attach(
            context: secondContext,
            chatAPIKeyForPreset: { _ in "" },
            defaultHapticFeedbackEnabled: true,
            defaultAPIAdvancedSettings: .defaults
        )

        XCTAssertTrue(controller.context === secondContext)
        XCTAssertEqual(reloaded?.loadedState.chatSettings.apiURL, "https://new.example.com")
        XCTAssertTrue(controller.entity === reloaded?.entity)
    }

    @MainActor
    func testRollbackDiscardsDeferredStartupBackfills() throws {
        let container = try ModelContainer(
            for: AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let settings = AppSettings(
            hapticFeedbackEnabled: nil,
            apiAdvancedSettingsJSON: nil
        )
        context.insert(settings)
        try context.save()

        let controller = SettingsPersistenceController()
        _ = try controller.attach(
            context: context,
            chatAPIKeyForPreset: { _ in "" },
            defaultHapticFeedbackEnabled: true,
            defaultAPIAdvancedSettings: .defaults,
            deferSave: true
        )

        XCTAssertTrue(context.hasChanges)
        controller.discardBinding()
        XCTAssertFalse(context.hasChanges)
        XCTAssertNil(controller.context)
        XCTAssertNil(controller.entity)

        let verificationContext = ModelContext(container)
        let restored = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<AppSettings>()).first
        )
        XCTAssertNil(restored.hapticFeedbackEnabled)
        XCTAssertNil(restored.apiAdvancedSettingsJSON)
    }
}
