import XCTest
@testable import Voice_Chat

final class ChatToolSchemaEncoderTests: XCTestCase {
    func testOpenAIChatCompletionsAddsToolsAndDisablesParallelToolCalls() throws {
        var body: [String: Any] = ["model": "gpt-test"]

        ChatToolSchemaEncoder.applyToolSchemas(
            to: &body,
            endpoint: endpoint(style: .openAIChatCompletions, chatURL: "https://example.com/v1/chat/completions"),
            settings: enabledSettings(
                calendar: true,
                reminders: false,
                location: false,
                motion: false,
                device: true,
                allowRemoteSensitiveTools: true
            )
        )

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(body["tool_choice"] as? String, "auto")
        XCTAssertEqual(body["parallel_tool_calls"] as? Bool, false)
        XCTAssertEqual((tools.first?["function"] as? [String: Any])?["name"] as? String, ChatToolID.calendarListEvents.rawValue)
        for tool in tools {
            let function = try XCTUnwrap(tool["function"] as? [String: Any])
            let name = try XCTUnwrap(function["name"] as? String)
            XCTAssertFalse(name.contains("."))
        }
    }

    func testResponsesEndpointUsesResponsesFunctionShape() throws {
        var body: [String: Any] = ["model": "gpt-test"]

        ChatToolSchemaEncoder.applyToolSchemas(
            to: &body,
            endpoint: endpoint(style: .openAIChatCompletions, chatURL: "https://api.openai.com/v1/responses"),
            settings: enabledSettings(calendar: false, reminders: false, location: false, motion: false, device: true)
        )

        let tool = try XCTUnwrap((body["tools"] as? [[String: Any]])?.first)
        XCTAssertEqual(tool["type"] as? String, "function")
        XCTAssertEqual(tool["name"] as? String, ChatToolID.deviceContext.rawValue)
        XCTAssertFalse((tool["name"] as? String)?.contains(".") == true)
        XCTAssertEqual(body["tool_choice"] as? String, "auto")
        XCTAssertNil(body["parallel_tool_calls"])
        XCTAssertNil(tool["strict"])
    }

    func testLMStudioNativeEndpointDoesNotInjectIntegrationYet() {
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

    func testRemoteEndpointFiltersSensitiveToolSchemasByDefault() throws {
        var body: [String: Any] = ["model": "gpt-test"]

        ChatToolSchemaEncoder.applyToolSchemas(
            to: &body,
            endpoint: endpoint(style: .openAIChatCompletions, chatURL: "https://api.openai.com/v1/chat/completions"),
            settings: enabledSettings(calendar: true, reminders: true, location: true, motion: true, device: true)
        )

        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let names = tools.compactMap { tool in
            (tool["function"] as? [String: Any])?["name"] as? String
        }
        XCTAssertEqual(names, [ChatToolID.deviceContext.rawValue])
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
        device: Bool = true,
        allowRemoteSensitiveTools: Bool = false
    ) -> ToolUseSettings {
        ToolUseSettings(
            isEnabled: true,
            calendarEnabled: calendar,
            remindersEnabled: reminders,
            locationEnabled: location,
            motionEnabled: motion,
            deviceContextEnabled: device,
            allowRemoteSensitiveTools: allowRemoteSensitiveTools
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
}
