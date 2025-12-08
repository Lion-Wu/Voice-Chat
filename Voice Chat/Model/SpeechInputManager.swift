//
//  SpeechInputManager.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/20.
//

#if os(iOS) || os(macOS)

import Foundation
import Combine

@MainActor
final class SpeechInputManager: NSObject, ObservableObject {
    static let shared = SpeechInputManager()

    // MARK: - Language (two options only)
    enum DictationLanguage: String, CaseIterable, Identifiable {
        case english = "en-US"
        case simplifiedChinese = "zh-CN"
        case traditionalChinese = "zh-TW"
        case japanese = "ja-JP"

        var id: String { rawValue }

        var defaultDisplayName: String {
            switch self {
            case .english:
                return NSLocalizedString("English", comment: "Dictation language")
            case .simplifiedChinese:
                return NSLocalizedString("Simplified Chinese", comment: "Dictation language")
            case .traditionalChinese:
                return NSLocalizedString("Traditional Chinese", comment: "Dictation language")
            case .japanese:
                return NSLocalizedString("Japanese", comment: "Dictation language")
            }
        }

        var locale: Locale { Locale(identifier: rawValue) }
    }

    // MARK: - Public State
    @Published private(set) var isRecording: Bool = false
    @Published var lastError: String?

    /// Realtime input loudness (0...1) with exponential smoothing for UI animations.
    @Published var inputLevel: Double = 0

    /// Currently selected dictation language.
    @Published var currentLanguage: DictationLanguage = .english

    // MARK: - Session bookkeeping
    private var currentSessionID: UUID?
    private var lastStableText: String = ""
    private var currentOnFinal: (@MainActor (String) -> Void)?

    // level smoothing
    private var levelEMA: Double = 0
    private let levelAlpha: Double = 0.20  // Smoothing factor.

    // All AVAudioEngine/SFSpeech objects are managed serially by the worker actor.
    private let worker = SpeechRecognizerWorker()

    // MARK: - API

    /// Starts realtime dictation.
    func startRecording(language: DictationLanguage? = nil,
                        onPartial: @escaping @MainActor (String) -> Void,
                        onFinal:   @escaping @MainActor (String) -> Void) async {
        lastError = nil

        // Stop any active recording before starting a new session.
        if isRecording { stopRecording() }

        guard await requestPermissions() else {
            lastError = NSLocalizedString("Speech recognition or microphone permission not granted", comment: "Shown when the app lacks microphone or speech recognition access")
            return
        }

        let newID = UUID()
        currentSessionID = newID
        lastStableText   = ""
        currentOnFinal   = onFinal
        levelEMA         = 0
        inputLevel       = 0

        let pickLang = language ?? currentLanguage

        // Ensure `@Sendable` closures hop back to the main actor before touching state.
        let partialWrapper: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                guard self.currentSessionID == newID else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                self.lastStableText = trimmed
                onPartial(trimmed)
            }
        }

        let finalWrapper: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor in
                guard let self else { return }
                guard self.currentSessionID == newID else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.lastStableText = trimmed
                onFinal(trimmed)
                // Session ends once non-empty text has been produced.
                self.isRecording       = false
                self.currentSessionID  = nil
                self.currentOnFinal    = nil
                self.inputLevel        = 0
                self.levelEMA          = 0
            }
        }

        // Audio level callback: scale and smooth into a 0...1 range.
        let levelWrapper: @Sendable (Float) -> Void = { [weak self] raw in
            Task { @MainActor in
                guard let self else { return }
                // Empirically scale RMS energy (typically 0.02-0.2) into 0...1.
                let scaled = min(1.0, max(0.0, Double(raw) * 8.0))
                self.levelEMA = self.levelEMA * (1 - self.levelAlpha) + scaled * self.levelAlpha
                self.inputLevel = self.levelEMA
            }
        }

        do {
            try await worker.start(
                locale: pickLang.locale,
                onPartial: partialWrapper,
                onFinal:   finalWrapper,
                onLevel:   levelWrapper
            )
            isRecording = true
        } catch {
            lastError = error.localizedDescription
            await worker.stop()
            isRecording = false
            currentSessionID = nil
            currentOnFinal   = nil
            inputLevel       = 0
            levelEMA         = 0
        }
    }

    /// Ends recording proactively (safe to call from any thread).
    nonisolated func stopRecording() {
        Task { [weak self] in
            guard let self else { return }

            let capturedID     = await self.currentSessionID
            let capturedFinal  = await self.currentOnFinal
            let capturedStable = await self.lastStableText

            await self.worker.stop(
                fallbackFinalText: capturedStable,
                onFinalOnMain: { text in
                    Task { @MainActor in
                        if self.currentSessionID == capturedID,
                           let f = capturedFinal,
                           !text.isEmpty {
                            f(text)
                        }
                    }
                })

            await MainActor.run {
                self.isRecording      = false
                self.currentSessionID = nil
                self.currentOnFinal   = nil
                self.inputLevel       = 0
                self.levelEMA         = 0
            }
        }
    }

    // MARK: - Permissions

    private func requestPermissions() async -> Bool {
        #if os(iOS) || os(macOS)
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            // TCC may invoke the callback on a background queue; detach to avoid tripping
            // main-actor isolation checks in Swift 6 and hop back only to resume.
            Task.detached {
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }
        }

        #if os(iOS)
        let micOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            Task.detached {
                AVAudioApplication.requestRecordPermission { ok in
                    cont.resume(returning: ok)
                }
            }
        }
        return speechOK && micOK
        #else
        // macOS exposes only speech recognition permission; microphone prompts are system-driven.
        return speechOK
        #endif
        #else
        lastError = NSLocalizedString("Speech input is not supported on this platform.", comment: "Shown when speech input is unavailable for the current OS")
        return false
        #endif
    }
}

#if os(iOS) || os(macOS)

import Speech
import AVFoundation

// MARK: - Background recognition worker (actor ensures serialization)
actor SpeechRecognizerWorker {

    // MARK: - Internal objects
    private let audioEngine = AVAudioEngine()
    private var request : SFSpeechAudioBufferRecognitionRequest?
    private var task    : SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    private var tapInstalled = false
    private var audioTap: AudioTap?

    // MARK: - Callbacks
    private var onPartialHandler: (@Sendable (String) -> Void)?
    private var onFinalHandler  : (@Sendable (String) -> Void)?
    private var onLevelHandler  : (@Sendable (Float) -> Void)?

    // MARK: - End-of-speech detection
    /// Timestamp of the most recent detected speech activity; remains nil until speech is detected.
    private var lastSpeechAt : Date? = nil
    private var silenceLimit : TimeInterval = 1.2
    private var monitorTask  : Task<Void, Never>?

    // Energy threshold (linear amplitude, roughly -44 dB). Lower values make voice detection more sensitive.
    private let vadLevelThreshold: Float = 0.006
    private var didEndAudioForSilence: Bool = false

    /// Grace period after non-empty text is recognized; silence will not end the session during this window.
    private let postPartialGrace: TimeInterval = 0.6
    private var graceUntil: Date? = nil

    /// Timestamp of the first non-empty transcript; used to guarantee a minimum session length.
    private var firstTextAt: Date? = nil
    /// Minimum time to keep the session open after the first text to avoid clipping natural pauses.
    private let minActiveAfterFirstText: TimeInterval = 1.0

    /// Silence-based termination is allowed only after producing non-empty text.
    private var hasRecognizedText: Bool = false

    // MARK: - Misc state
    private var lastNonEmptyText: String = ""
    private var didEmitFinal   : Bool = false

    enum SpeechError: LocalizedError {
        case recognizerUnavailable
        case engineStartFailed(String)
        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return NSLocalizedString("Speech recognition is unavailable. Check network connectivity and system settings.", comment: "Speech recognition unavailable error")
            case .engineStartFailed(let m):
                return String(format: NSLocalizedString("Audio engine failed to start: %@", comment: "Audio engine start failure"), m)
            }
        }
    }

    // MARK: - Public ------------------------------------------------------------------

    func start(locale: Locale,
               onPartial: @Sendable @escaping (String) -> Void,
               onFinal  : @Sendable @escaping (String) -> Void,
               onLevel  : @Sendable @escaping (Float) -> Void) async throws
    {
        // Stop any existing session before starting a new one.
        if tapInstalled || request != nil || task != nil {
            await stop()
        }

        onPartialHandler   = onPartial
        onFinalHandler     = onFinal
        onLevelHandler     = onLevel
        lastNonEmptyText   = ""
        didEmitFinal       = false

        // Important: silence cannot end the session until real speech has been heard.
        lastSpeechAt           = nil
        hasRecognizedText      = false
        didEndAudioForSilence  = false

        // 1) recognizer
        guard let r = SFSpeechRecognizer(locale: locale), r.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }
        recognizer = r

        // 2) Build the request (using the default mode with system auto-punctuation).
        try await makeNewRequestAndTap()

        // 3) Configure the iOS audio session.
        #if os(iOS)
        try await MainActor.run {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                    mode: .voiceChat,
                                    options: [.duckOthers,
                                              .defaultToSpeaker,
                                              .allowBluetoothA2DP,
                                              .allowBluetoothHFP])
            try session.setActive(true, options: [])
        }
        #endif

        // 4) Start the audio engine.
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw SpeechError.engineStartFailed(error.localizedDescription)
        }

        // 5) recognition task
        attachRecognitionTask()

        // 6) Begin silence monitoring.
        launchSilenceMonitor()
    }

    /// Stops recognition and releases resources.
    func stop(fallbackFinalText: String = "",
              onFinalOnMain: (@Sendable (String) -> Void)? = nil) async {

        // If no final result has been emitted, use the caller-provided fallback or the last non-empty text.
        if !didEmitFinal {
            let trimmedFallback = fallbackFinalText.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidateSource = trimmedFallback.isEmpty ? lastNonEmptyText : trimmedFallback
            let candidate = candidateSource.trimmingCharacters(in: .whitespacesAndNewlines)
            if let cb = onFinalOnMain, !candidate.isEmpty {
                cb(candidate)
                didEmitFinal = true
            }
        }

        // Tear down the recognition task and audio tap.
        task?.cancel()
        task = nil

        request?.endAudio()
        request = nil

        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
            audioTap = nil
        }

        if audioEngine.isRunning { audioEngine.stop() }

        // On iOS restore the default audio session category.
        #if os(iOS)
        try? await MainActor.run {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(false, options: [])
        }
        #endif

        recognizer        = nil
        onPartialHandler  = nil
        onFinalHandler    = nil
        onLevelHandler    = nil

        monitorTask?.cancel()
        monitorTask = nil

        didEndAudioForSilence = false
        hasRecognizedText = false
        lastSpeechAt = nil
    }

    // MARK: - Internal setup helpers ---------------------------------------------------

    /// Creates a new request and tap. Reused when empty finals arrive so the session can continue.
    private func makeNewRequestAndTap() async throws {
        // Remove any existing tap.
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
            audioTap = nil
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Configure for continuous dictation to improve sensitivity and continuity.
        req.taskHint = .dictation
        // Enable automatic punctuation.
        req.addsPunctuation = true
        // Rely on the system default mode with automatic punctuation (formattedString).
        request = req

        let inputNode = audioEngine.inputNode
        let tap = AudioTap(request: req)
        tap.amplitudeHandler = { [weak self] level in
            guard let self else { return }
            Task { await self.handleAmplitude(level) }
        }
        // Let the system pick a suitable audio format by passing nil.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [tap] buffer, _ in
            tap.handle(buffer: buffer)
        }
        audioTap = tap
        tapInstalled = true
    }

    /// Establishes the recognition task.
    private func attachRecognitionTask() {
        guard let recognizer, let req = request else { return }
        task = recognizer.recognitionTask(with: req) { [weak self] result, err in
            guard let self else { return }

            if let r = result {
                let txt = r.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !txt.isEmpty {
                    Task { await self.updateLastTextAndActivity(txt) }
                }

                if r.isFinal {
                    // Only treat non-empty transcripts as final; restart otherwise.
                    if !txt.isEmpty {
                        Task {
                            await self.emitFinalIfNeeded(txt)
                            await self.stop()  // Triggers the outer layer to complete and update the UI.
                        }
                    } else {
                        // Empty finals usually mean a timeout or silence; restart the capture loop.
                        Task {
                            await self.handleEmptyFinalAndRestart()
                        }
                    }
                    return
                } else if !txt.isEmpty {
                    Task { await self.emitPartial(txt) }
                }
            }

            // Only stop the entire pipeline on actual errors.
            if let _ = err {
                Task { await self.stop() }
            }
        }
    }

    // MARK: - Actor helpers ------------------------------------------------------------

    private func handleAmplitude(_ level: Float) {
        // Used only for UI level display and tracking the first activity timestamp; silence detection no longer depends on raw energy.
        registerVoiceActivity(level)
        onLevelHandler?(level)
    }

    private func emitPartial(_ text: String) {
        onPartialHandler?(text)
    }

    private func emitFinalIfNeeded(_ text: String) {
        guard !didEmitFinal else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        didEmitFinal = true
        onFinalHandler?(text)
    }

    private func updateLastTextAndActivity(_ text: String) {
        lastNonEmptyText = text
        hasRecognizedText = true
        lastSpeechAt = .now
        // Enter the grace period so short pauses after new text do not cut off the session.
        graceUntil = Date().addingTimeInterval(postPartialGrace)
        // Record the first-text timestamp to enforce the minimum session length.
        if firstTextAt == nil { firstTextAt = .now }
    }

    private func registerVoiceActivity(_ level: Float) {
        // Track only the timestamps to avoid ending the session early due to background noise.
        if level >= vadLevelThreshold {
            lastSpeechAt = .now
        }
    }

    /// When an empty final result arrives, restart recognition instead of ending the session.
    private func handleEmptyFinalAndRestart() async {
        // Only restart if the session wasn't intentionally ended due to silence after valid text.
        if didEndAudioForSilence {
            // This final was triggered by our own `endAudio`; conservatively stop entirely.
            await stop()
            return
        }
        // Recreate the request/tap and attach a new task to keep the engine running.
        do {
            try await makeNewRequestAndTap()
            attachRecognitionTask()
            // Preserve `hasRecognizedText`; silence-based ending still requires prior text.
        } catch {
        // If restarting fails, fall back to fully stopping the session.
            await stop()
        }
    }

    // MARK: - End-of-speech silence monitor

    private func launchSilenceMonitor() {
        monitorTask?.cancel()
        monitorTask = Task.detached { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                await self.checkSilenceTimeout()
            }
        }
    }

    private func checkSilenceTimeout() {
        guard !didEmitFinal else { return }
        // Only consider silence termination after producing non-empty text.
        guard hasRecognizedText, let last = lastSpeechAt else { return }

        // Stay active during the grace period to avoid clipping natural pauses.
        if let g = graceUntil, Date() < g { return }

        // Enforce the minimum session length measured from the first recognized text.
        if let first = firstTextAt {
            let alive = Date().timeIntervalSince(first)
            if alive < minActiveAfterFirstText { return }
        }

        let elapsed = Date().timeIntervalSince(last)
        if elapsed > silenceLimit && !didEndAudioForSilence {
            // End audio so the recognizer can produce the final result now that text is available.
            request?.endAudio()
            didEndAudioForSilence = true
        }
    }
}

/// Feeds audio buffers into the recognition request and reports amplitude (Sendable for actor safety).
final class AudioTap: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    var amplitudeHandler: (@Sendable (Float) -> Void)?

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func handle(buffer: AVAudioPCMBuffer) {
        request.append(buffer)

        // Compute RMS energy (supports mono and multi-channel input).
        var rms: Float = 0
        if let chan = buffer.floatChannelData {
            let frames = Int(buffer.frameLength)
            if frames > 0 {
                var sum: Float = 0
                let channels = Int(buffer.format.channelCount)
                for c in 0..<channels {
                    let ptr = chan[c]
                    var i = 0
                    while i < frames {
                        let s = ptr[i]
                        sum += s * s
                        i += 1
                    }
                }
                rms = sqrt(sum / Float(frames * max(1, channels)))
            }
        }
        amplitudeHandler?(rms)
    }
}

#endif

#else

import Foundation
import Combine

@MainActor
final class SpeechInputManager: ObservableObject {
    static let shared = SpeechInputManager()

    enum DictationLanguage: String, CaseIterable, Identifiable {
        case english = "en-US"
        case simplifiedChinese = "zh-CN"
        case traditionalChinese = "zh-TW"
        case japanese = "ja-JP"

        var id: String { rawValue }
        var defaultDisplayName: String { "Unavailable" }
        var locale: Locale { Locale(identifier: rawValue) }
    }

    @Published private(set) var isRecording: Bool = false
    @Published var lastError: String? = NSLocalizedString("Speech input is not supported on this platform.", comment: "Shown when speech input is unavailable")
    @Published var inputLevel: Double = 0
    @Published var currentLanguage: DictationLanguage = .english

    func startRecording(language: DictationLanguage? = nil,
                        onPartial: @escaping @MainActor (String) -> Void,
                        onFinal:   @escaping @MainActor (String) -> Void) async {
        lastError = NSLocalizedString("Speech input is not supported on this platform.", comment: "Shown when speech input is unavailable")
    }

    nonisolated func stopRecording() {}
}

#endif
