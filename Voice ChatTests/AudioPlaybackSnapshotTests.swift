import XCTest
@testable import Voice_Chat

@MainActor
final class AudioPlaybackSnapshotTests: XCTestCase {
    func testSnapshotSummarizesVoiceWork() {
        XCTAssertTrue(snapshot(isRealtimeMode: true).hasVoiceWork)
        XCTAssertTrue(snapshot(isLoading: true).hasVoiceWork)
        XCTAssertTrue(snapshot(isAudioPlaying: true).hasVoiceWork)
        XCTAssertTrue(snapshot(hasAudioRequests: true).hasVoiceWork)
        XCTAssertFalse(snapshot().hasVoiceWork)
    }

    func testManagerProjectsOnlyReadOnlyPlaybackFacts() throws {
        let manager = GlobalAudioManager()
        manager.audioChunks = [nil, Data([1])]
        manager.chunkDurations = [0, 0]

        XCTAssertTrue(manager.audioPlaybackSnapshot.hasLoadedAudioChunk)
        XCTAssertFalse(manager.audioPlaybackSnapshot.hasSeekableAudio)

        manager.chunkDurations = [0, 0.25]
        XCTAssertTrue(manager.audioPlaybackSnapshot.hasSeekableAudio)

        let url = try XCTUnwrap(URL(string: "https://example.com/audio.wav"))
        manager.dataTasks = [URLSession.shared.dataTask(with: url)]

        XCTAssertTrue(manager.audioPlaybackSnapshot.hasAudioRequests)
    }

    private func snapshot(
        isRealtimeMode: Bool = false,
        isLoading: Bool = false,
        isAudioPlaying: Bool = false,
        isPlaybackRequested: Bool = false,
        hasAudioRequests: Bool = false,
        hasLoadedAudioChunk: Bool = false,
        hasSeekableAudio: Bool = false
    ) -> AudioPlaybackSnapshot {
        AudioPlaybackSnapshot(
            isRealtimeMode: isRealtimeMode,
            isLoading: isLoading,
            isAudioPlaying: isAudioPlaying,
            isPlaybackRequested: isPlaybackRequested,
            hasAudioRequests: hasAudioRequests,
            hasLoadedAudioChunk: hasLoadedAudioChunk,
            hasSeekableAudio: hasSeekableAudio
        )
    }
}
