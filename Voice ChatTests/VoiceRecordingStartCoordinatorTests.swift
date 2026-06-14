import XCTest
@testable import Voice_Chat

final class VoiceRecordingStartCoordinatorTests: XCTestCase {
    func testBeginStartTracksAttemptAndCancelsEarlierTasks() {
        var coordinator = VoiceRecordingStartCoordinator()
        let firstTask = sleepingTask()
        let firstWatchdog = sleepingTask()
        let secondTask = sleepingTask()
        defer {
            coordinator.cancelStartTasks()
            secondTask.cancel()
        }

        let firstID = coordinator.beginStart { uuid(41) }
        coordinator.registerStartRecordingTask(firstTask)
        coordinator.registerStartWatchdogTask(firstWatchdog)

        let secondID = coordinator.beginStart { uuid(42) }
        coordinator.registerStartRecordingTask(secondTask)

        XCTAssertEqual(firstID, uuid(41))
        XCTAssertEqual(secondID, uuid(42))
        XCTAssertFalse(coordinator.isActiveStartAttempt(firstID))
        XCTAssertTrue(coordinator.isActiveStartAttempt(secondID))
        XCTAssertTrue(firstTask.isCancelled)
        XCTAssertTrue(firstWatchdog.isCancelled)
    }

    func testRestartRequestIsDeferredUntilCurrentStartCompletes() {
        var coordinator = VoiceRecordingStartCoordinator()
        let attemptID = coordinator.beginStart { uuid(43) }

        XCTAssertTrue(coordinator.requestRestartAfterStartIfNeeded())
        XCTAssertEqual(coordinator.completeStart(attemptID: uuid(44)), .stale)
        XCTAssertEqual(coordinator.completeStart(attemptID: attemptID), .restartRequested)
        XCTAssertFalse(coordinator.isStartingRecording)
        XCTAssertFalse(coordinator.pendingRestartAfterStart)
    }

    func testFailStartClearsOnlyMatchingActiveAttempt() {
        var coordinator = VoiceRecordingStartCoordinator()
        let attemptID = coordinator.beginStart { uuid(45) }

        XCTAssertFalse(coordinator.failStart(attemptID: uuid(46)))
        XCTAssertTrue(coordinator.isStartingRecording)
        XCTAssertTrue(coordinator.failStart(attemptID: attemptID))
        XCTAssertFalse(coordinator.isStartingRecording)
        XCTAssertNil(coordinator.startAttemptID)
        XCTAssertFalse(coordinator.pendingRestartAfterStart)
    }

    func testCancelStartTasksClearsStateAndCancelsTasks() {
        var coordinator = VoiceRecordingStartCoordinator()
        let task = sleepingTask()
        let watchdog = sleepingTask()
        _ = coordinator.beginStart { uuid(47) }
        coordinator.registerStartRecordingTask(task)
        coordinator.registerStartWatchdogTask(watchdog)

        coordinator.cancelStartTasks()

        XCTAssertFalse(coordinator.isStartingRecording)
        XCTAssertNil(coordinator.startAttemptID)
        XCTAssertTrue(task.isCancelled)
        XCTAssertTrue(watchdog.isCancelled)
    }
}
