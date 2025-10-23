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

    // MARK: - Dictation languages
    enum DictationLanguage: String, CaseIterable, Identifiable {
        case english = "en-US"
        case simplifiedChinese = "zh-CN"
        case traditionalChinese = "zh-TW"
        case japanese = "ja-JP"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .english:
                return String(localized: "English")
            case .simplifiedChinese:
                return String(localized: "Simplified Chinese")
            case .traditionalChinese:
                return String(localized: "Traditional Chinese")
            case .japanese:
                return String(localized: "Japanese")
            }
        }

        var locale: Locale { Locale(identifier: rawValue) }
    }

    // MARK: - Public State
    @Published private(set) var isRecording: Bool = false
    @Published var lastError: String?

    /// Real-time input level (0~1) used by the overlay animation.
    @Published var inputLevel: Double = 0

    /// Currently selected dictation language.
    @Published var currentLanguage: DictationLanguage = .english

    // MARK: - Session bookkeeping
    private var currentSessionID: UUID?
    private var lastStableText: String = ""
    private var currentOnFinal: (@MainActor (String) -> Void)?

    // level smoothing
    private var levelEMA: Double = 0
    private let levelAlpha: Double = 0.20  // Smoothing factor for the exponential moving average

    // All AVAudioEngine/Speech objects are coordinated by the worker actor.
    private let worker = SpeechRecognizerWorker()

    // MARK: - API

    /// Starts realtime dictation.
    func startRecording(language: DictationLanguage? = nil,
                        onPartial: @escaping @MainActor (String) -> Void,
                        onFinal:   @escaping @MainActor (String) -> Void) async {
        lastError = nil

        // Stop any existing recording before starting a new session.
        if isRecording { stopRecording() }

        guard await requestPermissions() else {
            lastError = AppLocalization.string(.speechPermissionDenied)
            return
        }

        let newID = UUID()
        currentSessionID = newID
        lastStableText   = ""
        currentOnFinal   = onFinal
        levelEMA         = 0
        inputLevel       = 0

        let pickLang = language ?? currentLanguage

        // Ensure @Sendable closures hop back to the main actor before interacting with state.
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
                // The session ends only after emitting non-empty final text.
                self.isRecording       = false
                self.currentSessionID  = nil
                self.currentOnFinal    = nil
                self.inputLevel        = 0
                self.levelEMA          = 0
            }
        }

        // Volume callback: scale and smooth raw amplitude into a 0-1 range.
        let levelWrapper: @Sendable (Float) -> Void = { [weak self] raw in
            Task { @MainActor in
                guard let self else { return }
                // Empirical scaling: speech RMS typically sits between 0.02 and 0.2.
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

    /// Ends the current recording session (safe to call from any thread).
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
        // On macOS only speech recognition permission is requested (microphone access is system-managed).
        return speechOK
        #endif
        #else
        lastError = AppLocalization.string(.speechUnsupportedPlatform)
        return false
        #endif
    }
}

#if os(iOS) || os(macOS)

import Speech
import AVFoundation

// MARK: - Background speech recognition worker (actor serialized)
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
    /// Timestamp of the most recent detected speech activity; nil until the first activity is observed.
    private var lastSpeechAt : Date? = nil
    private var silenceLimit : TimeInterval = 1.2
    private var monitorTask  : Task<Void, Never>?

    // Amplitude threshold (~ -44 dB) for voice activity detection.
    private let vadLevelThreshold: Float = 0.006
    private var didEndAudioForSilence: Bool = false

    /// Grace period after emitting non-empty text; silence does not end the session within this window.
    private let postPartialGrace: TimeInterval = 0.6
    private var graceUntil: Date? = nil

    /// Timestamp of the first non-empty transcription.
    private var firstTextAt: Date? = nil
    /// Minimum lifetime after the first transcription to avoid cutting off natural pauses.
    private let minActiveAfterFirstText: TimeInterval = 1.0

    /// Dictation can only auto-stop once non-empty text has been recognized.
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
                return AppLocalization.string(.speechRecognizerUnavailable)
            case .engineStartFailed(let message):
                let format = AppLocalization.string(.speechEngineStartFailed)
                return String(format: format, message)
            }
        }
    }

    // MARK: - Public ------------------------------------------------------------------

    func start(locale: Locale,
               onPartial: @Sendable @escaping (String) -> Void,
               onFinal  : @Sendable @escaping (String) -> Void,
               onLevel  : @Sendable @escaping (Float) -> Void) async throws
    {
        // Tear down any existing session before starting a new one.
        if tapInstalled || request != nil || task != nil {
            await stop()
        }

        onPartialHandler   = onPartial
        onFinalHandler     = onFinal
        onLevelHandler     = onLevel
        lastNonEmptyText   = ""
        didEmitFinal       = false

        // Start with silence-based termination disabled until speech is detected.
        lastSpeechAt           = nil
        hasRecognizedText      = false
        didEndAudioForSilence  = false

        // 1) recognizer
        guard let r = SFSpeechRecognizer(locale: locale), r.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }
        recognizer = r

        // 2) Recognition request (dictation hint with system punctuation)
        try await makeNewRequestAndTap()

        // 3) Configure the iOS audio session
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

        // 4) Prepare and start the engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw SpeechError.engineStartFailed(error.localizedDescription)
        }

        // 5) Recognition task
        attachRecognitionTask()

        // 6) Start monitoring for silence timeouts
        launchSilenceMonitor()
    }

    /// Stops the recognizer and releases resources.
    func stop(fallbackFinalText: String = "",
              onFinalOnMain: (@Sendable (String) -> Void)? = nil) async {

        // If no final result has been emitted, fall back to the last non-empty text.
        if !didEmitFinal {
            let candidate = lastNonEmptyText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let cb = onFinalOnMain, !candidate.isEmpty {
                cb(candidate)
                didEmitFinal = true
            }
        }

        // Cancel active tasks and remove taps
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

        // Restore the iOS audio session configuration
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

    /// Creates a fresh recognition request and tap. Reused when the session receives an empty final result.
    private func makeNewRequestAndTap() async throws {
        // Clear any previously installed tap
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
            audioTap = nil
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Hint the recognizer for continuous dictation to improve responsiveness.
        req.taskHint = .dictation
        // Enable automatic punctuation
        req.addsPunctuation = true
        // Use the system defaults and rely on formattedString for punctuation.
        request = req

        let inputNode = audioEngine.inputNode
        let tap = AudioTap(request: req)
        tap.amplitudeHandler = { [weak self] level in
            guard let self else { return }
            Task { await self.handleAmplitude(level) }
        }
        // Allow the system to determine the proper audio format
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [tap] buffer, _ in
            tap.handle(buffer: buffer)
        }
        audioTap = tap
        tapInstalled = true
    }

    /// Installs the speech recognition task.
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
                    // Only treat non-empty results as final; otherwise restart listening.
                    if !txt.isEmpty {
                        Task {
                            await self.emitFinalIfNeeded(txt)
                            await self.stop()  // Triggers upstream completion and UI cleanup
                        }
                    } else {
                        // Empty final results typically mean the system timed out without text.
                        Task {
                            await self.handleEmptyFinalAndRestart()
                        }
                    }
                    return
                } else if !txt.isEmpty {
                    Task { await self.emitPartial(txt) }
                }
            }

            // Stop the session when a real error occurs.
            if let _ = err {
                Task { await self.stop() }
            }
        }
    }

    // MARK: - Actor helpers ------------------------------------------------------------

    private func handleAmplitude(_ level: Float) {
        // Used for UI metering and initial activity timestamps—no silence detection occurs here.
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
        // Enter a grace period so short pauses do not immediately end the session.
        graceUntil = Date().addingTimeInterval(postPartialGrace)
        // Record the timestamp of the first text to ensure a minimum session length.
        if firstTextAt == nil { firstTextAt = .now }
    }

    private func registerVoiceActivity(_ level: Float) {
        // Track timestamps only to avoid ending due to environmental noise.
        if level >= vadLevelThreshold {
            lastSpeechAt = .now
        }
    }

    /// When receiving an empty final result, restart the request without ending the session.
    private func handleEmptyFinalAndRestart() async {
        // Restart only if the session did not stop because of intentional silence handling.
        if didEndAudioForSilence {
            // If we ended audio deliberately we expect text; in doubt, stop safely.
            await stop()
            return
        }
        // Recreate the request and tap, then attach a new task to keep the engine running.
        do {
            try await makeNewRequestAndTap()
            attachRecognitionTask()
            // Preserve the recognition flags so silence handling continues to require prior text.
        } catch {
            // Stop the session entirely if restart fails.
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
        // Only allow silence-based termination after non-empty text has been produced.
        guard hasRecognizedText, let last = lastSpeechAt else { return }

        // Stay alive during the grace period to avoid cutting off recent speech.
        if let g = graceUntil, Date() < g { return }

        // Enforce the minimum session length after the first transcription.
        if let first = firstTextAt {
            let alive = Date().timeIntervalSince(first)
            if alive < minActiveAfterFirstText { return }
        }

        let elapsed = Date().timeIntervalSince(last)
        if elapsed > silenceLimit && !didEndAudioForSilence {
            // End the audio input; the recognizer will deliver a final result at this point.
            request?.endAudio()
            didEndAudioForSilence = true
        }
    }
}

/// Appends audio buffers to the recognition request and reports amplitude levels.
final class AudioTap: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    var amplitudeHandler: (@Sendable (Float) -> Void)?

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func handle(buffer: AVAudioPCMBuffer) {
        request.append(buffer)

        // Calculate RMS as an energy indicator (works for mono or multi-channel input).
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
