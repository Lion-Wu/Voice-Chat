import XCTest
@testable import Voice_Chat

final class ChatProviderStreamReducerTests: XCTestCase {
    func testOpenAIResponsesStreamItemReducerEmitsStructuredSegmentsWithoutThinkTags() throws {
        let reducer = OpenAIResponsesStreamItemReducer()
        var state = OpenAIResponsesStreamItemState()

        let reasoning = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.reasoning_text.delta","item_id":"r1","delta":"Need time."}"#),
            fallbackType: nil,
            state: &state
        )
        XCTAssertEqual(reasoning.actions, [
            .segment(.reasoning(id: "r1", text: "Need time."), marksPrimaryOutput: false)
        ])

        let toolArguments = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.function_call_arguments.delta","item_id":"fc1","delta":"{\"timezone\":\"Asia/Shanghai\""}"#),
            fallbackType: nil,
            state: &state
        )
        XCTAssertEqual(toolArguments.actions, [])

        let text = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.output_text.delta","item_id":"m1","delta":"现在是北京时间 12:34。"}"#),
            fallbackType: nil,
            state: &state
        )
        XCTAssertEqual(text.actions, [
            .segment(.text(id: "m1", text: "现在是北京时间 12:34。"), marksPrimaryOutput: true)
        ])
    }

    func testOpenAIResponsesReducerPreservesInterleavedReasoningAndTextItems() throws {
        let reducer = OpenAIResponsesStreamItemReducer()
        var state = OpenAIResponsesStreamItemState()
        let message = ChatMessage(content: "", isUser: false)
        let payloads = [
            #"{"type":"response.reasoning_text.delta","item_id":"r1","delta":"Plan the first tool."}"#,
            #"{"type":"response.output_text.delta","item_id":"m1","delta":"I will check the time first."}"#,
            #"{"type":"response.reasoning_text.delta","item_id":"r2","delta":"Use the returned time."}"#,
            #"{"type":"response.function_call_arguments.delta","item_id":"fc1","delta":"{}"}"#,
            #"{"type":"response.output_text.delta","item_id":"m2","delta":"The result is ready."}"#
        ]

        for payload in payloads {
            let reduction = reducer.reduce(
                jsonData: try jsonData(payload),
                fallbackType: nil,
                state: &state
            )
            for action in reduction.actions {
                guard case let .segment(segment, _) = action else { continue }
                message.appendAssistantSegment(segment)
            }
        }

        XCTAssertEqual(message.assistantSegments, [
            ChatAssistantSegment(kind: .reasoning, itemID: "r1", text: "Plan the first tool."),
            ChatAssistantSegment(kind: .text, itemID: "m1", text: "I will check the time first."),
            ChatAssistantSegment(kind: .reasoning, itemID: "r2", text: "Use the returned time."),
            ChatAssistantSegment(kind: .text, itemID: "m2", text: "The result is ready.")
        ])
        XCTAssertEqual(
            ChatAssistantRenderBlockBuilder.blocks(
                segments: message.assistantSegments,
                placements: []
            ).map(\.kind),
            [.reasoning, .text, .reasoning, .text]
        )
    }

    func testRenderTimelineKeepsReasoningAroundToolInOneBlock() {
        let segments = [
            ChatAssistantSegment(kind: .reasoning, itemID: "r1", text: "Need the current time."),
            ChatAssistantSegment(kind: .reasoning, itemID: "r2", text: " Now answer.")
        ]
        let toolPlacement = ChatToolActivityPlacement(
            activity: ChatToolActivity(
                id: "call-1",
                toolName: ChatToolID.systemGetTime.rawValue,
                title: "Getting Time",
                phase: .succeeded
            ),
            scope: .thinking,
            offset: segments[0].text.count,
            assistantSegmentAnchor: ChatAssistantSegmentAnchor(
                segmentIndex: 0,
                characterOffset: segments[0].text.count
            )
        )

        let blocks = ChatAssistantRenderBlockBuilder.blocks(
            segments: segments,
            placements: [toolPlacement]
        )

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .reasoning)
        XCTAssertEqual(blocks[0].text, "Need the current time. Now answer.")
        XCTAssertEqual(blocks[0].toolActivityPlacements.map(\.offset), [segments[0].text.count])
    }

    func testOpenAIResponsesReducerHandlesOfficialSummaryAndRefusalEvents() throws {
        let reducer = OpenAIResponsesStreamItemReducer()
        var state = OpenAIResponsesStreamItemState()

        let summary = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.reasoning_summary_text.delta","item_id":"r1","summary_index":0,"delta":"Checked policy."}"#),
            fallbackType: nil,
            state: &state
        )
        let refusal = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.refusal.done","item_id":"m1","content_index":0,"refusal":"I cannot help with that."}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertEqual(summary.actions, [
            .segment(.reasoning(id: "r1", text: "Checked policy."), marksPrimaryOutput: false)
        ])
        XCTAssertEqual(refusal.actions, [
            .segment(.text(id: "m1", text: "I cannot help with that."), marksPrimaryOutput: true)
        ])
    }

    func testOpenAIResponsesReducerRecoversMissingTextAfterReasoningDelta() throws {
        let reducer = OpenAIResponsesStreamItemReducer()
        var state = OpenAIResponsesStreamItemState()

        _ = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.reasoning_text.delta","item_id":"r1","content_index":0,"delta":"Need the tool."}"#),
            fallbackType: nil,
            state: &state
        )
        let completed = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.completed","response":{"id":"resp_1","status":"completed","output":[{"type":"reasoning","id":"r1","content":[{"type":"reasoning_text","text":"Need the tool."}]},{"type":"message","id":"m1","role":"assistant","content":[{"type":"output_text","text":"Final answer."}]}]}}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertFalse(completed.actions.contains(
            .segment(.reasoning(id: "r1", text: "Need the tool."), marksPrimaryOutput: false)
        ))
        XCTAssertTrue(completed.actions.contains(
            .segment(.text(id: "m1", text: "Final answer."), marksPrimaryOutput: true)
        ))
        XCTAssertTrue(completed.actions.contains(.finish))
    }

    func testOpenAIResponsesReducerDoesNotRepeatOpenRouterContentPartDeltasAtItemDone() throws {
        let reducer = OpenAIResponsesStreamItemReducer()
        var state = OpenAIResponsesStreamItemState()

        let delta = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.content_part.delta","output_index":0,"content_index":0,"delta":"Once"}"#),
            fallbackType: nil,
            state: &state
        )
        let done = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"msg_abc123","role":"assistant","status":"completed","content":[{"type":"output_text","text":"Once"}]}}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertEqual(delta.actions, [
            .segment(.text(id: "output_index:0", text: "Once"), marksPrimaryOutput: true)
        ])
        XCTAssertTrue(done.actions.isEmpty)
    }

    func testOpenAIResponsesReducerFinishesToolOnlyResponse() throws {
        let reducer = OpenAIResponsesStreamItemReducer()
        var state = OpenAIResponsesStreamItemState()

        let completed = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.completed","response":{"id":"resp_1","status":"completed","output":[{"type":"function_call","id":"fc_1","call_id":"call_1","name":"system_get_time","arguments":"{}"}]}}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertTrue(completed.actions.contains(.finish))
    }

    func testOpenAIResponsesReducerPreservesMetadataOnFailedResponse() throws {
        let reducer = OpenAIResponsesStreamItemReducer()
        var state = OpenAIResponsesStreamItemState()

        let failed = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.failed","response":{"id":"resp_failed","status":"failed","usage":{"output_tokens":12},"error":{"message":"rate limited"}}}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertTrue(failed.actions.contains(.metadata(ChatResponseMetadata(
            providerResponseID: "resp_failed",
            outputTokenCount: 12,
            finishReason: "failed"
        ))))
        XCTAssertTrue(failed.actions.contains(.fail("rate limited")))
    }

    func testOpenAIResponsesReducerMarksTypedRateLimitFailureRetryable() throws {
        let reducer = OpenAIResponsesStreamItemReducer()
        var state = OpenAIResponsesStreamItemState()

        let failed = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.failed","response":{"status":"failed","error":{"code":"rate_limit_exceeded","message":"try later"}}}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertTrue(failed.actions.contains(.retryableFailure("try later", statusCode: 429)))
    }

    func testOpenAIResponsesReducerMarksTopLevelServerErrorRetryable() throws {
        let reducer = OpenAIResponsesStreamItemReducer()
        var state = OpenAIResponsesStreamItemState()

        let failed = reducer.reduce(
            jsonData: try jsonData(#"{"type":"server_error","message":"try later"}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertTrue(failed.actions.contains(.retryableFailure("try later", statusCode: 500)))
    }

    func testOpenAIChatCompletionsReducerMarksTypedRateLimitFailureRetryable() throws {
        let reducer = OpenAICompatibleStreamEventReducer()
        var state = OpenAICompatibleStreamEventState()

        let failed = reducer.reduce(
            jsonData: try jsonData(#"{"error":{"type":"rate_limit_error","message":"try later"}}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertTrue(failed.actions.contains(.retryableFailure("try later", statusCode: 429)))
    }

    func testOpenAIChatCompletionsReducerMarksOpenRouterNumericMidStreamRateLimitRetryable() throws {
        let reducer = OpenAICompatibleStreamEventReducer()
        var state = OpenAICompatibleStreamEventState()

        let failed = reducer.reduce(
            jsonData: try jsonData(#"{"error":{"code":429,"message":"Rate limit exceeded","metadata":{"error_type":"rate_limit_exceeded"}},"choices":[{"index":0,"delta":{"content":""},"finish_reason":"error"}]}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertTrue(failed.actions.contains(.retryableFailure("Rate limit exceeded", statusCode: 429)))
    }

    func testOpenAIChatCompletionsReducerDoesNotRetryNumericAuthenticationError() throws {
        let reducer = OpenAICompatibleStreamEventReducer()
        var state = OpenAICompatibleStreamEventState()

        let failed = reducer.reduce(
            jsonData: try jsonData(#"{"error":{"code":401,"message":"Invalid API key"}}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertTrue(failed.actions.contains(.fail("Invalid API key")))
        XCTAssertFalse(failed.actions.contains { action in
            if case .retryableFailure = action { return true }
            return false
        })
    }

    func testAnthropicReducerMarksOverloadFailureRetryable() throws {
        let event = try JSONDecoder().decode(
            AnthropicStreamEvent.self,
            from: try jsonData(#"{"type":"error","error":{"type":"overloaded_error","message":"try later"}}"#)
        )
        var state = AnthropicStreamEventState()

        let actions = AnthropicStreamEventReducer().reduce(event, state: &state)

        XCTAssertTrue(actions.contains(.retryableFailure("try later", statusCode: 529)))
    }

    func testOpenAIResponsesReducerTreatsIncompleteAsFailureNotFinish() throws {
        let reducer = OpenAIResponsesStreamItemReducer()
        var state = OpenAIResponsesStreamItemState()

        let incomplete = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[{"type":"function_call","id":"fc_1","status":"incomplete","call_id":"call_1","name":"calendar_create_event","arguments":"{\"title\":\"Unsafe\"}"}]}}"#),
            fallbackType: nil,
            state: &state
        )

        let failures = incomplete.actions.compactMap { action -> (String, [AssistantStreamSegment])? in
            guard case let .incomplete(message, segments) = action else { return nil }
            return (message, segments)
        }
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures[0].0.contains("max_output_tokens"))
        XCTAssertTrue(failures[0].1.isEmpty)
        XCTAssertFalse(incomplete.actions.contains(.finish))
    }

    func testOpenAIResponsesIncompleteCarriesCompleteTerminalOutputSnapshot() throws {
        let reducer = OpenAIResponsesStreamItemReducer()
        var state = OpenAIResponsesStreamItemState()

        _ = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.output_text.delta","item_id":"m1","content_index":0,"delta":"Partial"}"#),
            fallbackType: nil,
            state: &state
        )
        let incomplete = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[{"type":"reasoning","id":"r1","content":[{"type":"reasoning_text","text":"Need more room."}]},{"type":"message","id":"m1","role":"assistant","content":[{"type":"output_text","text":"Partial answer"}]}]}}"#),
            fallbackType: nil,
            state: &state
        )

        let snapshots = incomplete.actions.compactMap { action -> [AssistantStreamSegment]? in
            guard case let .incomplete(_, segments) = action else { return nil }
            return segments
        }
        XCTAssertEqual(snapshots, [[
            .reasoning(id: "r1", text: "Need more room."),
            .text(id: "m1", text: "Partial answer")
        ]])
        XCTAssertFalse(incomplete.actions.contains { action in
            if case .segment = action { return true }
            return false
        })
    }

    func testOpenAICompatibleStreamEventReducerSeparatesReasoningVariantsFromText() throws {
        for eventType in ["response.reasoning.delta", "response.reasoning_text.delta"] {
            let reducer = OpenAICompatibleStreamEventReducer()
            var state = OpenAICompatibleStreamEventState()
            let reasoningData = try JSONSerialization.data(withJSONObject: [
                "type": eventType,
                "item_id": "r1",
                "delta": "thinking"
            ])

            let reasoning = reducer.reduce(
                jsonData: reasoningData,
                fallbackType: nil,
                state: &state
            )

            XCTAssertEqual(reasoning.actions, [
                .segment(.reasoning(id: "r1", text: "thinking"), marksPrimaryOutput: false)
            ], "Unexpected reasoning reduction for \(eventType)")
            XCTAssertTrue(state.sawAnyAssistantToken, eventType)
            XCTAssertFalse(state.sawAnyPrimaryAssistantToken, eventType)

            let text = reducer.reduce(
                jsonData: try jsonData(#"{"type":"response.output_text.delta","item_id":"o1","delta":"answer"}"#),
                fallbackType: nil,
                state: &state
            )

            XCTAssertEqual(text.actions, [
                .segment(.text(id: nil, text: "answer"), marksPrimaryOutput: true)
            ], "Unexpected text reduction after \(eventType)")
            XCTAssertTrue(state.sawAnyPrimaryAssistantToken, eventType)
        }
    }

    func testOpenAICompatibleStreamEventReducerDeduplicatesSSESequenceNumbers() throws {
        let reducer = OpenAICompatibleStreamEventReducer()
        var state = OpenAICompatibleStreamEventState()

        let first = reducer.reduce(
            jsonData: try jsonData(#"{"sequence_number":5,"type":"response.output_text.delta","delta":"hello"}"#),
            fallbackType: nil,
            state: &state
        )
        let duplicate = reducer.reduce(
            jsonData: try jsonData(#"{"sequence_number":5,"type":"response.output_text.delta","delta":"again"}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertEqual(first.actions, [
            .segment(.text(id: nil, text: "hello"), marksPrimaryOutput: true)
        ])
        XCTAssertEqual(duplicate, OpenAICompatibleStreamReduction(handled: true))
        XCTAssertEqual(state.lastProcessedSSESequenceNumber, 5)
    }

    func testOpenAICompatibleStreamEventReducerRecoversCompletedTextAndFailure() throws {
        let reducer = OpenAICompatibleStreamEventReducer()
        var completionState = OpenAICompatibleStreamEventState()

        let completion = reducer.reduce(
            jsonData: try jsonData("""
            {
              "type": "response.completed",
              "response": {
                "output": [
                  {
                    "type": "message",
                    "content": [
                      { "type": "output_text", "text": "final answer" }
                    ]
                  }
                ]
              }
            }
            """),
            fallbackType: nil,
            state: &completionState
        )

        XCTAssertEqual(completion.actions, [
            .segment(.text(id: nil, text: "final answer"), marksPrimaryOutput: true),
            .finish
        ])
        XCTAssertTrue(completionState.sawAnyPrimaryAssistantToken)

        var failureState = OpenAICompatibleStreamEventState()
        let failure = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.failed","error":{"message":"bad request"}}"#),
            fallbackType: nil,
            state: &failureState
        )

        XCTAssertEqual(failure.actions, [.fail("bad request")])
    }

    func testOpenAICompatibleStreamEventReducerNormalizesLegacyThinkTagsFromChatDeltas() throws {
        let reducer = OpenAICompatibleStreamEventReducer()
        var state = OpenAICompatibleStreamEventState()

        let first = reducer.reduce(
            jsonData: try jsonData(#"{"choices":[{"index":0,"delta":{"content":"<think>\nUser asks current date and time. Need system_get_time.\n</think>\n<think>\nNow answer.\n</think>\n今天是 2026 年 7 月 1 日。"}}]}"#),
            fallbackType: nil,
            state: &state
        )

        let reasoning = first.actions.compactMap { action -> String? in
            guard case let .segment(.reasoning(_, text), _) = action else { return nil }
            return text
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let body = first.actions.compactMap { action -> String? in
            guard case let .segment(.text(_, text), _) = action else { return nil }
            return text
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(body, "今天是 2026 年 7 月 1 日。")
        XCTAssertEqual(reasoning, "User asks current date and time. Need system_get_time.\nNow answer.")
        XCTAssertFalse(first.actions.contains { action in
            if case .delta = action { return true }
            return false
        })
        XCTAssertTrue(state.sawAnyPrimaryAssistantToken)
    }

    func testOpenAIChatCompletionsKeepsInterleavedReasoningAndTextAsSegments() throws {
        let reducer = OpenAICompatibleStreamEventReducer()
        var state = OpenAICompatibleStreamEventState()
        let payloads = [
            #"{"choices":[{"delta":{"reasoning_content":"reason one"}}]}"#,
            #"{"choices":[{"delta":{"content":"visible one"}}]}"#,
            #"{"choices":[{"delta":{"reasoning_content":"reason two"}}]}"#,
            #"{"choices":[{"delta":{"content":"visible two"}}]}"#
        ]
        let actions = try payloads.flatMap { payload in
            reducer.reduce(
                jsonData: try jsonData(payload),
                fallbackType: nil,
                state: &state
            ).actions
        }

        XCTAssertEqual(actions, [
            .segment(.reasoning(id: nil, text: "reason one"), marksPrimaryOutput: false),
            .segment(.text(id: nil, text: "visible one"), marksPrimaryOutput: true),
            .segment(.reasoning(id: nil, text: "reason two"), marksPrimaryOutput: false),
            .segment(.text(id: nil, text: "visible two"), marksPrimaryOutput: true)
        ])
        let message = ChatMessage(content: "", isUser: false)
        for action in actions {
            guard case let .segment(segment, _) = action else { continue }
            message.appendAssistantSegment(segment)
        }
        XCTAssertEqual(message.assistantReasoningText, "reason onereason two")
        XCTAssertEqual(message.assistantText, "visible onevisible two")
    }

    func testOpenAICompatibleStreamEventReducerNormalizesSplitLegacyThinkTagsFromChatDeltas() throws {
        let reducer = OpenAICompatibleStreamEventReducer()
        var state = OpenAICompatibleStreamEventState()

        let start = reducer.reduce(
            jsonData: try jsonData(#"{"choices":[{"index":0,"delta":{"content":"<thi"}}]}"#),
            fallbackType: nil,
            state: &state
        )
        let reasoning = reducer.reduce(
            jsonData: try jsonData(#"{"choices":[{"index":0,"delta":{"content":"nk>\nNeed time."}}]}"#),
            fallbackType: nil,
            state: &state
        )
        let answer = reducer.reduce(
            jsonData: try jsonData(#"{"choices":[{"index":0,"delta":{"content":"</think>\n现在是北京时间 12:34。"}}]}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertTrue(start.actions.isEmpty)
        XCTAssertEqual(reasoning.actions, [
            .segment(.reasoning(id: nil, text: "Need time."), marksPrimaryOutput: false)
        ])
        XCTAssertEqual(answer.actions, [
            .segment(.text(id: nil, text: "\n现在是北京时间 12:34。"), marksPrimaryOutput: true)
        ])
        XCTAssertEqual(state.legacyThinkTagBuffer, "")
        XCTAssertFalse(state.isInsideLegacyThinkTag)
    }

    func testOpenAICompatibleStreamEventReducerFlushesTrailingThinkMarkerPrefixAtEndOfStream() throws {
        let reducer = OpenAICompatibleStreamEventReducer()
        var state = OpenAICompatibleStreamEventState()

        let streamed = reducer.reduce(
            jsonData: try jsonData(#"{"choices":[{"index":0,"delta":{"content":"answer <"}}]}"#),
            fallbackType: nil,
            state: &state
        )
        let flushed = reducer.flushPendingOutput(state: &state)

        XCTAssertEqual(streamed.actions, [
            .segment(.text(id: nil, text: "answer "), marksPrimaryOutput: true)
        ])
        XCTAssertEqual(flushed, [
            .segment(.text(id: nil, text: "<"), marksPrimaryOutput: true)
        ])
        XCTAssertEqual(state.legacyThinkTagBuffer, "")
    }

    func testOpenAICompatibleStreamEventReducerKeepsThinkingOpenForLegacyTagsAfterToolContinuation() throws {
        let reducer = OpenAICompatibleStreamEventReducer()
        var state = OpenAICompatibleStreamEventState()

        let itemStart = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.output_item.added","item":{"type":"message","id":"m2","role":"assistant","content":[]}}"#),
            fallbackType: nil,
            state: &state
        )
        let legacyThinking = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.output_text.delta","item_id":"m2","delta":"<think>\nUse the tool result.\n</think>\nFinal answer."}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertEqual(itemStart.actions, [])
        XCTAssertEqual(legacyThinking.actions, [
            .segment(.reasoning(id: nil, text: "Use the tool result.\n"), marksPrimaryOutput: false),
            .segment(.text(id: nil, text: "\nFinal answer."), marksPrimaryOutput: true)
        ])
        XCTAssertTrue(state.sawAnyPrimaryAssistantToken)
    }

    func testOpenAICompatibleStreamEventReducerNormalizesRecoveredLegacyThinkText() throws {
        let reducer = OpenAICompatibleStreamEventReducer()
        var state = OpenAICompatibleStreamEventState()

        let actions = reducer.reduceRecoveredOutputText(
            "<think>\nProvide answer.\n</think>\n今天是 2026 年 7 月 1 日。",
            state: &state
        )

        XCTAssertEqual(actions, [
            .segment(.reasoning(id: nil, text: "Provide answer.\n"), marksPrimaryOutput: false),
            .segment(.text(id: nil, text: "\n今天是 2026 年 7 月 1 日。"), marksPrimaryOutput: true),
            .finish
        ])
        XCTAssertTrue(state.sawAnyPrimaryAssistantToken)
    }

    func testAnthropicStreamEventReducerWrapsThinkingAndFinishesWithMetadata() throws {
        let reducer = AnthropicStreamEventReducer()
        var state = AnthropicStreamEventState()

        let thinking = reducer.reduce(
            try decodedAnthropicEvent(#"{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"plan"}}"#),
            state: &state
        )
        XCTAssertEqual(thinking, [
            .delta("<think>\n", marksPrimaryOutput: false),
            .delta("plan", marksPrimaryOutput: false)
        ])

        let text = reducer.reduce(
            try decodedAnthropicEvent(#"{"type":"content_block_delta","delta":{"type":"text_delta","text":"answer"}}"#),
            state: &state
        )
        XCTAssertEqual(text, [
            .delta("\n</think>\n", marksPrimaryOutput: false),
            .delta("answer", marksPrimaryOutput: true)
        ])

        let stop = reducer.reduce(
            try decodedAnthropicEvent("""
            {
              "type": "message_stop",
              "message": {
                "id": "msg_123",
                "stop_reason": "end_turn",
                "usage": {
                  "output_tokens": 42,
                  "output_tokens_details": { "thinking_tokens": 7 }
                }
              }
            }
            """),
            state: &state
        )

        var expectedMetadata = ChatResponseMetadata.empty
        expectedMetadata.providerResponseID = "msg_123"
        expectedMetadata.outputTokenCount = 42
        expectedMetadata.reasoningOutputTokenCount = 7
        expectedMetadata.finishReason = "end_turn"
        XCTAssertEqual(stop, [.metadata(expectedMetadata), .finish])
    }

    func testLMStudioStreamEventReducerHandlesCompletionAndPendingErrors() throws {
        let reducer = LMStudioStreamEventReducer()
        var completionState = LMStudioStreamEventState()

        let completion = reducer.reduce(
            try decodedLMStudioEvent("""
            {
              "type": "response.completed",
              "response": {
                "response_id": "resp_1",
                "output_text": "final answer",
                "stats": {
                  "total_output_tokens": 6,
                  "reasoning_output_tokens": 2,
                  "tokens_per_second": 12.5,
                  "time_to_first_token_seconds": 0.25
                }
              }
            }
            """),
            fallbackType: nil,
            state: &completionState
        )

        var expectedMetadata = ChatResponseMetadata.empty
        expectedMetadata.providerResponseID = "resp_1"
        expectedMetadata.outputTokenCount = 6
        expectedMetadata.reasoningOutputTokenCount = 2
        expectedMetadata.tokensPerSecond = 12.5
        expectedMetadata.timeToFirstTokenSeconds = 0.25
        XCTAssertEqual(completion, [
            .metadata(expectedMetadata),
            .delta("final answer", marksPrimaryOutput: true),
            .finish
        ])

        var errorState = LMStudioStreamEventState()
        let error = reducer.reduce(
            try decodedLMStudioEvent(#"{"type":"chat.error","error":{"message":"backend failed"}}"#),
            fallbackType: nil,
            state: &errorState
        )
        XCTAssertEqual(error, [.fail("backend failed")])
    }

    func testLMStudioStreamEventReducerFailsImmediatelyOnNumericRateLimitErrorAfterText() throws {
        let reducer = LMStudioStreamEventReducer()
        var state = LMStudioStreamEventState()

        _ = reducer.reduce(
            try decodedLMStudioEvent(#"{"type":"message.delta","content":"partial"}"#),
            fallbackType: nil,
            state: &state
        )
        let errorEvent = try decodedLMStudioEvent(
            #"{"type":"error","error":{"message":"rate limited","code":429}}"#
        )
        let actions = reducer.reduce(errorEvent, fallbackType: nil, state: &state)

        XCTAssertEqual(errorEvent.error?.code, "429")
        XCTAssertEqual(actions, [.retryableFailure("rate limited", statusCode: 429)])
    }

    func testLMStudioStreamEventReducerHandlesOfficialToolEventsAndRecoversChatEndOutput() throws {
        let reducer = LMStudioStreamEventReducer()
        var state = LMStudioStreamEventState()

        let start = reducer.reduce(
            try decodedLMStudioEvent("""
            {
              "type": "tool_call.start",
              "tool": "model_search",
              "provider_info": {
                "type": "ephemeral_mcp",
                "server_label": "huggingface"
              }
            }
            """),
            fallbackType: nil,
            state: &state
        )
        let arguments = reducer.reduce(
            try decodedLMStudioEvent("""
            {
              "type": "tool_call.arguments",
              "tool": "model_search",
              "arguments": { "sort": "trendingScore", "limit": 1 }
            }
            """),
            fallbackType: nil,
            state: &state
        )
        let success = reducer.reduce(
            try decodedLMStudioEvent("""
            {
              "type": "tool_call.success",
              "tool": "model_search",
              "arguments": { "sort": "trendingScore", "limit": 1 },
              "output": "[{\\"type\\":\\"text\\",\\"text\\":\\"Showing first 1 models...\\"}]"
            }
            """),
            fallbackType: nil,
            state: &state
        )
        let end = reducer.reduce(
            try decodedLMStudioEvent("""
            {
              "type": "chat.end",
              "result": {
                "model_instance_id": "openai/gpt-oss-20b",
                "output": [
                  { "type": "reasoning", "content": "Need the tool result." },
                  {
                    "type": "tool_call",
                    "tool": "model_search",
                    "arguments": { "sort": "trendingScore", "limit": 1 },
                    "output": "[{\\"type\\":\\"text\\",\\"text\\":\\"Showing first 1 models...\\"}]"
                  },
                  { "type": "message", "content": "The model is ready." }
                ],
                "stats": {
                  "total_output_tokens": 12,
                  "reasoning_output_tokens": 4,
                  "tokens_per_second": 20.5,
                  "time_to_first_token_seconds": 0.5
                },
                "response_id": "resp_lmstudio_tool_1"
              }
            }
            """),
            fallbackType: nil,
            state: &state
        )

        XCTAssertTrue(start.isEmpty)
        XCTAssertTrue(arguments.isEmpty)
        XCTAssertTrue(success.isEmpty)

        var expectedMetadata = ChatResponseMetadata.empty
        expectedMetadata.providerResponseID = "resp_lmstudio_tool_1"
        expectedMetadata.outputTokenCount = 12
        expectedMetadata.reasoningOutputTokenCount = 4
        expectedMetadata.tokensPerSecond = 20.5
        expectedMetadata.timeToFirstTokenSeconds = 0.5
        XCTAssertEqual(end, [
            .metadata(expectedMetadata),
            .delta("<think>\n", marksPrimaryOutput: false),
            .delta("Need the tool result.", marksPrimaryOutput: false),
            .delta("\n</think>\n", marksPrimaryOutput: false),
            .delta("The model is ready.", marksPrimaryOutput: true),
            .finish
        ])
        XCTAssertTrue(state.sawAnyReasoningToken)
        XCTAssertTrue(state.sawAnyPrimaryAssistantToken)
    }

    func testLMStudioStreamEventReducerDoesNotDuplicateChatEndReasoningAfterDelta() throws {
        let reducer = LMStudioStreamEventReducer()
        var state = LMStudioStreamEventState()

        _ = reducer.reduce(
            try decodedLMStudioEvent(#"{"type":"reasoning.delta","content":"Streamed reasoning."}"#),
            fallbackType: nil,
            state: &state
        )
        let end = reducer.reduce(
            try decodedLMStudioEvent("""
            {
              "type": "chat.end",
              "result": {
                "output": [
                  { "type": "reasoning", "content": "Streamed reasoning." },
                  { "type": "message", "content": "Final answer." }
                ]
              }
            }
            """),
            fallbackType: nil,
            state: &state
        )

        XCTAssertEqual(end, [
            .delta("\n</think>\n", marksPrimaryOutput: false),
            .delta("Final answer.", marksPrimaryOutput: true),
            .finish
        ])
    }

    func testLMStudioStreamEventReducerKeepsReasoningTogetherAcrossToolEvents() throws {
        let reducer = LMStudioStreamEventReducer()
        var state = LMStudioStreamEventState()

        let firstReasoning = reducer.reduce(
            try decodedLMStudioEvent(#"{"type":"reasoning.delta","content":"Need the current time. "}"#),
            fallbackType: nil,
            state: &state
        )
        let reasoningEnd = reducer.reduce(
            try decodedLMStudioEvent(#"{"type":"reasoning.end"}"#),
            fallbackType: nil,
            state: &state
        )
        let tool = reducer.reduce(
            try decodedLMStudioEvent(#"{"type":"tool_call.success","tool":"system_get_time","arguments":{},"output":"12:00"}"#),
            fallbackType: nil,
            state: &state
        )
        let secondReasoning = reducer.reduce(
            try decodedLMStudioEvent(#"{"type":"reasoning.delta","content":"Now answer."}"#),
            fallbackType: nil,
            state: &state
        )
        let message = reducer.reduce(
            try decodedLMStudioEvent(#"{"type":"message.delta","content":"It is noon."}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertEqual(firstReasoning, [
            .delta("<think>\n", marksPrimaryOutput: false),
            .delta("Need the current time. ", marksPrimaryOutput: false)
        ])
        XCTAssertTrue(reasoningEnd.isEmpty)
        XCTAssertTrue(tool.isEmpty)
        XCTAssertEqual(secondReasoning, [
            .delta("Now answer.", marksPrimaryOutput: false)
        ])
        XCTAssertEqual(message, [
            .delta("\n</think>\n", marksPrimaryOutput: false),
            .delta("It is noon.", marksPrimaryOutput: true)
        ])
    }

    func testLMStudioStreamEventReducerDefersOfficialToolFailureUntilChatEnd() throws {
        let reducer = LMStudioStreamEventReducer()
        var state = LMStudioStreamEventState()

        let failure = reducer.reduce(
            try decodedLMStudioEvent("""
            {
              "type": "tool_call.failure",
              "reason": "Cannot find tool with name open_browser.",
              "metadata": {
                "type": "invalid_name",
                "tool_name": "open_browser"
              }
            }
            """),
            fallbackType: nil,
            state: &state
        )
        let end = reducer.reduce(
            try decodedLMStudioEvent(#"{"type":"chat.end","result":{"output":[]}}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertTrue(failure.isEmpty)
        XCTAssertEqual(end, [.fail("Cannot find tool with name open_browser.")])
    }
}
