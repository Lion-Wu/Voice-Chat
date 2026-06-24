//
//  ChatToolDefinitions.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation

enum ChatToolDefinitions {
    static func definitions(enabledIDs: Set<ChatToolID>) -> [ChatToolDefinition] {
        ChatToolID.allCases.compactMap { id in
            guard enabledIDs.contains(id) else { return nil }
            return definition(for: id)
        }
    }

    static func definition(for id: ChatToolID) -> ChatToolDefinition {
        switch id {
        case .calendarListEvents:
            return ChatToolDefinition(
                id: id,
                description: "Read calendar events for a date range.",
                parametersSchema: object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "start_date": isoDateDescription("Inclusive local date in YYYY-MM-DD format. Defaults to today."),
                        "end_date": isoDateDescription("Inclusive local date in YYYY-MM-DD format. Defaults to start_date."),
                        "calendar_name": stringDescription("Optional calendar name filter."),
                        "limit": integerDescription("Maximum number of events to return. Defaults to 20, maximum 50.")
                    ])
                ])
            )

        case .remindersListReminders:
            return ChatToolDefinition(
                id: id,
                description: "Read reminders.",
                parametersSchema: object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "status": .object([
                            "type": .string("string"),
                            "description": .string("Reminder status filter."),
                            "enum": .array([.string("incomplete"), .string("completed"), .string("all")])
                        ]),
                        "start_date": isoDateDescription("Optional inclusive due-date lower bound in YYYY-MM-DD format."),
                        "end_date": isoDateDescription("Optional inclusive due-date upper bound in YYYY-MM-DD format."),
                        "list_name": stringDescription("Optional reminder list name filter."),
                        "limit": integerDescription("Maximum number of reminders to return. Defaults to 20, maximum 50.")
                    ])
                ])
            )

        case .locationCurrent:
            return ChatToolDefinition(
                id: id,
                description: "Read the device's current foreground location.",
                parametersSchema: emptyObjectSchema
            )

        case .motionDevice:
            return ChatToolDefinition(
                id: id,
                description: "Read a short device-motion snapshot.",
                parametersSchema: object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "duration_seconds": .object([
                            "type": .string("number"),
                            "description": .string("Snapshot duration. Defaults to 1.0 and is capped at 3.0 seconds."),
                            "minimum": .number(0.2),
                            "maximum": .number(3.0)
                        ])
                    ])
                ])
            )

        case .deviceContext:
            return ChatToolDefinition(
                id: id,
                description: "Read local device context such as platform, OS version, locale, timezone, and power state.",
                parametersSchema: emptyObjectSchema
            )
        }
    }

    static func activityTitle(for name: String) -> String {
        switch ChatToolID(toolName: name) {
        case .calendarListEvents:
            return NSLocalizedString("Checking Calendar", comment: "Tool activity title")
        case .remindersListReminders:
            return NSLocalizedString("Reading Reminders", comment: "Tool activity title")
        case .locationCurrent:
            return NSLocalizedString("Getting Location", comment: "Tool activity title")
        case .motionDevice:
            return NSLocalizedString("Reading Motion", comment: "Tool activity title")
        case .deviceContext:
            return NSLocalizedString("Checking Device", comment: "Tool activity title")
        case .none:
            return NSLocalizedString("Using Tool", comment: "Tool activity title")
        }
    }

    private static var emptyObjectSchema: JSONValue {
        object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([:])
        ])
    }

    private static func object(_ value: [String: JSONValue]) -> JSONValue {
        .object(value)
    }

    private static func isoDateDescription(_ description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "pattern": .string("^\\d{4}-\\d{2}-\\d{2}$")
        ])
    }

    private static func stringDescription(_ description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "description": .string(description)
        ])
    }

    private static func integerDescription(_ description: String) -> JSONValue {
        .object([
            "type": .string("integer"),
            "description": .string(description),
            "minimum": .number(1),
            "maximum": .number(50)
        ])
    }
}
