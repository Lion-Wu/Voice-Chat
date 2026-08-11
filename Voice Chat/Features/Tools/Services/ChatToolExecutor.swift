//
//  ChatToolExecutor.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation

protocol ChatToolExecuting: Sendable {
    func execute(
        _ call: ChatToolCallEnvelope,
        settings: ToolUseSettings,
        endpoint: ChatAPIEndpointCandidate
    ) async -> ChatToolResultEnvelope
}

struct ChatToolExecutor: ChatToolExecuting {
    private let calendarTool: CalendarToolServing
    private let remindersTool: RemindersToolServing
    private let locationTool: LocationToolServing
    private let motionTool: MotionToolServing
    private let deviceTool: DeviceContextToolServing
    private let clipboardTool: ClipboardToolServing
    private let systemActionTool: SystemActionToolServing
    private let javaScriptRuntimeTool: JavaScriptRuntimeToolServing

    init(
        calendarTool: CalendarToolServing = EventKitCalendarTool(),
        remindersTool: RemindersToolServing = EventKitRemindersTool(),
        locationTool: LocationToolServing = CoreLocationTool(),
        motionTool: MotionToolServing = CoreMotionTool(),
        deviceTool: DeviceContextToolServing = SystemDeviceContextTool(),
        clipboardTool: ClipboardToolServing = SystemClipboardTool(),
        systemActionTool: SystemActionToolServing = DefaultSystemActionTool(),
        javaScriptRuntimeTool: JavaScriptRuntimeToolServing = SandboxedJavaScriptRuntimeTool()
    ) {
        self.calendarTool = calendarTool
        self.remindersTool = remindersTool
        self.locationTool = locationTool
        self.motionTool = motionTool
        self.deviceTool = deviceTool
        self.clipboardTool = clipboardTool
        self.systemActionTool = systemActionTool
        self.javaScriptRuntimeTool = javaScriptRuntimeTool
    }

    func execute(
        _ call: ChatToolCallEnvelope,
        settings: ToolUseSettings,
        endpoint: ChatAPIEndpointCandidate
    ) async -> ChatToolResultEnvelope {
        do {
            try Task.checkCancellation()
            guard settings.isEnabled else { throw ChatToolError.disabled }
            guard let toolID = call.toolID else { throw ChatToolError.unknownTool(call.name) }
            guard settings.enabledToolIDs.contains(toolID) else { throw ChatToolError.disabled }

            let reader = try ChatToolArgumentReader(argumentsJSON: call.argumentsJSON)
            try ChatToolSchemaValidator.validate(
                reader.argumentsValue,
                against: ChatToolDefinitions.definition(for: toolID).parametersSchema
            )
            let payload: [String: JSONValue]
            let summary: String

            switch toolID {
            case .calendarListEvents:
                let result = try await calendarTool.listEvents(arguments: reader)
                payload = result.payload
                summary = result.summary
                return successResult(for: call, payload: payload, summary: summary, presentation: result.presentation)
            case .calendarCreateEvent:
                let result = try await calendarTool.createEvent(arguments: reader)
                payload = result.payload
                summary = result.summary
                return successResult(for: call, payload: payload, summary: summary, presentation: result.presentation)
            case .calendarDeleteEvent:
                let result = try await calendarTool.deleteEvent(arguments: reader)
                payload = result.payload
                summary = result.summary
                return successResult(for: call, payload: payload, summary: summary, presentation: result.presentation)
            case .calendarShowEvents:
                let result = try await calendarTool.showEvents(arguments: reader)
                payload = result.payload
                summary = result.summary
                return successResult(for: call, payload: payload, summary: summary, presentation: result.presentation)
            case .remindersListReminders:
                let result = try await remindersTool.listReminders(arguments: reader)
                payload = result.payload
                summary = result.summary
                return successResult(for: call, payload: payload, summary: summary, presentation: result.presentation)
            case .remindersCreateReminder:
                let result = try await remindersTool.createReminder(arguments: reader)
                payload = result.payload
                summary = result.summary
                return successResult(for: call, payload: payload, summary: summary, presentation: result.presentation)
            case .remindersDeleteReminder:
                let result = try await remindersTool.deleteReminder(arguments: reader)
                payload = result.payload
                summary = result.summary
                return successResult(for: call, payload: payload, summary: summary, presentation: result.presentation)
            case .remindersShowReminders:
                let result = try await remindersTool.showReminders(arguments: reader)
                payload = result.payload
                summary = result.summary
                return successResult(for: call, payload: payload, summary: summary, presentation: result.presentation)
            case .locationCurrent:
                let result = try await locationTool.currentLocation(arguments: reader)
                payload = result.payload
                summary = result.summary
            case .motionDevice:
                let result = try await motionTool.deviceMotion(arguments: reader)
                payload = result.payload
                summary = result.summary
            case .deviceContext:
                let result = try await deviceTool.deviceContext(arguments: reader)
                payload = result.payload
                summary = result.summary
            case .clipboardGetText:
                let result = try await clipboardTool.getText(arguments: reader)
                payload = result.payload
                summary = result.summary
            case .clipboardSetText:
                let result = try await clipboardTool.setText(arguments: reader)
                payload = result.payload
                summary = result.summary
            case .systemOpenURL:
                let result = try await systemActionTool.openURL(arguments: reader)
                payload = result.payload
                summary = result.summary
            case .systemGetTime:
                let result = try await systemActionTool.currentTime(arguments: reader)
                payload = result.payload
                summary = result.summary
            case .javaScriptRun:
                let result = try await javaScriptRuntimeTool.run(arguments: reader)
                payload = result.payload
                summary = result.summary
            }

            return successResult(for: call, payload: payload, summary: summary)
        } catch let error as ChatToolError {
            return failureResult(for: call, error: error)
        } catch {
            return failureResult(for: call, error: .failed(error.localizedDescription))
        }
    }

    private func successResult(
        for call: ChatToolCallEnvelope,
        payload: [String: JSONValue],
        summary: String,
        presentation: ChatToolPresentation? = nil
    ) -> ChatToolResultEnvelope {
        ChatToolResultEnvelope(
            callID: call.callID,
            name: call.name,
            status: .success,
            payload: payload,
            summary: summary,
            presentation: presentation
        )
    }

    private func failureResult(for call: ChatToolCallEnvelope, error: ChatToolError) -> ChatToolResultEnvelope {
        ChatToolResultEnvelope(
            callID: call.callID,
            name: call.name,
            status: error.resultStatus,
            payload: ["error": .string(error.localizedDescription)],
            summary: error.localizedDescription
        )
    }
}

enum ChatToolSchemaValidator {
    static func validate(
        _ value: JSONValue,
        against schema: JSONValue,
        path: String = "arguments"
    ) throws {
        guard case let .object(rules) = schema else { return }

        if case let .array(allowedValues)? = rules["enum"],
           !allowedValues.contains(value) {
            throw invalid(path, requirement: "one of the declared values")
        }
        if case let .string(expectedType)? = rules["type"],
           !matchesType(value, expectedType: expectedType) {
            throw invalid(path, requirement: expectedTypeRequirement(expectedType))
        }

        switch value {
        case let .object(fields):
            try validateObject(fields, rules: rules, path: path)
        case let .array(values):
            if let itemSchema = rules["items"] {
                for (index, item) in values.enumerated() {
                    try validate(item, against: itemSchema, path: "\(path)[\(index)]")
                }
            }
        case let .number(number):
            if case let .number(minimum)? = rules["minimum"], number < minimum {
                throw invalid(path, requirement: "a number greater than or equal to \(minimum)")
            }
            if case let .number(maximum)? = rules["maximum"], number > maximum {
                throw invalid(path, requirement: "a number less than or equal to \(maximum)")
            }
        case .string, .bool, .null:
            break
        }
    }

    private static func validateObject(
        _ fields: [String: JSONValue],
        rules: [String: JSONValue],
        path: String
    ) throws {
        let properties: [String: JSONValue]
        if case let .object(value)? = rules["properties"] {
            properties = value
        } else {
            properties = [:]
        }

        if rules["additionalProperties"] == .bool(false),
           let unknownKey = fields.keys.sorted().first(where: { properties[$0] == nil }) {
            throw invalid("\(path).\(unknownKey)", requirement: "a declared argument")
        }
        if case let .array(requiredValues)? = rules["required"] {
            for requiredValue in requiredValues {
                guard case let .string(requiredKey) = requiredValue else { continue }
                guard fields[requiredKey] != nil else {
                    throw ChatToolError.invalidArguments("\(path).\(requiredKey) is required.")
                }
            }
        }
        for (key, fieldValue) in fields {
            guard let fieldSchema = properties[key] else { continue }
            try validate(fieldValue, against: fieldSchema, path: "\(path).\(key)")
        }
    }

    private static func matchesType(_ value: JSONValue, expectedType: String) -> Bool {
        switch (expectedType, value) {
        case ("string", .string), ("number", .number), ("boolean", .bool),
             ("object", .object), ("array", .array), ("null", .null):
            return true
        case let ("integer", .number(number)):
            return number.isFinite && number.rounded(.towardZero) == number
        default:
            return false
        }
    }

    private static func expectedTypeRequirement(_ type: String) -> String {
        switch type {
        case "string": return "a string"
        case "number": return "a number"
        case "integer": return "an integer"
        case "boolean": return "a boolean"
        case "object": return "an object"
        case "array": return "an array"
        case "null": return "null"
        default: return "a \(type) value"
        }
    }

    private static func invalid(_ path: String, requirement: String) -> ChatToolError {
        .invalidArguments("\(path) must be \(requirement).")
    }
}

struct ChatToolExecutionPayload: Equatable, Sendable {
    let payload: [String: JSONValue]
    let summary: String
    var presentation: ChatToolPresentation? = nil
}
