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
        var displayName: String {
            switch self {
            case .zh:
                return String(localized: "dictation.language.chinese")
            case .en:
                return String(localized: "dictation.language.english")
            }
        }
        var locale: Locale { Locale(identifier: rawValue) }
    }

    // MARK: - Public State
    @Published private(set) var isRecording: Bool = false
    @Published var lastError: String?

    /// Smoothed input level (0...1) used to drive the overlay visuals.
    @Published var inputLevel: Double = 0

    /// Currently selected dictation language.
    @Published var currentLanguage: DictationLanguage = .zh

    // MARK: - Session bookkeeping
    private var currentSessionID: UUID?
    private var lastStableText: String = ""
    private var currentOnFinal: (@MainActor (String) -> Void)?

    // level smoothing
    private var levelEMA: Double = 0
    private let levelAlpha: Double = 0.20  // Smoothing coefficient.

    // Worker actor serializes all AVAudioEngine and Speech framework interactions.
    private let worker = SpeechRecognizerWorker()

    // MARK: - API

    /// Starts real-time dictation.
    func startRecording(language: DictationLanguage? = nil,
                        onPartial: @escaping @MainActor (String) -> Void,
                        onFinal:   @escaping @MainActor (String) -> Void) async {
        lastError = nil

        // Stop any previous session before starting a new one.
        if isRecording { stopRecording() }

        guard await requestPermissions() else {
            lastError = String(localized: "dictation.permission.denied")
            return
        }

        let newID = UUID()
        currentSessionID = newID
        lastStableText   = ""
        currentOnFinal   = onFinal
        levelEMA         = 0
        inputLevel       = 0

        let pickLang = language ?? currentLanguage

        // Ensure callbacks hop back to the main actor before touching observable state.
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
                // End the session only after non-empty text is delivered.
                self.isRecording       = false
                self.currentSessionID  = nil
                self.currentOnFinal    = nil
                self.inputLevel        = 0
                self.levelEMA          = 0
            }
        }

        // Smooth the audio level to stay within 0...1.
        let levelWrapper: @Sendable (Float) -> Void = { [weak self] raw in
            Task { @MainActor in
                guard let self else { return }
                // Empirically scale the RMS value into a 0...1 range.
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

    /// Stops dictation from any thread.
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
        // macOS handles microphone permission automatically via system prompts.
        return speechOK
        #endif
        #else
        lastError = String(localized: "dictation.unsupportedPlatform")
        return false
        #endif
    }
}

#if os(iOS) || os(macOS)

import Speech
import AVFoundation

// MARK: - Background recognizer worker (actor for serialization)
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
    /// Last time speech activity was detected; nil until the first spoken word.
    private var lastSpeechAt : Date? = nil
    private var silenceLimit : TimeInterval = 1.2
    private var monitorTask  : Task<Void, Never>?

    // Energy threshold tuned for conversational voice detection.
    private let vadLevelThreshold: Float = 0.006
    private var didEndAudioForSilence: Bool = false

    /// Grace period after detecting text to avoid prematurely ending the session.
    private let postPartialGrace: TimeInterval = 0.6
    private var graceUntil: Date? = nil

    /// Timestamp of the first recognized text to guarantee a minimum session length.
    private var firstTextAt: Date? = nil
    /// Required active duration after the first transcription to avoid truncating pauses.
    private let minActiveAfterFirstText: TimeInterval = 1.0

    /// Tracks whether non-empty text has been recognized so silence can end the session.
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
                return String(localized: "dictation.error.recognizerUnavailable")
            case .engineStartFailed(let message):
                return String(format: String(localized: "dictation.error.engineStartFailed"), locale: Locale.current, message)
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

        // Reset silence tracking so the session does not end immediately.
        lastSpeechAt           = nil
        hasRecognizedText      = false
        didEndAudioForSilence  = false

        // 1) Recognizer
        guard let r = SFSpeechRecognizer(locale: locale), r.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }
        recognizer = r

        // 2) Recognition request configured for continuous dictation with automatic punctuation.
        try await makeNewRequestAndTap()

        // 3) iOS audio session configuration.
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

        // 4) Prepare and start the audio engine.
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw SpeechError.engineStartFailed(error.localizedDescription)
        }

        // 5) Recognition task.
        attachRecognitionTask()

        // 6) Launch the silence monitor.
        launchSilenceMonitor()
    }

    /// Stops recognition and releases related resources.
    func stop(fallbackFinalText: String = "",
              onFinalOnMain: (@Sendable (String) -> Void)? = nil) async {

        // Emit the last non-empty transcription if a final result was not produced.
        if !didEmitFinal {
            let candidate = lastNonEmptyText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let cb = onFinalOnMain, !candidate.isEmpty {
                cb(candidate)
                didEmitFinal = true
            }
        }

        // Remove taps and cancel pending tasks.
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

        // Restore the iOS audio session to playback mode.
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

    /// Creates a fresh recognition request and tap so the session can restart seamlessly.
    private func makeNewRequestAndTap() async throws {
        // Remove any existing tap before installing a new one.
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
            audioTap = nil
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Hint to the recognizer that the session is continuous dictation.
        req.taskHint = .dictation
        // Enable automatic punctuation provided by the system.
        req.addsPunctuation = true
        // Use the formatted string with automatic punctuation.
        request = req

        let inputNode = audioEngine.inputNode
        let tap = AudioTap(request: req)
        tap.amplitudeHandler = { [weak self] level in
            guard let self else { return }
            Task { await self.handleAmplitude(level) }
        }
        // Allow the system to choose an appropriate input format.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [tap] buffer, _ in
            tap.handle(buffer: buffer)
        }
        audioTap = tap
        tapInstalled = true
    }

    /// Attaches the recognition task and routes callbacks.
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
                    // Treat only non-empty results as final; otherwise restart.
                    if !txt.isEmpty {
                        Task {
                            await self.emitFinalIfNeeded(txt)
                            await self.stop()  // Triggers cleanup on the caller side.
                        }
                    } else {
                        // Handle empty finals that often occur after timeouts or silent endings.
                        Task {
                            await self.handleEmptyFinalAndRestart()
                        }
                    }
                    return
                } else if !txt.isEmpty {
                    Task { await self.emitPartial(txt) }
                }
            }

            // Stop only when a genuine error occurs.
            if let _ = err {
                Task { await self.stop() }
            }
        }
    }

    // MARK: - Actor helpers ------------------------------------------------------------

    private func handleAmplitude(_ level: Float) {
        // Used solely for UI updates and to timestamp the first detected activity.
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
        // Enter a grace period after new text to avoid cutting short pauses.
        graceUntil = Date().addingTimeInterval(postPartialGrace)
        // Record when the first text was produced to enforce minimum active time.
        if firstTextAt == nil { firstTextAt = .now }
    }

    private func registerVoiceActivity(_ level: Float) {
        // Track timestamps only to avoid ending sessions due to early background noise.
        if level >= vadLevelThreshold {
            lastSpeechAt = .now
        }
    }

    /// Handles empty final results by restarting the recognition request.
    private func handleEmptyFinalAndRestart() async {
        // Restart only if the silence monitor did not intentionally end the audio.
        if didEndAudioForSilence {
            // If the silence monitor ended the audio, stop instead of restarting.
            await stop()
            return
        }
        // Recreate the request and tap to keep the engine running.
        do {
            try await makeNewRequestAndTap()
            attachRecognitionTask()
            // Preserve state so silence ending still requires recognized text.
        } catch {
            // Stop the session if restarting fails.
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
        // Only end due to silence after non-empty text has been recognized.
        guard hasRecognizedText, let last = lastSpeechAt else { return }

        // Respect the grace period to avoid truncating short pauses.
        if let g = graceUntil, Date() < g { return }

        // Ensure the session runs for at least the minimum active duration.
        if let first = firstTextAt {
            let alive = Date().timeIntervalSince(first)
            if alive < minActiveAfterFirstText { return }
        }

        let elapsed = Date().timeIntervalSince(last)
        if elapsed > silenceLimit && !didEndAudioForSilence {
            // End audio input and allow the recognizer to produce a final result.
            request?.endAudio()
            didEndAudioForSilence = true
        }
    }
}

/// Appends audio buffers to the recognition request and surfaces RMS levels.
final class AudioTap: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    var amplitudeHandler: (@Sendable (Float) -> Void)?

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func handle(buffer: AVAudioPCMBuffer) {
        request.append(buffer)

        // Compute the RMS energy as an amplitude indicator.
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
