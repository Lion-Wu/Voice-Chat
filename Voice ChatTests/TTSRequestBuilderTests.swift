import XCTest
@testable import Voice_Chat

final class TTSRequestBuilderTests: XCTestCase {
    func testMakeRequestEncodesConfiguredSynthParameters() throws {
        let configuration = TTSSynthesisConfiguration(
            serverAddress: "localhost:9880",
            url: try XCTUnwrap(URL(string: "http://localhost:9880/tts")),
            textLanguage: "zh",
            referenceAudioPath: "/tmp/ref.wav",
            promptText: "reference prompt",
            promptLanguage: "en",
            textSplitMethod: "cut0",
            mediaType: "wav",
            usesStreamingSegments: true
        )

        let request = try TTSRequestBuilder.makeRequest(
            for: "hello world",
            configuration: configuration
        )

        XCTAssertEqual(request.url, configuration.url)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 60)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["text"] as? String, "hello world")
        XCTAssertEqual(json["text_lang"] as? String, "zh")
        XCTAssertEqual(json["ref_audio_path"] as? String, "/tmp/ref.wav")
        XCTAssertEqual(json["prompt_text"] as? String, "reference prompt")
        XCTAssertEqual(json["prompt_lang"] as? String, "en")
        XCTAssertEqual(json["batch_size"] as? Int, 1)
        XCTAssertEqual(json["media_type"] as? String, "wav")
        XCTAssertEqual(json["text_split_method"] as? String, "cut0")
    }
}
