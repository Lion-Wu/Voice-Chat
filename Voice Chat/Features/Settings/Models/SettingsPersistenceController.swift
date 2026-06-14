//
//  SettingsPersistenceController.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2026/06/13.
//

import Foundation
import SwiftData

struct SettingsPersistenceLoad {
    let entity: AppSettings
    let loadedState: AppSettingsLoadedState
}

@MainActor
final class SettingsPersistenceController {
    private(set) var context: ModelContext?
    private(set) var entity: AppSettings?

    func attach(
        context: ModelContext,
        chatAPIKeyForPreset: (UUID?) -> String,
        defaultHapticFeedbackEnabled: Bool,
        defaultAPIAdvancedSettings: APIAdvancedSettings
    ) -> SettingsPersistenceLoad? {
        guard self.context == nil else { return nil }
        self.context = context

        let loadedEntity = AppSettingsStore.loadOrCreate(in: context)
        entity = loadedEntity

        let loadedState = AppSettingsStore.loadedState(
            from: loadedEntity,
            chatAPIKey: chatAPIKeyForPreset(loadedEntity.selectedChatServerPresetID),
            defaultHapticFeedbackEnabled: defaultHapticFeedbackEnabled,
            defaultAPIAdvancedSettings: defaultAPIAdvancedSettings
        )
        AppSettingsStore.backfillMissingValues(
            in: loadedEntity,
            loadedState: loadedState,
            save: saveContext(label:)
        )

        return SettingsPersistenceLoad(entity: loadedEntity, loadedState: loadedState)
    }

    func saveContext(label: String) {
        guard let context else { return }
        do {
            try context.save()
        } catch {
            print("SwiftData save failed (\(label)): \(error)")
        }
    }
}
