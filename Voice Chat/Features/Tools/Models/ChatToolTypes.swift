//
//  ChatToolTypes.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation

enum ChatToolID: String, CaseIterable, Codable, Sendable {
    case calendarListEvents = "calendar_list_events"
    case calendarCreateEvent = "calendar_create_event"
    case calendarDeleteEvent = "calendar_delete_event"
    case calendarShowEvents = "calendar_show_events"
    case remindersListReminders = "reminders_list_reminders"
    case remindersCreateReminder = "reminders_create_reminder"
    case remindersDeleteReminder = "reminders_delete_reminder"
    case remindersShowReminders = "reminders_show_reminders"
    case locationCurrent = "location_get_current_location"
    case motionDevice = "motion_get_device_motion"
    case deviceContext = "device_get_context"
    case clipboardGetText = "clipboard_get_text"
    case clipboardSetText = "clipboard_set_text"
    case systemOpenURL = "system_open_url"
    case systemGetTime = "system_get_time"
    case javaScriptRun = "javascript_run"

    init?(toolName: String) {
        let normalized = toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = ChatToolID(rawValue: normalized) else { return nil }
        self = id
    }
}

enum ChatToolOperationKind: String, Codable, Sendable {
    case read
    case write
    case display
    case action
    case compute
}

extension ChatToolID {
    var operationKind: ChatToolOperationKind {
        switch self {
        case .calendarListEvents, .remindersListReminders, .locationCurrent, .motionDevice, .deviceContext, .clipboardGetText, .systemGetTime:
            return .read
        case .calendarCreateEvent, .calendarDeleteEvent,
             .remindersCreateReminder, .remindersDeleteReminder,
             .clipboardSetText:
            return .write
        case .calendarShowEvents, .remindersShowReminders:
            return .display
        case .systemOpenURL:
            return .action
        case .javaScriptRun:
            return .compute
        }
    }
}

enum ChatToolGeneralRule: Hashable, Sendable {
    case dateTime
}

extension ChatToolID {
    var generalRuleRequirements: Set<ChatToolGeneralRule> {
        switch self {
        case .calendarListEvents, .calendarCreateEvent, .calendarShowEvents,
             .remindersListReminders, .remindersCreateReminder, .remindersShowReminders:
            return [.dateTime]
        case .calendarDeleteEvent, .remindersDeleteReminder,
             .locationCurrent, .motionDevice, .deviceContext,
             .clipboardGetText, .clipboardSetText,
             .systemOpenURL, .systemGetTime, .javaScriptRun:
            return []
        }
    }
}

struct ChatToolDefinition: Equatable, Sendable {
    let id: ChatToolID
    let description: String
    let parametersSchema: JSONValue

    var generalRuleRequirements: Set<ChatToolGeneralRule> {
        id.generalRuleRequirements
    }
}

struct ChatToolCallEnvelope: Equatable, Sendable {
    let callID: String
    let itemID: String?
    let name: String
    let argumentsJSON: String
    let provider: ChatProvider?

    init(
        callID: String,
        itemID: String? = nil,
        name: String,
        argumentsJSON: String,
        provider: ChatProvider?
    ) {
        self.callID = callID
        self.itemID = itemID
        self.name = name
        self.argumentsJSON = argumentsJSON
        self.provider = provider
    }

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
    var presentation: ChatToolPresentation?

    init(
        callID: String,
        name: String,
        status: ChatToolResultStatus,
        payload: [String: JSONValue],
        summary: String,
        presentation: ChatToolPresentation? = nil
    ) {
        self.callID = callID
        self.name = name
        self.status = status
        self.payload = payload
        self.summary = summary
        self.presentation = presentation
    }

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
    case generating
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
        case .generating, .requested, .authorizing, .running, .processing:
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
    var authorizationRequest: ChatToolAuthorizationRequest?
    var presentation: ChatToolPresentation?
    var modelRequestPayload: [String: JSONValue]?
    var resultPayload: [String: JSONValue]?

    init(
        id: String,
        toolName: String,
        title: String,
        phase: ChatToolActivityPhase,
        summary: String? = nil,
        authorizationRequest: ChatToolAuthorizationRequest? = nil,
        presentation: ChatToolPresentation? = nil,
        modelRequestPayload: [String: JSONValue]? = nil,
        resultPayload: [String: JSONValue]? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.title = title
        self.phase = phase
        self.summary = summary
        self.authorizationRequest = authorizationRequest
        self.presentation = presentation
        self.modelRequestPayload = modelRequestPayload
        self.resultPayload = resultPayload
    }
}

struct ChatToolAuthorizationRequest: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let toolName: String
    let title: String
    let operationKind: ChatToolOperationKind
    let argumentsSummary: String
}

struct ChatToolPresentation: Codable, Equatable, Sendable {
    var title: String
    var subtitle: String?
    var items: [ChatToolPresentationItem]
    var kind: ChatToolPresentationKind? = nil
}

enum ChatToolPresentationKind: String, Codable, Equatable, Sendable {
    case calendar
    case reminders
    case generic
}

struct ChatToolPresentationItem: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var subtitle: String?
    var detail: String?
    var metadata: [String: String]
}

enum ChatToolActivityScope: String, Codable, Sendable {
    case thinking
    case body
}

struct ChatAssistantSegmentAnchor: Codable, Equatable, Sendable {
    let segmentIndex: Int
    let characterOffset: Int

    init(segmentIndex: Int, characterOffset: Int) {
        self.segmentIndex = max(0, segmentIndex)
        self.characterOffset = max(0, characterOffset)
    }
}

struct ChatToolActivityPlacement: Identifiable, Codable, Equatable, Sendable {
    var id: String { activity.id }
    var activity: ChatToolActivity
    let scope: ChatToolActivityScope
    let offset: Int
    let assistantSegmentAnchor: ChatAssistantSegmentAnchor?

    init(
        activity: ChatToolActivity,
        scope: ChatToolActivityScope,
        offset: Int,
        assistantSegmentAnchor: ChatAssistantSegmentAnchor? = nil
    ) {
        self.activity = activity
        self.scope = scope
        self.offset = max(0, offset)
        self.assistantSegmentAnchor = assistantSegmentAnchor
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
    static func normalized(_ value: Any) -> JSONValue {
        switch value {
        case let value as String:
            return .string(value)
        case let value as NSNumber:
            return CFGetTypeID(value) == CFBooleanGetTypeID()
                ? .bool(value.boolValue)
                : .number(value.doubleValue)
        case let value as Bool:
            return .bool(value)
        case let value as Int:
            return .number(Double(value))
        case let value as Double:
            return .number(value)
        case let value as Float:
            return .number(Double(value))
        case let value as [String: Any]:
            return .object(value.mapValues(Self.normalized))
        case let value as [Any]:
            return .array(value.map(Self.normalized))
        case _ as NSNull:
            return .null
        default:
            return .string(String(describing: value))
        }
    }

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
        let object = jsonObject
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
