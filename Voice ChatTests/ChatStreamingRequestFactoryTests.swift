import XCTest
@testable import Voice_Chat

final class ChatStreamingRequestFactoryTests: XCTestCase {
    func testStreamingRequestFactoryBuildsOpenAICompatibleHeaders() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://example.com/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "https://example.com/v1/models"))
        )
        let body = try XCTUnwrap(#"{"stream":true}"#.data(using: .utf8))

        let request = ChatStreamingRequestFactory().makeStreamingRequest(
            endpoint: endpoint,
            requestBodyData: body,
            apiKey: "sk-test"
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 3900)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-OpenRouter-Cache"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-OpenRouter-Cache-TTL"))
        XCTAssertEqual(request.httpBody, body)
    }

    func testStreamingRequestFactoryBuildsAnthropicHeaders() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .anthropic,
            style: .anthropicMessages,
            chatURL: try XCTUnwrap(URL(string: "https://api.anthropic.com/v1/messages")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.anthropic.com/v1/models"))
        )

        let request = ChatStreamingRequestFactory().makeStreamingRequest(
            endpoint: endpoint,
            requestBodyData: Data(),
            apiKey: " Bearer sk-ant-test "
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    func testStreamingRequestFactoryBuildsOpenRouterAnthropicMessagesHeaders() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .anthropic,
            style: .anthropicMessages,
            chatURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/messages")),
            modelsURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/models"))
        )

        let request = ChatStreamingRequestFactory().makeStreamingRequest(
            endpoint: endpoint,
            requestBodyData: Data(),
            apiKey: "sk-or-test"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-test")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-OpenRouter-Cache"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-OpenRouter-Cache-TTL"))
        XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
        XCTAssertNil(request.value(forHTTPHeaderField: "anthropic-version"))
    }

    func testStreamingRequestFactoryDoesNotEnableOpenRouterResponseCachingImplicitly() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/models"))
        )

        let request = ChatStreamingRequestFactory().makeStreamingRequest(
            endpoint: endpoint,
            requestBodyData: Data(),
            apiKey: "sk-or-test"
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "X-OpenRouter-Cache"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-OpenRouter-Cache-TTL"))
    }

    func testStreamingRequestFactoryBuildsAzureOpenAIAPIKeyHeader() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://example-resource.openai.azure.com/openai/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://example-resource.openai.azure.com/openai/v1/models"))
        )

        let request = ChatStreamingRequestFactory().makeStreamingRequest(
            endpoint: endpoint,
            requestBodyData: Data(),
            apiKey: "sk-azure-test"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "sk-azure-test")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testStreamingRequestFactoryKeepsAzureBearerTokenAuthorization() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIResponses,
            chatURL: try XCTUnwrap(URL(string: "https://example-resource.openai.azure.com/openai/v1/responses")),
            modelsURL: try XCTUnwrap(URL(string: "https://example-resource.openai.azure.com/openai/v1/models"))
        )

        let request = ChatStreamingRequestFactory().makeStreamingRequest(
            endpoint: endpoint,
            requestBodyData: Data(),
            apiKey: "Bearer entra-token"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer entra-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "api-key"))
    }
}
