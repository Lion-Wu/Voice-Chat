//
//  GlobalAudioManager.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import Foundation
import AVFoundation
import Combine
import SwiftUI

struct TTSSynthesisConfiguration: Equatable {
    let serverAddress: String
    let url: URL
    let textLanguage: String
    let referenceAudioPath: String
    let promptText: String
    let promptLanguage: String
    let textSplitMethod: String
    let mediaType: String
    let usesStreamingSegments: Bool
}

@MainActor
final class GlobalAudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = GlobalAudioManager()

    // MARK: - Public State
    @Published var isShowingAudioPlayer: Bool = false
    @Published var isAudioPlaying: Bool = false
    @Published var isPlaybackRequested: Bool = false
    var currentTime: TimeInterval = 0 {
        didSet {
            guard abs(currentTime - oldValue) >= 0.0005 else { return }
            currentTimeSubject.send(currentTime)
        }
    }
    @Published var isLoading: Bool = false
    var isBuffering: Bool = false {
        didSet {
            guard isBuffering != oldValue else { return }
            isBufferingSubject.send(isBuffering)
        }
    }
    @Published var errorMessage: String?
    @Published var playbackNoticeMessage: String?
    var isRetrying: Bool = false {
        didSet {
            guard isRetrying != oldValue else { return }
            isRetryingSubject.send(isRetrying)
        }
    }
    var retryAttempt: Int = 0 {
        didSet {
            guard retryAttempt != oldValue else { return }
            retryAttemptSubject.send(retryAttempt)
        }
    }
    var retryLastError: String? = nil {
        didSet {
            guard retryLastError != oldValue else { return }
            retryLastErrorSubject.send(retryLastError)
        }
    }
    var totalDuration: TimeInterval = 0 {
        didSet {
            guard abs(totalDuration - oldValue) >= 0.0005 else { return }
            totalDurationSubject.send(totalDuration)
        }
    }
    var isPlaybackFullyLoaded: Bool = true {
        didSet {
            guard isPlaybackFullyLoaded != oldValue else { return }
            isPlaybackFullyLoadedSubject.send(isPlaybackFullyLoaded)
        }
    }

    // Realtime output level (0...1) for speaking animations.
    var outputLevel: Float = 0 {
        didSet {
            guard abs(outputLevel - oldValue) >= 0.0005 else { return }
            outputLevelSubject.send(outputLevel)
        }
    }
    private let currentTimeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let outputLevelSubject = CurrentValueSubject<Float, Never>(0)
    private let isBufferingSubject = CurrentValueSubject<Bool, Never>(false)
    private let isRetryingSubject = CurrentValueSubject<Bool, Never>(false)
    private let retryAttemptSubject = CurrentValueSubject<Int, Never>(0)
    private let retryLastErrorSubject = CurrentValueSubject<String?, Never>(nil)
    private let totalDurationSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let isPlaybackFullyLoadedSubject = CurrentValueSubject<Bool, Never>(true)

    var currentTimePublisher: AnyPublisher<TimeInterval, Never> {
        currentTimeSubject.eraseToAnyPublisher()
    }

    var outputLevelPublisher: AnyPublisher<Float, Never> {
        outputLevelSubject.eraseToAnyPublisher()
    }

    var isBufferingPublisher: AnyPublisher<Bool, Never> {
        isBufferingSubject.eraseToAnyPublisher()
    }

    var isRetryingPublisher: AnyPublisher<Bool, Never> {
        isRetryingSubject.eraseToAnyPublisher()
    }

    var retryAttemptPublisher: AnyPublisher<Int, Never> {
        retryAttemptSubject.eraseToAnyPublisher()
    }

    var retryLastErrorPublisher: AnyPublisher<String?, Never> {
        retryLastErrorSubject.eraseToAnyPublisher()
    }

    var totalDurationPublisher: AnyPublisher<TimeInterval, Never> {
        totalDurationSubject.eraseToAnyPublisher()
    }

    var isPlaybackFullyLoadedPublisher: AnyPublisher<Bool, Never> {
        isPlaybackFullyLoadedSubject.eraseToAnyPublisher()
    }

    // MARK: - Players & Timers
    var audioPlayer: AVAudioPlayer?
    var nextAudioPlayer: AVAudioPlayer?
    var audioDisplayDriver: AudioDisplayLinkDriver?

    // Watchdog
    var stallWatchdog: Timer?
    var lastObservedPlaybackTime: TimeInterval = 0
    var lastProgressTimestamp: Date = .init()

    // MARK: - Segmented Buffer
    var textSegments: [String] = []
    var audioChunks: [Data?] = []
    var chunkDurations: [TimeInterval] = []
    var skippedAudioChunkIndexes: Set<Int> = []

    var currentChunkIndex: Int = 0
    var currentPlayingIndex: Int = 0

    var dataTasks: [URLSessionDataTask] = []
    var inFlightIndexes: Set<Int> = []
    var ttsRetryTasks: [Int: Task<Void, Never>] = [:]
    var ttsRetryCounts: [Int: Int] = [:]
    var ttsRetryingIndexes: Set<Int> = []
    let ttsRetryPolicy = NetworkRetryPolicy(
        maxAttempts: 4,
        baseDelay: 0.6,
        maxDelay: 12.0,
        backoffFactor: 1.6,
        jitterRatio: 0.2
    )

    // MARK: - Seek State
    var seekTime: TimeInterval?
    var isSeeking: Bool = false

    // MARK: - Config
    let settingsManager = SettingsManager.shared
    private let errorCenter = AppErrorCenter.shared
    private var playbackNoticeDismissTask: Task<Void, Never>?
    var mediaType: String = "wav"
    var currentTTSConfiguration: TTSSynthesisConfiguration?

    // MARK: - Constants
    let endEpsilon: TimeInterval = 0.03

    // MARK: - Helpers
    private let segmentationWorker = TextSegmentationWorker.shared

    // Regenerated for every playback cycle to invalidate stale callbacks after cancellation.
    var currentGenerationID = UUID()

    // Track whether realtime streaming is active and whether the stream has been finalized.
    @Published private(set) var isRealtimeMode: Bool = false
    private var realtimeFinalized: Bool = false

    // Queue for realtime mode to ensure only one network request is in-flight at a time.
    var pendingRealtimeIndexes: [Int] = []

    // Dedicated URLSession for TTS requests so we can tune timeouts and cancellation without polluting shared state.
    lazy var ttsSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    func refreshPlaybackLoadState() {
        let hasTrackedAudioWork =
            !textSegments.isEmpty ||
            !audioChunks.isEmpty ||
            !inFlightIndexes.isEmpty ||
            !pendingRealtimeIndexes.isEmpty ||
            isLoading ||
            isRealtimeMode

        guard hasTrackedAudioWork else {
            isPlaybackFullyLoaded = true
            return
        }

        let hasMissingAudio = audioChunks.indices.contains { index in
            audioChunks[index] == nil && !skippedAudioChunkIndexes.contains(index)
        }
        let hasOutstandingRequests = !inFlightIndexes.isEmpty || !ttsRetryTasks.isEmpty

        if isRealtimeMode {
            isPlaybackFullyLoaded =
                realtimeFinalized &&
                !hasMissingAudio &&
                !hasOutstandingRequests &&
                pendingRealtimeIndexes.isEmpty
            return
        }

        if textSegments.isEmpty && audioChunks.isEmpty {
            isPlaybackFullyLoaded = !isLoading && !hasOutstandingRequests
            return
        }

        let hasQueuedSegments = currentChunkIndex < textSegments.count
        isPlaybackFullyLoaded =
            !hasMissingAudio &&
            !hasOutstandingRequests &&
            !hasQueuedSegments
    }

    // MARK: - Entry (Full-text mode)
    func startProcessing(text: String) {
        currentGenerationID = UUID()
        let generationID = currentGenerationID
        let configuration = makeTTSConfiguration(isRealtime: false)
        isRealtimeMode = false
        realtimeFinalized = false
        pendingRealtimeIndexes.removeAll()

        resetPlayer()
        currentTTSConfiguration = configuration
        withAnimation(.audioPlayerVisibility) {
            isShowingAudioPlayer = true
        }
        isLoading = true
        isPlaybackRequested = true
        isAudioPlaying = false
        currentTime = 0

        textSegments = []
        audioChunks = []
        chunkDurations = []
        totalDuration = 0
        currentChunkIndex = 0
        currentPlayingIndex = 0
        refreshPlaybackLoadState()

        guard let configuration else {
            isLoading = false
            isPlaybackRequested = false
            isAudioPlaying = false
            refreshPlaybackLoadState()
            surfaceTTSIssue(invalidTTSConfigurationMessage())
            return
        }

        let streamingEnabled = configuration.usesStreamingSegments
        let worker = segmentationWorker

        Task.detached(priority: .userInitiated) { [weak self] in
            let segments: [String]
            if streamingEnabled {
                segments = await worker.splitTextIntoMeaningfulSegments(text)
            } else {
                segments = [text]
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.currentGenerationID == generationID else { return }
                self.prepareSegmentsForPlayback(segments)
            }
        }
    }

    // MARK: - Realtime Pipeline
    /// Starts a realtime voice stream. Segments are appended later via `appendRealtimeSegment`.
    func startRealtimeStream() {
        currentGenerationID = UUID()
        let configuration = makeTTSConfiguration(isRealtime: true)
        isRealtimeMode = true
        realtimeFinalized = false
        pendingRealtimeIndexes.removeAll()

        resetPlayer()
        currentTTSConfiguration = configuration
        withAnimation(.audioPlayerVisibility) {
            isShowingAudioPlayer = true
        }
        isLoading = true
        isPlaybackRequested = true
        isAudioPlaying = false
        currentTime = 0

        textSegments = []
        audioChunks = []
        chunkDurations = []
        totalDuration = 0

        currentChunkIndex = 0
        currentPlayingIndex = 0
        refreshPlaybackLoadState()

        guard configuration != nil else {
            isLoading = false
            isPlaybackRequested = false
            isAudioPlaying = false
            refreshPlaybackLoadState()
            surfaceTTSIssue(invalidTTSConfigurationMessage())
            return
        }
    }

    /// Appends a segment to be converted to speech. Realtime mode enqueues the work, while
    /// regular mode sends it immediately.
    func appendRealtimeSegment(_ text: String) {
        guard isRealtimeMode else { return }
        guard currentTTSConfiguration != nil else {
            surfaceTTSIssue(invalidTTSConfigurationMessage())
            return
        }
        let idx = textSegments.count
        textSegments.append(text)
        audioChunks.append(nil)
        chunkDurations.append(0)
        refreshPlaybackLoadState()
        // In realtime mode enqueue the index so that only one request is active at a time.
        enqueueRealtimeIndex(idx)
    }

    /// Marks the realtime stream as complete. Playback ends naturally once all buffers finish.
    func finishRealtimeStream() {
        guard isRealtimeMode else { return }
        realtimeFinalized = true
        refreshPlaybackLoadState()
        // If every chunk has finished loading and playing, `finishPlayback()` will be triggered automatically.
        concludeRealtimeIfIdle()
    }

    // MARK: - Play/Pause
    func togglePlayback() {
        let playbackRequestedOrActive = isPlaybackRequested || isAudioPlaying

        if !playbackRequestedOrActive && playbackFinished() {
            currentPlayingIndex = 0
            currentTime = 0
        }

        if !playbackRequestedOrActive {
            // User requested playback.
            isPlaybackRequested = true
            if playbackFinished() {
                isPlaybackRequested = false
                isAudioPlaying = false
                return
            }
            if currentPlayingIndex < audioChunks.count {
                let didStart = playAudioChunk(at: currentPlayingIndex, fromTime: currentTime, shouldPlay: true)
                if isRealtimeMode {
                    // Consider playback active only after audio actually starts.
                    isAudioPlaying = didStart
                    isLoading = !didStart
                } else {
                    isAudioPlaying = didStart
                    if didStart { isLoading = false }
                }
            } else {
                isBuffering = true
                startStallWatchdog()
                isAudioPlaying = false
                if isRealtimeMode { isLoading = true }
            }
        } else {
            // Pause
            isPlaybackRequested = false
            isAudioPlaying = false
            audioPlayer?.pause()
            stopAudioTimer()
            startStallWatchdog()
            isBuffering = false
            isLoading = false
        }
    }

    // MARK: - Seek
    func forward15Seconds() { seek(to: currentTime + 15, shouldPlay: isPlaybackRequested || isAudioPlaying) }
    func backward15Seconds() { seek(to: currentTime - 15, shouldPlay: isPlaybackRequested || isAudioPlaying) }

    func seek(to time: TimeInterval, shouldPlay: Bool = false) {
        let maxKnown = max(totalDuration, startTime(forSegment: chunkDurations.count))
        guard maxKnown > 0.0005 else { return }

        var newT = time
        if maxKnown > 0 {
            newT = max(0, min(time, maxKnown))
        } else {
            newT = max(0, time)
        }
        currentTime = newT

        if allChunksLoaded() && currentTime >= totalDuration - endEpsilon {
            currentTime = totalDuration
            finishPlayback()
            return
        }

        let target = findSegmentIndex(for: newT)

        if target != currentPlayingIndex {
            audioPlayer?.stop()
            audioPlayer = nil
            currentPlayingIndex = target
        }

        if skippedAudioChunkIndexes.contains(target) {
            _ = playAudioChunk(at: target, fromTime: newT, shouldPlay: shouldPlay)
        } else if let chunkOpt = audioChunks[safe: target], let _ = chunkOpt {
            _ = playAudioChunk(at: target, fromTime: newT, shouldPlay: shouldPlay)
        } else {
            isBuffering = shouldPlay
            isSeeking = true
            seekTime = newT
            stopAudioTimer()
            startStallWatchdog()
            isPlaybackRequested = shouldPlay
            if shouldPlay { isAudioPlaying = false }
            if isRealtimeMode { isLoading = shouldPlay }
            if target < textSegments.count {
                if isRealtimeMode {
                    enqueueRealtimeIndex(target)
                } else if !inFlightIndexes.contains(target),
                          ttsRetryTasks[target] == nil {
                    sendTTSRequest(for: textSegments[target], index: target)
                }
            }
        }
    }

    // MARK: - Reset / Close
    func closeAudioPlayer() {
        resetPlayer()
        isPlaybackRequested = false
        isAudioPlaying = false
        withAnimation(.audioPlayerVisibility) {
            isShowingAudioPlayer = false
        }
        isLoading = false
        outputLevel = 0
        isRealtimeMode = false
        realtimeFinalized = false
        pendingRealtimeIndexes.removeAll()
    }

    func resetPlayer() {
        dataTasks.forEach { $0.cancel() }
        dataTasks.removeAll()
        inFlightIndexes.removeAll()
        pendingRealtimeIndexes.removeAll()
        ttsRetryTasks.values.forEach { $0.cancel() }
        ttsRetryTasks.removeAll()
        ttsRetryCounts.removeAll()
        ttsRetryingIndexes.removeAll()
        skippedAudioChunkIndexes.removeAll()
        isRetrying = false
        retryAttempt = 0
        retryLastError = nil
        playbackNoticeDismissTask?.cancel()
        playbackNoticeDismissTask = nil
        playbackNoticeMessage = nil
        currentTTSConfiguration = nil

        audioPlayer?.stop()
        audioPlayer = nil
        nextAudioPlayer?.stop()
        nextAudioPlayer = nil

        stopAudioTimer()
        stopStallWatchdog()

        textSegments.removeAll()
        audioChunks.removeAll()
        chunkDurations.removeAll()
        skippedAudioChunkIndexes.removeAll()
        totalDuration = 0

        currentChunkIndex = 0
        currentPlayingIndex = 0
        currentTime = 0
        isPlaybackRequested = false
        isAudioPlaying = false
        isBuffering = false
        isSeeking = false
        seekTime = nil
        isPlaybackFullyLoaded = true
        errorMessage = nil
        isRetrying = false
        retryAttempt = 0
        retryLastError = nil
        outputLevel = 0

        lastObservedPlaybackTime = 0
        lastProgressTimestamp = Date()
    }

    private func prepareSegmentsForPlayback(_ segments: [String]) {
        textSegments = segments
        let count = segments.count
        audioChunks = Array(repeating: nil, count: count)
        chunkDurations = Array(repeating: 0, count: count)
        skippedAudioChunkIndexes.removeAll()
        totalDuration = 0
        currentChunkIndex = 0
        currentPlayingIndex = 0
        refreshPlaybackLoadState()

        guard !segments.isEmpty else {
            isLoading = false
            isPlaybackRequested = false
            isAudioPlaying = false
            isPlaybackFullyLoaded = true
            return
        }
        sendNextSegment()
    }

    // MARK: - Realtime queue helpers (NEW)
    func queueRealtimeIndex(_ index: Int, atFront: Bool = false) {
        guard index >= 0, index < textSegments.count else { return }
        guard index >= audioChunks.count || audioChunks[index] == nil else {
            refreshPlaybackLoadState()
            return
        }
        guard !skippedAudioChunkIndexes.contains(index) else {
            refreshPlaybackLoadState()
            return
        }

        if let existing = pendingRealtimeIndexes.firstIndex(of: index) {
            if atFront && existing != pendingRealtimeIndexes.startIndex {
                pendingRealtimeIndexes.remove(at: existing)
                pendingRealtimeIndexes.insert(index, at: pendingRealtimeIndexes.startIndex)
            }
        } else if atFront {
            pendingRealtimeIndexes.insert(index, at: pendingRealtimeIndexes.startIndex)
        } else {
            pendingRealtimeIndexes.append(index)
        }
        refreshPlaybackLoadState()
    }

    func hasActiveRealtimeSynthesisWork() -> Bool {
        !inFlightIndexes.isEmpty || !ttsRetryTasks.isEmpty
    }

    func enqueueRealtimeIndex(_ index: Int) {
        guard index >= 0, index < textSegments.count else { return }
        if !isRealtimeMode {
            // Non-realtime mode sends the request immediately.
            sendTTSRequest(for: textSegments[index], index: index)
            return
        }
        let hasActiveWork = hasActiveRealtimeSynthesisWork()
        if !hasActiveWork && pendingRealtimeIndexes.isEmpty {
            sendTTSRequest(for: textSegments[index], index: index)
        } else {
            queueRealtimeIndex(index)
            if !hasActiveWork {
                processRealtimeQueueIfNeeded()
            }
        }
    }

    func processRealtimeQueueIfNeeded() {
        guard isRealtimeMode else { return }
        guard inFlightIndexes.isEmpty else { return }
        guard ttsRetryTasks.isEmpty else { return }
        guard !pendingRealtimeIndexes.isEmpty else { return }
        let next = pendingRealtimeIndexes.removeFirst()
        guard next < textSegments.count else {
            refreshPlaybackLoadState()
            processRealtimeQueueIfNeeded()
            return
        }
        sendTTSRequest(for: textSegments[next], index: next)
    }

    /// Ends realtime mode cleanly when no audio was produced or all work finished.
    func concludeRealtimeIfIdle() {
        guard isRealtimeMode, realtimeFinalized else { return }
        let noPending = inFlightIndexes.isEmpty && ttsRetryTasks.isEmpty && pendingRealtimeIndexes.isEmpty
        let hasAnyAudio = audioChunks.contains { $0 != nil }
        guard noPending else { return }

        if !hasAnyAudio {
            stopAudioTimer()
            stopStallWatchdog()
            isLoading = false
            isPlaybackRequested = false
            isAudioPlaying = false
            isPlaybackFullyLoaded = true
            withAnimation(.audioPlayerVisibility) {
                isShowingAudioPlayer = false
            }
            outputLevel = 0
            return
        }

        if playbackFinished() {
            isLoading = false
            finishPlayback()
        }
    }

    // MARK: - Error surfacing

    func surfaceTTSIssue(_ message: String, autoDismiss: TimeInterval = 10) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = trimmed
        errorCenter.publish(
            title: NSLocalizedString("TTS server unavailable", comment: "Shown when the TTS server cannot be reached or replied with an error"),
            message: trimmed,
            category: .tts,
            autoDismiss: autoDismiss
        )
    }

    func surfaceTTSNotice(_ message: String, autoDismiss: TimeInterval = 8) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playbackNoticeMessage = trimmed
        errorCenter.publish(
            title: NSLocalizedString("Voice Playback Issue", comment: "Fallback title when TTS or audio playback fails"),
            message: trimmed,
            category: isRealtimeMode ? .realtimeVoice : .tts,
            autoDismiss: autoDismiss
        )

        playbackNoticeDismissTask?.cancel()
        playbackNoticeDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(autoDismiss))
            await MainActor.run {
                guard self?.playbackNoticeMessage == trimmed else { return }
                self?.playbackNoticeMessage = nil
                self?.playbackNoticeDismissTask = nil
            }
        }
    }

    func formatTTSNetworkError(_ error: NSError, serverAddress: String? = nil) -> String {
        guard error.domain == NSURLErrorDomain else { return error.localizedDescription }
        let address = serverAddress ?? currentTTSConfiguration?.serverAddress ?? settingsManager.serverSettings.serverAddress
        let code = URLError.Code(rawValue: error.code)
        switch code {
        case .cannotConnectToHost, .cannotFindHost:
            return String(format: NSLocalizedString("Unable to connect to the TTS server at %@", comment: "Shown when the TTS host cannot be reached"), address)
        case .notConnectedToInternet:
            return NSLocalizedString("No internet connection for TTS requests.", comment: "Shown when the device is offline and TTS cannot be reached")
        case .networkConnectionLost:
            return NSLocalizedString("Connection to the TTS server was lost during playback.", comment: "Shown when the TTS stream drops mid-playback")
        case .timedOut:
            return NSLocalizedString("The TTS server did not respond in time.", comment: "Shown when the TTS request times out")
        default:
            return error.localizedDescription
        }
    }
}
