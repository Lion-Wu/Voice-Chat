import XCTest
@testable import Voice_Chat

final class ChatRequestBodyBuilderTests: XCTestCase {
    func testRequestBodyBuilderBuildsOpenAICompatibleMessagesBody() throws {
        let builder = ChatRequestBodyBuilder()
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAICompatible,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:8000/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:8000/v1/models"))
        )

        let data = try builder.buildRequestBodyData(
            model: "test-model",
            messagePayload: [["role": "user", "content": "hello"]],
            developerPrompt: nil,
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(openAICompatibleMaxTokens: 777),
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let body = try decodedBody(from: data)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])

        XCTAssertEqual(body["model"] as? String, "test-model")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["max_tokens"] as? Int, 777)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "hello")
    }

    func testEndpointResolverAndRequestBodyBuilderDefaultOpenAICompatibleToResponsesBody() throws {
        let endpoint = try XCTUnwrap(DefaultChatEndpointResolver().streamingCandidates(
            for: "http://localhost:8000",
            providerHint: .openAICompatible,
            styleHint: .openAIChatCompletions
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
        XCTAssertEqual(body["max_output_tokens"] as? Int, 256)
        XCTAssertEqual(input.first?["type"] as? String, "text")
        XCTAssertTrue((input.first?["content"] as? String)?.contains("User: describe") == true)
        XCTAssertEqual(input.last?["type"] as? String, "image")
        XCTAssertEqual(input.last?["data_url"] as? String, dataURL)
    }

    func testRequestBodyBuilderMapsProviderSpecificAdvancedSettings() throws {
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

        let gemini = try providerBody(provider: .gemini, settings: APIAdvancedSettings(geminiMaxTokens: 101, geminiSampling: sampling), messagePayload: messagePayload)
        XCTAssertEqual(gemini["max_tokens"] as? Int, 101)
        XCTAssertEqual(gemini["temperature"] as? Double, 1.5)
        XCTAssertEqual(gemini["top_p"] as? Double, 0.75)
        XCTAssertNil(gemini["presence_penalty"])

        let deepSeek = try providerBody(provider: .deepSeek, settings: APIAdvancedSettings(deepSeekMaxTokens: 202, deepSeekSampling: sampling), messagePayload: messagePayload)
        XCTAssertEqual(deepSeek["max_tokens"] as? Int, 202)
        XCTAssertEqual(deepSeek["presence_penalty"] as? Double, 0.3)
        XCTAssertEqual(deepSeek["frequency_penalty"] as? Double, 0.4)
        XCTAssertEqual(deepSeek["top_logprobs"] as? Int, 9)

        let openRouter = try providerBody(provider: .openRouter, settings: APIAdvancedSettings(openRouterMaxTokens: 303, openRouterMaxCompletionTokens: 404, openRouterSampling: sampling), messagePayload: messagePayload)
        XCTAssertEqual(openRouter["max_tokens"] as? Int, 303)
        XCTAssertEqual(openRouter["max_completion_tokens"] as? Int, 404)
        XCTAssertEqual(openRouter["top_k"] as? Int, 40)
        XCTAssertEqual(openRouter["min_p"] as? Double, 0.1)
        XCTAssertEqual(openRouter["top_a"] as? Double, 0.2)
        XCTAssertEqual(openRouter["repetition_penalty"] as? Double, 1.1)
        XCTAssertEqual(openRouter["structured_outputs"] as? Bool, true)
        XCTAssertEqual(openRouter["verbosity"] as? String, "high")

        let llamaCpp = try providerBody(provider: .llamaCpp, settings: APIAdvancedSettings(llamaCppMaxTokens: 505, llamaCppSampling: sampling), messagePayload: messagePayload)
        XCTAssertEqual(llamaCpp["max_tokens"] as? Int, 505)
        XCTAssertEqual(llamaCpp["top_k"] as? Int, 40)
        XCTAssertEqual(llamaCpp["repeat_penalty"] as? Double, 1.1)
    }

    func testRequestBodyBuilderKeepsDeepSeekReasonerSamplingRestricted() throws {
        let sampling = APIAdvancedSamplingSettings(
            temperatureEnabled: true,
            temperature: 1.2,
            topPEnabled: true,
            topP: 0.8,
            presencePenaltyEnabled: true,
            presencePenalty: 0.5,
            jsonModeEnabled: true
        )
        let endpoint = ChatAPIEndpointCandidate(
            provider: .deepSeek,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://api.deepseek.com/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.deepseek.com/v1/models"))
        )

        let data = try ChatRequestBodyBuilder().buildRequestBodyData(
            model: "deepseek-reasoner",
            messagePayload: [["role": "user", "content": "hello"]],
            developerPrompt: nil,
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(deepSeekMaxTokens: 256, deepSeekSampling: sampling),
            thinkingCapability: nil,
            thinkingOption: nil
        )
        let body = try decodedBody(from: data)

        XCTAssertEqual(body["max_tokens"] as? Int, 256)
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["top_p"])
        XCTAssertNil(body["presence_penalty"])
        XCTAssertEqual((body["response_format"] as? [String: String])?["type"], "json_object")
    }

    func testRequestBodyBuilderMapsThinkingForResponsesGeminiOpenRouterAndLMStudio() throws {
        let messagePayload = [["role": "user", "content": "hello"]]

        let responsesEndpoint = try XCTUnwrap(DefaultChatEndpointResolver().streamingCandidates(
            for: "https://api.openai.com",
            providerHint: .openAI,
            styleHint: .openAIChatCompletions
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

        let geminiBody = try providerBody(
            provider: .gemini,
            settings: APIAdvancedSettings(),
            messagePayload: messagePayload,
            thinkingOption: .xhigh
        )
        XCTAssertEqual(geminiBody["reasoning_effort"] as? String, "high")

        let openRouterBody = try providerBody(
            provider: .openRouter,
            settings: APIAdvancedSettings(),
            messagePayload: messagePayload,
            thinkingOption: .max
        )
        XCTAssertEqual((openRouterBody["reasoning"] as? [String: String])?["effort"], "xhigh")

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
}
