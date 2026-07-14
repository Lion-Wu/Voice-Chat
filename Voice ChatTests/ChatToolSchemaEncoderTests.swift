import XCTest
@testable import Voice_Chat

final class ChatToolSchemaEncoderTests: XCTestCase {
    func testOpenAIChatCompletionsAddsToolsAndDisablesParallelToolCalls() throws {
        var body: [String: Any] = ["model": "gpt-test"]
        let settings = enabledSettings(
            calendar: true,
            reminders: false,
            location: false,
            motion: false,
            device: true
        )

        ChatToolSchemaEncoder.applyToolSchemas(
            to: &body,
            endpoint: endpoint(style: .openAIChatCompletions, chatURL: "https://example.com/v1/chat/completions"),
            settings: settings
        )

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 6)
        XCTAssertEqual(body["tool_choice"] as? String, "auto")
        XCTAssertEqual(body["parallel_tool_calls"] as? Bool, false)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertTrue((messages.first?["content"] as? String)?.contains(ChatToolDefinitions.untrustedResultInstruction) == true)
        XCTAssertEqual((tools.first?["function"] as? [String: Any])?["name"] as? String, ChatToolID.calendarListEvents.rawValue)
        for tool in tools {
            let function = try XCTUnwrap(tool["function"] as? [String: Any])
            let name = try XCTUnwrap(function["name"] as? String)
            XCTAssertFalse(name.contains("."))
        }

        let calendarList = try XCTUnwrap(tools.compactMap { $0["function"] as? [String: Any] }.first {
            $0["name"] as? String == ChatToolID.calendarListEvents.rawValue
        })
        let calendarShow = try XCTUnwrap(tools.compactMap { $0["function"] as? [String: Any] }.first {
            $0["name"] as? String == ChatToolID.calendarShowEvents.rawValue
        })
        XCTAssertTrue((calendarList["description"] as? String)?.contains("without rendering event cards") == true)
        XCTAssertTrue((calendarList["description"] as? String)?.contains("event_id") == true)
        XCTAssertTrue((calendarShow["description"] as? String)?.contains("One call returns matching event records") == true)
    }

    func testResponsesEndpointUsesResponsesFunctionShape() throws {
        var body: [String: Any] = ["model": "gpt-test"]

        ChatToolSchemaEncoder.applyToolSchemas(
            to: &body,
            endpoint: endpoint(style: .openAIResponses, chatURL: "https://api.openai.com/v1/responses"),
            settings: enabledSettings(
                calendar: false,
                reminders: false,
                location: false,
                motion: false,
                device: true
            )
        )

        let tool = try XCTUnwrap((body["tools"] as? [[String: Any]])?.first)
        XCTAssertEqual(tool["type"] as? String, "function")
        XCTAssertEqual(tool["name"] as? String, ChatToolID.deviceContext.rawValue)
        XCTAssertFalse((tool["name"] as? String)?.contains(".") == true)
        XCTAssertEqual(body["tool_choice"] as? String, "auto")
        XCTAssertTrue((body["instructions"] as? String)?.contains(ChatToolDefinitions.untrustedResultInstruction) == true)
        XCTAssertNil(body["parallel_tool_calls"])
        XCTAssertNil(tool["strict"])
    }

    func testAnthropicToolsAddToolResultTrustInstructionToSystemPrompt() {
        var body: [String: Any] = ["model": "claude-test", "system": "Be concise."]

        ChatToolSchemaEncoder.applyToolSchemas(
            to: &body,
            endpoint: endpoint(style: .anthropicMessages, chatURL: "https://api.anthropic.com/v1/messages"),
            settings: enabledSettings(
                calendar: false,
                reminders: false,
                location: false,
                motion: false,
                device: true
            )
        )

        let system = body["system"] as? String
        XCTAssertTrue(system?.hasPrefix("Be concise.") == true)
        XCTAssertTrue(system?.contains(ChatToolDefinitions.untrustedResultInstruction) == true)
    }

    func testOpenRouterResponsesEndpointDoesNotSendNullStrict() throws {
        var body: [String: Any] = ["model": "gpt-test"]

        ChatToolSchemaEncoder.applyToolSchemas(
            to: &body,
            endpoint: endpoint(style: .openAIResponses, chatURL: "https://openrouter.ai/api/v1/responses"),
            settings: enabledSettings(
                calendar: false,
                reminders: false,
                location: false,
                motion: false,
                device: true
            )
        )

        let tool = try XCTUnwrap((body["tools"] as? [[String: Any]])?.first)
        XCTAssertEqual(tool["type"] as? String, "function")
        XCTAssertEqual(tool["name"] as? String, ChatToolID.deviceContext.rawValue)
        XCTAssertNil(tool["strict"])
    }

    func testResponsesEndpointCanRestrictAllowedToolsWithoutChangingToolList() throws {
        var body: [String: Any] = ["model": "gpt-test"]

        ChatToolSchemaEncoder.applyToolSchemas(
            to: &body,
            endpoint: endpoint(style: .openAIResponses, chatURL: "https://openrouter.ai/api/v1/responses"),
            settings: ToolUseSettings(
                isEnabled: true,
                calendarEnabled: true,
                remindersEnabled: true,
                locationEnabled: true,
                motionEnabled: true,
                deviceContextEnabled: true,
                timeEnabled: true
            ),
            allowedToolIDs: [.systemGetTime]
        )

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let toolChoice = try XCTUnwrap(body["tool_choice"] as? [String: Any])
        let allowedTools = try XCTUnwrap(toolChoice["tools"] as? [[String: Any]])

        XCTAssertGreaterThan(tools.count, 1)
        XCTAssertEqual(toolChoice["type"] as? String, "allowed_tools")
        XCTAssertEqual(toolChoice["mode"] as? String, "auto")
        XCTAssertEqual(allowedTools.count, 1)
        XCTAssertEqual(allowedTools.first?["type"] as? String, "function")
        XCTAssertEqual(allowedTools.first?["name"] as? String, ChatToolID.systemGetTime.rawValue)
    }

    func testPromptBasedEndpointInjectsPromptToolProtocol() {
        var body: [String: Any] = ["model": "legacy", "stream": true]

        ChatToolSchemaEncoder.applyToolSchemas(
            to: &body,
            endpoint: endpoint(style: .lmStudioRESTV1, chatURL: "http://localhost:1234/api/v1/chat"),
            settings: enabledSettings(calendar: true, reminders: false, location: false, motion: false, device: true)
        )

        XCTAssertNil(body["tools"])
        XCTAssertNil(body["integrations"])
        XCTAssertEqual(body["model"] as? String, "legacy")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertTrue((body["system_prompt"] as? String)?.contains("<tool_call>") == true)
        XCTAssertTrue((body["system_prompt"] as? String)?.contains(ChatToolID.calendarListEvents.rawValue) == true)
        XCTAssertTrue((body["system_prompt"] as? String)?.contains("Available functions:") == true)
        XCTAssertTrue((body["system_prompt"] as? String)?.contains("Function-call rules:") == true)
        XCTAssertTrue((body["system_prompt"] as? String)?.contains("\"function\":") == true)
        XCTAssertFalse((body["system_prompt"] as? String)?.contains("LM Studio") == true)
        let prompt = body["system_prompt"] as? String ?? ""
        XCTAssertEqual(prompt.components(separatedBy: "Accepted relative date/time expressions").count, 2)
    }

    func testToolDescriptionsUseUnifiedPromptFormat() {
        for toolID in ChatToolID.allCases {
            let description = ChatToolDefinitions.definition(for: toolID).description

            XCTAssertTrue(description.contains("Purpose:"), toolID.rawValue)
            XCTAssertTrue(description.contains("Use when:"), toolID.rawValue)
            XCTAssertTrue(description.contains("Returns:"), toolID.rawValue)
            XCTAssertTrue(description.contains("After use:"), toolID.rawValue)
        }
    }

    func testGeneralRulesOwnCrossToolTemporalGuidance() {
        for toolID in ChatToolID.allCases {
            let definition = ChatToolDefinitions.definition(for: toolID)
            let schemaText = definition.parametersSchema.compactJSONString
            let promptText = definition.description + schemaText
            let schemaUsesDateTimeRules = Self.contains(
                ChatToolTemporalResolver.generalToolRuleReference,
                in: definition.parametersSchema
            )

            for otherToolID in ChatToolID.allCases where otherToolID != toolID {
                XCTAssertFalse(
                    promptText.contains(otherToolID.rawValue),
                    "\(toolID.rawValue) references \(otherToolID.rawValue)"
                )
            }
            XCTAssertFalse(promptText.contains("Accepted relative date/time expressions"), toolID.rawValue)
            XCTAssertEqual(
                definition.generalRuleRequirements.contains(.dateTime),
                schemaUsesDateTimeRules,
                "\(toolID.rawValue) must declare the general date/time rule exactly when one of its arguments references it"
            )
        }

        let temporalDefinitions = [
            ChatToolDefinitions.definition(for: .calendarCreateEvent),
            ChatToolDefinitions.definition(for: .systemGetTime)
        ]
        let temporalInstructions = ChatToolDefinitions.generalModelInstructions(for: temporalDefinitions)
        XCTAssertTrue(temporalInstructions.contains("Accepted formats:"))
        XCTAssertTrue(temporalInstructions.contains("Accepted relative date/time expressions"))
        XCTAssertTrue(temporalInstructions.contains(ChatToolTemporalResolver.generalToolRuleReference))
        XCTAssertTrue(temporalInstructions.contains(ChatToolID.systemGetTime.rawValue))
        XCTAssertFalse(temporalInstructions.localizedCaseInsensitiveContains("calendar/reminder"))

        let nonTemporalInstructions = ChatToolDefinitions.generalModelInstructions(for: [
            ChatToolDefinitions.definition(for: .deviceContext)
        ])
        XCTAssertFalse(nonTemporalInstructions.contains("Accepted formats:"))
        XCTAssertFalse(nonTemporalInstructions.contains(ChatToolID.systemGetTime.rawValue))
    }

    func testPromptToolProtocolDoesNotDescribeDisabledTools() throws {
        var body: [String: Any] = ["model": "local"]
        ChatToolSchemaEncoder.applyToolSchemas(
            to: &body,
            endpoint: endpoint(style: .lmStudioRESTV1, chatURL: "http://localhost:1234/api/v1/chat"),
            settings: enabledSettings(
                calendar: false,
                reminders: false,
                location: false,
                motion: false,
                device: true
            )
        )

        let prompt = try XCTUnwrap(body["system_prompt"] as? String)
        XCTAssertTrue(prompt.contains(ChatToolID.deviceContext.rawValue))
        for disabledToolID in ChatToolID.allCases where disabledToolID != .deviceContext {
            XCTAssertFalse(prompt.contains(disabledToolID.rawValue), disabledToolID.rawValue)
        }
    }

    func testRangeToolSchemasExposeOnlyCurrentTimeRangeFields() {
        let expectedKeysByToolID: [ChatToolID: Set<String>] = [
            .calendarListEvents: ["start", "end", "calendar_name", "keywords", "limit"],
            .calendarShowEvents: ["start", "end", "calendar_name", "keywords", "limit"],
            .remindersListReminders: ["status", "start", "end", "list_name", "keywords", "limit"],
            .remindersShowReminders: ["status", "start", "end", "list_name", "keywords", "limit"]
        ]

        for (toolID, expectedKeys) in expectedKeysByToolID {
            let properties = Self.properties(in: ChatToolDefinitions.definition(for: toolID).parametersSchema)

            XCTAssertEqual(Set(properties.keys), expectedKeys, toolID.rawValue)
        }
    }

    func testDeleteToolSchemasRequireStableIdentifiers() {
        let calendarSchema = ChatToolDefinitions.definition(for: .calendarDeleteEvent).parametersSchema
        let reminderSchema = ChatToolDefinitions.definition(for: .remindersDeleteReminder).parametersSchema

        XCTAssertEqual(Self.requiredFields(in: calendarSchema), ["event_id"])
        XCTAssertEqual(Self.requiredFields(in: reminderSchema), ["reminder_id"])
        XCTAssertEqual(Set(Self.properties(in: calendarSchema).keys), ["event_id", "delete_future_events"])
        XCTAssertEqual(Set(Self.properties(in: reminderSchema).keys), ["reminder_id"])
    }

    func testDisabledSettingsDoNotAddSchemas() {
        var body: [String: Any] = ["model": "gpt-test"]

        ChatToolSchemaEncoder.applyToolSchemas(
            to: &body,
            endpoint: endpoint(style: .openAIChatCompletions, chatURL: "https://example.com/v1/chat/completions"),
            settings: .defaults
        )

        XCTAssertNil(body["tools"])
    }

    func testRemoteEndpointIncludesAllEnabledToolSchemas() throws {
        var body: [String: Any] = ["model": "gpt-test"]

        ChatToolSchemaEncoder.applyToolSchemas(
            to: &body,
            endpoint: endpoint(style: .openAIChatCompletions, chatURL: "https://api.openai.com/v1/chat/completions"),
            settings: enabledSettings(calendar: true, reminders: true, location: true, motion: true, device: true)
        )

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let names = Set(tools.compactMap { tool -> String? in
            guard let function = tool["function"] as? [String: Any] else { return nil }
            return function["name"] as? String
        })
        XCTAssertEqual(names, [
            ChatToolID.calendarListEvents.rawValue,
            ChatToolID.calendarCreateEvent.rawValue,
            ChatToolID.calendarDeleteEvent.rawValue,
            ChatToolID.calendarShowEvents.rawValue,
            ChatToolID.remindersListReminders.rawValue,
            ChatToolID.remindersCreateReminder.rawValue,
            ChatToolID.remindersDeleteReminder.rawValue,
            ChatToolID.remindersShowReminders.rawValue,
            ChatToolID.locationCurrent.rawValue,
            ChatToolID.motionDevice.rawValue,
            ChatToolID.deviceContext.rawValue,
            ChatToolID.systemGetTime.rawValue
        ])
        XCTAssertEqual(body["tool_choice"] as? String, "auto")
        XCTAssertEqual(body["parallel_tool_calls"] as? Bool, false)
    }

    func testLocalEndpointKeepsSensitiveToolSchemas() throws {
        var body: [String: Any] = ["model": "local"]

        ChatToolSchemaEncoder.applyToolSchemas(
            to: &body,
            endpoint: endpoint(style: .lmStudioRESTV1, chatURL: "http://localhost:1234/api/v1/chat"),
            settings: enabledSettings(calendar: true, reminders: true, location: false, motion: false, device: false)
        )

        let prompt = try XCTUnwrap(body["system_prompt"] as? String)
        XCTAssertTrue(prompt.contains(ChatToolID.calendarListEvents.rawValue))
        XCTAssertTrue(prompt.contains(ChatToolID.remindersListReminders.rawValue))
    }

    private func enabledSettings(
        calendar: Bool = true,
        reminders: Bool = true,
        location: Bool = true,
        motion: Bool = true,
        device: Bool = true
    ) -> ToolUseSettings {
        ToolUseSettings(
            isEnabled: true,
            calendarEnabled: calendar,
            remindersEnabled: reminders,
            locationEnabled: location,
            motionEnabled: motion,
            deviceContextEnabled: device
        )
    }

    private func endpoint(style: ChatRequestStyle, chatURL: String) -> ChatAPIEndpointCandidate {
        ChatAPIEndpointCandidate(
            provider: .openAI,
            style: style,
            chatURL: URL(string: chatURL)!,
            modelsURL: URL(string: "https://example.com/v1/models")!
        )
    }

    private static func properties(in schema: JSONValue) -> [String: JSONValue] {
        guard case let .object(root) = schema,
              case let .object(properties)? = root["properties"] else {
            return [:]
        }
        return properties
    }

    private static func requiredFields(in schema: JSONValue) -> [String] {
        guard case let .object(root) = schema,
              case let .array(values)? = root["required"] else {
            return []
        }
        return values.compactMap { value in
            guard case let .string(field) = value else { return nil }
            return field
        }
    }

    private static func contains(_ text: String, in value: JSONValue) -> Bool {
        switch value {
        case let .string(value):
            return value.contains(text)
        case let .array(values):
            return values.contains { contains(text, in: $0) }
        case let .object(values):
            return values.values.contains { contains(text, in: $0) }
        case .number, .bool, .null:
            return false
        }
    }
}
