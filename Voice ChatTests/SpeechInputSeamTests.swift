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

    func testRecognitionTaskErrorDisposition() {
        let noSpeech = NSError(domain: "kAFAssistantErrorDomain", code: 1110)
        let interrupted = NSError(domain: "kAFAssistantErrorDomain", code: 1107)
        let cases: [(Error, Bool, Bool, Bool, SpeechRecognitionTaskErrorDisposition)] = [
            (noSpeech, false, false, false, .restart),
            (noSpeech, true, false, false, .finish),
            (noSpeech, false, true, true, .restart),
            (noSpeech, false, true, false, .finish),
            (interrupted, false, false, false, .fail)
        ]

        for (error, endedForSilence, taskHasText, continuesListening, expected) in cases {
            XCTAssertEqual(
                SpeechRecognitionTaskErrorPolicy.disposition(
                    for: error,
                    didEndAudioForSilence: endedForSilence,
                    currentTaskHasRecognizedText: taskHasText,
                    continuesListeningAfterRecognizedText: continuesListening
                ),
                expected
            )
        }
    }
}
