import XCTest
@testable import Voice_Chat

final class VoiceWorkSnapshotTests: XCTestCase {
    func testVoiceWorkIncludesRealtimePlaybackLoadingAndRequests() {
        XCTAssertTrue(snapshot(isRealtimeMode: true).hasVoiceWork)
        XCTAssertTrue(snapshot(isAudioLoading: true).hasVoiceWork)
        XCTAssertTrue(snapshot(isAudioPlaying: true).hasVoiceWork)
        XCTAssertTrue(snapshot(hasAudioRequests: true).hasVoiceWork)
        XCTAssertFalse(snapshot().hasVoiceWork)
    }

    func testListeningStartBlocksOnChatAndAudioWorkButAutoResumeOnlyBlocksOnAudio() {
        XCTAssertTrue(snapshot(isChatLoading: true).blocksListeningStart)
        XCTAssertTrue(snapshot(isChatPriming: true).blocksListeningStart)
        XCTAssertTrue(snapshot(isPlaybackRequested: true).blocksListeningStart)
        XCTAssertTrue(snapshot(isPlaybackRequested: true).hasActiveVoiceWork)
        XCTAssertFalse(snapshot(isChatLoading: true).blocksAutoResume)
        XCTAssertTrue(snapshot(isAudioPlaying: true).blocksAutoResume)
        XCTAssertTrue(snapshot(hasAudioRequests: true).blocksAutoResume)
        XCTAssertFalse(snapshot().blocksListeningStart)
    }

    func testPresentationPhaseCoversRequestPlaybackAndInterSegmentWaiting() {
        XCTAssertEqual(snapshot(isChatLoading: true).presentationPhase, .loading)
        XCTAssertEqual(
            snapshot(isAudioLoading: true, isPlaybackRequested: true).presentationPhase,
            .loading
        )
        XCTAssertEqual(
            snapshot(isAudioPlaying: true, isPlaybackRequested: true, hasAudioRequests: true).presentationPhase,
            .speaking
        )
        XCTAssertEqual(
            snapshot(isPlaybackRequested: true, hasAudioRequests: true).presentationPhase,
            .loading
        )
        XCTAssertEqual(snapshot().presentationPhase, .idle)
    }

    func testLoadingStallTimeoutUsesLongerTimeoutWhenAudioRequestsAreActive() {
        XCTAssertEqual(
            snapshot().loadingStallTimeout(defaultTimeout: 60, activeAudioRequestTimeout: 120),
            60
        )
        XCTAssertEqual(
            snapshot(hasAudioRequests: true).loadingStallTimeout(defaultTimeout: 60, activeAudioRequestTimeout: 120),
            120
        )
        XCTAssertEqual(
            snapshot(isWaitingForToolAuthorization: true).loadingStallTimeout(
                defaultTimeout: 60,
                activeAudioRequestTimeout: 120
            ),
            .infinity
        )
    }

    private func snapshot(
        isRealtimeMode: Bool = false,
        isAudioLoading: Bool = false,
        isAudioPlaying: Bool = false,
        isPlaybackRequested: Bool = false,
        hasAudioRequests: Bool = false,
        isChatLoading: Bool = false,
        isChatPriming: Bool = false,
        isWaitingForToolAuthorization: Bool = false
    ) -> VoiceWorkSnapshot {
        VoiceWorkSnapshot(
            isRealtimeMode: isRealtimeMode,
            isAudioLoading: isAudioLoading,
            isAudioPlaying: isAudioPlaying,
            isPlaybackRequested: isPlaybackRequested,
            hasAudioRequests: hasAudioRequests,
            isChatLoading: isChatLoading,
            isChatPriming: isChatPriming,
            isWaitingForToolAuthorization: isWaitingForToolAuthorization
        )
    }
}
