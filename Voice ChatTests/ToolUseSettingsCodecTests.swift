import XCTest
@testable import Voice_Chat

final class ToolUseSettingsCodecTests: XCTestCase {
    func testDefaultsKeepGlobalToolUseDisabledForExistingUsers() {
        let decoded = ToolUseSettingsCodec.decode(from: nil)

        XCTAssertFalse(decoded.isEnabled)
        XCTAssertFalse(decoded.calendarEnabled)
        XCTAssertFalse(decoded.remindersEnabled)
        XCTAssertFalse(decoded.locationEnabled)
        XCTAssertFalse(decoded.motionEnabled)
        XCTAssertFalse(decoded.deviceContextEnabled)
        XCTAssertFalse(decoded.allowRemoteSensitiveTools)
        XCTAssertTrue(decoded.enabledToolIDs.isEmpty)
    }

    func testDecodeBackfillsInvalidPayloadToFallback() {
        let fallback = ToolUseSettings(
            isEnabled: true,
            calendarEnabled: false,
            remindersEnabled: true,
            locationEnabled: false,
            motionEnabled: true,
            deviceContextEnabled: false,
            allowRemoteSensitiveTools: true
        )

        XCTAssertEqual(ToolUseSettingsCodec.decode(from: "not-json", fallback: fallback), fallback)
    }

    func testDecodeBackfillsMissingKeysFromDefaults() {
        let decoded = ToolUseSettingsCodec.decode(from: """
        {"isEnabled":true,"calendarEnabled":false}
        """)

        XCTAssertTrue(decoded.isEnabled)
        XCTAssertFalse(decoded.calendarEnabled)
        XCTAssertFalse(decoded.remindersEnabled)
        XCTAssertFalse(decoded.locationEnabled)
        XCTAssertFalse(decoded.motionEnabled)
        XCTAssertFalse(decoded.deviceContextEnabled)
        XCTAssertFalse(decoded.allowRemoteSensitiveTools)
    }

    func testEnabledToolIDsRespectPerToolToggles() {
        let settings = ToolUseSettings(
            isEnabled: true,
            calendarEnabled: true,
            remindersEnabled: false,
            locationEnabled: true,
            motionEnabled: false,
            deviceContextEnabled: true
        )

        XCTAssertEqual(settings.enabledToolIDs, [
            .calendarListEvents,
            .locationCurrent,
            .deviceContext
        ])
    }

    func testRemoteEndpointFiltersSensitiveToolsUnlessExplicitlyAllowed() {
        var settings = ToolUseSettings(
            isEnabled: true,
            calendarEnabled: true,
            remindersEnabled: true,
            locationEnabled: true,
            motionEnabled: true,
            deviceContextEnabled: true
        )
        let remoteEndpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: URL(string: "https://api.openai.com/v1/chat/completions")!,
            modelsURL: URL(string: "https://api.openai.com/v1/models")!
        )

        XCTAssertEqual(settings.enabledToolIDs(for: remoteEndpoint), [.deviceContext])

        settings.allowRemoteSensitiveTools = true
        XCTAssertEqual(settings.enabledToolIDs(for: remoteEndpoint), settings.enabledToolIDs)
    }

    func testLocalEndpointKeepsSensitiveTools() {
        let settings = ToolUseSettings(
            isEnabled: true,
            calendarEnabled: true,
            remindersEnabled: true,
            locationEnabled: true,
            motionEnabled: true,
            deviceContextEnabled: true
        )
        let localEndpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: URL(string: "http://localhost:1234/api/v1/chat")!,
            modelsURL: URL(string: "http://localhost:1234/api/v1/models")!
        )

        XCTAssertEqual(settings.enabledToolIDs(for: localEndpoint), settings.enabledToolIDs)
    }
}
