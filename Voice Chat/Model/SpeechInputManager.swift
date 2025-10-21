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
        var displayName: String { self == .zh ? L10n.Speech.languageChinese : L10n.Speech.languageEnglish }
        var locale: Locale { Locale(identifier: rawValue) }
    }

    // MARK: - Public State
    @Published private(set) var isRecording: Bool = false
    @Published var lastError: String?

    /// Smoothed realtime input level (0...1) for the voice overlay UI
    @Published var inputLevel: Double = 0

    /// Selected dictation language (Chinese or English)
    @Published var currentLanguage: DictationLanguage = .zh

    // MARK: - Session bookkeeping
    private var currentSessionID: UUID?
    private var lastStableText: String = ""
    private var currentOnFinal: (@MainActor (String) -> Void)?

    // Level smoothing
    private var levelEMA: Double = 0
    private let levelAlpha: Double = 0.20  // Exponential smoothing factor

    // Manage AVAudioEngine and Speech objects on a dedicated actor
    private let worker = SpeechRecognizerWorker()

    // MARK: - API

    /// Starts realtime dictation
    func startRecording(language: DictationLanguage? = nil,
                        onPartial: @escaping @MainActor (String) -> Void,
                        onFinal:   @escaping @MainActor (String) -> Void) async {
        lastError = nil

        // Stop any previous session before starting a new one
        if isRecording { stopRecording() }

        guard await requestPermissions() else {
            lastError = L10n.Speech.permissionsDenied
            return
        }

        let newID = UUID()
        currentSessionID = newID
        lastStableText   = ""
        currentOnFinal   = onFinal
        levelEMA         = 0
        inputLevel       = 0

        let pickLang = language ?? currentLanguage

        // Ensure callbacks hop back to the main actor before touching state
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
                // Session teardown happens only after non-empty text is produced
                self.isRecording       = false
                self.currentSessionID  = nil
                self.currentOnFinal    = nil
                self.inputLevel        = 0
                self.levelEMA          = 0
            }
        }

        // Normalize audio level callbacks to a 0...1 range with exponential smoothing
        let levelWrapper: @Sendable (Float) -> Void = { [weak self] raw in
            Task { @MainActor in
                guard let self else { return }
                // Scale RMS values (typically 0.02~0.2) into the 0...1 range
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
            lastError = L10n.Speech.engineStartFailed(error.localizedDescription)
            await worker.stop()
            isRecording = false
            currentSessionID = nil
            currentOnFinal   = nil
            inputLevel       = 0
            levelEMA         = 0
        }
    }

    /// Ends recording from any thread
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
        // macOS only requests speech recognition permission; microphone prompts are handled by the system
        return speechOK
        #endif
        #else
        lastError = L10n.Speech.unsupportedPlatform
        return false
        #endif
    }
}

#if os(iOS) || os(macOS)

import Speech
import AVFoundation

// MARK: - Background speech recognizer (actor enforces serialization)
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
    /// Timestamp of the last detected speech event; nil until audio activity is observed
    private var lastSpeechAt : Date? = nil
    private var silenceLimit : TimeInterval = 1.2
    private var monitorTask  : Task<Void, Never>?

    // Energy threshold (~-44 dB) chosen for responsive voice activity detection
    private let vadLevelThreshold: Float = 0.006
    private var didEndAudioForSilence: Bool = false

    /// Grace period after partial text during which silence does not end the session
    private let postPartialGrace: TimeInterval = 0.6
    private var graceUntil: Date? = nil

    /// Timestamp of the first non-empty transcription to enforce minimum session length
    private var firstTextAt: Date? = nil
    /// Minimum amount of active time after the first recognized text before allowing silence termination
    private let minActiveAfterFirstText: TimeInterval = 1.0

    /// Ensures silence can end the session only after non-empty text has been produced
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
                return L10n.Speech.recognizerUnavailable
            case .engineStartFailed(let message):
                return L10n.Speech.engineStartFailed(message)
            }
        }
    }

    // MARK: - Public ------------------------------------------------------------------

    func start(locale: Locale,
               onPartial: @Sendable @escaping (String) -> Void,
               onFinal  : @Sendable @escaping (String) -> Void,
               onLevel  : @Sendable @escaping (Float) -> Void) async throws
    {
        // Tear down any previous session before starting a new one
        if tapInstalled || request != nil || task != nil {
            await stop()
        }

        onPartialHandler   = onPartial
        onFinalHandler     = onFinal
        onLevelHandler     = onLevel
        lastNonEmptyText   = ""
        didEmitFinal       = false

        // Initially disable silence-based endings until real speech is detected
        lastSpeechAt           = nil
        hasRecognizedText      = false
        didEndAudioForSilence  = false

        // 1) recognizer
        guard let r = SFSpeechRecognizer(locale: locale), r.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }
        recognizer = r

        // 2) Recognition request (default mode with automatic punctuation)
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

        // 4) Prepare and start the audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw SpeechError.engineStartFailed(error.localizedDescription)
        }

        // 5) recognition task
        attachRecognitionTask()

        // 6) Launch the silence monitor
        launchSilenceMonitor()
    }

    /// Stops recognition and releases related resources
    func stop(fallbackFinalText: String = "",
              onFinalOnMain: (@Sendable (String) -> Void)? = nil) async {

        // If no final result has been emitted, fall back to the last non-empty text
        if !didEmitFinal {
            let candidate = lastNonEmptyText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let cb = onFinalOnMain, !candidate.isEmpty {
                cb(candidate)
                didEmitFinal = true
            }
        }

        // Cancel tasks and remove the audio tap
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

    /// Rebuilds the recognition request and audio tap without interrupting the session
    private func makeNewRequestAndTap() async throws {
        // Remove any existing tap before installing a new one
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
            audioTap = nil
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Hint that we expect continuous dictation for better responsiveness
        req.taskHint = .dictation
        // Enable automatic punctuation
        req.addsPunctuation = true
        // Use the system default formatting with automatic punctuation
        request = req

        let inputNode = audioEngine.inputNode
        let tap = AudioTap(request: req)
        tap.amplitudeHandler = { [weak self] level in
            guard let self else { return }
            Task { await self.handleAmplitude(level) }
        }
        // Provide a nil format so the system chooses an appropriate one
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [tap] buffer, _ in
            tap.handle(buffer: buffer)
        }
        audioTap = tap
        tapInstalled = true
    }

    /// Attaches a recognition task to the speech recognizer
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
                    // Only treat non-empty text as final; otherwise restart listening
                    if !txt.isEmpty {
                        Task {
                            await self.emitFinalIfNeeded(txt)
                            await self.stop()  // Allow the caller to complete UI teardown
                        }
                    } else {
                        // Empty finals usually indicate a timeout or silence without text
                        Task {
                            await self.handleEmptyFinalAndRestart()
                        }
                    }
                    return
                } else if !txt.isEmpty {
                    Task { await self.emitPartial(txt) }
                }
            }

            // Stop only on genuine errors
            if let _ = err {
                Task { await self.stop() }
            }
        }
    }

    // MARK: - Actor helpers ------------------------------------------------------------

    private func handleAmplitude(_ level: Float) {
        // Record activity for UI feedback; silence detection relies on explicit timers
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
        // Enter a grace period so short pauses after speech do not end the session
        graceUntil = Date().addingTimeInterval(postPartialGrace)
        // Track the first piece of text to enforce the minimum session duration
        if firstTextAt == nil { firstTextAt = .now }
    }

    private func registerVoiceActivity(_ level: Float) {
        // Only record a timestamp to avoid false positives from initial noise
        if level >= vadLevelThreshold {
            lastSpeechAt = .now
        }
    }

    /// Restart recognition when the recognizer reports an empty final result
    private func handleEmptyFinalAndRestart() async {
        // Restart only if we did not explicitly end audio because of silence
        if didEndAudioForSilence {
            // We triggered endAudio ourselves and expect text; stop to avoid loops
            await stop()
            return
        }
        // Recreate the request and tap so the engine keeps running continuously
        do {
            try await makeNewRequestAndTap()
            attachRecognitionTask()
            // Preserve hasRecognizedText; silence should still require prior text
        } catch {
            // On failure fall back to stopping entirely
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
        // Only allow silence to end input after non-empty text has been produced
        guard hasRecognizedText, let last = lastSpeechAt else { return }

        // Respect the post-partial grace period to avoid cutting short brief pauses
        if let g = graceUntil, Date() < g { return }

        // Do not end early if the session has not reached the minimum active duration
        if let first = firstTextAt {
            let alive = Date().timeIntervalSince(first)
            if alive < minActiveAfterFirstText { return }
        }

        let elapsed = Date().timeIntervalSince(last)
        if elapsed > silenceLimit && !didEndAudioForSilence {
            // End audio so the recognizer can deliver its final result
            request?.endAudio()
            didEndAudioForSilence = true
        }
    }
}

/// Wraps buffering audio into the recognition request and reports amplitude in a Sendable manner
final class AudioTap: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    var amplitudeHandler: (@Sendable (Float) -> Void)?

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func handle(buffer: AVAudioPCMBuffer) {
        request.append(buffer)

        // Calculate RMS amplitude across all channels
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
