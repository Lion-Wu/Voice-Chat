import XCTest
@testable import Voice_Chat

final class ChatToolAuthorizationCoordinatorTests: XCTestCase {
    func testResolveAllowsWaitingRequest() async throws {
        let coordinator = ChatToolAuthorizationCoordinator()
        let waiter = Task {
            await coordinator.waitForDecision(requestID: "request")
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        await coordinator.resolve(requestID: "request", allowed: true)

        let allowed = await waiter.value
        XCTAssertTrue(allowed)
    }

    func testResolveDeniesWaitingRequest() async throws {
        let coordinator = ChatToolAuthorizationCoordinator()
        let waiter = Task {
            await coordinator.waitForDecision(requestID: "request")
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        await coordinator.resolve(requestID: "request", allowed: false)

        let allowed = await waiter.value
        XCTAssertFalse(allowed)
    }

    func testCancelAllDeniesWaitingRequests() async throws {
        let coordinator = ChatToolAuthorizationCoordinator()
        let first = Task {
            await coordinator.waitForDecision(requestID: "first")
        }
        let second = Task {
            await coordinator.waitForDecision(requestID: "second")
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        await coordinator.cancelAll()

        let values = await [first.value, second.value]
        XCTAssertEqual(values, [false, false])
    }

    func testDuplicateRequestIDReleasesOlderWaiter() async throws {
        let coordinator = ChatToolAuthorizationCoordinator()
        let older = Task {
            await coordinator.waitForDecision(requestID: "request")
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        let newer = Task {
            await coordinator.waitForDecision(requestID: "request")
        }

        let olderValue = await older.value
        XCTAssertFalse(olderValue)

        await coordinator.resolve(requestID: "request", allowed: true)
        let newerValue = await newer.value
        XCTAssertTrue(newerValue)
    }

    func testDecisionTimeoutDeniesWaitingRequest() async throws {
        let coordinator = ChatToolAuthorizationCoordinator()
        let allowed = await coordinator.waitForDecision(
            requestID: "request",
            timeoutNanoseconds: 1_000_000
        )
        XCTAssertFalse(allowed)
    }

    func testCancelledTimeoutCannotResolveReplacementWithSameRequestID() async throws {
        let coordinator = ChatToolAuthorizationCoordinator()
        let first = Task {
            await coordinator.waitForDecision(
                requestID: "request",
                timeoutNanoseconds: 30_000_000
            )
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        await coordinator.cancelAll()
        let firstResult = await first.value
        XCTAssertFalse(firstResult)

        let replacement = Task {
            await coordinator.waitForDecision(
                requestID: "request",
                timeoutNanoseconds: 1_000_000_000
            )
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        await coordinator.resolve(requestID: "request", allowed: true)

        let replacementResult = await replacement.value
        XCTAssertTrue(replacementResult)
    }
}
