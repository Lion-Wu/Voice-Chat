import XCTest
@testable import Voice_Chat

final class APIAdvancedSettingsCodecTests: XCTestCase {
    func testRoundTripsSanitizedSettings() throws {
        let settings = APIAdvancedSettings(
            openAIResponsesMaxOutputTokens: -10,
            anthropicMaxTokens: 0,
            anthropicLowThinkingBudget: 100
        )

        let json = try XCTUnwrap(APIAdvancedSettingsCodec.encode(settings))
        let decoded = APIAdvancedSettingsCodec.decode(from: json)

        XCTAssertEqual(decoded.openAIResponsesMaxOutputTokens, 0)
        XCTAssertEqual(decoded.anthropicMaxTokens, 1)
        XCTAssertEqual(decoded.anthropicLowThinkingBudget, 1024)
    }

    func testInvalidJSONFallsBackToDefaults() {
        XCTAssertEqual(
            APIAdvancedSettingsCodec.decode(from: "not-json"),
            APIAdvancedSettings.defaults.sanitized
        )
    }
}
