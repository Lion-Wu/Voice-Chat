import XCTest
@testable import Voice_Chat

final class ChatResponseParsingTests: XCTestCase {
    func testResponseMetadataExtractorReadsOpenAIUsageAndFinishReason() {
        let metadata = ChatResponseMetadataExtractor().extractResponseMetadata(
            from: [
                "id": "resp_123",
                "usage": [
                    "output_tokens": 42,
                    "output_tokens_details": ["reasoning_tokens": 7]
                ],
                "choices": [["finish_reason": "stop"]]
            ],
            style: .openAIChatCompletions
        )

        XCTAssertEqual(metadata.providerResponseID, "resp_123")
        XCTAssertEqual(metadata.outputTokenCount, 42)
        XCTAssertEqual(metadata.reasoningOutputTokenCount, 7)
        XCTAssertEqual(metadata.finishReason, "stop")
    }

    func testResponseMetadataExtractorReadsAnthropicMessageWrapper() {
        let metadata = ChatResponseMetadataExtractor().extractResponseMetadata(
            from: [
                "message": [
                    "id": "msg_123",
                    "usage": ["output_tokens": 12],
                    "stop_reason": "end_turn"
                ]
            ],
            style: .anthropicMessages
        )

        XCTAssertEqual(metadata.providerResponseID, "msg_123")
        XCTAssertEqual(metadata.outputTokenCount, 12)
        XCTAssertEqual(metadata.finishReason, "end_turn")
    }

    func testResponseMetadataExtractorReadsLMStudioNestedStats() {
        let metadata = ChatResponseMetadataExtractor().extractResponseMetadata(
            from: [
                "response": [
                    "response_id": "lm_123",
                    "stats": [
                        "total_output_tokens": 9,
                        "reasoning_output_tokens": 3,
                        "tokens_per_second": 4.5,
                        "time_to_first_token_seconds": 0.25
                    ]
                ]
            ],
            style: .lmStudioRESTV1
        )

        XCTAssertEqual(metadata.providerResponseID, "lm_123")
        XCTAssertEqual(metadata.outputTokenCount, 9)
        XCTAssertEqual(metadata.reasoningOutputTokenCount, 3)
        XCTAssertEqual(metadata.tokensPerSecond, 4.5)
        XCTAssertEqual(metadata.timeToFirstTokenSeconds, 0.25)
    }

    func testResponseMetadataExtractorNormalizesTokenCounts() {
        let extractor = ChatResponseMetadataExtractor()

        XCTAssertEqual(extractor.normalizedTokenCount(3.6), 4)
        XCTAssertEqual(extractor.normalizedTokenCount(3.2), 3)
        XCTAssertNil(extractor.normalizedTokenCount(-1))
        XCTAssertNil(extractor.normalizedTokenCount(.infinity))
    }

    func testStreamPayloadExtractorReadsSSEIdentifiersAndDeltaText() {
        let extractor = ChatStreamPayloadExtractor()

        XCTAssertEqual(extractor.sseSequenceNumber(from: ["sequence_number": " 42 "]), 42)
        XCTAssertEqual(extractor.sseItemID(from: ["item": ["id": " item-1 "]]), "item-1")
        XCTAssertEqual(extractor.sseItemType(from: ["item": ["type": " Output_Text "]]), "output_text")
        XCTAssertEqual(extractor.ssePartType(from: ["part": ["type": " Text "]]), "text")

        let choiceDelta: [String: Any] = [
            "choices": [
                ["delta": ["content": "hello"]]
            ]
        ]
        XCTAssertEqual(extractor.openAICompatibleStreamDeltaText(from: choiceDelta), "hello")

        let responseOutput: [String: Any] = [
            "response": [
                "output": [
                    [
                        "type": "message",
                        "content": [
                            ["type": "output_text", "text": "fallback"]
                        ]
                    ]
                ]
            ]
        ]
        XCTAssertEqual(extractor.openAICompatibleStreamDeltaText(from: responseOutput), "fallback")
    }

    func testStreamPayloadExtractorSkipsNonAssistantItemsAndReadsErrors() {
        let extractor = ChatStreamPayloadExtractor()

        XCTAssertNil(extractor.openAICompatibleStreamDeltaText(from: [
            "item": ["type": "reasoning", "text": "hidden"]
        ]))
        XCTAssertNil(extractor.openAICompatibleStreamDeltaText(from: [
            "item": ["type": "tool_call", "content": "tool payload"]
        ]))
        XCTAssertEqual(extractor.openAICompatibleStreamErrorMessage(from: [
            "error": ["message": " failed "]
        ]), "failed")

        let sseData = """
        event: error
        data: {"type":"server_error","message":" streamed failure "}
        """.data(using: .utf8)!
        XCTAssertEqual(extractor.sseStreamErrorMessage(from: sseData), "streamed failure")
    }

    func testSSEStreamParserKeepsPartialLinesAndEventTypes() {
        var parser = ChatSSEStreamParser(maxBufferedBytes: 256)

        XCTAssertEqual(
            parser.append("event: response.output_text.delta\ndata: {\"delta\":\"hel".data(using: .utf8)!),
            .frames([])
        )

        XCTAssertEqual(
            parser.append("lo\"}\n\n".data(using: .utf8)!),
            .frames([
                ChatSSEStreamFrame(payload: "{\"delta\":\"hello\"}", eventType: "response.output_text.delta")
            ])
        )

        parser.clearPendingEventType()
        XCTAssertEqual(
            parser.append("data: [DONE]\n".data(using: .utf8)!),
            .frames([
                ChatSSEStreamFrame(payload: "[DONE]", eventType: nil)
            ])
        )
    }

    func testSSEStreamParserReportsBufferLimit() {
        var parser = ChatSSEStreamParser(maxBufferedBytes: 8)

        XCTAssertEqual(
            parser.append("data: 123456789".data(using: .utf8)!),
            .exceededBufferLimit
        )
    }

    func testBufferedResponseParserRecoversOpenAITextAndMetadata() throws {
        let data = """
        {
          "id": "resp_buffered",
          "usage": {
            "output_tokens": 12,
            "output_tokens_details": { "reasoning_tokens": 2 }
          },
          "output": [
            {
              "type": "message",
              "content": [
                { "type": "output_text", "text": " buffered answer " }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let result = ChatBufferedResponseParser().parse(data, style: .openAIChatCompletions)

        XCTAssertEqual(result.text, "buffered answer")
        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.metadata.providerResponseID, "resp_buffered")
        XCTAssertEqual(result.metadata.outputTokenCount, 12)
        XCTAssertEqual(result.metadata.reasoningOutputTokenCount, 2)
    }

    func testBufferedResponseParserIgnoresSSEFrameBody() {
        let data = """
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"hello"}
        """.data(using: .utf8)!

        let result = ChatBufferedResponseParser().parse(data, style: .openAIChatCompletions)

        XCTAssertNil(result.text)
        XCTAssertNil(result.errorMessage)
        XCTAssertFalse(result.metadata.hasAnyValue)
    }
}
