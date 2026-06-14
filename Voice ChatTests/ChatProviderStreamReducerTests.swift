import XCTest
@testable import Voice_Chat

final class ChatProviderStreamReducerTests: XCTestCase {
    func testOpenAICompatibleStreamEventReducerWrapsReasoningBeforeText() throws {
        let reducer = OpenAICompatibleStreamEventReducer()
        var state = OpenAICompatibleStreamEventState()

        let reasoning = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.reasoning_text.delta","item_id":"r1","delta":"thinking"}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertEqual(reasoning.actions, [
            .delta("<think>\n", marksPrimaryOutput: false),
            .delta("thinking", marksPrimaryOutput: false)
        ])
        XCTAssertTrue(state.newFormatActive)
        XCTAssertTrue(state.sentThinkOpen)
        XCTAssertFalse(state.sentThinkClose)
        XCTAssertFalse(state.sawAnyPrimaryAssistantToken)

        let text = reducer.reduce(
            jsonData: try jsonData(#"{"type":"response.output_text.delta","item_id":"o1","delta":"answer"}"#),
            fallbackType: nil,
            state: &state
        )

        XCTAssertEqual(text.actions, [
            .delta("\n</think>\n", marksPrimaryOutput: false),
            .delta("answer", marksPrimaryOutput: true)
        ])
        XCTAssertTrue(state.sentThinkClose)
        XCTAssertTrue(state.sawAnyPrimaryAssistantToken)
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
            .delta("hello", marksPrimaryOutput: true)
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
            .delta("final answer", marksPrimaryOutput: true),
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
                "usage": { "output_tokens": 42 }
              }
            }
            """),
            state: &state
        )

        var expectedMetadata = ChatResponseMetadata.empty
        expectedMetadata.providerResponseID = "msg_123"
        expectedMetadata.outputTokenCount = 42
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
        XCTAssertTrue(error.isEmpty)

        let end = reducer.reduce(
            try decodedLMStudioEvent(#"{"type":"chat.end"}"#),
            fallbackType: nil,
            state: &errorState
        )
        XCTAssertEqual(end, [.fail("backend failed")])
    }
}
