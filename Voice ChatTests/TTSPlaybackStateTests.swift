import XCTest
@testable import Voice_Chat

final class TTSPlaybackStateTests: XCTestCase {
    func testAllChunksLoadedTreatsSkippedChunksAsComplete() {
        let state = TTSPlaybackState(
            textSegmentCount: 3,
            audioChunkIsLoaded: [true, false, true],
            chunkDurations: [1, 1, 1],
            skippedAudioChunkIndexes: [1]
        )

        XCTAssertTrue(state.allChunksLoaded)
    }

    func testPlaybackFinishedHandlesZeroDurationCompletedBatch() {
        let state = TTSPlaybackState(
            textSegmentCount: 2,
            audioChunkIsLoaded: [false, false],
            chunkDurations: [0, 0],
            skippedAudioChunkIndexes: [0, 1],
            currentChunkIndex: 2,
            totalDuration: 0
        )

        XCTAssertTrue(state.playbackFinished)
    }

    func testSegmentTimingIgnoresNegativeDurationsAndFindsZeroDurationBoundary() {
        let state = TTSPlaybackState(
            textSegmentCount: 4,
            audioChunkIsLoaded: [true, true, true, true],
            chunkDurations: [1.5, -1, 0, 2],
            skippedAudioChunkIndexes: []
        )

        XCTAssertEqual(state.startTime(forSegment: 3), 1.5, accuracy: 0.0001)
        XCTAssertEqual(state.findSegmentIndex(for: 0.5), 0)
        XCTAssertEqual(state.findSegmentIndex(for: 1.5005), 1)
        XCTAssertEqual(state.findSegmentIndex(for: 1.6), 3)
    }

    func testPlaybackFullyLoadedTracksRealtimeFinalizationAndOutstandingRequests() {
        let pendingRealtime = TTSPlaybackState(
            textSegmentCount: 1,
            audioChunkIsLoaded: [true],
            chunkDurations: [1],
            skippedAudioChunkIndexes: [],
            currentChunkIndex: 1,
            isRealtimeMode: true,
            realtimeFinalized: false
        )
        XCTAssertFalse(pendingRealtime.isPlaybackFullyLoaded)

        let finalizedRealtime = TTSPlaybackState(
            textSegmentCount: 1,
            audioChunkIsLoaded: [true],
            chunkDurations: [1],
            skippedAudioChunkIndexes: [],
            currentChunkIndex: 1,
            isRealtimeMode: true,
            realtimeFinalized: true
        )
        XCTAssertTrue(finalizedRealtime.isPlaybackFullyLoaded)

        let queuedRequest = TTSPlaybackState(
            textSegmentCount: 0,
            audioChunkIsLoaded: [],
            chunkDurations: [],
            skippedAudioChunkIndexes: [],
            inFlightIndexes: [0]
        )
        XCTAssertFalse(queuedRequest.isPlaybackFullyLoaded)
    }

    func testRealtimePlaybackCannotFinishBeforeStreamFinalization() {
        let pendingRealtime = TTSPlaybackState(
            textSegmentCount: 1,
            audioChunkIsLoaded: [true],
            chunkDurations: [1],
            skippedAudioChunkIndexes: [],
            currentTime: 1,
            totalDuration: 1,
            isRealtimeMode: true,
            realtimeFinalized: false
        )
        let finalizedRealtime = TTSPlaybackState(
            textSegmentCount: 1,
            audioChunkIsLoaded: [true],
            chunkDurations: [1],
            skippedAudioChunkIndexes: [],
            currentTime: 1,
            totalDuration: 1,
            isRealtimeMode: true,
            realtimeFinalized: true
        )

        XCTAssertFalse(pendingRealtime.playbackFinished)
        XCTAssertFalse(pendingRealtime.playbackFinished(at: 1))
        XCTAssertTrue(finalizedRealtime.playbackFinished)
    }
}
