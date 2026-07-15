import XCTest
@testable import Voice_Chat

final class ChatRequestBodyBuilderTests: XCTestCase {
    private let requestContextFingerprint = "sha256:test-request-state"

    func testRequestBodyBuilderBuildsOpenAIChatMessagesBody() throws {
        let builder = ChatRequestBodyBuilder()
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:8000/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:8000/v1/models"))
        )

        let data = try builder.buildRequestBodyData(
            model: "test-model",
            messagePayload: [["role": "user", "content": "hello"]],
            developerPrompt: nil,
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(openAIChatMaxCompletionTokens: 777),
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let body = try decodedBody(from: data)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])

        XCTAssertEqual(body["model"] as? String, "test-model")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["max_tokens"] as? Int, 777)
        XCTAssertNil(body["max_completion_tokens"])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "hello")
    }

    func testOpenAIChatCompletionsUsesSystemMessageForPrompts() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )

        let data = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "gpt-test",
            messagePayload: [
                ["role": "developer", "content": "You are concise."],
                ["role": "user", "content": "hello"]
            ],
            developerPrompt: "You are concise.",
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let body = try decodedBody(from: data)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, "You are concise.")
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertFalse(String(describing: messages).contains("\"developer\""))
    }

    func testEndpointResolverAndRequestBodyBuilderDefaultOpenAICompatibleToResponsesBody() throws {
        let endpoint = try XCTUnwrap(DefaultChatEndpointResolver().streamingCandidates(
            for: "http://localhost:8000",
            providerHint: .openAI,
            styleHint: .openAIResponses
        ).first)
        XCTAssertEqual(endpoint.chatURL.absoluteString, "http://localhost:8000/v1/responses")

        let data = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "test-model",
            messagePayload: [["role": "user", "content": "hello"]],
            developerPrompt: nil,
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(openAIResponsesMaxOutputTokens: 321),
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let body = try decodedBody(from: data)
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let firstContent = try XCTUnwrap(input.first?["content"] as? [[String: Any]])

        XCTAssertNil(body["messages"])
        XCTAssertEqual(body["model"] as? String, "test-model")
        XCTAssertEqual(body["max_output_tokens"] as? Int, 321)
        XCTAssertEqual(input.first?["role"] as? String, "user")
        XCTAssertEqual(firstContent.first?["type"] as? String, "input_text")
        XCTAssertEqual(firstContent.first?["text"] as? String, "hello")
    }

    func testOpenAIResponsesUsesInstructionsInsteadOfDeveloperInputMessage() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )

        let data = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "gpt-test",
            messagePayload: [
                ["role": "developer", "content": "new system prompt"],
                ["role": "user", "content": "hello"]
            ],
            developerPrompt: "new system prompt",
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let body = try decodedBody(from: data)
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])

        XCTAssertEqual(body["instructions"] as? String, "new system prompt")
        XCTAssertEqual(input.count, 1)
        XCTAssertEqual(input.first?["role"] as? String, "user")
        XCTAssertFalse(String(describing: input).contains("new system prompt"))
    }

    func testOpenAIResponsesExtractsPayloadPromptsIntoInstructions() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )

        let data = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "gpt-test",
            messagePayload: [
                ["role": "system", "content": "System prompt."],
                ["role": "developer", "content": "Developer prompt."],
                ["role": "user", "content": "hello"]
            ],
            developerPrompt: nil,
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let body = try decodedBody(from: data)
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])

        XCTAssertEqual(body["instructions"] as? String, "System prompt.\n\nDeveloper prompt.")
        XCTAssertEqual(input.count, 1)
        XCTAssertEqual(input.first?["role"] as? String, "user")
        XCTAssertFalse(String(describing: input).contains("System prompt."))
        XCTAssertFalse(String(describing: input).contains("Developer prompt."))
    }

    func testOfficialOpenAIResponsesAddsStablePromptCacheKeyWithoutForcingRetention() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )

        let first = try decodedBody(from: ChatRequestBodyBuilder().buildRequestBodyData(
            model: "gpt-5",
            messagePayload: [["role": "user", "content": "first variable tail"]],
            developerPrompt: "stable instructions",
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: nil,
            thinkingOption: nil
        ))
        let second = try decodedBody(from: ChatRequestBodyBuilder().buildRequestBodyData(
            model: "gpt-5",
            messagePayload: [["role": "user", "content": "second variable tail"]],
            developerPrompt: "stable instructions",
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: nil,
            thinkingOption: nil
        ))

        let firstKey = try XCTUnwrap(first["prompt_cache_key"] as? String)
        XCTAssertTrue(firstKey.hasPrefix("voice-chat-"))
        XCTAssertLessThanOrEqual(firstKey.count, 64)
        XCTAssertEqual(second["prompt_cache_key"] as? String, firstKey)
        XCTAssertNil(first["prompt_cache_retention"])
        XCTAssertNil(second["prompt_cache_retention"])
    }

    func testOfficialOpenAIResponsesDoesNotInferPromptCacheRetentionFromModelName() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )

        for model in ["gpt-5-mini", "gpt-4o"] {
            let body = try decodedBody(from: ChatRequestBodyBuilder().buildRequestBodyData(
                model: model,
                messagePayload: [["role": "user", "content": "hello"]],
                developerPrompt: nil,
                endpoint: endpoint,
                apiAdvancedSettings: APIAdvancedSettings(),
                thinkingCapability: nil,
                thinkingOption: nil
            ))

            XCTAssertTrue(
                (body["prompt_cache_key"] as? String)?.hasPrefix("voice-chat-") == true,
                "Expected an official OpenAI cache key for \(model)"
            )
            XCTAssertNil(
                body["prompt_cache_retention"],
                "Model names must not imply a cache retention policy for \(model)"
            )
        }
    }

    func testOfficialOpenAIResponsesPromptCacheKeyChangesWithStaticPrefix() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )

        let first = try decodedBody(from: ChatRequestBodyBuilder().buildRequestBodyData(
            model: "gpt-5",
            messagePayload: [["role": "user", "content": "same tail"]],
            developerPrompt: "stable instructions",
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: nil,
            thinkingOption: nil
        ))
        let second = try decodedBody(from: ChatRequestBodyBuilder().buildRequestBodyData(
            model: "gpt-5",
            messagePayload: [["role": "user", "content": "same tail"]],
            developerPrompt: "changed instructions",
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: nil,
            thinkingOption: nil
        ))

        XCTAssertNotEqual(first["prompt_cache_key"] as? String, second["prompt_cache_key"] as? String)
    }

    func testOpenRouterResponsesDoesNotReceiveOpenAIPromptCacheBodyParameters() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/models"))
        )

        let body = try decodedBody(from: ChatRequestBodyBuilder().buildRequestBodyData(
            model: "openai/gpt-oss-120b:free",
            messagePayload: [["role": "user", "content": "hello"]],
            developerPrompt: "stable instructions",
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: nil,
            thinkingOption: nil
        ))

        XCTAssertNil(body["prompt_cache_key"])
        XCTAssertNil(body["prompt_cache_retention"])
    }

    func testRequestBodyBuilderBuildsAnthropicThinkingBody() throws {
        let builder = ChatRequestBodyBuilder()
        let endpoint = ChatAPIEndpointCandidate(
            provider: .anthropic,
            style: .anthropicMessages,
            chatURL: try XCTUnwrap(URL(string: "https://api.anthropic.com/v1/messages")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.anthropic.com/v1/models"))
        )

        let data = try builder.buildRequestBodyData(
            model: "claude-test",
            messagePayload: [
                ["role": "developer", "content": "developer prompt"],
                ["role": "user", "content": "hello"]
            ],
            developerPrompt: "system prompt",
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(
                anthropicMaxTokens: 1,
                anthropicSampling: APIAdvancedSamplingSettings(
                    temperatureEnabled: true,
                    temperature: 0.7,
                    topPEnabled: true,
                    topP: 0.5,
                    topKEnabled: true,
                    topK: 20
                ),
                anthropicThinkingResponseReserve: 1,
                anthropicHighThinkingBudget: 1024
            ),
            thinkingCapability: nil,
            thinkingOption: .high
        )
        let body = try decodedBody(from: data)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let thinking = try XCTUnwrap(body["thinking"] as? [String: Any])

        XCTAssertEqual(body["system"] as? String, "system prompt")
        XCTAssertEqual(body["max_tokens"] as? Int, 1025)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(thinking["type"] as? String, "enabled")
        XCTAssertEqual(thinking["budget_tokens"] as? Int, 1024)
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["top_p"])
        XCTAssertNil(body["top_k"])
    }

    func testRequestBodyBuilderBuildsLMStudioRESTMultimodalBody() throws {
        let builder = ChatRequestBodyBuilder()
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )

        let dataURL = "data:image/png;base64,AAAA"
        let data = try builder.buildRequestBodyData(
            model: "local-model",
            messagePayload: [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "describe"],
                        ["type": "image_url", "image_url": ["url": dataURL]]
                    ]
                ]
            ],
            developerPrompt: "local system",
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(lmStudioMaxTokens: 256),
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let body = try decodedBody(from: data)
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])

        XCTAssertEqual(body["model"] as? String, "local-model")
        XCTAssertEqual(body["system_prompt"] as? String, "local system")
        XCTAssertEqual(body["store"] as? Bool, true)
        XCTAssertNil(body["previous_response_id"])
        XCTAssertEqual(body["max_output_tokens"] as? Int, 256)
        XCTAssertEqual(input.first?["type"] as? String, "text")
        XCTAssertTrue((input.first?["content"] as? String)?.contains("User: describe") == true)
        XCTAssertEqual(input.last?["type"] as? String, "image")
        XCTAssertEqual(input.last?["data_url"] as? String, dataURL)
    }

    func testLMStudioPreviousResponseContinuationSkipsPromptToolMetadata() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )

        let data = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "local-model",
            messagePayload: [
                ["role": "user", "content": "first question"],
                ["role": "assistant", "content": "first answer"],
                ["role": "user", "content": "what time is it?"]
            ],
            developerPrompt: "local system",
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            toolUseSettings: ToolUseSettings(
                isEnabled: true,
                calendarEnabled: false,
                remindersEnabled: false,
                locationEnabled: false,
                motionEnabled: false,
                deviceContextEnabled: true
            ),
            previousResponseID: "resp_previous123",
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let body = try decodedBody(from: data)

        XCTAssertEqual(body["store"] as? Bool, true)
        XCTAssertEqual(body["previous_response_id"] as? String, "resp_previous123")
        XCTAssertEqual(body["input"] as? String, "what time is it?")
        XCTAssertNil(body["system_prompt"])
        XCTAssertNil(body["tools"])
        XCTAssertFalse(String(describing: body).contains("Local tool use protocol:"))
        XCTAssertFalse(String(describing: body).contains("device_get_context"))
    }

    func testLMStudioToolContinuationWithPreviousResponseIDSendsOnlyToolResultInput() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )
        let payload = ChatToolResultMessageEncoder.followUpPayload(
            for: endpoint,
            originalPayload: [
                ["role": "user", "content": "first question"],
                ["role": "assistant", "content": "first answer"]
            ],
            calls: [
                ChatToolCallEnvelope(
                    callID: "call_1",
                    name: ChatToolID.deviceContext.rawValue,
                    argumentsJSON: "{}",
                    provider: .lmStudio
                )
            ],
            results: [
                ChatToolResultEnvelope(
                    callID: "call_1",
                    name: ChatToolID.deviceContext.rawValue,
                    status: .success,
                    payload: ["battery": .string("80%")],
                    summary: "Device context collected."
                )
            ],
            previousResponseID: "resp_previous123"
        )

        let data = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "local-model",
            messagePayload: payload,
            developerPrompt: "local system",
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            toolUseSettings: ToolUseSettings(
                isEnabled: true,
                calendarEnabled: false,
                remindersEnabled: false,
                locationEnabled: false,
                motionEnabled: false,
                deviceContextEnabled: true
            ),
            previousResponseID: "resp_previous123",
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let body = try decodedBody(from: data)
        let input = try XCTUnwrap(body["input"] as? String)

        XCTAssertEqual(body["previous_response_id"] as? String, "resp_previous123")
        XCTAssertNil(body["system_prompt"])
        XCTAssertFalse(String(describing: body).contains("Local tool use protocol:"))
        XCTAssertFalse(input.contains("first question"))
        XCTAssertFalse(input.contains("first answer"))
        XCTAssertFalse(input.contains("<tool_call>"))
        XCTAssertTrue(input.contains("<tool_result "))
        XCTAssertTrue(input.contains("Device context collected."))
    }

    func testLMStudioMultiToolContinuationUsesLatestResponseIDAndOnlyLatestResult() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )
        let firstCall = ChatToolCallEnvelope(
            callID: "call_time",
            name: ChatToolID.systemGetTime.rawValue,
            argumentsJSON: "{}",
            provider: .lmStudio
        )
        let firstResult = ChatToolResultEnvelope(
            callID: firstCall.callID,
            name: firstCall.name,
            status: .success,
            payload: ["local_iso8601": .string("2001-01-01T08:00:00+08:00")],
            summary: "Current time was read."
        )
        let firstPayload = ChatToolResultMessageEncoder.followUpPayload(
            for: endpoint,
            originalPayload: [["role": "user", "content": "Read time and device context."]],
            calls: [firstCall],
            results: [firstResult],
            previousResponseID: "resp_first_tool"
        )
        let secondCall = ChatToolCallEnvelope(
            callID: "call_device",
            name: ChatToolID.deviceContext.rawValue,
            argumentsJSON: "{}",
            provider: .lmStudio
        )
        let secondResult = ChatToolResultEnvelope(
            callID: secondCall.callID,
            name: secondCall.name,
            status: .success,
            payload: ["platform": .string("macOS")],
            summary: "Device context was read."
        )
        let secondPayload = ChatToolResultMessageEncoder.followUpPayload(
            for: endpoint,
            originalPayload: firstPayload,
            calls: [secondCall],
            results: [secondResult],
            previousResponseID: "resp_second_tool"
        )

        let data = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "local-model",
            messagePayload: secondPayload,
            developerPrompt: "local system",
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            toolUseSettings: ToolUseSettings(
                isEnabled: true,
                calendarEnabled: false,
                remindersEnabled: false,
                locationEnabled: false,
                motionEnabled: false,
                deviceContextEnabled: true
            ),
            previousResponseID: "resp_second_tool",
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let body = try decodedBody(from: data)
        let input = try XCTUnwrap(body["input"] as? String)

        XCTAssertEqual(body["previous_response_id"] as? String, "resp_second_tool")
        XCTAssertNil(body["system_prompt"])
        XCTAssertTrue(input.contains("Device context was read."))
        XCTAssertFalse(input.contains("Current time was read."))
        XCTAssertFalse(input.contains("Read time and device context."))
        XCTAssertFalse(input.contains("<tool_call>"))
    }

    func testOpenAIResponsesPreviousResponseContinuationKeepsToolsAndSendsLatestUserOnly() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )

        let data = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "gpt-test",
            messagePayload: [
                ["role": "user", "content": "first question"],
                ["role": "assistant", "content": "first answer"],
                ["role": "user", "content": "follow up only"]
            ],
            developerPrompt: "system prompt",
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            toolUseSettings: ToolUseSettings(
                isEnabled: true,
                calendarEnabled: false,
                remindersEnabled: false,
                locationEnabled: false,
                motionEnabled: false,
                deviceContextEnabled: true
            ),
            previousResponseID: "resp_previous123",
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let body = try decodedBody(from: data)
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let firstContent = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])

        XCTAssertEqual(body["previous_response_id"] as? String, "resp_previous123")
        let instructions = try XCTUnwrap(body["instructions"] as? String)
        XCTAssertTrue(instructions.hasPrefix("system prompt"))
        XCTAssertTrue(instructions.contains(ChatToolDefinitions.untrustedResultInstruction))
        XCTAssertTrue((body["prompt_cache_key"] as? String)?.hasPrefix("voice-chat-") == true)
        XCTAssertEqual(input.count, 1)
        XCTAssertEqual(input.first?["role"] as? String, "user")
        XCTAssertEqual(firstContent.first?["text"] as? String, "follow up only")
        XCTAssertEqual(tools.first?["name"] as? String, "device_get_context")
        XCTAssertEqual(body["tool_choice"] as? String, "auto")
        XCTAssertFalse(String(describing: input).contains("first question"))
        XCTAssertFalse(String(describing: input).contains("first answer"))
    }

    func testOpenAIResponsesKeepsFullToolSetWithAutomaticChoice() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/models"))
        )

        let data = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "openai/gpt-oss-20b:free",
            messagePayload: [
                ["role": "user", "content": "What is the current time Use the systemgettime tool"]
            ],
            developerPrompt: "system prompt",
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            toolUseSettings: ToolUseSettings(
                isEnabled: true,
                calendarEnabled: true,
                remindersEnabled: true,
                locationEnabled: true,
                motionEnabled: true,
                deviceContextEnabled: true,
                clipboardEnabled: true,
                urlActionsEnabled: true,
                codeInterpreterEnabled: true,
                timeEnabled: true
            ),
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let body = try decodedBody(from: data)
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(body["tool_choice"] as? String, "auto")
        let names = Set(tools.compactMap { $0["name"] as? String })
        XCTAssertEqual(names, Set(ChatToolID.allCases.map(\.rawValue)))
    }

    func testOpenAIResponsesToolContinuationUsesPreviousResponseIDAndToolOutputInput() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )

        let data = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "gpt-test",
            messagePayload: [
                [
                    "type": "function_call_output",
                    "call_id": "call_1",
                    "output": "{\"status\":\"success\"}"
                ]
            ],
            developerPrompt: nil,
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            previousResponseID: "resp_previous",
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let body = try decodedBody(from: data)
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])

        XCTAssertEqual(body["previous_response_id"] as? String, "resp_previous")
        XCTAssertEqual(input.count, 1)
        XCTAssertEqual(input.first?["type"] as? String, "function_call_output")
        XCTAssertEqual(input.first?["call_id"] as? String, "call_1")
    }

    func testRequestBodyBuilderSerializesStableSortedJSONKeys() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://example.com/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "https://example.com/v1/models"))
        )

        let data = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "gpt-test",
            messagePayload: [["role": "user", "content": "hello"]],
            developerPrompt: nil,
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: nil,
            thinkingOption: nil
        )

        XCTAssertEqual(
            String(data: data, encoding: .utf8),
            "{\"messages\":[{\"content\":\"hello\",\"role\":\"user\"}],\"model\":\"gpt-test\",\"stream\":true}"
        )
    }

    func testToolResultOutputJSONStringUsesStableSortedKeys() {
        let result = ChatToolResultEnvelope(
            callID: "call_1",
            name: "device_get_context",
            status: .success,
            payload: [
                "zeta": .string("last"),
                "alpha": .string("first")
            ],
            summary: "Collected."
        )

        XCTAssertEqual(
            result.outputJSONString,
            "{\"data\":{\"alpha\":\"first\",\"zeta\":\"last\"},\"status\":\"success\",\"summary\":\"Collected.\",\"tool\":\"device_get_context\"}"
        )
    }

    func testPreviousResponseIDAllowsProviderIDsWithoutRespPrefix() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )

        let responseID = ChatService.previousResponseID(
            in: [
                ChatRequestSourceMessage(content: "first", isUser: true),
                ChatRequestSourceMessage(
                    content: "first answer",
                    isUser: false,
                    providerResponseID: "response_without_known_prefix",
                    requestContextFingerprint: requestContextFingerprint
                ),
                ChatRequestSourceMessage(content: "follow up", isUser: true)
            ],
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint
        )

        XCTAssertEqual(responseID, "response_without_known_prefix")
    }

    func testPreviousResponseIDCanBeDisabledByDeveloperPolicy() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )

        let responseID = ChatService.previousResponseID(
            in: [
                ChatRequestSourceMessage(content: "first", isUser: true),
                ChatRequestSourceMessage(
                    content: "first answer",
                    isUser: false,
                    providerResponseID: "resp_first",
                    requestContextFingerprint: requestContextFingerprint
                ),
                ChatRequestSourceMessage(content: "follow up", isUser: true)
            ],
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint,
            useProviderContinuationIDs: false
        )

        XCTAssertNil(responseID)
    }

    func testOpenRouterResponsesPreviousResponseIDFollowsDeveloperEndpointPolicy() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/models"))
        )
        let sourceMessages = [
            ChatRequestSourceMessage(content: "first", isUser: true),
            ChatRequestSourceMessage(
                content: "first answer",
                isUser: false,
                providerResponseID: "gen-openrouter-response",
                requestContextFingerprint: requestContextFingerprint
            ),
            ChatRequestSourceMessage(content: "follow up", isUser: true)
        ]

        let defaultResponseID = ChatService.previousResponseID(
            in: sourceMessages,
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint,
            useProviderContinuationIDs: ToolUseSettings.defaults.useProviderContinuationIDs(for: endpoint)
        )
        var enabledSettings = ToolUseSettings.defaults
        enabledSettings.enableOpenAIResponsesStatefulChat(for: endpoint)
        let enabledResponseID = ChatService.previousResponseID(
            in: sourceMessages,
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint,
            useProviderContinuationIDs: enabledSettings.useProviderContinuationIDs(for: endpoint)
        )

        XCTAssertNil(defaultResponseID)
        XCTAssertEqual(enabledResponseID, "gen-openrouter-response")
        XCTAssertTrue(ChatRequestBodyProviderEncoder.supportsPreviousResponseContinuation(endpoint))
        XCTAssertFalse(ToolUseSettings.defaults.useProviderContinuationIDs(for: endpoint))
        XCTAssertTrue(enabledSettings.useProviderContinuationIDs(for: endpoint))
    }

    func testOpenRouterResponsesRequestBodyUsesPreviousResponseIDWhenEndpointIsEnabled() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/models"))
        )
        var toolUseSettings = ToolUseSettings.defaults
        toolUseSettings.enableOpenAIResponsesStatefulChat(for: endpoint)

        let payload = ChatRequestPayloadProjector().transformedMessagesForRequest(
            messages: [
                ChatRequestSourceMessage(content: "first question", isUser: true),
                ChatRequestSourceMessage(
                    content: "first answer",
                    isUser: false,
                    assistantSegments: [
                        ChatAssistantSegment(kind: .text, itemID: "msg_openrouter_1", text: "first answer")
                    ]
                ),
                ChatRequestSourceMessage(content: "follow up", isUser: true)
            ],
            developerPrompt: nil,
            includeImagesInUserContent: false
        )
        let data = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "openai/gpt-oss-120b:free",
            messagePayload: payload,
            developerPrompt: nil,
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            toolUseSettings: toolUseSettings,
            previousResponseID: "gen-openrouter-response",
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let body = try decodedBody(from: data)
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])

        XCTAssertEqual(body["previous_response_id"] as? String, "gen-openrouter-response")
        XCTAssertEqual(input.count, 1)
        XCTAssertFalse(String(describing: input).contains("first question"))
        XCTAssertFalse(String(describing: input).contains("first answer"))
        XCTAssertTrue(String(describing: input).contains("follow up"))
        XCTAssertTrue(toolUseSettings.useProviderContinuationIDs(for: endpoint))
    }

    func testChatCompletionsDropsResponsesAssistantHistoryMetadata() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://compatible.example.com/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "https://compatible.example.com/v1/models"))
        )
        let payload = ChatRequestPayloadProjector().transformedMessagesForRequest(
            messages: [
                ChatRequestSourceMessage(content: "first question", isUser: true),
                ChatRequestSourceMessage(
                    content: "first answer",
                    isUser: false,
                    assistantSegments: [
                        ChatAssistantSegment(kind: .text, itemID: "msg_responses_1", text: "first answer")
                    ]
                ),
                ChatRequestSourceMessage(content: "follow up", isUser: true)
            ],
            developerPrompt: nil,
            includeImagesInUserContent: false
        )

        let body = try decodedBody(from: ChatRequestBodyBuilder().buildRequestBodyData(
            model: "model",
            messagePayload: payload,
            developerPrompt: nil,
            endpoint: endpoint,
            apiAdvancedSettings: .defaults,
            thinkingCapability: nil,
            thinkingOption: nil
        ))
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let assistant = try XCTUnwrap(messages.first { ($0["role"] as? String) == "assistant" })

        XCTAssertEqual(assistant["content"] as? String, "first answer")
        XCTAssertNil(assistant["id"])
        XCTAssertNil(assistant["status"])
        XCTAssertNil(assistant["type"])
    }

    func testLMStudioMissingPreviousResponseErrorRequiresExplicitStoredResponseFailure() {
        XCTAssertTrue(ChatService.isLMStudioMissingPreviousResponseError(
            statusCode: 400,
            message: #"{"error":{"code":"previous_response_not_found","message":"Response was automatically deleted"}}"#
        ))
        XCTAssertTrue(ChatService.isLMStudioMissingPreviousResponseError(
            statusCode: 400,
            message: "previous_response_id could not find stored response"
        ))
        XCTAssertFalse(ChatService.isLMStudioMissingPreviousResponseError(
            statusCode: 429,
            message: "previous_response_not_found"
        ))
        XCTAssertFalse(ChatService.isLMStudioMissingPreviousResponseError(
            statusCode: 400,
            message: "invalid model"
        ))
    }

    func testOpenAIResponsesPreviousResponseIDUsesMatchingAssistantBeforeLatestUser() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )

        let responseID = ChatService.previousResponseID(
            in: [
                ChatRequestSourceMessage(content: "first", isUser: true),
                ChatRequestSourceMessage(
                    content: "first answer",
                    isUser: false,
                    providerResponseID: "resp_first",
                    requestContextFingerprint: requestContextFingerprint
                ),
                ChatRequestSourceMessage(content: "follow up", isUser: true)
            ],
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint
        )

        XCTAssertEqual(responseID, "resp_first")
    }

    func testOpenAIChatCompletionsPreviousResponseIDIsNotUsed() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )

        let responseID = ChatService.previousResponseID(
            in: [
                ChatRequestSourceMessage(content: "first", isUser: true),
                ChatRequestSourceMessage(
                    content: "first answer",
                    isUser: false,
                    providerResponseID: "resp_first",
                    requestContextFingerprint: requestContextFingerprint
                ),
                ChatRequestSourceMessage(content: "follow up", isUser: true)
            ],
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint
        )

        XCTAssertNil(responseID)
    }

    func testRequestContextFingerprintIgnoresLocalAuthorizationPolicy() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )

        do {
            let readOnly = ToolUseSettings(
                isEnabled: true,
                calendarEnabled: false,
                remindersEnabled: false,
                locationEnabled: false,
                motionEnabled: false,
                deviceContextEnabled: true,
                authorizationMode: .readOnly
            )
            let askEveryTime = ToolUseSettings(
                isEnabled: true,
                calendarEnabled: false,
                remindersEnabled: false,
                locationEnabled: false,
                motionEnabled: false,
                deviceContextEnabled: true,
                authorizationMode: .askEveryTime
            )
            let first = ChatRequestContextBuilder.make(
                model: "gpt-test",
                endpoint: endpoint,
                developerPrompt: "system prompt",
                toolUseSettings: readOnly,
                thinkingOption: .high
            )
            let second = ChatRequestContextBuilder.make(
                model: "gpt-test",
                endpoint: endpoint,
                developerPrompt: "system prompt",
                toolUseSettings: askEveryTime,
                thinkingOption: .high
            )

            XCTAssertEqual(first.fingerprint, second.fingerprint)
            XCTAssertEqual(first.snapshot.toolAuthorizationModeRawValue, ToolAuthorizationMode.readOnly.rawValue)
            XCTAssertEqual(second.snapshot.toolAuthorizationModeRawValue, ToolAuthorizationMode.askEveryTime.rawValue)
        }

        do {
            var disabled = ToolUseSettings.defaults
            disabled.isEnabled = true
            disabled.codeInterpreterEnabled = true
            disabled.allowHighRiskToolAutoExecution = false
            var enabled = disabled
            enabled.allowHighRiskToolAutoExecution = true

            let first = ChatRequestContextBuilder.make(
                model: "gpt-test",
                endpoint: endpoint,
                developerPrompt: "system prompt",
                toolUseSettings: disabled,
                thinkingOption: .high
            )
            let second = ChatRequestContextBuilder.make(
                model: "gpt-test",
                endpoint: endpoint,
                developerPrompt: "system prompt",
                toolUseSettings: enabled,
                thinkingOption: .high
            )

            XCTAssertEqual(first.fingerprint, second.fingerprint)
            XCTAssertFalse(first.snapshot.allowHighRiskToolAutoExecution)
            XCTAssertTrue(second.snapshot.allowHighRiskToolAutoExecution)
        }
    }

    func testRequestContextFingerprintReflectsDeveloperTransportPolicy() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )
        var enabled = ToolUseSettings.defaults
        enabled.useProviderContinuationIDs = true
        var disabled = enabled
        disabled.useProviderContinuationIDs = false

        let first = ChatRequestContextBuilder.make(
            model: "local-model",
            endpoint: endpoint,
            developerPrompt: "system prompt",
            toolUseSettings: enabled,
            thinkingOption: nil
        )
        let second = ChatRequestContextBuilder.make(
            model: "local-model",
            endpoint: endpoint,
            developerPrompt: "system prompt",
            toolUseSettings: disabled,
            thinkingOption: nil
        )

        XCTAssertNotEqual(first.fingerprint, second.fingerprint)
        XCTAssertTrue(first.snapshot.useProviderContinuationIDs)
        XCTAssertFalse(second.snapshot.useProviderContinuationIDs)
    }

    func testOpenAIResponsesRequestContextFingerprintIgnoresDeveloperPrompt() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )

        let first = ChatRequestContextBuilder.make(
            model: "gpt-test",
            endpoint: endpoint,
            developerPrompt: "old instructions",
            toolUseSettings: .defaults,
            thinkingOption: nil
        )
        let second = ChatRequestContextBuilder.make(
            model: "gpt-test",
            endpoint: endpoint,
            developerPrompt: "new instructions",
            toolUseSettings: .defaults,
            thinkingOption: nil
        )

        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertNotEqual(first.snapshot.developerPromptHash, second.snapshot.developerPromptHash)
    }

    func testLMStudioRequestContextFingerprintReflectsDeveloperPrompt() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )

        let first = ChatRequestContextBuilder.make(
            model: "local-model",
            endpoint: endpoint,
            developerPrompt: "old system prompt",
            toolUseSettings: .defaults,
            thinkingOption: nil
        )
        let second = ChatRequestContextBuilder.make(
            model: "local-model",
            endpoint: endpoint,
            developerPrompt: "new system prompt",
            toolUseSettings: .defaults,
            thinkingOption: nil
        )

        XCTAssertNotEqual(first.fingerprint, second.fingerprint)
    }

    func testPreviousResponseIDIsRejectedAfterModelSwitch() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )
        let previousContext = ChatRequestContextBuilder.make(
            model: "model-a",
            endpoint: endpoint,
            developerPrompt: "system prompt",
            toolUseSettings: .defaults,
            thinkingOption: nil
        )
        let currentContext = ChatRequestContextBuilder.make(
            model: "model-b",
            endpoint: endpoint,
            developerPrompt: "system prompt",
            toolUseSettings: .defaults,
            thinkingOption: nil
        )

        let responseID = ChatService.previousResponseID(
            in: [
                ChatRequestSourceMessage(content: "first", isUser: true),
                ChatRequestSourceMessage(
                    content: "first answer",
                    isUser: false,
                    providerResponseID: "resp_first",
                    requestContextFingerprint: previousContext.fingerprint
                ),
                ChatRequestSourceMessage(content: "follow up", isUser: true)
            ],
            endpoint: endpoint,
            currentRequestFingerprint: currentContext.fingerprint
        )

        XCTAssertNotEqual(previousContext.fingerprint, currentContext.fingerprint)
        XCTAssertNil(responseID)
    }

    func testRequestContextFingerprintReflectsActuallyEnabledTools() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )

        let disabled = ChatRequestContextBuilder.make(
            model: "gpt-test",
            endpoint: endpoint,
            developerPrompt: nil,
            toolUseSettings: ToolUseSettings(
                isEnabled: false,
                calendarEnabled: true,
                remindersEnabled: true,
                locationEnabled: true,
                motionEnabled: true,
                deviceContextEnabled: true
            ),
            thinkingOption: nil
        )

        XCTAssertEqual(disabled.snapshot.enabledToolIDsJSON, "[]")
        XCTAssertFalse(disabled.snapshot.toolSchemaSummaryJSON.contains("device_get_context"))
    }

    func testRequestContextFingerprintReflectsImageInputSummary() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )
        let textOnly = ChatRequestContextBuilder.make(
            model: "gpt-test",
            endpoint: endpoint,
            developerPrompt: nil,
            toolUseSettings: .defaults,
            thinkingOption: nil,
            sourceMessages: [
                ChatRequestSourceMessage(content: "describe this", isUser: true)
            ],
            includeImagesInUserContent: true
        )
        let withImage = ChatRequestContextBuilder.make(
            model: "gpt-test",
            endpoint: endpoint,
            developerPrompt: nil,
            toolUseSettings: .defaults,
            thinkingOption: nil,
            sourceMessages: [
                ChatRequestSourceMessage(
                    content: "describe this",
                    isUser: true,
                    imageAttachments: [
                        ChatImageAttachment(mimeType: "image/png", data: Data([0x01, 0x02, 0x03]))
                    ]
                )
            ],
            includeImagesInUserContent: true
        )
        let imageNotIncluded = ChatRequestContextBuilder.make(
            model: "gpt-test",
            endpoint: endpoint,
            developerPrompt: nil,
            toolUseSettings: .defaults,
            thinkingOption: nil,
            sourceMessages: [
                ChatRequestSourceMessage(
                    content: "describe this",
                    isUser: true,
                    imageAttachments: [
                        ChatImageAttachment(mimeType: "image/png", data: Data([0x01, 0x02, 0x03]))
                    ]
                )
            ],
            includeImagesInUserContent: false
        )

        XCTAssertNotEqual(textOnly.fingerprint, withImage.fingerprint)
        XCTAssertNotEqual(withImage.fingerprint, imageNotIncluded.fingerprint)
    }

    func testRequestContextFingerprintReflectsAdvancedSettings() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )
        let defaultSettings = ChatRequestContextBuilder.make(
            model: "gpt-test",
            endpoint: endpoint,
            developerPrompt: "system prompt",
            toolUseSettings: .defaults,
            apiAdvancedSettings: .defaults,
            thinkingOption: nil
        )
        let jsonModeSettings = ChatRequestContextBuilder.make(
            model: "gpt-test",
            endpoint: endpoint,
            developerPrompt: "system prompt",
            toolUseSettings: .defaults,
            apiAdvancedSettings: APIAdvancedSettings(
                openAIResponsesSampling: APIAdvancedSamplingSettings(jsonModeEnabled: true)
            ),
            thinkingOption: nil
        )

        XCTAssertNotEqual(defaultSettings.fingerprint, jsonModeSettings.fingerprint)
    }

    func testLMStudioPreviousResponseIDUsesAssistantBeforeLatestUser() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )

        let responseID = ChatService.previousResponseID(
            in: [
                ChatRequestSourceMessage(content: "first", isUser: true),
                ChatRequestSourceMessage(
                    content: "first answer",
                    isUser: false,
                    providerResponseID: "resp_first",
                    requestContextFingerprint: requestContextFingerprint
                ),
                ChatRequestSourceMessage(content: "follow up", isUser: true)
            ],
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint
        )

        XCTAssertEqual(responseID, "resp_first")
    }

    func testLMStudioPreviousResponseIDRequiresMatchingRequestFingerprint() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )

        let responseID = ChatService.previousResponseID(
            in: [
                ChatRequestSourceMessage(content: "first", isUser: true),
                ChatRequestSourceMessage(
                    content: "first answer",
                    isUser: false,
                    providerResponseID: "resp_first",
                    requestContextFingerprint: "sha256:old-state"
                ),
                ChatRequestSourceMessage(content: "follow up", isUser: true)
            ],
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint
        )

        XCTAssertNil(responseID)
    }

    func testLMStudioPreviousResponseIDIgnoresAssistantAfterLatestUser() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )

        let responseID = ChatService.previousResponseID(
            in: [
                ChatRequestSourceMessage(content: "retry this", isUser: true),
                ChatRequestSourceMessage(content: "failed answer", isUser: false, providerResponseID: "resp_failed_retry")
            ],
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint
        )

        XCTAssertNil(responseID)
    }

    func testLMStudioPreviousResponseIDRequiresImmediatePreviousAssistant() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )

        let responseID = ChatService.previousResponseID(
            in: [
                ChatRequestSourceMessage(content: "first", isUser: true),
                ChatRequestSourceMessage(
                    content: "first answer",
                    isUser: false,
                    providerResponseID: "resp_first",
                    requestContextFingerprint: requestContextFingerprint
                ),
                ChatRequestSourceMessage(content: "second without answer", isUser: true),
                ChatRequestSourceMessage(content: "third latest", isUser: true)
            ],
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint
        )

        XCTAssertNil(responseID)
    }

    func testLMStudioPreviousResponseIDIgnoresPreviousErrorAssistantEvenWithResponseID() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )

        let responseID = ChatService.previousResponseID(
            in: [
                ChatRequestSourceMessage(content: "first", isUser: true),
                ChatRequestSourceMessage(
                    content: "!error:network failed",
                    isUser: false,
                    providerResponseID: "resp_failed",
                    requestContextFingerprint: requestContextFingerprint
                ),
                ChatRequestSourceMessage(content: "continue after failure", isUser: true)
            ],
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint
        )

        XCTAssertNil(responseID)
    }

    func testLMStudioPreviousResponseIDIgnoresAssistantOlderThanThirtyDays() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )
        let now = TestDate.reference
        let oldAssistantDate = now.addingTimeInterval(-(31 * 24 * 60 * 60))

        let responseID = ChatService.previousResponseID(
            in: [
                ChatRequestSourceMessage(content: "first", isUser: true, createdAt: oldAssistantDate),
                ChatRequestSourceMessage(
                    content: "first answer",
                    isUser: false,
                    providerResponseID: "resp_old",
                    requestContextFingerprint: requestContextFingerprint,
                    createdAt: oldAssistantDate
                ),
                ChatRequestSourceMessage(content: "follow up", isUser: true, createdAt: now)
            ],
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint,
            now: now
        )

        XCTAssertNil(responseID)
    }

    func testLMStudioRetryRequestBodyUsesPreviousAssistantBeforeRetriedUserOnly() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )
        let sourceMessages = [
            ChatRequestSourceMessage(content: "first", isUser: true),
            ChatRequestSourceMessage(
                content: "first answer",
                isUser: false,
                providerResponseID: "resp_first",
                requestContextFingerprint: requestContextFingerprint
            ),
            ChatRequestSourceMessage(content: "retry this", isUser: true)
        ]
        let previousID = ChatService.previousResponseID(
            in: sourceMessages,
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint
        )
        let payload = ChatRequestPayloadProjector().transformedMessagesForRequest(
            messages: sourceMessages,
            developerPrompt: nil,
            includeImagesInUserContent: false
        )

        let body = try decodedBody(from: ChatRequestBodyBuilder().buildRequestBodyData(
            model: "local-model",
            messagePayload: payload,
            developerPrompt: nil,
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            previousResponseID: previousID,
            thinkingCapability: nil,
            thinkingOption: nil
        ))

        XCTAssertEqual(body["previous_response_id"] as? String, "resp_first")
        XCTAssertEqual(body["input"] as? String, "retry this")
    }

    func testLMStudioConsecutiveUserRequestBodyDoesNotUsePreviousResponseID() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )
        let sourceMessages = [
            ChatRequestSourceMessage(content: "first", isUser: true),
            ChatRequestSourceMessage(
                content: "first answer",
                isUser: false,
                providerResponseID: "resp_first",
                requestContextFingerprint: requestContextFingerprint
            ),
            ChatRequestSourceMessage(content: "second without answer", isUser: true),
            ChatRequestSourceMessage(content: "third latest", isUser: true)
        ]
        let previousID = ChatService.previousResponseID(
            in: sourceMessages,
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint
        )
        let payload = ChatRequestPayloadProjector().transformedMessagesForRequest(
            messages: sourceMessages,
            developerPrompt: nil,
            includeImagesInUserContent: false
        )

        let body = try decodedBody(from: ChatRequestBodyBuilder().buildRequestBodyData(
            model: "local-model",
            messagePayload: payload,
            developerPrompt: nil,
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            previousResponseID: previousID,
            thinkingCapability: nil,
            thinkingOption: nil
        ))

        let input = try XCTUnwrap(body["input"] as? String)
        XCTAssertNil(body["previous_response_id"])
        XCTAssertTrue(input.contains("User: second without answer"))
        XCTAssertTrue(input.contains("User: third latest"))
    }

    func testLMStudioRequestBodyAfterErrorDoesNotUseFailedResponseID() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )
        let sourceMessages = [
            ChatRequestSourceMessage(content: "first", isUser: true),
            ChatRequestSourceMessage(
                content: "!error:network failed",
                isUser: false,
                providerResponseID: "resp_failed",
                requestContextFingerprint: requestContextFingerprint
            ),
            ChatRequestSourceMessage(content: "continue after failure", isUser: true)
        ]
        let previousID = ChatService.previousResponseID(
            in: sourceMessages,
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint
        )
        let payload = ChatRequestPayloadProjector().transformedMessagesForRequest(
            messages: sourceMessages,
            developerPrompt: nil,
            includeImagesInUserContent: false
        )

        let body = try decodedBody(from: ChatRequestBodyBuilder().buildRequestBodyData(
            model: "local-model",
            messagePayload: payload,
            developerPrompt: nil,
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            previousResponseID: previousID,
            thinkingCapability: nil,
            thinkingOption: nil
        ))

        let input = try XCTUnwrap(body["input"] as? String)
        XCTAssertNil(body["previous_response_id"])
        XCTAssertTrue(input.contains("User: first"))
        XCTAssertTrue(input.contains("User: continue after failure"))
        XCTAssertFalse(input.contains("resp_failed"))
        XCTAssertFalse(input.contains("!error:network failed"))
    }

    func testLMStudioRequestBodyAfterOldResponseIDSendsFullTranscript() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )
        let now = TestDate.reference
        let oldAssistantDate = now.addingTimeInterval(-(31 * 24 * 60 * 60))
        let sourceMessages = [
            ChatRequestSourceMessage(content: "first", isUser: true, createdAt: oldAssistantDate),
            ChatRequestSourceMessage(
                content: "first answer",
                isUser: false,
                providerResponseID: "resp_old",
                requestContextFingerprint: requestContextFingerprint,
                createdAt: oldAssistantDate
            ),
            ChatRequestSourceMessage(content: "follow up", isUser: true, createdAt: now)
        ]
        let previousID = ChatService.previousResponseID(
            in: sourceMessages,
            endpoint: endpoint,
            currentRequestFingerprint: requestContextFingerprint,
            now: now
        )
        let payload = ChatRequestPayloadProjector().transformedMessagesForRequest(
            messages: sourceMessages,
            developerPrompt: nil,
            includeImagesInUserContent: false
        )

        let body = try decodedBody(from: ChatRequestBodyBuilder().buildRequestBodyData(
            model: "local-model",
            messagePayload: payload,
            developerPrompt: nil,
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            previousResponseID: previousID,
            thinkingCapability: nil,
            thinkingOption: nil
        ))

        let input = try XCTUnwrap(body["input"] as? String)
        XCTAssertNil(body["previous_response_id"])
        XCTAssertTrue(input.contains("User: first"))
        XCTAssertTrue(input.contains("Assistant: first answer"))
        XCTAssertTrue(input.contains("User: follow up"))
    }

    func testRequestBodyBuilderMapsOpenAIAndLMStudioAdvancedSettings() throws {
        let sampling = APIAdvancedSamplingSettings(
            temperatureEnabled: true,
            temperature: 1.5,
            topPEnabled: true,
            topP: 0.75,
            topKEnabled: true,
            topK: 40,
            minPEnabled: true,
            minP: 0.1,
            topAEnabled: true,
            topA: 0.2,
            presencePenaltyEnabled: true,
            presencePenalty: 0.3,
            frequencyPenaltyEnabled: true,
            frequencyPenalty: 0.4,
            repetitionPenaltyEnabled: true,
            repetitionPenalty: 1.1,
            seedEnabled: true,
            seed: 123,
            contextLengthEnabled: true,
            contextLength: 4096,
            jsonModeEnabled: true,
            structuredOutputsEnabled: true,
            logprobsEnabled: true,
            topLogprobsEnabled: true,
            topLogprobs: 9,
            verbosityEnabled: true,
            verbosity: "high"
        )
        let messagePayload = [["role": "user", "content": "hello"]]

        let openAIEndpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )
        let openAIData = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "open-model",
            messagePayload: messagePayload,
            developerPrompt: nil,
            endpoint: openAIEndpoint,
            apiAdvancedSettings: APIAdvancedSettings(openAIChatMaxCompletionTokens: 404, openAIChatSampling: sampling),
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let openAI = try decodedBody(from: openAIData)
        XCTAssertEqual(openAI["max_completion_tokens"] as? Int, 404)
        XCTAssertEqual(openAI["temperature"] as? Double, 1.5)
        XCTAssertEqual(openAI["top_p"] as? Double, 0.75)
        XCTAssertEqual(openAI["presence_penalty"] as? Double, 0.3)
        XCTAssertEqual(openAI["frequency_penalty"] as? Double, 0.4)
        XCTAssertEqual(openAI["top_logprobs"] as? Int, 9)

        let lmStudioChatCompletionsEndpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/v1/models"))
        )
        let lmStudioChatCompletionsData = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "local-openai",
            messagePayload: messagePayload,
            developerPrompt: nil,
            endpoint: lmStudioChatCompletionsEndpoint,
            apiAdvancedSettings: APIAdvancedSettings(openAIChatMaxCompletionTokens: 505, openAIChatSampling: sampling),
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let lmStudioChatCompletions = try decodedBody(from: lmStudioChatCompletionsData)
        XCTAssertEqual(lmStudioChatCompletions["max_tokens"] as? Int, 505)
        XCTAssertNil(lmStudioChatCompletions["max_completion_tokens"])
        XCTAssertEqual(lmStudioChatCompletions["top_logprobs"] as? Int, 9)
        XCTAssertNil(lmStudioChatCompletions["top_k"])
        XCTAssertNil(lmStudioChatCompletions["repeat_penalty"])

        let deepSeekEndpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://api.deepseek.com/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.deepseek.com/models"))
        )
        let deepSeekData = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "deepseek-chat",
            messagePayload: messagePayload,
            developerPrompt: nil,
            endpoint: deepSeekEndpoint,
            apiAdvancedSettings: APIAdvancedSettings(openAIChatMaxCompletionTokens: 303),
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let deepSeek = try decodedBody(from: deepSeekData)
        XCTAssertEqual(deepSeek["max_tokens"] as? Int, 303)
        XCTAssertNil(deepSeek["max_completion_tokens"])

        let lmStudioNativeEndpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )
        let lmStudioNativeData = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "local-native",
            messagePayload: messagePayload,
            developerPrompt: nil,
            endpoint: lmStudioNativeEndpoint,
            apiAdvancedSettings: APIAdvancedSettings(lmStudioMaxTokens: 606, lmStudioSampling: sampling),
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let lmStudioNative = try decodedBody(from: lmStudioNativeData)
        XCTAssertEqual(lmStudioNative["max_output_tokens"] as? Int, 606)
        XCTAssertEqual(lmStudioNative["top_k"] as? Int, 40)
        XCTAssertEqual(lmStudioNative["repeat_penalty"] as? Double, 1.1)
    }

    func testRequestBodyBuilderMapsThinkingForResponsesOpenAIChatAndLMStudio() throws {
        let messagePayload = [["role": "user", "content": "hello"]]

        let responsesEndpoint = try XCTUnwrap(DefaultChatEndpointResolver().streamingCandidates(
            for: "https://api.openai.com",
            providerHint: .openAI,
            styleHint: .openAIResponses
        ).first)
        let responsesData = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "gpt-test",
            messagePayload: messagePayload,
            developerPrompt: nil,
            endpoint: responsesEndpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: nil,
            thinkingOption: .max
        )
        let responsesBody = try decodedBody(from: responsesData)
        XCTAssertEqual((responsesBody["reasoning"] as? [String: String])?["effort"], "xhigh")

        let gpt56Capability = ModelThinkingCapability(
            options: [.none, .low, .medium, .high, .xhigh, .max],
            defaultOption: .medium,
            requestParameter: .reasoning
        )
        let gpt56Data = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "gpt-5.6-luna",
            messagePayload: messagePayload,
            developerPrompt: nil,
            endpoint: responsesEndpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: gpt56Capability,
            thinkingOption: .max
        )
        let gpt56Body = try decodedBody(from: gpt56Data)
        XCTAssertEqual((gpt56Body["reasoning"] as? [String: String])?["effort"], "max")

        let futureCapability = ModelThinkingCapability(
            options: [.high, .ultra],
            defaultOption: .high,
            requestParameter: .reasoning
        )
        let futureData = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "future-reasoner",
            messagePayload: messagePayload,
            developerPrompt: nil,
            endpoint: responsesEndpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: futureCapability,
            thinkingOption: .ultra
        )
        let futureBody = try decodedBody(from: futureData)
        XCTAssertEqual((futureBody["reasoning"] as? [String: String])?["effort"], "ultra")

        let openAIChatEndpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://api.example.com/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.example.com/v1/models"))
        )
        let openAIChatData = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "reasoner",
            messagePayload: messagePayload,
            developerPrompt: nil,
            endpoint: openAIChatEndpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: nil,
            thinkingOption: .xhigh
        )
        let openAIChatBody = try decodedBody(from: openAIChatData)
        XCTAssertEqual(openAIChatBody["reasoning_effort"] as? String, "xhigh")

        let lmStudioEndpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )
        let lmStudioData = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "local",
            messagePayload: messagePayload,
            developerPrompt: nil,
            endpoint: lmStudioEndpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: nil,
            thinkingOption: ModelThinkingOption.none
        )
        let lmStudioBody = try decodedBody(from: lmStudioData)
        XCTAssertEqual(lmStudioBody["reasoning"] as? String, "off")
    }

    func testDeepSeekOfficialChatUsesDocumentedThinkingFields() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://api.deepseek.com/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.deepseek.com/models"))
        )
        let capability = ModelThinkingCapability(
            options: [.off, .high, .max],
            defaultOption: .high,
            requestParameter: .reasoning
        )

        let enabledData = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "deepseek-v4-pro",
            messagePayload: [["role": "user", "content": "hello"]],
            developerPrompt: nil,
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: capability,
            thinkingOption: .max
        )
        let enabledBody = try decodedBody(from: enabledData)
        XCTAssertEqual((enabledBody["thinking"] as? [String: String])?["type"], "enabled")
        XCTAssertEqual(enabledBody["reasoning_effort"] as? String, "max")
        XCTAssertNil(enabledBody["reasoning"])

        let disabledData = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "deepseek-v4-pro",
            messagePayload: [["role": "user", "content": "hello"]],
            developerPrompt: nil,
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(),
            thinkingCapability: capability,
            thinkingOption: .off
        )
        let disabledBody = try decodedBody(from: disabledData)
        XCTAssertEqual((disabledBody["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertNil(disabledBody["reasoning_effort"])
        XCTAssertNil(disabledBody["reasoning"])
    }

}
