import XCTest
@testable import Voice_Chat

@MainActor
final class SettingsViewModelSuppressionControllerTests: XCTestCase {
    func testSingleFlagIsActiveOnlyInsideScope() {
        let controller = SettingsViewModelSuppressionController()

        XCTAssertFalse(controller.isActive(.autoSaves))
        controller.withSuppressed(.autoSaves) {
            XCTAssertTrue(controller.isActive(.autoSaves))
        }
        XCTAssertFalse(controller.isActive(.autoSaves))
    }

    func testMultipleFlagsAreSuppressedTogether() {
        let controller = SettingsViewModelSuppressionController()

        controller.withSuppressed([.saveChatServerPreset, .saveChatServerPresetFormat]) {
            XCTAssertTrue(controller.isActive(.saveChatServerPreset))
            XCTAssertTrue(controller.isActive(.saveChatServerPresetFormat))
            XCTAssertFalse(controller.isActive(.saveVoicePreset))
        }

        XCTAssertFalse(controller.isActive(.saveChatServerPreset))
        XCTAssertFalse(controller.isActive(.saveChatServerPresetFormat))
    }

    func testNestedSuppressionRestoresOuterFlag() {
        let controller = SettingsViewModelSuppressionController()

        controller.withSuppressed(.autoSaves) {
            XCTAssertTrue(controller.isActive(.autoSaves))
            controller.withSuppressed(.autoSaves) {
                XCTAssertTrue(controller.isActive(.autoSaves))
            }
            XCTAssertTrue(controller.isActive(.autoSaves))
        }

        XCTAssertFalse(controller.isActive(.autoSaves))
    }
}
