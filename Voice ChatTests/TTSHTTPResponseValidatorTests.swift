import XCTest
@testable import Voice_Chat

final class TTSHTTPResponseValidatorTests: XCTestCase {
    func testServerErrorClassifiesContentFailureWithBodyPreview() throws {
        let response = try makeResponse(statusCode: 422, contentType: "application/json")
        let body = Data(" invalid voice input ".utf8)

        let failure = try XCTUnwrap(TTSHTTPResponseValidator.failure(for: response, data: body))

        XCTAssertEqual(failure.disposition, .content)
        XCTAssertTrue(failure.message.contains("422"))
        XCTAssertTrue(failure.message.contains("invalid voice input"))
    }

    func testRetryableStatusClassifiesTransientFailure() throws {
        let response = try makeResponse(statusCode: 503, contentType: "text/plain")

        let failure = try XCTUnwrap(TTSHTTPResponseValidator.failure(for: response, data: nil))

        XCTAssertEqual(failure.disposition, .transient)
        XCTAssertTrue(failure.message.contains("503"))
    }

    func testNonAudioSuccessClassifiesContentFailure() throws {
        let response = try makeResponse(statusCode: 200, contentType: "application/json")
        let body = Data("{\"error\":\"not audio\"}".utf8)

        let failure = try XCTUnwrap(TTSHTTPResponseValidator.failure(for: response, data: body))

        XCTAssertEqual(failure.disposition, .content)
        XCTAssertTrue(failure.message.contains("not audio"))
    }

    func testAudioSuccessDoesNotReportFailure() throws {
        let response = try makeResponse(statusCode: 200, contentType: "audio/wav")

        XCTAssertNil(TTSHTTPResponseValidator.failure(for: response, data: Data([0x52, 0x49, 0x46, 0x46])))
    }

    private func makeResponse(statusCode: Int, contentType: String) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(
            url: XCTUnwrap(URL(string: "http://localhost:9880/tts")),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        ))
    }
}
