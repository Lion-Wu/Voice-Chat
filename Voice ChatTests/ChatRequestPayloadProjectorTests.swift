import XCTest
@testable import Voice_Chat

final class ChatRequestPayloadProjectorTests: XCTestCase {
    func testRequestPayloadProjectorFiltersErrorsAndAddsDeveloperPrompt() throws {
        let payload = ChatRequestPayloadProjector().transformedMessagesForRequest(
            messages: [
                ChatRequestSourceMessage(content: "hello", isUser: true),
                ChatRequestSourceMessage(content: "!error: transient", isUser: false),
                ChatRequestSourceMessage(content: "answer", isUser: false)
            ],
            developerPrompt: "  system  ",
            includeImagesInUserContent: true
        )

        XCTAssertEqual(payload.count, 3)
        XCTAssertEqual(payload[0]["role"] as? String, "developer")
        XCTAssertEqual(payload[0]["content"] as? String, "system")
        XCTAssertEqual(payload[1]["role"] as? String, "user")
        XCTAssertEqual(payload[1]["content"] as? String, "hello")
        XCTAssertEqual(payload[2]["role"] as? String, "assistant")
        XCTAssertEqual(payload[2]["content"] as? String, "answer")
    }

    func testRequestPayloadProjectorIncludesUserImagesWhenRequested() throws {
        let attachment = ChatImageAttachment(mimeType: "image/png", data: try XCTUnwrap("image".data(using: .utf8)))
        let payload = ChatRequestPayloadProjector().transformedMessagesForRequest(
            messages: [
                ChatRequestSourceMessage(content: "look", isUser: true, imageAttachments: [attachment])
            ],
            developerPrompt: nil,
            includeImagesInUserContent: true
        )
        let parts = try XCTUnwrap(payload.first?["content"] as? [[String: Any]])
        let imageURL = try XCTUnwrap(parts.last?["image_url"] as? [String: Any])

        XCTAssertEqual(payload.first?["role"] as? String, "user")
        XCTAssertEqual(parts.first?["type"] as? String, "text")
        XCTAssertEqual(parts.first?["text"] as? String, "look")
        XCTAssertEqual(parts.last?["type"] as? String, "image_url")
        XCTAssertEqual(imageURL["url"] as? String, attachment.dataURLString)
    }
}
