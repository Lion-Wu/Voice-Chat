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
}

protocol RemindersToolServing: Sendable {
    func listReminders(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload
}

struct EventKitCalendarTool: CalendarToolServing {
    func listEvents(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        #if canImport(EventKit)
        let store = EKEventStore()
        try await EventKitAuthorization.requestCalendarAccess(store: store)

        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let requestedStart = try arguments.localDate("start_date", calendar: calendar) ?? today
        let requestedEnd = try arguments.localDate("end_date", calendar: calendar) ?? requestedStart
        let cappedEnd = min(calendar.date(byAdding: .day, value: 31, to: requestedStart) ?? requestedEnd, requestedEnd)
        let rangeTruncated = requestedEnd > cappedEnd
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: cappedEnd) ?? cappedEnd
        let limit = arguments.int("limit", default: 20, range: 1...50)
        let calendarName = arguments.string("calendar_name")?.lowercased()

        let calendars = store.calendars(for: .event).filter { calendar in
            guard let calendarName else { return true }
            return calendar.title.lowercased().contains(calendarName)
        }
        if calendarName != nil && calendars.isEmpty {
            return ChatToolExecutionPayload(
                payload: [
                    "events": .array([]),
                    "count": .number(0),
                    "truncated": .bool(false),
                    "range_truncated": .bool(rangeTruncated)
                ],
                summary: String(format: NSLocalizedString("Found %d calendar event(s).", comment: "Tool summary"), 0)
            )
        }
        let predicate = store.predicateForEvents(
            withStart: requestedStart,
            end: endExclusive,
            calendars: calendars
        )
        let sortedEvents = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
        let events = Array(sortedEvents.prefix(limit))

        let rows: [JSONValue] = events.map { event in
            .object([
                "title": .string(event.title ?? ""),
                "calendar": .string(event.calendar?.title ?? ""),
                "start": .string(Self.isoString(event.startDate)),
                "end": .string(Self.isoString(event.endDate)),
                "is_all_day": .bool(event.isAllDay),
                "location": .string(event.location ?? "")
            ])
        }
        return ChatToolExecutionPayload(
            payload: [
                "events": .array(rows),
                "count": .number(Double(rows.count)),
                "truncated": .bool(sortedEvents.count > limit || rangeTruncated),
                "range_truncated": .bool(rangeTruncated)
            ],
            summary: String(format: NSLocalizedString("Found %d calendar event(s).", comment: "Tool summary"), rows.count)
        )
        #else
        throw ChatToolError.unsupported(NSLocalizedString("Calendar access is not available on this platform.", comment: "Tool-use error"))
        #endif
    }

    #if canImport(EventKit)
    private static func isoString(_ date: Date?) -> String {
        guard let date else { return "" }
        return ISO8601DateFormatter().string(from: date)
    }
    #endif
}

struct EventKitRemindersTool: RemindersToolServing {
    func listReminders(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        #if canImport(EventKit)
        let store = EKEventStore()
        try await EventKitAuthorization.requestReminderAccess(store: store)

        let status = arguments.string("status") ?? "incomplete"
        let listName = arguments.string("list_name")?.lowercased()
        let limit = arguments.int("limit", default: 20, range: 1...50)
        let startDate = try arguments.localDate("start_date")
        let endDate = try arguments.localDate("end_date").flatMap {
            Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: $0)
        }

        let calendars = store.calendars(for: .reminder).filter { calendar in
            guard let listName else { return true }
            return calendar.title.lowercased().contains(listName)
        }
        if listName != nil && calendars.isEmpty {
            return ChatToolExecutionPayload(
                payload: [
                    "reminders": .array([]),
                    "count": .number(0),
                    "truncated": .bool(false)
                ],
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
            if let startDate {
                startsAfter = due.map { $0 >= startDate } ?? false
            } else {
                startsAfter = true
            }

            let endsBefore: Bool
            if let endDate {
                endsBefore = due.map { $0 < endDate } ?? false
            } else {
                endsBefore = true
            }

            return statusMatches && startsAfter && endsBefore
        }

        let sortedReminders = filteredReminders.sorted { lhs, rhs in
            (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
        }
        let limitedReminders = Array(sortedReminders.prefix(limit))

        let rows: [JSONValue] = limitedReminders.map { reminder in
            .object([
                "title": .string(reminder.title ?? ""),
                "list": .string(reminder.listTitle),
                "is_completed": .bool(reminder.isCompleted),
                "due": .string(reminder.dueDate.map(EventKitCalendarToolISO.isoString) ?? ""),
                "priority": .number(Double(reminder.priority))
            ])
        }
        return ChatToolExecutionPayload(
            payload: [
                "reminders": .array(rows),
                "count": .number(Double(rows.count)),
                "truncated": .bool(sortedReminders.count > limit)
            ],
            summary: String(format: NSLocalizedString("Found %d reminder(s).", comment: "Tool summary"), rows.count)
        )
        #else
        throw ChatToolError.unsupported(NSLocalizedString("Reminders access is not available on this platform.", comment: "Tool-use error"))
        #endif
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
        ISO8601DateFormatter().string(from: date)
    }
}

private struct EventKitReminderSnapshot: Sendable {
    let title: String?
    let listTitle: String
    let isCompleted: Bool
    let dueDate: Date?
    let priority: Int

    init(reminder: EKReminder) {
        title = reminder.title
        listTitle = reminder.calendar.title
        isCompleted = reminder.isCompleted
        dueDate = reminder.dueDateComponents?.date
        priority = reminder.priority
    }
}
#endif
