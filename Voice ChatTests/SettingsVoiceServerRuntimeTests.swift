import XCTest
@testable import Voice_Chat

@MainActor
final class SettingsVoiceServerRuntimeTests: XCTestCase {
    func testUpdateSettingsPersistsSnapshotAndUpdatesSelectedPresetWhenContextExists() {
        let preset = VoiceServerPreset(
            name: "Primary",
            serverAddress: "http://old.local:9880"
        )
        var serverSettings = ServerSettings(serverAddress: "http://old.local:9880", textLang: "auto")
        var persisted: [ServerSettings] = []
        var saveLabels: [String] = []

        let didUpdatePreset = SettingsVoiceServerRuntime.updateSettings(
            serverAddress: "http://new.local:9880",
            textLang: "zh",
            serverSettings: &serverSettings,
            presets: [preset],
            selectedID: preset.id,
            hasContext: true,
            persistServerSettings: { persisted.append($0) },
            save: { saveLabels.append($0) }
        )

        XCTAssertTrue(didUpdatePreset)
        XCTAssertEqual(serverSettings, ServerSettings(serverAddress: "http://new.local:9880", textLang: "zh"))
        XCTAssertEqual(persisted, [serverSettings])
        XCTAssertEqual(preset.serverAddress, "http://new.local:9880")
        XCTAssertEqual(saveLabels, ["update voice server preset"])
    }

    func testUpdateSettingsWithoutContextPersistsOnlyServerSettings() {
        let preset = VoiceServerPreset(
            name: "Primary",
            serverAddress: "http://old.local:9880"
        )
        var serverSettings = ServerSettings(serverAddress: "http://old.local:9880", textLang: "auto")
        var persisted: [ServerSettings] = []

        let didUpdatePreset = SettingsVoiceServerRuntime.updateSettings(
            serverAddress: "http://offline.local:9880",
            textLang: "en",
            serverSettings: &serverSettings,
            presets: [preset],
            selectedID: preset.id,
            hasContext: false,
            persistServerSettings: { persisted.append($0) },
            save: { _ in XCTFail("preset saves require a model context") }
        )

        XCTAssertFalse(didUpdatePreset)
        XCTAssertEqual(serverSettings, ServerSettings(serverAddress: "http://offline.local:9880", textLang: "en"))
        XCTAssertEqual(persisted, [serverSettings])
        XCTAssertEqual(preset.serverAddress, "http://old.local:9880")
    }

    func testEqualSettingsDoNotPublishOrWrite() {
        let preset = VoiceServerPreset(
            name: "Primary",
            serverAddress: "http://same.local:9880"
        )
        var serverSettings = ServerSettings(
            serverAddress: "http://same.local:9880",
            textLang: "auto"
        )

        let didUpdatePreset = SettingsVoiceServerRuntime.updateSettings(
            serverAddress: "http://same.local:9880",
            textLang: "auto",
            serverSettings: &serverSettings,
            presets: [preset],
            selectedID: preset.id,
            hasContext: true,
            persistServerSettings: { _ in XCTFail("equal settings must not publish") },
            save: { _ in XCTFail("equal settings must not write") }
        )

        XCTAssertFalse(didUpdatePreset)
    }

    func testSelectPresetAppliesServerAddressAndKeepsCurrentTextLanguage() {
        let first = VoiceServerPreset(
            name: "First",
            serverAddress: "http://first.local:9880"
        )
        let second = VoiceServerPreset(
            name: "Second",
            serverAddress: "http://second.local:9880"
        )
        let appSettings = AppSettings(selectedVoiceServerPresetID: first.id)
        var selectedID: UUID? = first.id
        var serverSettings = ServerSettings(serverAddress: "http://old.local:9880", textLang: "ja")
        var persisted: [ServerSettings] = []
        var saveLabels: [String] = []

        let didSelect = SettingsVoiceServerRuntime.selectPreset(
            id: second.id,
            selectedID: &selectedID,
            appSettings: appSettings,
            presets: [first, second],
            serverSettings: &serverSettings,
            persistServerSettings: { persisted.append($0) },
            save: { saveLabels.append($0) }
        )

        XCTAssertTrue(didSelect)
        XCTAssertEqual(selectedID, second.id)
        XCTAssertEqual(appSettings.selectedVoiceServerPresetID, second.id)
        XCTAssertEqual(serverSettings, ServerSettings(serverAddress: "http://second.local:9880", textLang: "ja"))
        XCTAssertEqual(persisted, [serverSettings])
        XCTAssertEqual(saveLabels, ["select voice server preset"])
    }

    func testApplySelectedPresetPublishesFallbackSettingsAfterDeletion() {
        let fallback = VoiceServerPreset(
            name: "Fallback",
            serverAddress: "http://fallback.local:9880"
        )
        var serverSettings = ServerSettings(
            serverAddress: "http://deleted.local:9880",
            textLang: "zh"
        )
        var persisted: [ServerSettings] = []

        let didApply = SettingsVoiceServerRuntime.applySelectedPresetToServerSettings(
            presets: [fallback],
            selectedID: fallback.id,
            serverSettings: &serverSettings,
            persistServerSettings: { persisted.append($0) }
        )

        XCTAssertTrue(didApply)
        XCTAssertEqual(
            serverSettings,
            ServerSettings(serverAddress: "http://fallback.local:9880", textLang: "zh")
        )
        XCTAssertEqual(persisted, [serverSettings])
    }
}
