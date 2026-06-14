import XCTest
@testable import Voice_Chat

final class ChatRequestBodyProviderEncoderTests: XCTestCase {
    func testAnthropicBaseBodyKeepsSystemPromptAndMaxTokens() throws {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .anthropic,
            style: .anthropicMessages,
            chatURL: try XCTUnwrap(URL(string: "https://api.anthropic.com/v1/messages")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.anthropic.com/v1/models"))
        )

        let body = ChatRequestBodyProviderEncoder.makeBaseRequestBody(
            model: "claude-sonnet-4",
            messagePayload: [["role": "user", "content": "hello"]],
            developerPrompt: "answer tersely",
            endpoint: endpoint,
            apiAdvancedSettings: APIAdvancedSettings(anthropicMaxTokens: 1234)
        )

        XCTAssertEqual(body["model"] as? String, "claude-sonnet-4")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["system"] as? String, "answer tersely")
        XCTAssertEqual(body["max_tokens"] as? Int, 1234)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
    }

    func testOpenAIResponsesInputKeepsImagesAndNormalizesRoles() throws {
        let input = ChatProviderMessagePayloadEncoder.openAIResponsesInput(from: [
            ["role": "tool", "content": "fallback role"],
            [
                "role": "assistant",
                "content": [
                    ["type": "text", "text": "caption"],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,AAAA"]]
                ]
            ]
        ])

        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[0]["role"] as? String, "user")
        XCTAssertEqual(input[1]["role"] as? String, "assistant")
        let assistantContent = try XCTUnwrap(input[1]["content"] as? [[String: Any]])
        XCTAssertEqual(assistantContent.map { $0["type"] as? String }, ["input_text", "input_image"])
        XCTAssertEqual(assistantContent.last?["image_url"] as? String, "data:image/png;base64,AAAA")
    }

    func testLMStudioRESTInputUsesOnlyLatestUserImages() throws {
        let input = try XCTUnwrap(ChatProviderMessagePayloadEncoder.lmStudioRESTInput(
            from: [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "first"],
                        ["type": "image_url", "image_url": ["url": "data:image/png;base64,OLD"]]
                    ]
                ],
                ["role": "assistant", "content": "reply"],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "second"],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,NEW"]]
                    ]
                ]
            ],
            textDiscriminator: "text"
        ) as? [[String: Any]])

        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[0]["type"] as? String, "text")
        XCTAssertEqual(input[1]["type"] as? String, "image")
        XCTAssertEqual(input[1]["data_url"] as? String, "data:image/jpeg;base64,NEW")
    }

    func testAnthropicInputConvertsDataURLImages() throws {
        let input = ChatProviderMessagePayloadEncoder.anthropicMessagesInput(from: [
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": "look"],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,AAAA"]]
                ]
            ]
        ])

        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        let source = try XCTUnwrap(content.last?["source"] as? [String: String])
        XCTAssertEqual(source["type"], "base64")
        XCTAssertEqual(source["media_type"], "image/png")
        XCTAssertEqual(source["data"], "AAAA")
    }
}
