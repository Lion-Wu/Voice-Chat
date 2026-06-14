import XCTest
@testable import Voice_Chat

final class TTSRealtimeRequestQueueTests: XCTestCase {
    func testQueuesValidUnloadedUnskippedIndexesInOrder() {
        var queue = TTSRealtimeRequestQueue()

        XCTAssertTrue(queue.queue(index: 0, segmentCount: 3, loadedIndexes: [], skippedIndexes: []))
        XCTAssertTrue(queue.queue(index: 2, segmentCount: 3, loadedIndexes: [], skippedIndexes: []))

        XCTAssertEqual(queue.pendingIndexes, [0, 2])
    }

    func testRejectsInvalidLoadedAndSkippedIndexes() {
        var queue = TTSRealtimeRequestQueue()

        XCTAssertFalse(queue.queue(index: -1, segmentCount: 2, loadedIndexes: [], skippedIndexes: []))
        XCTAssertFalse(queue.queue(index: 2, segmentCount: 2, loadedIndexes: [], skippedIndexes: []))
        XCTAssertFalse(queue.queue(index: 0, segmentCount: 2, loadedIndexes: [0], skippedIndexes: []))
        XCTAssertFalse(queue.queue(index: 1, segmentCount: 2, loadedIndexes: [], skippedIndexes: [1]))

        XCTAssertTrue(queue.pendingIndexes.isEmpty)
    }

    func testDuplicateCanMoveToFrontWhenPrioritized() {
        var queue = TTSRealtimeRequestQueue(pendingIndexes: [0, 1, 2])

        XCTAssertFalse(queue.queue(index: 1, segmentCount: 3, loadedIndexes: [], skippedIndexes: []))
        XCTAssertEqual(queue.pendingIndexes, [0, 1, 2])

        XCTAssertTrue(queue.queue(index: 2, segmentCount: 3, loadedIndexes: [], skippedIndexes: [], atFront: true))
        XCTAssertEqual(queue.pendingIndexes, [2, 0, 1])
    }

    func testDequeueSkipsStaleIndexes() {
        var queue = TTSRealtimeRequestQueue(pendingIndexes: [9, -1, 1, 2])

        XCTAssertEqual(queue.dequeueNextValidIndex(segmentCount: 2), 1)
        XCTAssertEqual(queue.pendingIndexes, [2])
        XCTAssertNil(queue.dequeueNextValidIndex(segmentCount: 2))
        XCTAssertTrue(queue.pendingIndexes.isEmpty)
    }
}
