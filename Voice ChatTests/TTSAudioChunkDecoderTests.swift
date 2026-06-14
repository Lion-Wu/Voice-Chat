import XCTest
@testable import Voice_Chat

final class TTSAudioChunkDecoderTests: XCTestCase {
    func testEmptyDataIsTransientFailure() {
        XCTAssertThrowsError(try TTSAudioChunkDecoder.decode(Data())) { error in
            let failure = error as? TTSAudioChunkDecodeFailure
            XCTAssertEqual(failure, .emptyData)
            XCTAssertEqual(failure?.disposition, .transient)
        }
    }

    func testUnsupportedAudioDataIsContentFailure() {
        XCTAssertThrowsError(try TTSAudioChunkDecoder.decode(Data("not audio".utf8))) { error in
            let failure = error as? TTSAudioChunkDecodeFailure
            XCTAssertEqual(failure, .unsupportedAudioData)
            XCTAssertEqual(failure?.disposition, .content)
        }
    }
}
