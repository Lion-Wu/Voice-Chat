//
//  ChatToolTypes.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation

enum ChatToolID: String, CaseIterable, Codable, Sendable {
    case calendarListEvents = "calendar_list_events"
    case remindersListReminders = "reminders_list_reminders"
    case locationCurrent = "location_get_current_location"
    case motionDevice = "motion_get_device_motion"
    case deviceContext = "device_get_context"

    init?(toolName: String) {
        let normalized = toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = ChatToolID(rawValue: normalized) {
            self = id
            return
        }

        switch normalized {
        case "calendar.list_events":
            self = .calendarListEvents
        case "reminders.list_reminders":
            self = .remindersListReminders
        case "location.get_current_location":
            self = .locationCurrent
        case "motion.get_device_motion":
            self = .motionDevice
        case "device.get_context":
            self = .deviceContext
        default:
            return nil
        }
    }
}

struct ChatToolDefinition: Equatable, Sendable {
    let id: ChatToolID
    let description: String
    let parametersSchema: JSONValue
}

struct ChatToolCallEnvelope: Equatable, Sendable {
    let callID: String
    let name: String
    let argumentsJSON: String
    let provider: ChatProvider?

    var toolID: ChatToolID? {
        ChatToolID(toolName: name)
    }
}

enum ChatToolResultStatus: String, Codable, Sendable {
    case success
    case denied
    case unsupported
    case invalidArguments = "invalid_arguments"
    case failed
}

struct ChatToolResultEnvelope: Equatable, Sendable {
    let callID: String
    let name: String
    let status: ChatToolResultStatus
    let payload: [String: JSONValue]
    let summary: String

    var outputJSONString: String {
        let object: [String: JSONValue] = [
            "tool": .string(name),
            "status": .string(status.rawValue),
            "summary": .string(summary),
            "data": .object(payload)
        ]
        return JSONValue.object(object).compactJSONString
    }
}

enum ChatToolActivityPhase: String, Codable, Sendable {
    case requested
    case authorizing
    case running
    case processing
    case succeeded
    case failed
    case denied
    case unsupported
}

extension ChatToolActivityPhase {
    var isPersistentToolTracePhase: Bool {
        switch self {
        case .succeeded, .failed, .denied, .unsupported:
            return true
        case .requested, .authorizing, .running, .processing:
            return false
        }
    }
}

struct ChatToolActivity: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let toolName: String
    var title: String
    var phase: ChatToolActivityPhase
    var summary: String?

    init(
        id: String,
        toolName: String,
        title: String,
        phase: ChatToolActivityPhase,
        summary: String? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.title = title
        self.phase = phase
        self.summary = summary
    }
}

enum ChatToolActivityScope: String, Codable, Sendable {
    case thinking
    case body
}

struct ChatToolActivityPlacement: Identifiable, Codable, Equatable, Sendable {
    var id: String { activity.id }
    var activity: ChatToolActivity
    let scope: ChatToolActivityScope
    let offset: Int

    init(
        activity: ChatToolActivity,
        scope: ChatToolActivityScope,
        offset: Int
    ) {
        self.activity = activity
        self.scope = scope
        self.offset = max(0, offset)
    }
}

enum ChatToolError: LocalizedError, Equatable {
    case disabled
    case unknownTool(String)
    case invalidArguments(String)
    case denied(String)
    case unsupported(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return NSLocalizedString("Tool use is disabled.", comment: "Tool-use error")
        case let .unknownTool(name):
            return String(format: NSLocalizedString("Unknown tool: %@", comment: "Tool-use error"), name)
        case let .invalidArguments(message),
             let .denied(message),
             let .unsupported(message),
             let .failed(message):
            return message
        }
    }

    var resultStatus: ChatToolResultStatus {
        switch self {
        case .disabled, .unknownTool, .failed:
            return .failed
        case .invalidArguments:
            return .invalidArguments
        case .denied:
            return .denied
        case .unsupported:
            return .unsupported
        }
    }
}

extension JSONValue {
    var jsonObject: Any {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            return value
        case let .bool(value):
            return value
        case let .object(value):
            return value.mapValues { $0.jsonObject }
        case let .array(value):
            return value.map { $0.jsonObject }
        case .null:
            return NSNull()
        }
    }

    var compactJSONString: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
