import XCTest
@testable import Voice_Chat

final class ChatToolExecutorTests: XCTestCase {
    func testUnknownToolReturnsStructuredFailure() async {
        let result = await makeExecutor().execute(
            ChatToolCallEnvelope(callID: "bad", name: "weather.get", argumentsJSON: "{}", provider: .openAI),
            settings: enabledSettings(),
            endpoint: localEndpoint()
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.callID, "bad")
        XCTAssertTrue(result.outputJSONString.contains("\"status\":\"failed\""))
    }

    func testMalformedArgumentsReturnInvalidArguments() async {
        let result = await makeExecutor().execute(
            ChatToolCallEnvelope(
                callID: "calendar",
                name: ChatToolID.calendarListEvents.rawValue,
                argumentsJSON: "{",
                provider: .openAI
            ),
            settings: enabledSettings(),
            endpoint: localEndpoint()
        )

        XCTAssertEqual(result.status, .invalidArguments)
    }

    func testDisabledToolUseDoesNotInvokeAdapter() async {
        let calendar = FakeCalendarTool()
        let result = await makeExecutor(calendarTool: calendar).execute(
            ChatToolCallEnvelope(
                callID: "calendar",
                name: ChatToolID.calendarListEvents.rawValue,
                argumentsJSON: "{}",
                provider: .openAI
            ),
            settings: .defaults,
            endpoint: localEndpoint()
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(calendar.callCount, 0)
    }

    func testEnabledToolReturnsAdapterPayload() async {
        let result = await makeExecutor().execute(
            ChatToolCallEnvelope(
                callID: "device",
                name: ChatToolID.deviceContext.rawValue,
                argumentsJSON: "{}",
                provider: .openAI
            ),
            settings: enabledSettings(),
            endpoint: localEndpoint()
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.payload["ok"], .bool(true))
        XCTAssertEqual(result.summary, "device ok")
    }

    func testLegacyDottedToolNameStillExecutes() async {
        let result = await makeExecutor().execute(
            ChatToolCallEnvelope(
                callID: "legacy-device",
                name: "device.get_context",
                argumentsJSON: "{}",
                provider: .openAI
            ),
            settings: enabledSettings(),
            endpoint: localEndpoint()
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.payload["ok"], .bool(true))
    }

    func testSensitiveToolIsDeniedForRemoteEndpointByDefault() async {
        let calendar = FakeCalendarTool()
        let result = await makeExecutor(calendarTool: calendar).execute(
            ChatToolCallEnvelope(
                callID: "remote-calendar",
                name: ChatToolID.calendarListEvents.rawValue,
                argumentsJSON: "{}",
                provider: .openAI
            ),
            settings: enabledSettings(),
            endpoint: remoteEndpoint()
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(calendar.callCount, 0)
    }

    func testSensitiveToolCanRunForRemoteEndpointWhenExplicitlyAllowed() async {
        let calendar = FakeCalendarTool()
        var settings = enabledSettings()
        settings.allowRemoteSensitiveTools = true

        let result = await makeExecutor(calendarTool: calendar).execute(
            ChatToolCallEnvelope(
                callID: "remote-calendar",
                name: ChatToolID.calendarListEvents.rawValue,
                argumentsJSON: "{}",
                provider: .openAI
            ),
            settings: settings,
            endpoint: remoteEndpoint()
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(calendar.callCount, 1)
    }

    private func makeExecutor(calendarTool: FakeCalendarTool = FakeCalendarTool()) -> ChatToolExecutor {
        ChatToolExecutor(
            calendarTool: calendarTool,
            remindersTool: FakeRemindersTool(),
            locationTool: FakeLocationTool(),
            motionTool: FakeMotionTool(),
            deviceTool: FakeDeviceTool()
        )
    }

    private func enabledSettings() -> ToolUseSettings {
        ToolUseSettings(
            isEnabled: true,
            calendarEnabled: true,
            remindersEnabled: true,
            locationEnabled: true,
            motionEnabled: true,
            deviceContextEnabled: true
        )
    }

    private func localEndpoint() -> ChatAPIEndpointCandidate {
        ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: URL(string: "http://localhost:1234/api/v1/chat")!,
            modelsURL: URL(string: "http://localhost:1234/api/v1/models")!
        )
    }

    private func remoteEndpoint() -> ChatAPIEndpointCandidate {
        ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: URL(string: "https://api.openai.com/v1/chat/completions")!,
            modelsURL: URL(string: "https://api.openai.com/v1/models")!
        )
    }
}

private final class FakeCalendarTool: CalendarToolServing, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCallCount = 0

    var callCount: Int {
        lock.withLock { storedCallCount }
    }

    func listEvents(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        lock.withLock {
            storedCallCount += 1
        }
        return ChatToolExecutionPayload(payload: ["ok": .bool(true)], summary: "calendar ok")
    }
}

private struct FakeRemindersTool: RemindersToolServing {
    func listReminders(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        ChatToolExecutionPayload(payload: ["ok": .bool(true)], summary: "reminders ok")
    }
}

private struct FakeLocationTool: LocationToolServing {
    func currentLocation(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        ChatToolExecutionPayload(payload: ["ok": .bool(true)], summary: "location ok")
    }
}

private struct FakeMotionTool: MotionToolServing {
    func deviceMotion(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        ChatToolExecutionPayload(payload: ["ok": .bool(true)], summary: "motion ok")
    }
}

private struct FakeDeviceTool: DeviceContextToolServing {
    func deviceContext(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        ChatToolExecutionPayload(payload: ["ok": .bool(true)], summary: "device ok")
    }
}
