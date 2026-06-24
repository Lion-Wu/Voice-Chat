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

    init(
        calendarTool: CalendarToolServing = EventKitCalendarTool(),
        remindersTool: RemindersToolServing = EventKitRemindersTool(),
        locationTool: LocationToolServing = CoreLocationTool(),
        motionTool: MotionToolServing = CoreMotionTool(),
        deviceTool: DeviceContextToolServing = SystemDeviceContextTool()
    ) {
        self.calendarTool = calendarTool
        self.remindersTool = remindersTool
        self.locationTool = locationTool
        self.motionTool = motionTool
        self.deviceTool = deviceTool
    }

    func execute(
        _ call: ChatToolCallEnvelope,
        settings: ToolUseSettings,
        endpoint: ChatAPIEndpointCandidate
    ) async -> ChatToolResultEnvelope {
        do {
            guard settings.isEnabled else { throw ChatToolError.disabled }
            guard let toolID = call.toolID else { throw ChatToolError.unknownTool(call.name) }
            guard settings.enabledToolIDs.contains(toolID) else { throw ChatToolError.disabled }
            guard settings.enabledToolIDs(for: endpoint).contains(toolID) else {
                throw ChatToolError.denied(NSLocalizedString(
                    "This tool is disabled for the current endpoint.",
                    comment: "Tool-use error"
                ))
            }

            let reader = try ChatToolArgumentReader(argumentsJSON: call.argumentsJSON)
            let payload: [String: JSONValue]
            let summary: String

            switch toolID {
            case .calendarListEvents:
                let result = try await calendarTool.listEvents(arguments: reader)
                payload = result.payload
                summary = result.summary
            case .remindersListReminders:
                let result = try await remindersTool.listReminders(arguments: reader)
                payload = result.payload
                summary = result.summary
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
            }

            return ChatToolResultEnvelope(
                callID: call.callID,
                name: call.name,
                status: .success,
                payload: payload,
                summary: summary
            )
        } catch let error as ChatToolError {
            return failureResult(for: call, error: error)
        } catch {
            return failureResult(for: call, error: .failed(error.localizedDescription))
        }
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

struct ChatToolExecutionPayload: Equatable, Sendable {
    let payload: [String: JSONValue]
    let summary: String
}
