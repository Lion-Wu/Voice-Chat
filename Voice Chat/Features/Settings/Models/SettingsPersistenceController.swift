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
        defaultAPIAdvancedSettings: APIAdvancedSettings,
        deferSave: Bool = false
    ) throws -> SettingsPersistenceLoad? {
        guard self.context !== context else { return nil }
        self.context = context
        self.entity = nil

        let loadedEntity = try AppSettingsStore.loadOrCreate(in: context)
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
            save: { _ in }
        )

        if !deferSave {
            saveContext(label: "initialize app settings")
        }

        return SettingsPersistenceLoad(entity: loadedEntity, loadedState: loadedState)
    }

    func saveContext(label: String) {
        do {
            try saveContextOrThrow(label: label)
        } catch {
            print("SwiftData save failed (\(label)): \(error)")
        }
    }

    func saveContextOrThrow(label: String) throws {
        guard let context else { return }
        guard context.hasChanges else { return }
        try context.save()
    }

    func discardBinding() {
        context?.rollback()
        entity = nil
        context = nil
    }

    func rollbackPendingChanges() {
        context?.rollback()
    }
}
