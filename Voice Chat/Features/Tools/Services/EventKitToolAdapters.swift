//
//  EventKitToolAdapters.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation
#if canImport(EventKit)
import EventKit
#endif

protocol CalendarToolServing: Sendable {
    func listEvents(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload
    func createEvent(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload
    func deleteEvent(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload
    func showEvents(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload
}

protocol RemindersToolServing: Sendable {
    func listReminders(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload
    func createReminder(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload
    func deleteReminder(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload
    func showReminders(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload
}

enum EventKitReminderDateComponentsFactory {
    static func make(
        date: Date,
        isDateOnly: Bool,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let fields: Set<Calendar.Component> = isDateOnly
            ? [.year, .month, .day]
            : [.year, .month, .day, .hour, .minute, .second]
        var components = calendar.dateComponents(fields, from: date)
        components.calendar = calendar
        components.timeZone = timeZone
        return components
    }
}

struct EventKitCalendarTool: CalendarToolServing {
    func listEvents(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        #if canImport(EventKit)
        let store = EKEventStore()
        try await EventKitAuthorization.requestCalendarAccess(store: store)

        let calendar = Calendar.autoupdatingCurrent
        let requestedRange = try arguments.temporalRange(defaultRange: .today, calendar: calendar)
        guard let requestedRange, requestedRange.isValid else {
            throw ChatToolError.invalidArguments(NSLocalizedString("Calendar range end must be after start.", comment: "Tool-use error"))
        }
        let cappedEndExclusive = min(calendar.date(byAdding: .day, value: 31, to: requestedRange.start) ?? requestedRange.end, requestedRange.end)
        let rangeTruncated = requestedRange.end > cappedEndExclusive
        let limit = try arguments.int("limit", default: 20, range: 1...50)
        let calendarName = arguments.string("calendar_name")?.lowercased()
        let keywords = try Self.keywords(from: arguments)

        let calendars = store.calendars(for: .event).filter { calendar in
            guard let calendarName else { return true }
            return calendar.title.lowercased() == calendarName
        }
        if calendarName != nil && calendars.isEmpty {
            var payload: [String: JSONValue] = [
                "events": .array([]),
                "count": .number(0),
                "truncated": .bool(false),
                "range_truncated": .bool(rangeTruncated),
                "start": .string(Self.isoString(requestedRange.start)),
                "end": .string(Self.isoString(cappedEndExclusive)),
                "keywords": .array(keywords.map(JSONValue.string))
            ]
            payload.merge(ChatToolTimeFormatter.timeZonePayloadFields()) { current, _ in current }
            return ChatToolExecutionPayload(
                payload: payload,
                summary: String(format: NSLocalizedString("Found %d calendar event(s).", comment: "Tool summary"), 0)
            )
        }
        let predicate = store.predicateForEvents(
            withStart: requestedRange.start,
            end: cappedEndExclusive,
            calendars: calendars
        )
        let sortedEvents = store.events(matching: predicate)
            .filter { Self.matches($0, keywords: keywords) }
            .sorted { $0.startDate < $1.startDate }
        let events = Array(sortedEvents.prefix(limit))

        let rows: [JSONValue] = events.map { event in
            .object([
                "event_id": .string(event.eventIdentifier ?? ""),
                "title": .string(event.title ?? ""),
                "calendar": .string(event.calendar?.title ?? ""),
                "start": .string(Self.isoString(event.startDate)),
                "start_utc": .string(Self.utcIsoString(event.startDate)),
                "end": .string(Self.isoString(event.endDate)),
                "end_utc": .string(Self.utcIsoString(event.endDate)),
                "is_all_day": .bool(event.isAllDay),
                "location": .string(event.location ?? ""),
                "notes": .string(event.notes ?? "")
            ])
        }
        var payload: [String: JSONValue] = [
            "events": .array(rows),
            "count": .number(Double(rows.count)),
            "truncated": .bool(sortedEvents.count > limit || rangeTruncated),
            "range_truncated": .bool(rangeTruncated),
            "start": .string(Self.isoString(requestedRange.start)),
            "end": .string(Self.isoString(cappedEndExclusive)),
            "keywords": .array(keywords.map(JSONValue.string))
        ]
        payload.merge(ChatToolTimeFormatter.timeZonePayloadFields()) { current, _ in current }
        return ChatToolExecutionPayload(
            payload: payload,
            summary: String(format: NSLocalizedString("Found %d calendar event(s).", comment: "Tool summary"), rows.count)
        )
        #else
        throw ChatToolError.unsupported(NSLocalizedString("Calendar access is not available on this platform.", comment: "Tool-use error"))
        #endif
    }

    func createEvent(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        #if canImport(EventKit)
        let store = EKEventStore()
        try await EventKitAuthorization.requestCalendarAccess(store: store)

        let title = try arguments.requiredString("title")
        let start = try arguments.requiredTemporalDate("start")
        let end = try arguments.requiredTemporalDate("end")
        guard end > start else {
            throw ChatToolError.invalidArguments(NSLocalizedString("Event end must be after start.", comment: "Tool-use error"))
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = try arguments.bool("is_all_day")
        event.location = arguments.string("location")
        event.notes = arguments.string("notes")
        event.calendar = try Self.calendar(
            named: arguments.string("calendar_name"),
            in: store
        )
        try Task.checkCancellation()
        try store.save(event, span: .thisEvent, commit: true)

        let payload: [String: JSONValue] = [
            "event_id": .string(event.eventIdentifier ?? ""),
            "title": .string(event.title ?? ""),
            "calendar": .string(event.calendar?.title ?? ""),
            "start": .string(Self.isoString(event.startDate)),
            "start_utc": .string(Self.utcIsoString(event.startDate)),
            "end": .string(Self.isoString(event.endDate)),
            "end_utc": .string(Self.utcIsoString(event.endDate)),
            "timezone": .string(TimeZone.autoupdatingCurrent.identifier),
            "timezone_offset": .string(ChatToolTimeFormatter.timeZoneOffsetString(for: event.startDate)),
            "is_all_day": .bool(event.isAllDay)
        ]
        return ChatToolExecutionPayload(
            payload: payload,
            summary: NSLocalizedString("Calendar event was created.", comment: "Tool summary"),
            presentation: ChatToolPresentation(
                title: NSLocalizedString("Created Calendar Event", comment: "Tool presentation title"),
                subtitle: event.calendar?.title,
                items: [
                    ChatToolPresentationItem(
                        id: event.eventIdentifier ?? UUID().uuidString,
                        title: event.title ?? "",
                        subtitle: "\(Self.isoString(event.startDate)) - \(Self.isoString(event.endDate))",
                        detail: event.location,
                        metadata: [
                            "calendar": event.calendar?.title ?? "",
                            "all_day": event.isAllDay ? "true" : "false",
                            "notes": event.notes ?? ""
                        ]
                    )
                ],
                kind: .calendar
            )
        )
        #else
        throw ChatToolError.unsupported(NSLocalizedString("Calendar access is not available on this platform.", comment: "Tool-use error"))
        #endif
    }

    func deleteEvent(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        #if canImport(EventKit)
        let store = EKEventStore()
        try await EventKitAuthorization.requestCalendarAccess(store: store)

        let eventID = try arguments.requiredString("event_id")
        guard let event = store.event(withIdentifier: eventID) else {
            throw ChatToolError.invalidArguments(
                NSLocalizedString("No calendar event matches the supplied event_id.", comment: "Tool-use error")
            )
        }
        let deleteFutureEvents = try arguments.bool("delete_future_events")
        let payload: [String: JSONValue] = [
            "event_id": .string(event.eventIdentifier ?? eventID),
            "title": .string(event.title ?? ""),
            "calendar": .string(event.calendar?.title ?? ""),
            "start": .string(Self.isoString(event.startDate)),
            "end": .string(Self.isoString(event.endDate)),
            "deleted_future_events": .bool(deleteFutureEvents)
        ]
        try Task.checkCancellation()
        try store.remove(
            event,
            span: deleteFutureEvents ? .futureEvents : .thisEvent,
            commit: true
        )
        return ChatToolExecutionPayload(
            payload: payload,
            summary: NSLocalizedString("Calendar event was deleted.", comment: "Tool summary")
        )
        #else
        throw ChatToolError.unsupported(NSLocalizedString("Calendar access is not available on this platform.", comment: "Tool-use error"))
        #endif
    }

    func showEvents(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        var result = try await listEvents(arguments: arguments)
        let items = Self.presentationItems(fromEventsPayload: result.payload)
        result.presentation = ChatToolPresentation(
            title: NSLocalizedString("Calendar Events", comment: "Tool presentation title"),
            subtitle: result.summary,
            items: items,
            kind: .calendar
        )
        return result
    }

    #if canImport(EventKit)
    private static func isoString(_ date: Date?) -> String {
        guard let date else { return "" }
        return ChatToolTimeFormatter.localISO8601String(from: date)
    }

    private static func utcIsoString(_ date: Date?) -> String {
        guard let date else { return "" }
        return ChatToolTimeFormatter.utcISO8601String(from: date)
    }

    private static func calendar(named name: String?, in store: EKEventStore) throws -> EKCalendar {
        guard let name else {
            guard let calendar = store.defaultCalendarForNewEvents else {
                throw ChatToolError.failed(NSLocalizedString("No default calendar is available.", comment: "Tool-use error"))
            }
            return calendar
        }
        let lowercased = name.lowercased()
        let calendars = store.calendars(for: .event)
        let exactMatches = calendars.filter { $0.title.lowercased() == lowercased }
        if exactMatches.count == 1, let calendar = exactMatches.first {
            return calendar
        }
        if exactMatches.count > 1 {
            throw ChatToolError.invalidArguments(
                String(format: NSLocalizedString("Calendar name is ambiguous: %@", comment: "Tool-use error"), name)
            )
        }
        throw ChatToolError.invalidArguments(
            String(format: NSLocalizedString("Calendar not found: %@", comment: "Tool-use error"), name)
        )
    }

    private static func keywords(from arguments: ChatToolArgumentReader) throws -> [String] {
        let values = try arguments.stringArray("keywords")
        var output: [String] = []
        var seen = Set<String>()
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            output.append(normalized)
        }
        return output
    }

    private static func matches(_ event: EKEvent, keywords: [String]) -> Bool {
        guard !keywords.isEmpty else { return true }
        let haystack = [
            event.title,
            event.location,
            event.notes,
            event.calendar?.title
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: "\n")
        return keywords.contains { haystack.contains($0) }
    }

    private static func presentationItems(fromEventsPayload payload: [String: JSONValue]) -> [ChatToolPresentationItem] {
        guard case let .array(events)? = payload["events"] else { return [] }
        return events.enumerated().compactMap { index, value in
            guard case let .object(event) = value else { return nil }
            let title = event.stringValue("title") ?? NSLocalizedString("Untitled Event", comment: "Tool presentation fallback")
            let start = event.stringValue("start") ?? ""
            let end = event.stringValue("end") ?? ""
            return ChatToolPresentationItem(
                id: event.stringValue("event_id") ?? "\(index)-\(title)-\(start)",
                title: title,
                subtitle: "\(start) - \(end)",
                detail: event.stringValue("location"),
                metadata: [
                    "calendar": event.stringValue("calendar") ?? "",
                    "all_day": event.boolValue("is_all_day") ? "true" : "false",
                    "notes": event.stringValue("notes") ?? ""
                ]
            )
        }
    }
    #endif
}

struct EventKitRemindersTool: RemindersToolServing {
    func listReminders(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        #if canImport(EventKit)
        let store = EKEventStore()
        try await EventKitAuthorization.requestReminderAccess(store: store)

        let status = arguments.string("status") ?? "incomplete"
        guard ["incomplete", "completed", "all"].contains(status) else {
            throw ChatToolError.invalidArguments(NSLocalizedString("status must be incomplete, completed, or all.", comment: "Tool-use error"))
        }
        let listName = arguments.string("list_name")?.lowercased()
        let limit = try arguments.int("limit", default: 20, range: 1...50)
        let calendar = Calendar.autoupdatingCurrent
        let requestedRange = try arguments.temporalRange(defaultRange: nil, calendar: calendar)
        if let requestedRange, !requestedRange.isValid {
            throw ChatToolError.invalidArguments(NSLocalizedString("Reminder range end must be after start.", comment: "Tool-use error"))
        }
        let keywords = try Self.keywords(from: arguments)

        let calendars = store.calendars(for: .reminder).filter { calendar in
            guard let listName else { return true }
            return calendar.title.lowercased() == listName
        }
        if listName != nil && calendars.isEmpty {
            var payload: [String: JSONValue] = [
                "reminders": .array([]),
                "count": .number(0),
                "truncated": .bool(false),
                "start": .string(requestedRange.map { EventKitCalendarToolISO.isoString($0.start) } ?? ""),
                "end": .string(requestedRange.map { EventKitCalendarToolISO.isoString($0.end) } ?? ""),
                "keywords": .array(keywords.map(JSONValue.string))
            ]
            payload.merge(ChatToolTimeFormatter.timeZonePayloadFields()) { current, _ in current }
            return ChatToolExecutionPayload(
                payload: payload,
                summary: String(format: NSLocalizedString("Found %d reminder(s).", comment: "Tool summary"), 0)
            )
        }
        let predicate = store.predicateForReminders(in: calendars)
        let reminders: [EventKitReminderSnapshot] = await withCheckedContinuation { (continuation: CheckedContinuation<[EventKitReminderSnapshot], Never>) in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(EventKitReminderSnapshot.init(reminder:)))
            }
        }

        let filteredReminders = reminders.filter { reminder in
            let statusMatches: Bool
            switch status {
            case "completed":
                statusMatches = reminder.isCompleted
            case "all":
                statusMatches = true
            default:
                statusMatches = !reminder.isCompleted
            }

            let due = reminder.dueDate
            let startsAfter: Bool
            if let requestedRange {
                startsAfter = due.map { $0 >= requestedRange.start } ?? false
            } else {
                startsAfter = true
            }

            let endsBefore: Bool
            if let requestedRange {
                endsBefore = due.map { $0 < requestedRange.end } ?? false
            } else {
                endsBefore = true
            }

            return statusMatches && startsAfter && endsBefore && Self.matches(reminder, keywords: keywords)
        }

        let sortedReminders = filteredReminders.sorted { lhs, rhs in
            (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
        }
        let limitedReminders = Array(sortedReminders.prefix(limit))

        let rows: [JSONValue] = limitedReminders.map { reminder in
            .object([
                "reminder_id": .string(reminder.identifier),
                "title": .string(reminder.title ?? ""),
                "list": .string(reminder.listTitle),
                "is_completed": .bool(reminder.isCompleted),
                "due": .string(reminder.dueDate.map(EventKitCalendarToolISO.isoString) ?? ""),
                "due_utc": .string(reminder.dueDate.map(EventKitCalendarToolISO.utcIsoString) ?? ""),
                "priority": .number(Double(reminder.priority)),
                "notes": .string(reminder.notes ?? "")
            ])
        }
        var payload: [String: JSONValue] = [
            "reminders": .array(rows),
            "count": .number(Double(rows.count)),
            "truncated": .bool(sortedReminders.count > limit),
            "start": .string(requestedRange.map { EventKitCalendarToolISO.isoString($0.start) } ?? ""),
            "end": .string(requestedRange.map { EventKitCalendarToolISO.isoString($0.end) } ?? ""),
            "keywords": .array(keywords.map(JSONValue.string))
        ]
        payload.merge(ChatToolTimeFormatter.timeZonePayloadFields()) { current, _ in current }
        return ChatToolExecutionPayload(
            payload: payload,
            summary: String(format: NSLocalizedString("Found %d reminder(s).", comment: "Tool summary"), rows.count)
        )
        #else
        throw ChatToolError.unsupported(NSLocalizedString("Reminders access is not available on this platform.", comment: "Tool-use error"))
        #endif
    }

    func createReminder(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        #if canImport(EventKit)
        let store = EKEventStore()
        try await EventKitAuthorization.requestReminderAccess(store: store)

        let reminder = EKReminder(eventStore: store)
        reminder.title = try arguments.requiredString("title")
        reminder.notes = arguments.string("notes")
        reminder.priority = try arguments.int("priority", default: 0, range: 0...9)
        reminder.calendar = try Self.calendar(
            named: arguments.string("list_name"),
            in: store
        )
        if let due = try arguments.temporalTimePoint("due") {
            let dateComponents = EventKitReminderDateComponentsFactory.make(
                date: due.date,
                isDateOnly: due.isDateOnly
            )
            reminder.startDateComponents = dateComponents
            reminder.dueDateComponents = dateComponents
        }
        try Task.checkCancellation()
        try store.save(reminder, commit: true)

        let payload: [String: JSONValue] = [
            "reminder_id": .string(reminder.calendarItemIdentifier),
            "title": .string(reminder.title ?? ""),
            "list": .string(reminder.calendar.title),
            "due": .string(reminder.dueDateComponents?.date.map(EventKitCalendarToolISO.isoString) ?? ""),
            "due_utc": .string(reminder.dueDateComponents?.date.map(EventKitCalendarToolISO.utcIsoString) ?? ""),
            "timezone": .string(TimeZone.autoupdatingCurrent.identifier),
            "timezone_offset": .string(ChatToolTimeFormatter.timeZoneOffsetString(for: reminder.dueDateComponents?.date ?? Date())),
            "priority": .number(Double(reminder.priority))
        ]
        return ChatToolExecutionPayload(
            payload: payload,
            summary: NSLocalizedString("Reminder was created.", comment: "Tool summary"),
            presentation: ChatToolPresentation(
                title: NSLocalizedString("Created Reminder", comment: "Tool presentation title"),
                subtitle: reminder.calendar.title,
                items: [
                    ChatToolPresentationItem(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "",
                        subtitle: reminder.dueDateComponents?.date.map(EventKitCalendarToolISO.isoString),
                        detail: reminder.notes,
                        metadata: [
                            "list": reminder.calendar.title,
                            "priority": "\(reminder.priority)",
                            "completed": "false"
                        ]
                    )
                ],
                kind: .reminders
            )
        )
        #else
        throw ChatToolError.unsupported(NSLocalizedString("Reminders access is not available on this platform.", comment: "Tool-use error"))
        #endif
    }

    func deleteReminder(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        #if canImport(EventKit)
        let store = EKEventStore()
        try await EventKitAuthorization.requestReminderAccess(store: store)

        let reminderID = try arguments.requiredString("reminder_id")
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw ChatToolError.invalidArguments(
                NSLocalizedString("No reminder matches the supplied reminder_id.", comment: "Tool-use error")
            )
        }
        let dueDate = reminder.dueDateComponents?.date
        let payload: [String: JSONValue] = [
            "reminder_id": .string(reminder.calendarItemIdentifier),
            "title": .string(reminder.title ?? ""),
            "list": .string(reminder.calendar.title),
            "due": .string(dueDate.map(EventKitCalendarToolISO.isoString) ?? ""),
            "is_completed": .bool(reminder.isCompleted)
        ]
        try Task.checkCancellation()
        try store.remove(reminder, commit: true)
        return ChatToolExecutionPayload(
            payload: payload,
            summary: NSLocalizedString("Reminder was deleted.", comment: "Tool summary")
        )
        #else
        throw ChatToolError.unsupported(NSLocalizedString("Reminders access is not available on this platform.", comment: "Tool-use error"))
        #endif
    }

    func showReminders(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        var result = try await listReminders(arguments: arguments)
        result.presentation = ChatToolPresentation(
            title: NSLocalizedString("Reminders", comment: "Tool presentation title"),
            subtitle: result.summary,
            items: Self.presentationItems(fromRemindersPayload: result.payload),
            kind: .reminders
        )
        return result
    }

    #if canImport(EventKit)
    private static func calendar(named name: String?, in store: EKEventStore) throws -> EKCalendar {
        guard let name else {
            guard let calendar = store.defaultCalendarForNewReminders() else {
                throw ChatToolError.failed(NSLocalizedString("No default reminder list is available.", comment: "Tool-use error"))
            }
            return calendar
        }
        let lowercased = name.lowercased()
        let calendars = store.calendars(for: .reminder)
        let exactMatches = calendars.filter { $0.title.lowercased() == lowercased }
        if exactMatches.count == 1, let calendar = exactMatches.first {
            return calendar
        }
        if exactMatches.count > 1 {
            throw ChatToolError.invalidArguments(
                String(format: NSLocalizedString("Reminder list name is ambiguous: %@", comment: "Tool-use error"), name)
            )
        }
        throw ChatToolError.invalidArguments(
            String(format: NSLocalizedString("Reminder list not found: %@", comment: "Tool-use error"), name)
        )
    }

    private static func keywords(from arguments: ChatToolArgumentReader) throws -> [String] {
        let values = try arguments.stringArray("keywords")
        var output: [String] = []
        var seen = Set<String>()
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            output.append(normalized)
        }
        return output
    }

    private static func matches(_ reminder: EventKitReminderSnapshot, keywords: [String]) -> Bool {
        guard !keywords.isEmpty else { return true }
        let haystack = [
            reminder.title,
            reminder.notes,
            reminder.listTitle
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: "\n")
        return keywords.contains { haystack.contains($0) }
    }

    private static func presentationItems(fromRemindersPayload payload: [String: JSONValue]) -> [ChatToolPresentationItem] {
        guard case let .array(reminders)? = payload["reminders"] else { return [] }
        return reminders.enumerated().compactMap { index, value in
            guard case let .object(reminder) = value else { return nil }
            let title = reminder.stringValue("title") ?? NSLocalizedString("Untitled Reminder", comment: "Tool presentation fallback")
            return ChatToolPresentationItem(
                id: reminder.stringValue("reminder_id") ?? "\(index)-\(title)-\(reminder.stringValue("due") ?? "")",
                title: title,
                subtitle: reminder.stringValue("due"),
                detail: reminder.stringValue("notes"),
                metadata: [
                    "list": reminder.stringValue("list") ?? "",
                    "priority": "\(Int(reminder.numberValue("priority") ?? 0))",
                    "completed": reminder.boolValue("is_completed") ? "true" : "false"
                ]
            )
        }
    }
    #endif
}

private extension Dictionary where Key == String, Value == JSONValue {
    func stringValue(_ key: String) -> String? {
        guard case let .string(value)? = self[key], !value.isEmpty else { return nil }
        return value
    }

    func boolValue(_ key: String) -> Bool {
        guard case let .bool(value)? = self[key] else { return false }
        return value
    }

    func numberValue(_ key: String) -> Double? {
        guard case let .number(value)? = self[key] else { return nil }
        return value
    }
}

#if canImport(EventKit)
private enum EventKitAuthorization {
    static func requestCalendarAccess(store: EKEventStore) async throws {
        if #available(iOS 17.0, macOS 14.0, visionOS 1.0, *) {
            let granted = try await store.requestFullAccessToEvents()
            guard granted else { throw ChatToolError.denied(NSLocalizedString("Calendar permission was denied.", comment: "Tool-use error")) }
        } else {
            let granted = try await store.requestAccess(to: .event)
            guard granted else { throw ChatToolError.denied(NSLocalizedString("Calendar permission was denied.", comment: "Tool-use error")) }
        }
    }

    static func requestReminderAccess(store: EKEventStore) async throws {
        if #available(iOS 17.0, macOS 14.0, visionOS 1.0, *) {
            let granted = try await store.requestFullAccessToReminders()
            guard granted else { throw ChatToolError.denied(NSLocalizedString("Reminders permission was denied.", comment: "Tool-use error")) }
        } else {
            let granted = try await store.requestAccess(to: .reminder)
            guard granted else { throw ChatToolError.denied(NSLocalizedString("Reminders permission was denied.", comment: "Tool-use error")) }
        }
    }
}

private enum EventKitCalendarToolISO {
    static func isoString(_ date: Date) -> String {
        ChatToolTimeFormatter.localISO8601String(from: date)
    }

    static func utcIsoString(_ date: Date) -> String {
        ChatToolTimeFormatter.utcISO8601String(from: date)
    }
}

private struct EventKitReminderSnapshot: Sendable {
    let identifier: String
    let title: String?
    let listTitle: String
    let isCompleted: Bool
    let dueDate: Date?
    let priority: Int
    let notes: String?

    init(reminder: EKReminder) {
        identifier = reminder.calendarItemIdentifier
        title = reminder.title
        listTitle = reminder.calendar.title
        isCompleted = reminder.isCompleted
        dueDate = reminder.dueDateComponents?.date
        priority = reminder.priority
        notes = reminder.notes
    }
}
#endif
