import XCTest
@testable import Voice_Chat

final class ChatToolExecutorTests: XCTestCase {
    func testUnknownToolReturnsStructuredFailure() async {
        let result = await makeExecutor().execute(
            ChatToolCallEnvelope(
                callID: "unknown-tool-call",
                name: "unknown_tool",
                argumentsJSON: "{}",
                provider: .openAI
            ),
            settings: enabledSettings(),
            endpoint: localEndpoint()
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.callID, "unknown-tool-call")
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

    func testSchemaMismatchIsRejectedBeforeAdapterExecution() async {
        let calendar = FakeCalendarTool()
        let result = await makeExecutor(calendarTool: calendar).execute(
            ChatToolCallEnvelope(
                callID: "calendar-create",
                name: ChatToolID.calendarCreateEvent.rawValue,
                argumentsJSON: #"{"title":"Class","start":"tomorrow","end":"tomorrow 1 hour from now","calendar_name":42}"#,
                provider: .openAI
            ),
            settings: enabledSettings(),
            endpoint: localEndpoint()
        )

        XCTAssertEqual(result.status, .invalidArguments)
        XCTAssertEqual(calendar.callCount, 0)
        XCTAssertTrue(result.summary.contains("arguments.calendar_name"))
    }

    func testUnknownArgumentIsRejectedBeforeAdapterExecution() async {
        let calendar = FakeCalendarTool()
        let result = await makeExecutor(calendarTool: calendar).execute(
            ChatToolCallEnvelope(
                callID: "calendar-list",
                name: ChatToolID.calendarListEvents.rawValue,
                argumentsJSON: #"{"unexpected":true}"#,
                provider: .openAI
            ),
            settings: enabledSettings(),
            endpoint: localEndpoint()
        )

        XCTAssertEqual(result.status, .invalidArguments)
        XCTAssertEqual(calendar.callCount, 0)
        XCTAssertTrue(result.summary.contains("arguments.unexpected"))
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

    func testEnabledReadToolIsAvailableToRemoteEndpoint() async {
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

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(calendar.callCount, 1)
    }

    func testWriteToolStillRequiresApprovalByPolicyForRemoteEndpointInReadOnlyMode() {
        var settings = enabledSettings()
        settings.calendarEnabled = true
        settings.authorizationMode = .readOnly

        for toolID in [ChatToolID.calendarCreateEvent, .calendarDeleteEvent, .remindersDeleteReminder] {
            XCTAssertEqual(
                ChatToolAuthorizationPolicy.decision(for: toolID, settings: settings, endpoint: remoteEndpoint()),
                .ask
            )
        }
    }

    func testCalendarDeleteToolUsesExactEventIdentifier() async {
        let result = await makeExecutor().execute(
            ChatToolCallEnvelope(
                callID: "calendar-delete",
                name: ChatToolID.calendarDeleteEvent.rawValue,
                argumentsJSON: #"{"event_id":"example-event-id"}"#,
                provider: .openAI
            ),
            settings: enabledSettings(),
            endpoint: localEndpoint()
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.payload["event_id"], .string("example-event-id"))
    }

    func testReminderDeleteToolUsesExactReminderIdentifier() async {
        let result = await makeExecutor().execute(
            ChatToolCallEnvelope(
                callID: "reminder-delete",
                name: ChatToolID.remindersDeleteReminder.rawValue,
                argumentsJSON: #"{"reminder_id":"example-reminder-id"}"#,
                provider: .openAI
            ),
            settings: enabledSettings(),
            endpoint: localEndpoint()
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.payload["reminder_id"], .string("example-reminder-id"))
    }

    func testSystemTimeReturnsLocalAndUTCRepresentations() async throws {
        var settings = enabledSettings()
        settings.timeEnabled = true
        let result = await makeExecutor().execute(
            ChatToolCallEnvelope(
                callID: "time",
                name: ChatToolID.systemGetTime.rawValue,
                argumentsJSON: "{}",
                provider: .lmStudio
            ),
            settings: settings,
            endpoint: localEndpoint()
        )

        XCTAssertEqual(result.status, .success)
        let isoTime = try XCTUnwrap(result.payload.stringValue("iso_time"))
        let localISOTime = try XCTUnwrap(result.payload.stringValue("local_iso_time"))
        let utcISOTime = try XCTUnwrap(result.payload.stringValue("utc_iso_time"))
        let offset = ChatToolTimeFormatter.timeZoneOffsetString()

        XCTAssertEqual(isoTime, localISOTime)
        XCTAssertTrue(localISOTime.hasSuffix(offset), localISOTime)
        XCTAssertTrue(utcISOTime.hasSuffix("Z") || utcISOTime.hasSuffix("+00:00"), utcISOTime)
        XCTAssertEqual(result.payload.stringValue("timezone"), TimeZone.autoupdatingCurrent.identifier)
        XCTAssertEqual(result.payload.stringValue("timezone_offset"), offset)
    }

    func testTemporalResolverAcceptsCommonISO8601Variants() {
        let samples = [
            "2001-01-01T12:34+08:00",
            "2001-01-01T12:34:56+08:00",
            "2001-01-01T12:34:56.789+08:00",
            "2001-01-01T12:34",
            "2001-01-01T12:34:56",
            "2001-01-01T12:34:56.789"
        ]

        for sample in samples {
            XCTAssertNotNil(ChatToolTemporalResolver.parseDateTime(sample), sample)
        }
    }

    func testTemporalResolverParsesNoSecondsOffsetAsExpectedInstant() throws {
        let date = try XCTUnwrap(ChatToolTemporalResolver.parseDateTime("2001-01-01T12:34+08:00"))
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2001-01-01T04:34:00Z"))

        XCTAssertEqual(date.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    func testTemporalRangeAcceptsEnglishRelativeTimesToTheSecond() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2001-01-07T12:34:56Z"))

        let range = try XCTUnwrap(ChatToolTemporalResolver.range(
            start: "1 hour ago",
            end: "now",
            defaultRange: nil,
            calendar: calendar,
            now: now
        ))
        let future = try XCTUnwrap(ChatToolTemporalResolver.timePoint(
            from: "1 hour from now",
            calendar: calendar,
            now: now
        ))

        XCTAssertEqual(range.start.timeIntervalSince1970, now.addingTimeInterval(-3600).timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(range.end.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(future.date.timeIntervalSince1970, now.addingTimeInterval(3600).timeIntervalSince1970, accuracy: 0.001)
    }

    func testTemporalRangeCoversDateOnlyAndWeekDescriptions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2001-01-07T12:34:56Z"))

        let today = try XCTUnwrap(ChatToolTemporalResolver.range(
            start: "today",
            end: nil,
            defaultRange: nil,
            calendar: calendar,
            now: now
        ))
        let thisWeek = try XCTUnwrap(ChatToolTemporalResolver.range(
            start: "this week",
            end: nil,
            defaultRange: nil,
            calendar: calendar,
            now: now
        ))

        XCTAssertEqual(today.end.timeIntervalSince(today.start), 86_400, accuracy: 0.001)
        XCTAssertEqual(thisWeek.end.timeIntervalSince(thisWeek.start), 7 * 86_400, accuracy: 0.001)
    }

    func testTemporalRangeKeepsExactEndWhenStartIsDateOnly() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2001-01-07T12:34:56Z"))

        let range = try XCTUnwrap(ChatToolTemporalResolver.range(
            start: "today",
            end: "now",
            defaultRange: nil,
            calendar: calendar,
            now: now
        ))

        XCTAssertEqual(range.end.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
    }

    func testTemporalRangeRejectsEndWithoutStart() {
        XCTAssertThrowsError(try ChatToolTemporalResolver.range(
            start: nil,
            end: "today",
            defaultRange: nil
        ))
    }

    func testTemporalResolverRejectsRemovedLegacyAndPartialDateForms() {
        XCTAssertThrowsError(try ChatToolTemporalResolver.date(from: "一小时前"))
        XCTAssertThrowsError(try ChatToolTemporalResolver.date(from: "2001-01-01 trailing text"))
        XCTAssertThrowsError(try ChatToolTemporalResolver.date(from: "right_now"))
        XCTAssertThrowsError(try ChatToolTemporalResolver.date(from: "Monday"))
        XCTAssertThrowsError(try ChatToolTemporalResolver.date(from: "+1 hour ago"))
        XCTAssertThrowsError(try ChatToolTemporalResolver.date(from: "1 hour later"))
        XCTAssertThrowsError(try ChatToolTemporalResolver.timePoint(from: "this week"))
    }

    func testArgumentReaderRejectsWrongTypesAndOutOfRangeValues() throws {
        let reader = try ChatToolArgumentReader(argumentsJSON: #"{"limit":"20","duration":4,"keywords":"math,science","enabled":1}"#)
        let hugeIntegerReader = try ChatToolArgumentReader(argumentsJSON: #"{"limit":1e100}"#)

        XCTAssertThrowsError(try reader.int("limit", default: 10, range: 1...50))
        XCTAssertThrowsError(try hugeIntegerReader.int("limit", default: 10, range: 1...50))
        XCTAssertThrowsError(try reader.double("duration", default: 1, range: 0.2...3))
        XCTAssertThrowsError(try reader.stringArray("keywords"))
        XCTAssertThrowsError(try reader.bool("enabled"))
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

    func createEvent(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        lock.withLock {
            storedCallCount += 1
        }
        return ChatToolExecutionPayload(payload: ["ok": .bool(true)], summary: "calendar created")
    }

    func deleteEvent(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        lock.withLock {
            storedCallCount += 1
        }
        return ChatToolExecutionPayload(
            payload: ["event_id": .string(arguments.string("event_id") ?? "")],
            summary: "calendar deleted"
        )
    }

    func showEvents(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        lock.withLock {
            storedCallCount += 1
        }
        return ChatToolExecutionPayload(
            payload: ["ok": .bool(true)],
            summary: "calendar shown",
            presentation: ChatToolPresentation(title: "Events", items: [])
        )
    }
}

private struct FakeRemindersTool: RemindersToolServing {
    func listReminders(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        ChatToolExecutionPayload(payload: ["ok": .bool(true)], summary: "reminders ok")
    }

    func createReminder(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        ChatToolExecutionPayload(payload: ["ok": .bool(true)], summary: "reminder created")
    }

    func deleteReminder(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        ChatToolExecutionPayload(
            payload: ["reminder_id": .string(arguments.string("reminder_id") ?? "")],
            summary: "reminder deleted"
        )
    }

    func showReminders(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        ChatToolExecutionPayload(
            payload: ["ok": .bool(true)],
            summary: "reminders shown",
            presentation: ChatToolPresentation(title: "Reminders", items: [])
        )
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

private extension Dictionary where Key == String, Value == JSONValue {
    func stringValue(_ key: String) -> String? {
        guard case let .string(value)? = self[key] else { return nil }
        return value
    }
}
