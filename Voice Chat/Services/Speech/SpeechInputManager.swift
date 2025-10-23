//
//  SpeechInputManager.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/20.
//

import Foundation
import Combine

@MainActor
final class SpeechInputManager: NSObject, ObservableObject {

    // MARK: - Language (two options only)
    enum DictationLanguage: String, CaseIterable, Identifiable {
        case zh = "zh-CN"
        case en = "en-US"
        var id: String { rawValue }
        var displayName: String { self == .zh ? "Chinese" : "English" }
        var locale: Locale { Locale(identifier: rawValue) }
    }

    // MARK: - Public State
    @Published private(set) var isRecording: Bool = false
    @Published var lastError: String?

    /// Exponentially-smoothed input level (0~1) used by the UI overlay.
    @Published var inputLevel: Double = 0

    /// Currently selected dictation language.
    @Published var currentLanguage: DictationLanguage = .zh

    // MARK: - Session bookkeeping
    private var currentSessionID: UUID?
    private var lastStableText: String = ""
    private var currentOnFinal: (@MainActor (String) -> Void)?

    // level smoothing
    private var levelEMA: Double = 0
    private let levelAlpha: Double = 0.20  // Smoothing factor for exponential averaging.

    // All AVAudioEngine / Speech objects are managed by an actor to keep access serialized.
    private let worker = SpeechRecognizerWorker()

    // MARK: - API

    /// Starts a dictation session.
    func startRecording(language: DictationLanguage? = nil,
                        onPartial: @escaping @MainActor (String) -> Void,
                        onFinal:   @escaping @MainActor (String) -> Void) async {
        lastError = nil

        // Stop any ongoing session before starting a new one.
        if isRecording { stopRecording() }

        guard await requestPermissions() else {
            lastError = NSLocalizedString("Speech recognition or microphone permission not granted", comment: "")
            return
        }

        let newID = UUID()
        currentSessionID = newID
        lastStableText   = ""
        currentOnFinal   = onFinal
        levelEMA         = 0
        inputLevel       = 0

        let pickLang = language ?? currentLanguage

        // The @Sendable closures hop back to the main actor to safely reference state.
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
                // Session finishes once a non-empty final result is delivered.
                self.isRecording       = false
                self.currentSessionID  = nil
                self.currentOnFinal    = nil
                self.inputLevel        = 0
                self.levelEMA          = 0
            }
        }

        // Normalize the level callback to the 0...1 range and smooth the value.
        let levelWrapper: @Sendable (Float) -> Void = { [weak self] raw in
            Task { @MainActor in
                guard let self else { return }
                // Empirically scale RMS values (typically 0.02~0.2) into 0...1.
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

    /// Stops the current dictation session. Safe to call from any thread.
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
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }

        #if os(iOS)
        let micOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
        return speechOK && micOK
        #else
        // macOS only exposes speech recognition permission; microphone prompts are handled by the system.
        return speechOK
        #endif
        #else
        lastError = NSLocalizedString("Speech input is not supported on this platform.", comment: "")
        return false
        #endif
    }
}

#if os(iOS) || os(macOS)

import Speech
import AVFoundation

// MARK: - Background recognizer worker (actor ensures serial access)
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
    /// Timestamp for the most recent detected voice activity; nil until speech is detected.
    private var lastSpeechAt : Date? = nil
    private var silenceLimit : TimeInterval = 1.2
    private var monitorTask  : Task<Void, Never>?

    // Energy threshold (linear amplitude, roughly -44 dB) tuned for voice sensitivity.
    private let vadLevelThreshold: Float = 0.006
    private var didEndAudioForSilence: Bool = false

    /// Grace period after receiving non-empty text during which silence will not end the session.
    private let postPartialGrace: TimeInterval = 0.6
    private var graceUntil: Date? = nil

    /// Time when the first non-empty text was produced, enforcing a minimum session duration.
    private var firstTextAt: Date? = nil
    /// Minimum active duration after the first text to avoid cutting off natural pauses.
    private let minActiveAfterFirstText: TimeInterval = 1.0

    /// Becomes true once any non-empty text is recognized, allowing silence-based termination.
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
                return NSLocalizedString("Speech recognition is unavailable (check network or system settings)", comment: "")
            case .engineStartFailed(let m):
                let template = NSLocalizedString("Unable to start audio input: %1$@", comment: "")
                return String(format: template, m)
            }
        }
    }

    // MARK: - Public ------------------------------------------------------------------

    func start(locale: Locale,
               onPartial: @Sendable @escaping (String) -> Void,
               onFinal  : @Sendable @escaping (String) -> Void,
               onLevel  : @Sendable @escaping (Float) -> Void) async throws
    {
        // Stop an existing session before starting a new one.
        if tapInstalled || request != nil || task != nil {
            await stop()
        }

        onPartialHandler   = onPartial
        onFinalHandler     = onFinal
        onLevelHandler     = onLevel
        lastNonEmptyText   = ""
        didEmitFinal       = false

        // Prevent silence-based termination until voice activity is detected.
        lastSpeechAt           = nil
        hasRecognizedText      = false
        didEndAudioForSilence  = false

        // 1) recognizer
        guard let r = SFSpeechRecognizer(locale: locale), r.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }
        recognizer = r

        // 2) Recognition request configured for dictation with automatic punctuation.
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

        // 6) Start monitoring for prolonged silence.
        launchSilenceMonitor()
    }

    /// Stops recognition and resets related resources.
    func stop(fallbackFinalText: String = "",
              onFinalOnMain: (@Sendable (String) -> Void)? = nil) async {

        // Emit the final callback if it has not been produced yet.
        if !didEmitFinal {
            let candidate = lastNonEmptyText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let cb = onFinalOnMain, !candidate.isEmpty {
                cb(candidate)
                didEmitFinal = true
            }
        }

        // Cancel the recognition task and remove the tap.
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

        // Reset the iOS audio session back to playback mode.
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

    /// Create a new recognition request and tap, allowing the session to restart without interruption.
    private func makeNewRequestAndTap() async throws {
        // Remove the previous tap if it exists.
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
            audioTap = nil
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Hint dictation to increase continuity and sensitivity for voice input.
        req.taskHint = .dictation
        // Enable automatic punctuation.
        req.addsPunctuation = true
        // Use the system default mode, leveraging the formatted string for punctuation.
        request = req

        let inputNode = audioEngine.inputNode
        let tap = AudioTap(request: req)
        tap.amplitudeHandler = { [weak self] level in
            guard let self else { return }
            Task { await self.handleAmplitude(level) }
        }
        // Let the system determine the appropriate format.
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
                    // Treat only non-empty text as final; otherwise restart listening.
                    if !txt.isEmpty {
                        Task {
                            await self.emitFinalIfNeeded(txt)
                            await self.stop()  // Triggers the upstream completion and UI cleanup
                        }
                    } else {
                        // Empty finals typically indicate timeouts or silence without recognition.
                        Task {
                            await self.handleEmptyFinalAndRestart()
                        }
                    }
                    return
                } else if !txt.isEmpty {
                    Task { await self.emitPartial(txt) }
                }
            }

            // Stop only when a real error occurs.
            if let _ = err {
                Task { await self.stop() }
            }
        }
    }

    // MARK: - Actor helpers ------------------------------------------------------------

    private func handleAmplitude(_ level: Float) {
        // Update UI levels and track voice activity without relying solely on energy thresholds.
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
        // Enter the grace period to avoid closing the microphone after a short pause.
        graceUntil = Date().addingTimeInterval(postPartialGrace)
        // Record the timestamp of the first text to enforce minimum duration.
        if firstTextAt == nil { firstTextAt = .now }
    }

    private func registerVoiceActivity(_ level: Float) {
        // Only record the timestamp to avoid prematurely ending due to early noise.
        if level >= vadLevelThreshold {
            lastSpeechAt = .now
        }
    }

    /// Restart listening if the recognizer ends with an empty final result.
    private func handleEmptyFinalAndRestart() async {
        // Restart only when silence did not intentionally end the session after text appeared.
        if didEndAudioForSilence {
            // If we intentionally ended the audio, stop instead of restarting.
            await stop()
            return
        }
        // Recreate the request and tap, then attach the task to keep the engine alive.
        do {
            try await makeNewRequestAndTap()
            attachRecognitionTask()
            // Preserve the recognition flag so silence rules remain intact.
        } catch {
            // If restart fails, stop gracefully.
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
        // Only end input based on silence after non-empty text has been produced.
        guard hasRecognizedText, let last = lastSpeechAt else { return }

        // Stay in the session while the grace period is active.
        if let g = graceUntil, Date() < g { return }

        // Enforce the minimum active duration.
        if let first = firstTextAt {
            let alive = Date().timeIntervalSince(first)
            if alive < minActiveAfterFirstText { return }
        }

        let elapsed = Date().timeIntervalSince(last)
        if elapsed > silenceLimit && !didEndAudioForSilence {
            // End audio input, allowing the recognizer to deliver its final result.
            request?.endAudio()
            didEndAudioForSilence = true
        }
    }
}

/// Appends audio buffers to the recognition request and reports volume levels.
final class AudioTap: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    var amplitudeHandler: (@Sendable (Float) -> Void)?

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func handle(buffer: AVAudioPCMBuffer) {
        request.append(buffer)

        // Compute RMS as the energy metric for any channel configuration.
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
