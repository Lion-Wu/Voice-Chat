import XCTest
@testable import Voice_Chat

@MainActor
final class VoiceLoadingWatchdogTests: XCTestCase {
    func testTimesOutWhenLoadingStalls() async {
        var now = Date(timeIntervalSince1970: 100)
        let timedOut = expectation(description: "watchdog timed out")
        let watchdog = VoiceLoadingWatchdog(
            defaultTimeout: 1,
            activeAudioRequestTimeout: 2,
            pollInterval: .milliseconds(10),
            now: { now }
        )
        defer { watchdog.stop() }

        watchdog.start(
            isActive: { true },
            voiceWorkSnapshot: { .idle },
            onTimeout: { timedOut.fulfill() }
        )
        now = now.addingTimeInterval(1.1)

        await fulfillment(of: [timedOut], timeout: 1)
        XCTAssertFalse(watchdog.isRunning)
    }

    func testMarkProgressDelaysTimeout() async {
        var now = Date(timeIntervalSince1970: 200)
        var didTimeout = false
        let timedOut = expectation(description: "watchdog timed out after progress")
        let watchdog = VoiceLoadingWatchdog(
            defaultTimeout: 1,
            activeAudioRequestTimeout: 2,
            pollInterval: .milliseconds(10),
            now: { now }
        )
        defer { watchdog.stop() }

        watchdog.start(
            isActive: { true },
            voiceWorkSnapshot: { .idle },
            onTimeout: {
                didTimeout = true
                timedOut.fulfill()
            }
        )
        now = now.addingTimeInterval(0.8)
        watchdog.markProgress()
        now = now.addingTimeInterval(0.4)
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(didTimeout)

        now = now.addingTimeInterval(0.8)
        await fulfillment(of: [timedOut], timeout: 1)
        XCTAssertFalse(watchdog.isRunning)
    }

    func testStopPreventsTimeout() async {
        var now = Date(timeIntervalSince1970: 300)
        var didTimeout = false
        let watchdog = VoiceLoadingWatchdog(
            defaultTimeout: 1,
            activeAudioRequestTimeout: 2,
            pollInterval: .milliseconds(10),
            now: { now }
        )

        watchdog.start(
            isActive: { true },
            voiceWorkSnapshot: { .idle },
            onTimeout: { didTimeout = true }
        )
        watchdog.stop()
        now = now.addingTimeInterval(10)
        try? await Task.sleep(for: .milliseconds(40))

        XCTAssertFalse(didTimeout)
        XCTAssertFalse(watchdog.isRunning)
    }
}
