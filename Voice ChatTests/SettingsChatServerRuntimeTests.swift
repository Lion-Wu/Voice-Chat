import XCTest
@testable import Voice_Chat

@MainActor
final class SettingsChatServerRuntimeTests: XCTestCase {
    func testUpdateSettingsPersistsSnapshotAndUpdatesSelectedPresetWhenContextExists() {
        let preset = ChatServerPreset(
            name: "Primary",
            apiURL: "http://old.local",
            selectedModel: "old-model"
        )
        var chatSettings = ChatSettings(apiURL: "http://old.local", selectedModel: "old-model", apiKey: "secret")
        var persisted: [ChatSettings] = []
        var saveLabels: [String] = []

        let didUpdatePreset = SettingsChatServerRuntime.updateSettings(
            apiURL: "http://new.local",
            selectedModel: "new-model",
            chatSettings: &chatSettings,
            presets: [preset],
            selectedID: preset.id,
            hasContext: true,
            persistChatSettings: { persisted.append($0) },
            save: { saveLabels.append($0) }
        )

        XCTAssertTrue(didUpdatePreset)
        XCTAssertEqual(chatSettings, ChatSettings(apiURL: "http://new.local", selectedModel: "new-model", apiKey: "secret"))
        XCTAssertEqual(persisted, [chatSettings])
        XCTAssertEqual(preset.apiURL, "http://new.local")
        XCTAssertEqual(preset.selectedModel, "new-model")
        XCTAssertEqual(saveLabels, ["update chat server preset"])
    }

    func testUpdateSettingsWithoutContextPersistsOnlyChatSettings() {
        let preset = ChatServerPreset(
            name: "Primary",
            apiURL: "http://old.local",
            selectedModel: "old-model"
        )
        var chatSettings = ChatSettings(apiURL: "http://old.local", selectedModel: "old-model", apiKey: "secret")
        var persisted: [ChatSettings] = []

        let didUpdatePreset = SettingsChatServerRuntime.updateSettings(
            apiURL: "http://offline.local",
            selectedModel: "offline-model",
            chatSettings: &chatSettings,
            presets: [preset],
            selectedID: preset.id,
            hasContext: false,
            persistChatSettings: { persisted.append($0) },
            save: { _ in XCTFail("preset saves require a model context") }
        )

        XCTAssertFalse(didUpdatePreset)
        XCTAssertEqual(chatSettings, ChatSettings(apiURL: "http://offline.local", selectedModel: "offline-model", apiKey: "secret"))
        XCTAssertEqual(persisted, [chatSettings])
        XCTAssertEqual(preset.apiURL, "http://old.local")
        XCTAssertEqual(preset.selectedModel, "old-model")
    }

    func testEqualSettingsDoNotPublishOrWrite() {
        let preset = ChatServerPreset(
            name: "Primary",
            apiURL: "http://same.local",
            selectedModel: "same-model"
        )
        var chatSettings = ChatSettings(
            apiURL: "http://same.local",
            selectedModel: "same-model",
            apiKey: "secret"
        )

        let didUpdatePreset = SettingsChatServerRuntime.updateSettings(
            apiURL: "http://same.local",
            selectedModel: "same-model",
            chatSettings: &chatSettings,
            presets: [preset],
            selectedID: preset.id,
            hasContext: true,
            persistChatSettings: { _ in XCTFail("equal settings must not publish") },
            save: { _ in XCTFail("equal settings must not write") }
        )

        XCTAssertFalse(didUpdatePreset)
    }

    func testEqualAPIKeyDoesNotTouchKeychainOrPreset() {
        let preset = ChatServerPreset(name: "Primary")
        var chatSettings = ChatSettings(
            apiURL: "http://local",
            selectedModel: "model",
            apiKey: "same-key"
        )
        let store = ChatAPIKeyStore(
            service: "runtime.test",
            loadString: { _, _ in XCTFail("equal in-memory key must not access Keychain"); return nil },
            saveString: { _, _, _ in
                XCTFail("equal key must not be saved")
                return false
            },
            deleteString: { _, _ in
                XCTFail("equal key must not be deleted")
                return false
            }
        )

        let didTouchPreset = SettingsChatServerRuntime.updateAPIKey(
            " same-key ",
            chatSettings: &chatSettings,
            selectedID: preset.id,
            presets: [preset],
            hasContext: true,
            apiKeyStore: store,
            save: { _ in XCTFail("equal key must not touch the preset") }
        )

        XCTAssertFalse(didTouchPreset)
    }

    func testUpdateAPIKeyStoresTrimmedKeyAndTouchesSelectedPreset() {
        let preset = ChatServerPreset(name: "Primary")
        var chatSettings = ChatSettings(apiURL: "http://local", selectedModel: "model", apiKey: "")
        var saved: [(value: String, service: String, account: String)] = []
        var saveLabels: [String] = []
        let store = ChatAPIKeyStore(
            service: "runtime.test",
            loadString: { _, _ in nil },
            saveString: { value, service, account in
                saved.append((value, service, account))
                return true
            },
            deleteString: { _, _ in
                XCTFail("non-empty API keys should be saved")
                return false
            }
        )

        let didTouchPreset = SettingsChatServerRuntime.updateAPIKey(
            "  token-123\n",
            chatSettings: &chatSettings,
            selectedID: preset.id,
            presets: [preset],
            hasContext: true,
            apiKeyStore: store,
            save: { saveLabels.append($0) }
        )

        XCTAssertTrue(didTouchPreset)
        XCTAssertEqual(chatSettings.apiKey, "token-123")
        XCTAssertEqual(saved.first?.value, "token-123")
        XCTAssertEqual(saved.first?.service, "runtime.test")
        XCTAssertEqual(saved.first?.account, store.account(forChatServerPresetID: preset.id))
        XCTAssertEqual(saveLabels, ["touch chat server preset api key"])
    }

    func testSelectPresetAppliesServerSettingsAndLoadedAPIKey() {
        let first = ChatServerPreset(
            name: "First",
            apiURL: "http://first.local",
            selectedModel: "first-model"
        )
        let second = ChatServerPreset(
            name: "Second",
            apiURL: "http://second.local",
            selectedModel: "second-model"
        )
        let appSettings = AppSettings(selectedChatServerPresetID: first.id)
        var selectedID: UUID? = first.id
        var chatSettings = ChatSettings(apiURL: "http://old.local", selectedModel: "old-model", apiKey: "old-key")
        var loadedAccounts: [String] = []
        var persisted: [ChatSettings] = []
        var saveLabels: [String] = []
        let store = ChatAPIKeyStore(
            service: "runtime.test",
            loadString: { _, account in
                loadedAccounts.append(account)
                return "  loaded-key\n"
            },
            saveString: { _, _, _ in
                XCTFail("selecting a preset should not save API keys")
                return false
            },
            deleteString: { _, _ in
                XCTFail("selecting a preset should not delete API keys")
                return false
            }
        )

        let didSelect = SettingsChatServerRuntime.selectPreset(
            id: second.id,
            selectedID: &selectedID,
            appSettings: appSettings,
            presets: [first, second],
            chatSettings: &chatSettings,
            apiKeyStore: store,
            persistChatSettings: { persisted.append($0) },
            save: { saveLabels.append($0) }
        )

        XCTAssertTrue(didSelect)
        XCTAssertEqual(selectedID, second.id)
        XCTAssertEqual(appSettings.selectedChatServerPresetID, second.id)
        XCTAssertEqual(chatSettings, ChatSettings(apiURL: "http://second.local", selectedModel: "second-model", apiKey: "loaded-key"))
        XCTAssertEqual(persisted, [chatSettings])
        XCTAssertEqual(loadedAccounts, [store.account(forChatServerPresetID: second.id)])
        XCTAssertEqual(saveLabels, ["select chat server preset"])
    }

    func testApplySelectedPresetPublishesFallbackSettingsAfterDeletion() {
        let fallback = ChatServerPreset(
            name: "Fallback",
            apiURL: "http://fallback.local",
            selectedModel: "fallback-model"
        )
        var chatSettings = ChatSettings(
            apiURL: "http://deleted.local",
            selectedModel: "deleted-model",
            apiKey: "deleted-key"
        )
        var persisted: [ChatSettings] = []
        let store = ChatAPIKeyStore(
            service: "runtime.test",
            loadString: { _, account in
                XCTAssertEqual(account, "chat_server_preset_api_key.\(fallback.id.uuidString)")
                return "fallback-key"
            },
            saveString: { _, _, _ in
                XCTFail("applying a fallback must not write its API key")
                return false
            },
            deleteString: { _, _ in
                XCTFail("applying a fallback must not delete an API key")
                return false
            }
        )

        let didApply = SettingsChatServerRuntime.applySelectedPresetToChatSettings(
            presets: [fallback],
            selectedID: fallback.id,
            chatSettings: &chatSettings,
            apiKeyStore: store,
            persistChatSettings: { persisted.append($0) }
        )

        XCTAssertTrue(didApply)
        XCTAssertEqual(
            chatSettings,
            ChatSettings(
                apiURL: "http://fallback.local",
                selectedModel: "fallback-model",
                apiKey: "fallback-key"
            )
        )
        XCTAssertEqual(persisted, [chatSettings])
    }
}
