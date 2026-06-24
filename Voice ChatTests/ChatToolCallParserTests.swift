import XCTest
@testable import Voice_Chat

final class ChatToolCallParserTests: XCTestCase {
    func testOpenAIChatCompletionsToolCallDeltaIsAccumulatedUntilFinishReason() {
        var accumulator = ChatToolCallAccumulator()

        let first = accumulator.absorbOpenAICompatiblePayload([
            "choices": [[
                "delta": [
                    "tool_calls": [[
                        "index": 0,
                        "id": "call_1",
                        "function": [
                            "name": ChatToolID.calendarListEvents.rawValue,
                            "arguments": "{\"start_date\":\"2026-06-22\""
                        ]
                    ]]
                ]
            ]]
        ], provider: .openAI)

        let second = accumulator.absorbOpenAICompatiblePayload([
            "choices": [[
                "delta": [
                    "tool_calls": [[
                        "index": 0,
                        "function": [
                            "arguments": "}"
                        ]
                    ]]
                ],
                "finish_reason": "tool_calls"
            ]]
        ], provider: .openAI)

        XCTAssertTrue(first.isEmpty)
        XCTAssertEqual(second, [
            ChatToolCallEnvelope(
                callID: "call_1",
                name: ChatToolID.calendarListEvents.rawValue,
                argumentsJSON: "{\"start_date\":\"2026-06-22\"}",
                provider: .openAI
            )
        ])
    }

    func testOpenAICompatibleToolCallDeltasWithReasoningAndDuplicateFinishAreAccumulated() {
        var accumulator = ChatToolCallAccumulator()

        XCTAssertTrue(accumulator.absorbOpenAICompatiblePayload([
            "choices": [[
                "delta": [
                    "reasoning": "We need to call the function."
                ]
            ]]
        ], provider: .openAICompatible).isEmpty)

        XCTAssertTrue(accumulator.absorbOpenAICompatiblePayload([
            "choices": [[
                "delta": [
                    "content": NSNull(),
                    "role": "assistant",
                    "tool_calls": [[
                        "index": 0,
                        "id": "call_compatible_1",
                        "type": "function",
                        "function": [
                            "name": ChatToolID.deviceContext.rawValue,
                            "arguments": ""
                        ]
                    ]]
                ]
            ]]
        ], provider: .openAICompatible).isEmpty)

        XCTAssertTrue(accumulator.absorbOpenAICompatiblePayload([
            "choices": [[
                "delta": [
                    "content": NSNull(),
                    "role": "assistant",
                    "tool_calls": [[
                        "index": 0,
                        "function": [
                            "arguments": "{}"
                        ]
                    ]]
                ]
            ]]
        ], provider: .openAICompatible).isEmpty)

        let completed = accumulator.absorbOpenAICompatiblePayload([
            "choices": [[
                "delta": [:],
                "finish_reason": "tool_calls"
            ]]
        ], provider: .openAICompatible)

        XCTAssertEqual(completed, [
            ChatToolCallEnvelope(
                callID: "call_compatible_1",
                name: ChatToolID.deviceContext.rawValue,
                argumentsJSON: "{}",
                provider: .openAICompatible
            )
        ])

        XCTAssertTrue(accumulator.absorbOpenAICompatiblePayload([
            "choices": [[
                "delta": [:],
                "finish_reason": "tool_calls"
            ]]
        ], provider: .openAICompatible).isEmpty)
    }

    func testOpenAIChatCompletionsToolCallWithoutStableIndexReusesSingleOpenChunk() {
        var accumulator = ChatToolCallAccumulator()

        XCTAssertTrue(accumulator.absorbOpenAICompatiblePayload([
            "choices": [[
                "delta": [
                    "tool_calls": [[
                        "id": "call_no_index",
                        "type": "function",
                        "function": [
                            "name": ChatToolID.deviceContext.rawValue,
                            "arguments": "{"
                        ]
                    ]]
                ]
            ]]
        ], provider: .openAI).isEmpty)

        let completed = accumulator.absorbOpenAICompatiblePayload([
            "choices": [[
                "delta": [
                    "tool_calls": [[
                        "function": [
                            "arguments": "}"
                        ]
                    ]]
                ],
                "finish_reason": "tool_calls"
            ]]
        ], provider: .openAI)

        XCTAssertEqual(completed.first?.callID, "call_no_index")
        XCTAssertEqual(completed.first?.name, ChatToolID.deviceContext.rawValue)
        XCTAssertEqual(completed.first?.argumentsJSON, "{}")
    }

    func testOpenAIChatCompletionsToolCallCanArriveOnMessageAndWithObjectArguments() {
        var accumulator = ChatToolCallAccumulator()

        let completed = accumulator.absorbOpenAICompatiblePayload([
            "choices": [[
                "message": [
                    "role": "assistant",
                    "tool_calls": [[
                        "id": "call_message",
                        "type": "function",
                        "function": [
                            "name": ChatToolID.calendarListEvents.rawValue,
                            "arguments": [
                                "start_date": "2026-06-24"
                            ]
                        ]
                    ]]
                ],
                "finish_reason": "tool_calls"
            ]]
        ], provider: .openAI)

        XCTAssertEqual(completed.first?.callID, "call_message")
        XCTAssertEqual(completed.first?.name, ChatToolID.calendarListEvents.rawValue)
        XCTAssertEqual(completed.first?.argumentsJSON, "{\"start_date\":\"2026-06-24\"}")
    }

    func testOpenAIChatCompletionsLegacyFunctionCallIsAccepted() {
        var accumulator = ChatToolCallAccumulator()

        XCTAssertTrue(accumulator.absorbOpenAICompatiblePayload([
            "choices": [[
                "delta": [
                    "function_call": [
                        "name": "device_",
                        "arguments": "{"
                    ]
                ]
            ]]
        ], provider: .openAI).isEmpty)

        let completed = accumulator.absorbOpenAICompatiblePayload([
            "choices": [[
                "delta": [
                    "function_call": [
                        "name": "get_context",
                        "arguments": "}"
                    ]
                ],
                "finish_reason": "function_call"
            ]]
        ], provider: .openAI)

        XCTAssertEqual(completed.first?.callID, "legacy-function-call")
        XCTAssertEqual(completed.first?.name, ChatToolID.deviceContext.rawValue)
        XCTAssertEqual(completed.first?.argumentsJSON, "{}")
    }

    func testResponsesFunctionCallArgumentsAreParsed() {
        var accumulator = ChatToolCallAccumulator()

        XCTAssertTrue(accumulator.absorbOpenAICompatiblePayload([
            "type": "response.output_item.added",
            "item": [
                "id": "item_1",
                "call_id": "call_1",
                "type": "function_call",
                "name": ChatToolID.deviceContext.rawValue
            ]
        ], provider: .openAI).isEmpty)

        XCTAssertTrue(accumulator.absorbOpenAICompatiblePayload([
            "type": "response.function_call_arguments.delta",
            "item_id": "item_1",
            "delta": "{"
        ], provider: .openAI).isEmpty)

        let completed = accumulator.absorbOpenAICompatiblePayload([
            "type": "response.function_call_arguments.done",
            "item_id": "item_1",
            "arguments": "{}"
        ], provider: .openAI)

        XCTAssertEqual(completed.first?.callID, "call_1")
        XCTAssertEqual(completed.first?.name, ChatToolID.deviceContext.rawValue)
        XCTAssertEqual(completed.first?.argumentsJSON, "{}")
    }

    func testResponsesFunctionCallCanDrainWhenProviderOmitsDoneEvents() {
        var accumulator = ChatToolCallAccumulator()

        XCTAssertTrue(accumulator.absorbOpenAICompatiblePayload([
            "type": "response.output_item.added",
            "output_index": 1,
            "item": [
                "id": "fc_tmp_1",
                "type": "function_call",
                "status": "in_progress",
                "call_id": "call_responses_1",
                "name": ChatToolID.deviceContext.rawValue,
                "arguments": ""
            ]
        ], provider: .openAICompatible).isEmpty)

        XCTAssertTrue(accumulator.absorbOpenAICompatiblePayload([
            "type": "response.function_call_arguments.delta",
            "output_index": 1,
            "item_id": "fc_tmp_1",
            "delta": "{}"
        ], provider: .openAICompatible).isEmpty)

        XCTAssertEqual(accumulator.drain(provider: .openAICompatible), [
            ChatToolCallEnvelope(
                callID: "call_responses_1",
                name: ChatToolID.deviceContext.rawValue,
                argumentsJSON: "{}",
                provider: .openAICompatible
            )
        ])
    }

    func testResponsesCompletedOutputFunctionCallIsParsed() {
        var accumulator = ChatToolCallAccumulator()

        let completed = accumulator.absorbOpenAICompatiblePayload([
            "type": "response.completed",
            "response": [
                "id": "resp_1",
                "output": [[
                    "id": "fc_1",
                    "type": "function_call",
                    "call_id": "call_completed_1",
                    "name": ChatToolID.deviceContext.rawValue,
                    "arguments": "{}"
                ]]
            ]
        ], provider: .openAI)

        XCTAssertEqual(completed, [
            ChatToolCallEnvelope(
                callID: "call_completed_1",
                name: ChatToolID.deviceContext.rawValue,
                argumentsJSON: "{}",
                provider: .openAI
            )
        ])
    }

    func testAnthropicToolUseArgumentsAreAccumulatedByContentBlockIndex() throws {
        var accumulator = ChatToolCallAccumulator()

        let start = try decodedAnthropicEvent("""
        {
          "type": "content_block_start",
          "index": 0,
          "content_block": {
            "type": "tool_use",
            "id": "toolu_1",
            "name": "calendar_list_events",
            "input": {}
          }
        }
        """)
        let delta = try decodedAnthropicEvent("""
        {
          "type": "content_block_delta",
          "index": 0,
          "delta": {
            "type": "input_json_delta",
            "partial_json": "{\\"start_date\\":\\"2026-06-22\\"}"
          }
        }
        """)
        let stop = try decodedAnthropicEvent("""
        {
          "type": "content_block_stop",
          "index": 0
        }
        """)

        XCTAssertTrue(accumulator.absorbAnthropicEvent(start, provider: .anthropic).isEmpty)
        XCTAssertTrue(accumulator.absorbAnthropicEvent(delta, provider: .anthropic).isEmpty)
        let completed = accumulator.absorbAnthropicEvent(stop, provider: .anthropic)

        XCTAssertEqual(completed, [
            ChatToolCallEnvelope(
                callID: "toolu_1",
                name: ChatToolID.calendarListEvents.rawValue,
                argumentsJSON: "{\"start_date\":\"2026-06-22\"}",
                provider: .anthropic
            )
        ])
    }

    func testLMStudioPromptToolCallIsParsedFromTaggedMessage() {
        let calls = LMStudioPromptToolProtocol.parseToolCalls(
            from: "<tool_call>{\"name\":\"device_get_context\",\"arguments\":{}}</tool_call>",
            provider: .lmStudio
        )

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, ChatToolID.deviceContext.rawValue)
        XCTAssertEqual(calls.first?.argumentsJSON, "{}")
        XCTAssertEqual(calls.first?.provider, .lmStudio)
    }

    func testLMStudioPromptToolCallIsParsedFromInlineOpenTagJSON() {
        let calls = LMStudioPromptToolProtocol.parseToolCalls(
            from: "<tool_call {\"name\":\"device_get_context\",\"arguments\":{}}></tool_call>",
            provider: .lmStudio
        )

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, ChatToolID.deviceContext.rawValue)
        XCTAssertEqual(calls.first?.argumentsJSON, "{}")
    }

    func testLMStudioPromptToolCallIsParsedFromPipeDelimitedJSON() {
        let calls = LMStudioPromptToolProtocol.parseToolCalls(
            from: "<|tool_call>{\"name\":\"device_get_context\",\"arguments\":{}}<tool_call|>",
            provider: .lmStudio
        )

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, ChatToolID.deviceContext.rawValue)
        XCTAssertEqual(calls.first?.argumentsJSON, "{}")
    }

    func testLMStudioPromptToolCallIsParsedFromPipeDelimitedVariants() {
        let variants = [
            "<|tool_call>{\"name\":\"device_get_context\",\"arguments\":{}}",
            "<|tool_call|>{\"name\":\"device_get_context\",\"arguments\":{}}<|/tool_call|>",
            "<|tool_call {\"name\":\"device_get_context\",\"arguments\":{}}",
            "<|tool_call{\"name\":\"device_get_context\",\"arguments\":{}}",
            "<|tool_call>{\"name\":\"device_get_context\",\"arguments\":{\"note\":\"brace } inside string\"}}<|/tool_call>"
        ]

        for variant in variants {
            let calls = LMStudioPromptToolProtocol.parseToolCalls(
                from: variant,
                provider: .lmStudio
            )

            XCTAssertEqual(calls.count, 1, variant)
            XCTAssertEqual(calls.first?.name, ChatToolID.deviceContext.rawValue, variant)
        }
    }

    func testLMStudioPromptToolCallDoesNotTreatLongerPipePrefixAsToolCall() {
        XCTAssertFalse(LMStudioPromptToolProtocol.isDefiniteToolCallStart("<|tool_callback"))
        XCTAssertFalse(LMStudioPromptToolProtocol.canStillBecomeToolCallStart("<|tool_callback"))
        let calls = LMStudioPromptToolProtocol.parseToolCalls(
            from: "<|tool_callback>{\"name\":\"device_get_context\",\"arguments\":{}}",
            provider: .lmStudio
        )

        XCTAssertTrue(calls.isEmpty)
    }

    func testLMStudioPromptToolCallDoesNotParseCallPrefixShorthand() {
        let calls = LMStudioPromptToolProtocol.parseToolCalls(
            from: "call:device_get_context{}",
            provider: .lmStudio
        )

        XCTAssertTrue(calls.isEmpty)
    }

    func testLMStudioPromptToolCallTextEscapesNameWithoutJSONSerializationCrash() {
        let call = ChatToolCallEnvelope(
            callID: "call_escaped",
            name: "device.get_\"context\"",
            argumentsJSON: "{}",
            provider: .lmStudio
        )

        let text = LMStudioPromptToolProtocol.toolCallText(for: call)

        XCTAssertTrue(text.contains(#"device.get_\"context\""#))
    }

    @MainActor
    func testLMStudioPromptToolGateStreamsReasoningAndSuppressesToolCallText() async throws {
        let service = try lmStudioPromptToolService()

        var deltas: [String] = []
        let reasoningExpectation = expectation(description: "reasoning deltas streamed")
        reasoningExpectation.expectedFulfillmentCount = 2
        service.onDelta = { piece in
            deltas.append(piece)
            reasoningExpectation.fulfill()
        }

        service.handleLMStudioPromptToolDelta("<think>\n", marksPrimaryOutput: false)
        service.handleLMStudioPromptToolDelta("Need device context.", marksPrimaryOutput: false)
        for piece in ["<", "tool", "_", "call", ">", "{\"name\":\"device_get_context\",\"arguments\":{}}</tool_call>"] {
            service.handleLMStudioPromptToolDelta(piece, marksPrimaryOutput: true)
        }

        await fulfillment(of: [reasoningExpectation], timeout: 1.0)
        XCTAssertEqual(deltas, ["<think>\n", "Need device context."])
        XCTAssertEqual(service.lmStudioPromptToolStreamDecision, .toolCall)
        XCTAssertEqual(
            LMStudioPromptToolProtocol.parseToolCalls(
                from: service.lmStudioPromptToolPrimaryText,
                provider: .lmStudio
            ).first?.name,
            ChatToolID.deviceContext.rawValue
        )
    }

    @MainActor
    func testLMStudioPromptToolGateSuppressesPipeDelimitedJSONToolCallText() async throws {
        let service = try lmStudioPromptToolService()

        var deltas: [String] = []
        service.onDelta = { deltas.append($0) }

        for piece in ["<", "|", "tool", "_call", ">", "{\"name\":\"device_get_context\",", "\"arguments\":{}}", "<tool_call|>"] {
            service.handleLMStudioPromptToolDelta(piece, marksPrimaryOutput: true)
        }

        XCTAssertTrue(deltas.isEmpty)
        XCTAssertEqual(service.lmStudioPromptToolStreamDecision, .toolCall)
        XCTAssertEqual(
            LMStudioPromptToolProtocol.parseToolCalls(
                from: service.lmStudioPromptToolPrimaryText,
                provider: .lmStudio
            ).first?.name,
            ChatToolID.deviceContext.rawValue
        )
    }

    @MainActor
    func testLMStudioPromptToolGateSuppressesPipeDelimitedVariantWithoutClosingMarker() async throws {
        let service = try lmStudioPromptToolService()

        var deltas: [String] = []
        service.onDelta = { deltas.append($0) }

        for piece in ["<", "|", "tool", "_call", "{\"name\":\"device_get_context\",", "\"arguments\":{}}"] {
            service.handleLMStudioPromptToolDelta(piece, marksPrimaryOutput: true)
        }

        XCTAssertTrue(deltas.isEmpty)
        XCTAssertEqual(service.lmStudioPromptToolStreamDecision, .toolCall)
        XCTAssertEqual(
            LMStudioPromptToolProtocol.parseToolCalls(
                from: service.lmStudioPromptToolPrimaryText,
                provider: .lmStudio
            ).first?.name,
            ChatToolID.deviceContext.rawValue
        )
    }

    @MainActor
    func testLMStudioPromptToolGateSuppressesInlineOpenTagToolCallText() async throws {
        let service = try lmStudioPromptToolService()

        var deltas: [String] = []
        service.onDelta = { deltas.append($0) }

        for piece in ["<", "tool", "_call ", "{\"name\":\"device_get_context\",", "\"arguments\":{}}", "></tool_call>"] {
            service.handleLMStudioPromptToolDelta(piece, marksPrimaryOutput: true)
        }

        XCTAssertTrue(deltas.isEmpty)
        XCTAssertEqual(service.lmStudioPromptToolStreamDecision, .toolCall)
        XCTAssertEqual(
            LMStudioPromptToolProtocol.parseToolCalls(
                from: service.lmStudioPromptToolPrimaryText,
                provider: .lmStudio
            ).first?.name,
            ChatToolID.deviceContext.rawValue
        )
    }

    @MainActor
    func testLMStudioPromptToolGateKeepsThinkingOpenAcrossToolContinuation() async throws {
        let service = try lmStudioPromptToolService()

        var deltas: [String] = []
        let expectation = expectation(description: "thinking stream remains continuous around tool call")
        expectation.expectedFulfillmentCount = 5
        service.onDelta = { piece in
            deltas.append(piece)
            expectation.fulfill()
        }

        service.handleLMStudioPromptToolDelta("<think>\n", marksPrimaryOutput: false)
        service.handleLMStudioPromptToolDelta("First reasoning.", marksPrimaryOutput: false)
        service.handleLMStudioPromptToolDelta("\n</think>\n", marksPrimaryOutput: false)
        for piece in ["<", "tool", "_", "call", ">", "{\"name\":\"device_get_context\",\"arguments\":{}}</tool_call>"] {
            service.handleLMStudioPromptToolDelta(piece, marksPrimaryOutput: true)
        }

        XCTAssertTrue(service.lmStudioPromptToolKeepsThinkOpen)
        service.resetLMStudioPromptToolGate(preservingOpenThinking: true)

        service.handleLMStudioPromptToolDelta("<think>\n", marksPrimaryOutput: false)
        service.handleLMStudioPromptToolDelta("Second reasoning.", marksPrimaryOutput: false)
        service.handleLMStudioPromptToolDelta("\n</think>\n", marksPrimaryOutput: false)
        service.handleLMStudioPromptToolDelta("Final answer.", marksPrimaryOutput: true)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(deltas, [
            "<think>\n",
            "First reasoning.",
            "Second reasoning.",
            "\n</think>\n",
            "Final answer."
        ])
        XCTAssertFalse(service.lmStudioPromptToolKeepsThinkOpen)
    }

    @MainActor
    func testLMStudioPromptToolGateClosesThinkingWhenContinuationStartsWithAnswer() async throws {
        let service = try lmStudioPromptToolService()

        var deltas: [String] = []
        let expectation = expectation(description: "answer is emitted outside thinking")
        expectation.expectedFulfillmentCount = 4
        service.onDelta = { piece in
            deltas.append(piece)
            expectation.fulfill()
        }

        service.handleLMStudioPromptToolDelta("<think>\n", marksPrimaryOutput: false)
        service.handleLMStudioPromptToolDelta("Need device context.", marksPrimaryOutput: false)
        service.handleLMStudioPromptToolDelta("\n</think>\n", marksPrimaryOutput: false)
        for piece in ["<", "tool", "_", "call", ">", "{\"name\":\"device_get_context\",\"arguments\":{}}</tool_call>"] {
            service.handleLMStudioPromptToolDelta(piece, marksPrimaryOutput: true)
        }

        XCTAssertTrue(service.lmStudioPromptToolKeepsThinkOpen)
        service.resetLMStudioPromptToolGate(preservingOpenThinking: true)
        service.handleLMStudioPromptToolDelta("Final answer.", marksPrimaryOutput: true)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(deltas, [
            "<think>\n",
            "Need device context.",
            "\n</think>\n",
            "Final answer."
        ])
        XCTAssertFalse(service.lmStudioPromptToolKeepsThinkOpen)
    }

    func testResponsesFollowUpPayloadIncludesFunctionCallAndOutput() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/v1/models"))
        )
        let call = ChatToolCallEnvelope(
            callID: "call_1",
            name: ChatToolID.deviceContext.rawValue,
            argumentsJSON: "{\"include\":\"basic\"}",
            provider: .lmStudio
        )
        let result = ChatToolResultEnvelope(
            callID: "call_1",
            name: ChatToolID.deviceContext.rawValue,
            status: .success,
            payload: ["platform": .string("macOS")],
            summary: "Device context was read."
        )

        let payload = ChatToolResultMessageEncoder.followUpPayload(
            for: endpoint,
            originalPayload: [
                ["type": "reasoning", "id": "rs_1", "summary": []]
            ],
            calls: [call],
            results: [result]
        )

        XCTAssertEqual(payload.count, 3)
        XCTAssertEqual(payload[0]["type"] as? String, "reasoning")
        XCTAssertEqual(payload[1]["type"] as? String, "function_call")
        XCTAssertEqual(payload[1]["call_id"] as? String, "call_1")
        XCTAssertEqual(payload[1]["arguments"] as? String, "{\"include\":\"basic\"}")
        XCTAssertEqual(payload.last?["type"] as? String, "function_call_output")
        XCTAssertEqual(payload.last?["call_id"] as? String, "call_1")
    }

    func testResponsesToolContinuationDropsPreviousResponseIDWhenReplayingPayload() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAICompatible,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/models"))
        )

        XCTAssertNil(ChatToolResultMessageEncoder.previousResponseIDForToolContinuation(
            "resp_stateful",
            endpoint: endpoint
        ))
    }

    func testNonResponsesToolContinuationKeepsPreviousResponseID() throws {
        let chatCompletionsEndpoint = ChatAPIEndpointCandidate(
            provider: .openAICompatible,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/models"))
        )
        let lmStudioEndpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )

        XCTAssertEqual(
            ChatToolResultMessageEncoder.previousResponseIDForToolContinuation(
                "resp_stateful",
                endpoint: chatCompletionsEndpoint
            ),
            "resp_stateful"
        )
        XCTAssertEqual(
            ChatToolResultMessageEncoder.previousResponseIDForToolContinuation(
                "resp_stateful",
                endpoint: lmStudioEndpoint
            ),
            "resp_stateful"
        )
    }

    func testOpenAIChatFollowUpPayloadAppendsToAccumulatedToolTranscript() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.openai.com/v1/models"))
        )
        let previousPayload: [[String: Any]] = [
            ["role": "user", "content": "Use tools twice."],
            [
                "role": "assistant",
                "content": NSNull(),
                "tool_calls": [[
                    "id": "call_1",
                    "type": "function",
                    "function": [
                        "name": ChatToolID.deviceContext.rawValue,
                        "arguments": "{}"
                    ]
                ]]
            ],
            [
                "role": "tool",
                "tool_call_id": "call_1",
                "content": "{\"status\":\"success\"}"
            ]
        ]
        let secondCall = ChatToolCallEnvelope(
            callID: "call_2",
            name: ChatToolID.calendarListEvents.rawValue,
            argumentsJSON: "{\"start_date\":\"2026-06-22\"}",
            provider: .openAI
        )
        let secondResult = ChatToolResultEnvelope(
            callID: "call_2",
            name: ChatToolID.calendarListEvents.rawValue,
            status: .success,
            payload: ["count": .number(0)],
            summary: "Found 0 calendar event(s)."
        )

        let payload = ChatToolResultMessageEncoder.followUpPayload(
            for: endpoint,
            originalPayload: previousPayload,
            calls: [secondCall],
            results: [secondResult]
        )

        XCTAssertEqual(payload.count, 5)
        XCTAssertEqual(payload[2]["tool_call_id"] as? String, "call_1")
        XCTAssertEqual(payload[4]["tool_call_id"] as? String, "call_2")
    }

    func testAnthropicFollowUpPayloadAppendsToAccumulatedToolTranscript() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .anthropic,
            style: .anthropicMessages,
            chatURL: try XCTUnwrap(URL(string: "https://api.anthropic.com/v1/messages")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.anthropic.com/v1/models"))
        )
        let previousPayload: [[String: Any]] = [
            ["role": "user", "content": "Use tools twice."],
            [
                "role": "assistant",
                "content": [[
                    "type": "tool_use",
                    "id": "toolu_1",
                    "name": ChatToolID.deviceContext.rawValue,
                    "input": [:]
                ]]
            ],
            [
                "role": "user",
                "content": [[
                    "type": "tool_result",
                    "tool_use_id": "toolu_1",
                    "content": "{\"status\":\"success\"}",
                    "is_error": false
                ]]
            ]
        ]
        let secondCall = ChatToolCallEnvelope(
            callID: "toolu_2",
            name: ChatToolID.calendarListEvents.rawValue,
            argumentsJSON: "{\"start_date\":\"2026-06-22\"}",
            provider: .anthropic
        )
        let secondResult = ChatToolResultEnvelope(
            callID: "toolu_2",
            name: ChatToolID.calendarListEvents.rawValue,
            status: .success,
            payload: ["count": .number(0)],
            summary: "Found 0 calendar event(s)."
        )

        let payload = ChatToolResultMessageEncoder.followUpPayload(
            for: endpoint,
            originalPayload: previousPayload,
            calls: [secondCall],
            results: [secondResult]
        )

        XCTAssertEqual(payload.count, 5)
        let previousToolResult = try XCTUnwrap((payload[2]["content"] as? [[String: Any]])?.first)
        let nextToolResult = try XCTUnwrap((payload[4]["content"] as? [[String: Any]])?.first)
        XCTAssertEqual(previousToolResult["tool_use_id"] as? String, "toolu_1")
        XCTAssertEqual(nextToolResult["tool_use_id"] as? String, "toolu_2")
    }

    func testLMStudioPromptFollowUpPayloadIncludesToolResultTag() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )
        let call = ChatToolCallEnvelope(
            callID: "call_1",
            name: ChatToolID.deviceContext.rawValue,
            argumentsJSON: "{}",
            provider: .lmStudio
        )
        let result = ChatToolResultEnvelope(
            callID: "call_1",
            name: ChatToolID.deviceContext.rawValue,
            status: .success,
            payload: ["platform": .string("macOS")],
            summary: "Device context was read."
        )

        let payload = ChatToolResultMessageEncoder.followUpPayload(
            for: endpoint,
            originalPayload: [["role": "user", "content": "What device is this?"]],
            calls: [call],
            results: [result]
        )

        XCTAssertEqual(payload.count, 3)
        XCTAssertTrue((payload[1]["content"] as? String)?.contains("<tool_call>") == true)
        XCTAssertTrue((payload[2]["content"] as? String)?.contains("<tool_result") == true)
        XCTAssertTrue((payload[2]["content"] as? String)?.contains("Device context was read.") == true)
    }

    @MainActor
    private func lmStudioPromptToolService() throws -> ChatService {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )
        let service = ChatService(configurationProvider: ChatServiceConfiguration(
            apiBaseURL: "http://localhost:1234",
            modelIdentifier: "local",
            apiKey: "",
            providerHint: .lmStudio,
            requestStyleHint: .lmStudioRESTV1,
            toolUseSettings: ToolUseSettings(
                isEnabled: true,
                calendarEnabled: false,
                remindersEnabled: false,
                locationEnabled: false,
                motionEnabled: false,
                deviceContextEnabled: true
            )
        ))
        service.activeEndpointCandidate = endpoint
        return service
    }
}

final class ChatToolInlineSegmentBuilderTests: XCTestCase {
    func testTextSegmentIDsStayStableWhenTextAfterToolPlacementStreamsIn() {
        let placement = ChatToolActivityPlacement(
            activity: ChatToolActivity(
                id: "tool-1",
                toolName: ChatToolID.deviceContext.rawValue,
                title: "Checking Device",
                phase: .running
            ),
            scope: .body,
            offset: 5
        )

        let first = ChatToolInlineSegmentBuilder.segments(
            text: "Hello world",
            placements: [placement]
        )
        let second = ChatToolInlineSegmentBuilder.segments(
            text: "Hello world with more streamed markdown",
            placements: [placement]
        )

        XCTAssertEqual(first.map(\.id), [
            "text-0-start-tool-1",
            "tool-tool-1",
            "text-5-tool-1-end"
        ])
        XCTAssertEqual(second.map(\.id), [
            "text-0-start-tool-1",
            "tool-tool-1",
            "text-5-tool-1-end"
        ])
    }
}

final class ChatMessageToolTracePersistenceTests: XCTestCase {
    func testToolActivityPlacementsRoundTripThroughMessageStorage() {
        let placement = ChatToolActivityPlacement(
            activity: ChatToolActivity(
                id: "call-1",
                toolName: ChatToolID.deviceContext.rawValue,
                title: "Checking Device",
                phase: .succeeded,
                summary: "Device context was read."
            ),
            scope: .body,
            offset: 12
        )
        let message = ChatMessage(
            content: "Device info",
            isUser: false,
            toolActivityPlacements: [placement]
        )

        XCTAssertEqual(message.toolActivityPlacements, [placement])

        let reloaded = ChatMessage(content: "Reloaded", isUser: false)
        reloaded.toolActivityPlacementsData = message.toolActivityPlacementsData

        XCTAssertEqual(reloaded.toolActivityPlacements, [placement])
    }
}
