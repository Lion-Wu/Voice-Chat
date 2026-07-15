import XCTest
@testable import Voice_Chat

final class ChatStreamCompletionRecoveryTests: XCTestCase {
    func testHTTPErrorBuildsStatusAndPreviewMessage() {
        let decision = ChatStreamCompletionRecovery.decide(
            isCancelled: false,
            httpStatusCode: 500,
            error: nil,
            errorResponseData: Data("  upstream exploded  ".utf8),
            successResponseData: Data(),
            sawAnyPrimaryAssistantToken: false,
            hasPendingToolCalls: false,
            activeStyle: .openAIChatCompletions,
            pendingLMStudioStreamErrorMessage: nil,
            bufferedResponseParser: StubBufferedResponseParser(),
            streamPayloadExtractor: StubStreamPayloadExtractor()
        )

        guard case let .serverError(statusCode, message) = decision.outcome else {
            return XCTFail("expected server error")
        }
        XCTAssertNil(decision.metadata)
        XCTAssertEqual(statusCode, 500)
        XCTAssertEqual(message, "HTTP 500: upstream exploded")
    }

    func testRecoveredBufferedTextKeepsOriginalTextAndMetadata() {
        let metadata = ChatResponseMetadata(
            providerResponseID: "response-id",
            outputTokenCount: 7,
            reasoningOutputTokenCount: nil,
            tokensPerSecond: nil,
            timeToFirstTokenSeconds: nil,
            finishReason: "stop"
        )
        let parser = StubBufferedResponseParser(
            result: ChatBufferedResponseParseResult(
                text: "  recovered text\n",
                errorMessage: nil,
                metadata: metadata
            )
        )

        let decision = ChatStreamCompletionRecovery.decide(
            isCancelled: false,
            httpStatusCode: nil,
            error: nil,
            errorResponseData: Data(),
            successResponseData: Data("{}".utf8),
            sawAnyPrimaryAssistantToken: false,
            hasPendingToolCalls: false,
            activeStyle: .openAIChatCompletions,
            pendingLMStudioStreamErrorMessage: nil,
            bufferedResponseParser: parser,
            streamPayloadExtractor: StubStreamPayloadExtractor()
        )

        XCTAssertEqual(decision.metadata, metadata)
        guard case let .recoveredText(text) = decision.outcome else {
            return XCTFail("expected recovered text")
        }
        XCTAssertEqual(text, "  recovered text\n")
    }

    func testSSEErrorIsUsedWhenBufferedResponseHasNoTextOrError() {
        let extractor = StubStreamPayloadExtractor(rawBodyError: "stream failed")

        let decision = ChatStreamCompletionRecovery.decide(
            isCancelled: false,
            httpStatusCode: nil,
            error: nil,
            errorResponseData: Data(),
            successResponseData: Data("data: {\"error\":{\"message\":\"stream failed\"}}\n".utf8),
            sawAnyPrimaryAssistantToken: false,
            hasPendingToolCalls: false,
            activeStyle: .openAIChatCompletions,
            pendingLMStudioStreamErrorMessage: nil,
            bufferedResponseParser: StubBufferedResponseParser(),
            streamPayloadExtractor: extractor
        )

        guard case let .serverError(statusCode, message) = decision.outcome else {
            return XCTFail("expected server error")
        }
        XCTAssertNil(statusCode)
        XCTAssertEqual(message, "stream failed")
    }

    func testPrimaryOutputCompletesWithoutParsingBufferedBody() {
        let parser = StubBufferedResponseParser { _, _ in
            XCTFail("buffered response should not be parsed after primary output")
            return ChatBufferedResponseParseResult(text: nil, errorMessage: nil, metadata: .empty)
        }

        let decision = ChatStreamCompletionRecovery.decide(
            isCancelled: false,
            httpStatusCode: nil,
            error: nil,
            errorResponseData: Data(),
            successResponseData: Data("ignored".utf8),
            sawAnyPrimaryAssistantToken: true,
            hasPendingToolCalls: false,
            activeStyle: .openAIChatCompletions,
            pendingLMStudioStreamErrorMessage: nil,
            bufferedResponseParser: parser,
            streamPayloadExtractor: StubStreamPayloadExtractor()
        )

        guard case .finish = decision.outcome else {
            return XCTFail("expected finish")
        }
        XCTAssertNil(decision.metadata)
    }

    func testCancellationIsIgnored() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)

        let decision = ChatStreamCompletionRecovery.decide(
            isCancelled: false,
            httpStatusCode: nil,
            error: error,
            errorResponseData: Data(),
            successResponseData: Data(),
            sawAnyPrimaryAssistantToken: false,
            hasPendingToolCalls: false,
            activeStyle: .openAIChatCompletions,
            pendingLMStudioStreamErrorMessage: nil,
            bufferedResponseParser: StubBufferedResponseParser(),
            streamPayloadExtractor: StubStreamPayloadExtractor()
        )

        guard case .ignore = decision.outcome else {
            return XCTFail("expected ignore")
        }
    }

    func testCleanCompletionWithPendingToolsContinuesBeforeEmptyResponseRecovery() {
        let parser = StubBufferedResponseParser { _, _ in
            XCTFail("tool-only completion should continue before buffered text recovery")
            return ChatBufferedResponseParseResult(text: nil, errorMessage: nil, metadata: .empty)
        }

        let decision = ChatStreamCompletionRecovery.decide(
            isCancelled: false,
            httpStatusCode: 200,
            error: nil,
            errorResponseData: Data(),
            successResponseData: Data(),
            sawAnyPrimaryAssistantToken: false,
            hasPendingToolCalls: true,
            activeStyle: .openAIChatCompletions,
            pendingLMStudioStreamErrorMessage: nil,
            bufferedResponseParser: parser,
            streamPayloadExtractor: StubStreamPayloadExtractor()
        )

        guard case .continueWithPendingTools = decision.outcome else {
            return XCTFail("expected pending tool continuation")
        }
    }
}

private struct StubBufferedResponseParser: ChatBufferedResponseParsing {
    var parseHandler: (Data, ChatRequestStyle) -> ChatBufferedResponseParseResult

    init(
        result: ChatBufferedResponseParseResult = ChatBufferedResponseParseResult(
            text: nil,
            errorMessage: nil,
            metadata: .empty
        )
    ) {
        self.parseHandler = { _, _ in result }
    }

    init(parseHandler: @escaping (Data, ChatRequestStyle) -> ChatBufferedResponseParseResult) {
        self.parseHandler = parseHandler
    }

    func parse(_ data: Data, style: ChatRequestStyle) -> ChatBufferedResponseParseResult {
        parseHandler(data, style)
    }
}

private struct StubStreamPayloadExtractor: ChatStreamPayloadExtracting {
    var rawBodyError: String?

    func sseSequenceNumber(from dictionary: [String: Any]) -> Int? { nil }
    func sseItemID(from dictionary: [String: Any]) -> String? { nil }
    func sseItemType(from dictionary: [String: Any]) -> String? { nil }
    func ssePartType(from dictionary: [String: Any]) -> String? { nil }
    func openAICompatibleStreamDeltaText(from dictionary: [String: Any]) -> String? { nil }
    func openAICompatibleStreamErrorMessage(from dictionary: [String: Any]) -> String? { nil }
    func sseStreamErrorMessage(from dictionary: [String: Any]) -> String? { nil }
    func sseStreamErrorMessage(from rawBodyData: Data) -> String? { rawBodyError }
}
