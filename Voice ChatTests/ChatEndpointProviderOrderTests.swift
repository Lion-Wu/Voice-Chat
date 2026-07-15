import XCTest
@testable import Voice_Chat

final class ChatEndpointProviderOrderTests: XCTestCase {
    func testProviderOrderingMatrix() {
        let cases = [
            ProviderOrderCase(
                name: "Local LM Studio",
                context: .init(path: "", host: "localhost", port: 1234, isLocal: true),
                preferred: nil,
                expected: [.lmStudio, .unknown, .openAI]
            ),
            ProviderOrderCase(
                name: "Third-party messages path",
                context: .init(path: "/v1/messages", host: "proxy.example.com", port: nil, isLocal: false),
                preferred: .openAI,
                expected: [.openAI, .unknown]
            ),
            ProviderOrderCase(
                name: "Official Anthropic host",
                context: .init(path: "/v1/messages", host: "api.anthropic.com", port: nil, isLocal: false),
                preferred: .openAI,
                expectedPrefix: [.anthropic, .openAI]
            ),
            ProviderOrderCase(
                name: "Preferred generic provider",
                context: .init(path: "/custom", host: "example.internal", port: nil, isLocal: false),
                preferred: .openAI,
                expected: [.openAI, .unknown]
            ),
            ProviderOrderCase(
                name: "Unknown preference",
                context: .init(path: "", host: "example.com", port: nil, isLocal: false),
                preferred: .unknown,
                expected: [.unknown, .openAI]
            ),
            ProviderOrderCase(
                name: "Remote API v1 path",
                context: .init(path: "/api/v1", host: "openrouter.ai", port: nil, isLocal: false),
                preferred: nil,
                expected: [.openAI, .unknown]
            )
        ]

        for testCase in cases {
            let providers = ChatEndpointProviderOrder.providers(
                for: testCase.context,
                preferred: testCase.preferred
            )
            if let expected = testCase.expected {
                XCTAssertEqual(providers, expected, testCase.name)
            }
            if let expectedPrefix = testCase.expectedPrefix {
                XCTAssertEqual(
                    Array(providers.prefix(expectedPrefix.count)),
                    expectedPrefix,
                    testCase.name
                )
            }
        }
    }

    func testEndpointRoutingMatrix() {
        let cases = [
            EndpointRoutingCase(
                name: "Unknown backend",
                base: "https://models.example.net/custom",
                expectedProvider: .unknown,
                expectedStyle: .openAIResponses,
                expectedChatURL: "https://models.example.net/custom/v1/responses",
                expectedModelsURL: "https://models.example.net/custom/v1/models",
                requiredCandidates: [
                    .init(provider: .unknown, style: .openAIChatCompletions, url: "https://models.example.net/custom/v1/chat/completions")
                ]
            ),
            EndpointRoutingCase(
                name: "OpenRouter API base",
                base: "https://openrouter.ai/api/v1",
                expectedProvider: .openAI,
                expectedStyle: .openAIResponses,
                expectedChatURL: "https://openrouter.ai/api/v1/responses",
                expectedModelsURL: "https://openrouter.ai/api/v1/models",
                forbiddenProviders: [.lmStudio, .anthropic]
            ),
            EndpointRoutingCase(
                name: "OpenRouter messages path automatic",
                base: "https://openrouter.ai/api/v1/messages",
                expectedProvider: .openAI,
                expectedStyle: .openAIResponses,
                expectedChatURL: "https://openrouter.ai/api/v1/responses",
                expectedModelsURL: "https://openrouter.ai/api/v1/models",
                requiredCandidates: [
                    .init(provider: .openAI, style: .openAIChatCompletions, url: "https://openrouter.ai/api/v1/chat/completions")
                ]
            ),
            EndpointRoutingCase(
                name: "OpenRouter messages path manual Anthropic",
                base: "https://openrouter.ai/api/v1/messages",
                providerHint: .anthropic,
                styleHint: .anthropicMessages,
                expectedProvider: .anthropic,
                expectedStyle: .anthropicMessages,
                expectedChatURL: "https://openrouter.ai/api/v1/messages",
                expectedModelsURL: "https://openrouter.ai/api/v1/models"
            ),
            EndpointRoutingCase(
                name: "OpenAI API base",
                base: "https://api.openai.com/v1",
                expectedProvider: .openAI,
                expectedStyle: .openAIResponses,
                expectedChatURL: "https://api.openai.com/v1/responses",
                expectedModelsURL: "https://api.openai.com/v1/models"
            ),
            EndpointRoutingCase(
                name: "LM Studio explicit Chat Completions",
                base: "http://localhost:1234/v1/chat/completions",
                expectedProvider: .lmStudio,
                expectedStyle: .openAIChatCompletions,
                expectedChatURL: "http://localhost:1234/v1/chat/completions",
                expectedModelsURL: "http://localhost:1234/v1/models",
                requiredCandidates: [
                    .init(provider: .lmStudio, style: .lmStudioRESTV1, url: "http://localhost:1234/api/v1/chat")
                ]
            ),
            EndpointRoutingCase(
                name: "Gemini OpenAI compatibility base",
                base: "https://generativelanguage.googleapis.com/v1beta/openai",
                expectedProvider: .openAI,
                expectedStyle: .openAIChatCompletions,
                expectedChatURL: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
                expectedModelsURL: "https://generativelanguage.googleapis.com/v1beta/openai/models",
                forbiddenStyles: [.openAIResponses]
            ),
            EndpointRoutingCase(
                name: "Gemini API base",
                base: "https://generativelanguage.googleapis.com/v1beta",
                expectedProvider: .openAI,
                expectedStyle: .openAIChatCompletions,
                expectedChatURL: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
                expectedModelsURL: "https://generativelanguage.googleapis.com/v1beta/openai/models"
            ),
            EndpointRoutingCase(
                name: "DeepSeek official base",
                base: "https://api.deepseek.com",
                expectedProvider: .openAI,
                expectedStyle: .openAIChatCompletions,
                expectedChatURL: "https://api.deepseek.com/chat/completions",
                expectedModelsURL: "https://api.deepseek.com/models",
                forbiddenStyles: [.openAIResponses]
            ),
            EndpointRoutingCase(
                name: "xAI official base",
                base: "https://api.x.ai/v1",
                expectedProvider: .openAI,
                expectedStyle: .openAIResponses,
                expectedChatURL: "https://api.x.ai/v1/responses",
                expectedModelsURL: "https://api.x.ai/v1/models"
            ),
            EndpointRoutingCase(
                name: "Perplexity official base",
                base: "https://api.perplexity.ai/v1",
                expectedProvider: .openAI,
                expectedStyle: .openAIResponses,
                expectedChatURL: "https://api.perplexity.ai/v1/responses",
                expectedModelsURL: "https://api.perplexity.ai/v1/models"
            ),
            EndpointRoutingCase(
                name: "Azure OpenAI base",
                base: "https://example-resource.openai.azure.com",
                expectedProvider: .openAI,
                expectedStyle: .openAIResponses,
                expectedChatURL: "https://example-resource.openai.azure.com/openai/v1/responses",
                expectedModelsURL: "https://example-resource.openai.azure.com/openai/v1/models"
            ),
            EndpointRoutingCase(
                name: "Mistral official base",
                base: "https://api.mistral.ai/v1",
                expectedProvider: .openAI,
                expectedStyle: .openAIChatCompletions,
                expectedChatURL: "https://api.mistral.ai/v1/chat/completions",
                expectedModelsURL: "https://api.mistral.ai/v1/models",
                forbiddenStyles: [.openAIResponses]
            ),
            EndpointRoutingCase(
                name: "Explicit Chat Completions path automatic",
                base: "https://openrouter.ai/api/v1/chat/completions",
                providerHint: .openAI,
                expectedProvider: .openAI,
                expectedStyle: .openAIChatCompletions,
                expectedChatURL: "https://openrouter.ai/api/v1/chat/completions",
                expectedModelsURL: "https://openrouter.ai/api/v1/models",
                requiredCandidates: [
                    .init(provider: .openAI, style: .openAIResponses, url: "https://openrouter.ai/api/v1/responses")
                ]
            ),
            EndpointRoutingCase(
                name: "Explicit Chat Completions path forced Responses",
                base: "https://openrouter.ai/api/v1/chat/completions",
                providerHint: .openAI,
                styleHint: .openAIResponses,
                expectedProvider: .openAI,
                expectedStyle: .openAIResponses,
                expectedChatURL: "https://openrouter.ai/api/v1/responses",
                expectedModelsURL: "https://openrouter.ai/api/v1/models"
            ),
            EndpointRoutingCase(
                name: "Chat base forced Responses",
                base: "https://api.openai.com/v1/chat",
                providerHint: .openAI,
                styleHint: .openAIResponses,
                expectedProvider: .openAI,
                expectedStyle: .openAIResponses,
                expectedChatURL: "https://api.openai.com/v1/responses",
                expectedModelsURL: "https://api.openai.com/v1/models",
                forbiddenStyles: [.openAIChatCompletions]
            )
        ]

        for testCase in cases {
            let candidates = DefaultChatEndpointResolver().streamingCandidates(
                for: testCase.base,
                providerHint: testCase.providerHint,
                styleHint: testCase.styleHint
            )
            XCTAssertEqual(candidates.first?.provider, testCase.expectedProvider, testCase.name)
            XCTAssertEqual(candidates.first?.style, testCase.expectedStyle, testCase.name)
            XCTAssertEqual(candidates.first?.chatURL.absoluteString, testCase.expectedChatURL, testCase.name)
            XCTAssertEqual(candidates.first?.modelsURL.absoluteString, testCase.expectedModelsURL, testCase.name)

            for required in testCase.requiredCandidates {
                XCTAssertTrue(candidates.contains {
                    $0.provider == required.provider &&
                    $0.style == required.style &&
                    $0.chatURL.absoluteString == required.url
                }, testCase.name)
            }
            for provider in testCase.forbiddenProviders {
                XCTAssertFalse(candidates.contains { $0.provider == provider }, testCase.name)
            }
            for style in testCase.forbiddenStyles {
                XCTAssertFalse(candidates.contains { $0.style == style }, testCase.name)
            }
        }
    }
}

private struct ProviderOrderCase {
    let name: String
    let context: ChatEndpointProviderOrderContext
    let preferred: ChatProvider?
    let expected: [ChatProvider]?
    let expectedPrefix: [ChatProvider]?

    init(
        name: String,
        context: ChatEndpointProviderOrderContext,
        preferred: ChatProvider?,
        expected: [ChatProvider]? = nil,
        expectedPrefix: [ChatProvider]? = nil
    ) {
        self.name = name
        self.context = context
        self.preferred = preferred
        self.expected = expected
        self.expectedPrefix = expectedPrefix
    }
}

private struct EndpointRoutingCase {
    let name: String
    let base: String
    var providerHint: ChatProvider? = nil
    var styleHint: ChatRequestStyle? = nil
    let expectedProvider: ChatProvider
    let expectedStyle: ChatRequestStyle
    let expectedChatURL: String
    let expectedModelsURL: String
    var requiredCandidates: [RequiredEndpointCandidate] = []
    var forbiddenProviders: [ChatProvider] = []
    var forbiddenStyles: [ChatRequestStyle] = []
}

private struct RequiredEndpointCandidate {
    let provider: ChatProvider
    let style: ChatRequestStyle
    let url: String
}
