import XCTest
@testable import Voice_Chat

final class SpeechInputSeamTests: XCTestCase {
    func testTranscriptMergerKeepsCJKContinuousAndSpacesEnglish() {
        XCTAssertEqual(SpeechTranscriptMerger.merge("你好", "世界"), "你好世界")
        XCTAssertEqual(SpeechTranscriptMerger.merge("こんにちは", "世界"), "こんにちは世界")
        XCTAssertEqual(SpeechTranscriptMerger.merge("Hello", "world"), "Hello world")
        XCTAssertEqual(SpeechTranscriptMerger.merge("你好", "world"), "你好 world")
        XCTAssertEqual(SpeechTranscriptMerger.merge("Hello.", "world"), "Hello. world")
    }

    func testTranscriptMergerTrimsEmptySides() {
        XCTAssertEqual(SpeechTranscriptMerger.merge("  ", " next "), "next")
        XCTAssertEqual(SpeechTranscriptMerger.merge(" first ", "  "), "first")
    }
}
