//
//  SpeechInputManager.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/20.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class SpeechInputManager: NSObject, ObservableObject {

    // MARK: - Language (two options only)
    enum DictationLanguage: String, CaseIterable, Identifiable {
        case zh = "zh-CN"
        case en = "en-US"
        var id: String { rawValue }
        var displayNameKey: LocalizedStringKey {
            self == .zh ? L10n.Dictation.chinese : L10n.Dictation.english
        }
        var locale: Locale { Locale(identifier: rawValue) }
    }

    // MARK: - Public State
    @Published private(set) var isRecording: Bool = false
    @Published var lastError: String?

    /// Smoothed input level exposed to the UI (0...1).
    @Published var inputLevel: Double = 0

    /// Currently selected dictation language.
    @Published var currentLanguage: DictationLanguage = .en

    // MARK: - Session bookkeeping
    private var currentSessionID: UUID?
    private var lastStableText: String = ""
    private var currentOnFinal: (@MainActor (String) -> Void)?

    // Level smoothing cache
    private var levelEMA: Double = 0
    private let levelAlpha: Double = 0.20  // smoothing factor 0.2

    // All AVAudioEngine / Speech objects are managed serially inside the worker actor.
    private let worker = SpeechRecognizerWorker()

    // MARK: - API

    /// Start real-time dictation.
    func startRecording(language: DictationLanguage? = nil,
                        onPartial: @escaping @MainActor (String) -> Void,
                        onFinal:   @escaping @MainActor (String) -> Void) async {
        lastError = nil

        // Stop the existing recording session if needed.
        if isRecording { stopRecording() }

        guard await requestPermissions() else {
            lastError = L10n.SpeechInput.permissionsMissingText
            return
        }

        let newID = UUID()
        currentSessionID = newID
        lastStableText   = ""
        currentOnFinal   = onFinal
        levelEMA         = 0
        inputLevel       = 0

        let pickLang = language ?? currentLanguage

        // Important: @Sendable closures hop back to the main actor before touching shared state.
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
                // Tear down state when the current session ends.
                self.isRecording       = false
                self.currentSessionID  = nil
                self.currentOnFinal    = nil
                self.inputLevel        = 0
                self.levelEMA          = 0
            }
        }

        // Level callback: scale and smooth into the 0...1 range.
        let levelWrapper: @Sendable (Float) -> Void = { [weak self] raw in
            Task { @MainActor in
                guard let self else { return }
                // Empirically scale RMS (typically 0.02~0.2) to the 0...1 range.
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

    /// Stop recording proactively (safe to call from any thread).
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
        // macOS only requires speech recognition permission; the microphone prompt is managed by the OS.
        return speechOK
        #endif
        #else
        lastError = L10n.SpeechInput.unsupportedPlatformText
        return false
        #endif
    }
}

#if os(iOS) || os(macOS)

import Speech
import AVFoundation

// MARK: - Background recognizer worker (actor keeps the pipeline serialized)
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
    /// Last time we detected voice activity; nil until the first detection.
    private var lastSpeechAt : Date? = nil
    private var silenceLimit : TimeInterval = 1.2
    private var monitorTask  : Task<Void, Never>?

    // Energy threshold (linear amplitude, roughly -44 dB) to be sensitive to human speech.
    private let vadLevelThreshold: Float = 0.006
    private var didEndAudioForSilence: Bool = false

    /// Grace period after a non-empty partial result during which silence will not end the session.
    private let postPartialGrace: TimeInterval = 0.6
    private var graceUntil: Date? = nil

    /// Timestamp of the first non-empty transcript to enforce a minimum active duration.
    private var firstTextAt: Date? = nil
    /// Minimum time window after the first text before allowing automatic silence shutdown.
    private let minActiveAfterFirstText: TimeInterval = 1.0

    /// Silence-based shutdown only happens after at least one non-empty transcript.
    private var hasRecognizedText: Bool = false

    // MARK: - Misc state
    private var lastNonEmptyText: String = ""
    private var didEmitFinal   : Bool = false

    enum SpeechError: LocalizedError {
        case recognizerUnavailable
        case engineStartFailed(String)
        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable: return L10n.SpeechInput.recognizerUnavailableText
            case .engineStartFailed(let m): return L10n.SpeechInput.engineStartFailed(m)
            }
        }
    }

    // MARK: - Public ------------------------------------------------------------------

    func start(locale: Locale,
               onPartial: @Sendable @escaping (String) -> Void,
               onFinal  : @Sendable @escaping (String) -> Void,
               onLevel  : @Sendable @escaping (Float) -> Void) async throws
    {
        // Clean up any previously running session.
        if tapInstalled || request != nil || task != nil {
            await stop()
        }

        onPartialHandler   = onPartial
        onFinalHandler     = onFinal
        onLevelHandler     = onLevel
        lastNonEmptyText   = ""
        didEmitFinal       = false

        // Initially we do not allow silence to end the session automatically.
        lastSpeechAt           = nil
        hasRecognizedText      = false
        didEndAudioForSilence  = false

        // 1) recognizer
        guard let r = SFSpeechRecognizer(locale: locale), r.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }
        recognizer = r

        // 2) recognition request (default mode with automatic punctuation via formattedString)
        try await makeNewRequestAndTap()

        // 3) iOS audio session
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

        // 4) engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw SpeechError.engineStartFailed(error.localizedDescription)
        }

        // 5) recognition task
        attachRecognitionTask()

        // 6) start silence monitoring
        launchSilenceMonitor()
    }

    /// Stop the recognizer and clean up resources.
    func stop(fallbackFinalText: String = "",
              onFinalOnMain: (@Sendable (String) -> Void)? = nil) async {

        // If no final result has been emitted, fall back to the last non-empty transcript.
        if !didEmitFinal {
            let candidate = lastNonEmptyText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let cb = onFinalOnMain, !candidate.isEmpty {
                cb(candidate)
                didEmitFinal = true
            }
        }

        // Cancel the task and remove the tap.
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

        // Restore the default audio session configuration on iOS.
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

    /// Create a new recognition request and audio tap; used to restart on empty finals.
    private func makeNewRequestAndTap() async throws {
        // Remove any existing tap.
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
            audioTap = nil
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Hint the system for continuous dictation to improve sensitivity and coherence.
        req.taskHint = .dictation
        // Enable automatic punctuation.
        req.addsPunctuation = true
        // Rely on the default recognition mode plus automatic punctuation (formattedString).
        request = req

        let inputNode = audioEngine.inputNode
        let tap = AudioTap(request: req)
        tap.amplitudeHandler = { [weak self] level in
            guard let self else { return }
            Task { await self.handleAmplitude(level) }
        }
        // Passing format=nil lets the system select the appropriate format.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [tap] buffer, _ in
            tap.handle(buffer: buffer)
        }
        audioTap = tap
        tapInstalled = true
    }

    /// Attach the speech recognition task.
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
                    // Only non-empty transcripts count as a true final result; otherwise restart.
                    if !txt.isEmpty {
                        Task {
                            await self.emitFinalIfNeeded(txt)
                            await self.stop()  // triggers UI cleanup on the main actor
                        }
                    } else {
                        // Empty final: usually timeout or silence without a transcript.
                        Task {
                            await self.handleEmptyFinalAndRestart()
                        }
                    }
                    return
                } else if !txt.isEmpty {
                    Task { await self.emitPartial(txt) }
                }
            }

            // Only treat real errors as fatal.
            if let _ = err {
                Task { await self.stop() }
            }
        }
    }

    // MARK: - Actor helpers ------------------------------------------------------------

    private func handleAmplitude(_ level: Float) {
        // Used purely for UI level visualization and timing; silence ending no longer depends on RMS.
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
        // Enter the grace period so brief pauses after speech do not end the session.
        graceUntil = Date().addingTimeInterval(postPartialGrace)
        // Record the first-text timestamp to enforce the minimum session length.
        if firstTextAt == nil { firstTextAt = .now }
    }

    private func registerVoiceActivity(_ level: Float) {
        // Record the timestamp only to avoid ending the session prematurely because of noise.
        if level >= vadLevelThreshold {
            lastSpeechAt = .now
        }
    }

    /// When receiving an empty final result, reset the request and keep listening.
    private func handleEmptyFinalAndRestart() async {
        // Only restart if silence did not already terminate the session intentionally.
        if didEndAudioForSilence {
            // Our own endAudio should have produced text; stop defensively if it did not.
            await stop()
            return
        }
        // Re-create the request and tap, keeping the engine running.
        do {
            try await makeNewRequestAndTap()
            attachRecognitionTask()
            // Preserve hasRecognizedText so silence can still end the session only after text appears.
        } catch {
            // Fail-safe: stop entirely if restart fails.
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
        // Only end input because of silence after producing a non-empty transcript.
        guard hasRecognizedText, let last = lastSpeechAt else { return }

        // Stay active during the grace period so short pauses are tolerated.
        if let g = graceUntil, Date() < g { return }

        // Enforce the minimum active duration after the first transcript.
        if let first = firstTextAt {
            let alive = Date().timeIntervalSince(first)
            if alive < minActiveAfterFirstText { return }
        }

        let elapsed = Date().timeIntervalSince(last)
        if elapsed > silenceLimit && !didEndAudioForSilence {
            // End audio input and allow the recognizer to emit its final result (text is guaranteed now).
            request?.endAudio()
            didEndAudioForSilence = true
        }
    }
}

/// Append audio buffers to the recognition request and surface RMS levels (Sendable-safe helper).
final class AudioTap: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    var amplitudeHandler: (@Sendable (Float) -> Void)?

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func handle(buffer: AVAudioPCMBuffer) {
        request.append(buffer)

        // Calculate RMS as the energy indicator (works for mono or multi-channel audio).
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
