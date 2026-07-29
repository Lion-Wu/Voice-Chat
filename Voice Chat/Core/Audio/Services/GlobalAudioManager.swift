//
//  GlobalAudioManager.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import Foundation
import AVFoundation
import Combine

struct TTSSynthesisConfiguration: Equatable {
    let provider: TTSProvider
    let serverAddress: String
    let url: URL?
    let textLanguage: String
    let referenceAudioPath: String
    let promptText: String
    let promptLanguage: String
    let textSplitMethod: String
    let mediaType: String
    let usesStreamingSegments: Bool
    let appleSpeechVoiceIdentifier: String?

    init(
        serverAddress: String,
        url: URL,
        textLanguage: String,
        referenceAudioPath: String,
        promptText: String,
        promptLanguage: String,
        textSplitMethod: String,
        mediaType: String,
        usesStreamingSegments: Bool
    ) {
        self.provider = .gptSoVITS
        self.serverAddress = serverAddress
        self.url = url
        self.textLanguage = textLanguage
        self.referenceAudioPath = referenceAudioPath
        self.promptText = promptText
        self.promptLanguage = promptLanguage
        self.textSplitMethod = textSplitMethod
        self.mediaType = mediaType
        self.usesStreamingSegments = usesStreamingSegments
        self.appleSpeechVoiceIdentifier = nil
    }

    init(
        provider: TTSProvider,
        appleSpeechVoiceIdentifier: String?,
        usesStreamingSegments: Bool
    ) {
        precondition(provider.usesAppleSpeechSynthesizer)
        self.provider = provider
        self.serverAddress = ""
        self.url = nil
        self.textLanguage = ""
        self.referenceAudioPath = ""
        self.promptText = ""
        self.promptLanguage = ""
        self.textSplitMethod = ""
        self.mediaType = "caf"
        self.usesStreamingSegments = usesStreamingSegments
        self.appleSpeechVoiceIdentifier = appleSpeechVoiceIdentifier
    }
}

@MainActor
final class GlobalAudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
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
            outputLevelSubject.send(outputLevel)
        }
    }
    var outputAudioLevels = VoiceAudioLevels.silent {
        didSet {
            outputMotionAudioSource.store(outputAudioLevels)
        }
    }
    let outputMotionAudioSource = VoiceAudioLevelStore()
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
    var audioMotionTimelines: [VoiceAudioTimeline?] = []
    var chunkDurations: [TimeInterval] = []
    var skippedAudioChunkIndexes: Set<Int> = []

    var currentChunkIndex: Int = 0
    var currentPlayingIndex: Int = 0

    var activeDataTasks: [UUID: URLSessionDataTask] = [:]
    var activeAppleSpeechSessions: [UUID: AppleSpeechSynthesisSession] = [:]
    var inFlightIndexes: Set<Int> = []
    var ttsRetryTasks: [Int: Task<Void, Never>] = [:]
    var ttsRetryState = TTSRequestRetryState()
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
    private let ttsSettingsSnapshotProvider: @MainActor () -> TTSSettingsSnapshot
    private let noticePublisher: any AppNoticePublishing
    var playbackNoticeDismissTask: Task<Void, Never>?
    var mediaType: String = "wav"
    var currentTTSConfiguration: TTSSynthesisConfiguration?

    // MARK: - Constants
    let endEpsilon: TimeInterval = 0.03

    // MARK: - Helpers
    let segmentationWorker = TextSegmentationWorker.shared

    // Regenerated for every playback cycle to invalidate stale callbacks after cancellation.
    var currentGenerationID = UUID()

    // Track whether realtime streaming is active and whether the stream has been finalized.
    @Published var isRealtimeMode: Bool = false
    var realtimeFinalized: Bool = false

    // Queue for realtime mode to ensure only one network request is in-flight at a time.
    var realtimeRequestQueue = TTSRealtimeRequestQueue()
    var pendingRealtimeIndexes: [Int] {
        realtimeRequestQueue.pendingIndexes
    }

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

    init(
        ttsSettingsSnapshotProvider: @escaping @MainActor () -> TTSSettingsSnapshot = {
            TTSSettingsSnapshot.defaults
        },
        noticePublisher: any AppNoticePublishing = NoopAppNoticePublisher.shared
    ) {
        self.ttsSettingsSnapshotProvider = ttsSettingsSnapshotProvider
        self.noticePublisher = noticePublisher
        super.init()
    }

    func currentTTSSettingsSnapshot() -> TTSSettingsSnapshot {
        ttsSettingsSnapshotProvider()
    }

    func refreshPlaybackLoadState() {
        isPlaybackFullyLoaded = TTSPlaybackState(
            textSegmentCount: textSegments.count,
            audioChunkIsLoaded: audioChunks.map { $0 != nil },
            chunkDurations: chunkDurations,
            skippedAudioChunkIndexes: skippedAudioChunkIndexes,
            currentChunkIndex: currentChunkIndex,
            currentTime: currentTime,
            totalDuration: totalDuration,
            endEpsilon: endEpsilon,
            isLoading: isLoading,
            isRealtimeMode: isRealtimeMode,
            realtimeFinalized: realtimeFinalized,
            inFlightIndexes: inFlightIndexes,
            retryingIndexes: Set(ttsRetryTasks.keys),
            pendingRealtimeIndexes: pendingRealtimeIndexes
        ).isPlaybackFullyLoaded
    }

    // MARK: - Realtime queue helpers (NEW)
    func queueRealtimeIndex(_ index: Int, atFront: Bool = false) {
        realtimeRequestQueue.queue(
            index: index,
            segmentCount: textSegments.count,
            loadedIndexes: loadedAudioChunkIndexes(),
            skippedIndexes: skippedAudioChunkIndexes,
            atFront: atFront
        )
        refreshPlaybackLoadState()
    }

    private func loadedAudioChunkIndexes() -> Set<Int> {
        Set(audioChunks.indices.filter { audioChunks[$0] != nil })
    }

    func hasActiveRealtimeSynthesisWork() -> Bool {
        !inFlightIndexes.isEmpty || !ttsRetryTasks.isEmpty
    }

    func hasPendingTTSSynthesisWork() -> Bool {
        !inFlightIndexes.isEmpty ||
            !ttsRetryTasks.isEmpty ||
            (isRealtimeMode && !realtimeRequestQueue.isEmpty)
    }

    func clearRealtimeRequestQueue() {
        realtimeRequestQueue.removeAll()
        refreshPlaybackLoadState()
    }

    func enqueueRealtimeIndex(_ index: Int) {
        guard index >= 0, index < textSegments.count else { return }
        if !isRealtimeMode {
            // Non-realtime mode sends the request immediately.
            sendTTSRequest(for: textSegments[index], index: index)
            return
        }
        let hasActiveWork = hasActiveRealtimeSynthesisWork()
        if !hasActiveWork && realtimeRequestQueue.isEmpty {
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
        guard let next = realtimeRequestQueue.dequeueNextValidIndex(segmentCount: textSegments.count) else {
            refreshPlaybackLoadState()
            return
        }
        sendTTSRequest(for: textSegments[next], index: next)
    }

    /// Ends realtime mode cleanly when no audio was produced or all work finished.
    func concludeRealtimeIfIdle() {
        guard isRealtimeMode, realtimeFinalized else { return }
        let noPending = !hasPendingTTSSynthesisWork()
        let hasAnyAudio = audioChunks.contains { $0 != nil }
        guard noPending else { return }

        if !hasAnyAudio {
            stopAudioTimer()
            stopStallWatchdog()
            isLoading = false
            isPlaybackRequested = false
            isAudioPlaying = false
            isPlaybackFullyLoaded = true
            isShowingAudioPlayer = false
            outputAudioLevels = .silent
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
        let title: String
        if currentTTSConfiguration?.provider == .personalVoice {
            title = NSLocalizedString("Apple Personal Voice unavailable", comment: "Shown when Apple Personal Voice synthesis fails")
        } else if currentTTSConfiguration?.provider == .appleSpeech {
            title = NSLocalizedString("Apple Speech unavailable", comment: "Shown when Apple's built-in speech synthesis fails")
        } else {
            title = NSLocalizedString("TTS server unavailable", comment: "Shown when the TTS server cannot be reached or replied with an error")
        }
        noticePublisher.publish(
            title: title,
            message: trimmed,
            category: .tts,
            autoDismiss: autoDismiss
        )
    }

    func surfaceTTSNotice(_ message: String, autoDismiss: TimeInterval = 8) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playbackNoticeMessage = trimmed
        noticePublisher.publish(
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
        let address = serverAddress ?? currentTTSConfiguration?.serverAddress ?? currentTTSSettingsSnapshot().serverAddress
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

    func applyTTSAutoRetryPublishedState(_ state: TTSAutoRetryPublishedState) {
        isRetrying = state.isRetrying
        retryAttempt = state.retryAttempt
        retryLastError = state.retryLastError
    }
}
