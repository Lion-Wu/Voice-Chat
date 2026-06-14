//
//  SpeechRecognizerWorker.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

#if os(iOS) || os(macOS) || os(visionOS)

import AVFoundation
import Foundation
import Speech

// MARK: - Background recognition worker

actor SpeechRecognizerWorker {

    // MARK: - Internal objects
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    private var tapInstalled = false
    private var audioTap: SpeechAudioTap?

    // MARK: - Callbacks
    private var onPartialHandler: (@Sendable (String) -> Void)?
    private var onFinalHandler: (@Sendable (String) -> Void)?
    private var onLevelHandler: (@Sendable (Float) -> Void)?
    private var onErrorHandler: (@Sendable (String) -> Void)?

    // MARK: - End-of-speech detection
    /// Timestamp of the most recent detected speech activity; remains nil until speech is detected.
    private var lastSpeechAt: Date?
    private var silenceLimit: TimeInterval = 1.2
    private var monitorTask: Task<Void, Never>?

    // Energy threshold (linear amplitude, roughly -44 dB). Lower values make voice detection more sensitive.
    private let vadLevelThreshold: Float = 0.006
    private var didEndAudioForSilence = false

    /// Grace period after non-empty text is recognized; silence will not end the session during this window.
    private let postPartialGrace: TimeInterval = 0.6
    private var graceUntil: Date?

    /// Timestamp of the first non-empty transcript; used to guarantee a minimum session length.
    private var firstTextAt: Date?
    /// Minimum time to keep the session open after the first text to avoid clipping natural pauses.
    private let minActiveAfterFirstText: TimeInterval = 1.0

    /// Silence-based termination is allowed only after producing non-empty text.
    private var hasRecognizedText = false

    // MARK: - Misc state
    private var lastNonEmptyText = ""
    private var didEmitFinal = false
    private var isStopping = false
    private var isRecoveringEmptyRecognition = false
    private var recognitionTaskGeneration = 0

    /// When true, the worker will not terminate the session due to silence and will restart
    /// internally if the recognizer produces a final result.
    private var holdToSpeakActive = false

    /// Prefix transcript accumulated across internal restarts while hold-to-talk is active.
    private var holdToSpeakAccumulatedText = ""

    func lastNonEmptyTextSnapshot() -> String {
        lastNonEmptyText
    }

    enum SpeechError: LocalizedError {
        case recognizerUnavailable
        case engineStartFailed(String)

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return NSLocalizedString("Speech recognition is unavailable. Check network connectivity and system settings.", comment: "Speech recognition unavailable error")
            case .engineStartFailed(let message):
                return String(format: NSLocalizedString("Audio engine failed to start: %@", comment: "Audio engine start failure"), message)
            }
        }
    }

    // MARK: - Public

    func start(locale: Locale,
               onPartial: @Sendable @escaping (String) -> Void,
               onFinal: @Sendable @escaping (String) -> Void,
               onLevel: @Sendable @escaping (Float) -> Void,
               onError: @Sendable @escaping (String) -> Void) async throws {
        // Stop any existing session before starting a new one.
        if tapInstalled || request != nil || task != nil {
            await stop()
        }

        onPartialHandler = onPartial
        onFinalHandler = onFinal
        onLevelHandler = onLevel
        onErrorHandler = onError
        lastNonEmptyText = ""
        holdToSpeakAccumulatedText = ""
        didEmitFinal = false
        isStopping = false
        isRecoveringEmptyRecognition = false

        // Important: silence cannot end the session until real speech has been heard.
        lastSpeechAt = nil
        hasRecognizedText = false
        didEndAudioForSilence = false
        graceUntil = nil
        firstTextAt = nil

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }
        self.recognizer = recognizer

        #if os(iOS) || os(visionOS)
        try await MainActor.run {
            let session = AVAudioSession.sharedInstance()
            let category: AVAudioSession.Category =
                session.availableCategories.contains(.playAndRecord) ? .playAndRecord : .record

            let mode: AVAudioSession.Mode =
                session.availableModes.contains(.voiceChat) ? .voiceChat : .default

            #if os(iOS)
            let options: AVAudioSession.CategoryOptions = [.duckOthers,
                                                           .defaultToSpeaker,
                                                           .allowBluetoothA2DP,
                                                           .allowBluetoothHFP]
            #else
            let options: AVAudioSession.CategoryOptions = []
            #endif

            try session.setCategory(category,
                                    mode: mode,
                                    options: options)
            try session.setActive(true, options: [])
        }
        #endif

        try await makeNewRequestAndTap()

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw SpeechError.engineStartFailed(error.localizedDescription)
        }

        attachRecognitionTask()
        launchSilenceMonitor()
    }

    func setHoldToSpeakActive(_ active: Bool) {
        holdToSpeakActive = active
    }

    /// Stops recognition and releases resources.
    func stop() async {
        isStopping = true
        recognitionTaskGeneration &+= 1

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

        #if os(iOS) || os(visionOS)
        try? await MainActor.run {
            let session = AVAudioSession.sharedInstance()
            if session.availableCategories.contains(.playback) {
                try session.setCategory(.playback, mode: .default, options: [])
            }
            try session.setActive(false, options: [])
        }
        #endif

        recognizer = nil
        onPartialHandler = nil
        onFinalHandler = nil
        onLevelHandler = nil
        onErrorHandler = nil

        monitorTask?.cancel()
        monitorTask = nil

        didEndAudioForSilence = false
        hasRecognizedText = false
        lastSpeechAt = nil
        graceUntil = nil
        firstTextAt = nil
        isRecoveringEmptyRecognition = false
    }

    // MARK: - Internal setup helpers

    /// Creates a new request and tap. Reused when empty finals arrive so the session can continue.
    private func makeNewRequestAndTap() async throws {
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
            audioTap = nil
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let tap = SpeechAudioTap(request: request)
        tap.amplitudeHandler = { [weak self] level in
            guard let self else { return }
            Task { await self.handleAmplitude(level) }
        }
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw SpeechError.engineStartFailed("Microphone format is unavailable.")
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [tap] buffer, _ in
            tap.handle(buffer: buffer)
        }
        audioTap = tap
        tapInstalled = true
    }

    /// Establishes the recognition task.
    private func attachRecognitionTask() {
        guard let recognizer, let request else { return }
        recognitionTaskGeneration &+= 1
        let generation = recognitionTaskGeneration
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let error {
                Task { await self.handleRecognizerError(error, generation: generation) }
                return
            }
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            let isFinal = result.isFinal
            Task { await self.handleRecognitionResult(text: text, isFinal: isFinal, generation: generation) }
        }
    }

    // MARK: - Actor helpers

    private func handleRecognizerError(_ error: Error, generation: Int) async {
        guard generation == recognitionTaskGeneration else { return }
        guard !isStopping else { return }
        if shouldRecoverFromEmptyRecognitionError(error) {
            await recoverFromEmptyRecognitionEnd()
            return
        }

        isStopping = true
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
            onErrorHandler?(message)
        }
        await stop()
    }

    private func shouldRecoverFromEmptyRecognitionError(_ error: Error) -> Bool {
        guard !hasRecognizedText else { return false }
        guard lastNonEmptyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let nsError = error as NSError
        if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110 {
            return true
        }

        let message = nsError.localizedDescription.lowercased()
        return message.contains("no speech")
            || message.contains("no speech detected")
    }

    private func recoverFromEmptyRecognitionEnd() async {
        guard !isRecoveringEmptyRecognition else { return }
        isRecoveringEmptyRecognition = true
        defer { isRecoveringEmptyRecognition = false }

        isStopping = true
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
            audioTap = nil
        }

        lastSpeechAt = nil
        hasRecognizedText = false
        didEndAudioForSilence = false
        didEmitFinal = false
        graceUntil = nil
        firstTextAt = nil

        do {
            try await makeNewRequestAndTap()
            if !audioEngine.isRunning {
                audioEngine.prepare()
                try audioEngine.start()
            }
            isStopping = false
            attachRecognitionTask()
        } catch {
            isStopping = true
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                onErrorHandler?(message)
            }
            await stop()
        }
    }

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

    private func handleRecognitionResult(text: String, isFinal: Bool, generation: Int) async {
        guard generation == recognitionTaskGeneration else { return }
        guard !isStopping else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            if isFinal {
                // Empty finals usually mean a timeout or silence; restart the capture loop.
                await handleEmptyFinalAndRestart()
            }
            return
        }

        let combined = holdToSpeakActive
            ? SpeechTranscriptMerger.merge(holdToSpeakAccumulatedText, trimmed)
            : trimmed

        updateLastTextAndActivity(combined)

        if isFinal {
            if holdToSpeakActive {
                holdToSpeakAccumulatedText = combined
                emitPartial(combined)
                await handleNonEmptyFinalAndContinue()
            } else {
                emitFinalIfNeeded(combined)
                await stop()
            }
        } else {
            emitPartial(combined)
        }
    }

    private func updateLastTextAndActivity(_ text: String) {
        lastNonEmptyText = text
        hasRecognizedText = true
        lastSpeechAt = .now
        graceUntil = Date().addingTimeInterval(postPartialGrace)
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
            // This final was triggered by our own `endAudio`. Deliver whatever transcript we have
            // (even if empty) so the outer layer can end the session and update the UI.
            if !didEmitFinal {
                didEmitFinal = true
                onFinalHandler?(lastNonEmptyText)
            }
            await stop()
            return
        }
        // Recreate the request/tap and attach a new task to keep the engine running.
        do {
            task?.cancel()
            task = nil
            try await makeNewRequestAndTap()
            attachRecognitionTask()
            // Preserve `hasRecognizedText`; silence-based ending still requires prior text.
        } catch {
            // If restarting fails, fail the session so the UI doesn't get stuck "recording".
            let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = NSLocalizedString("Speech recognition stopped unexpectedly.", comment: "Shown when speech recognition ends without producing a final transcript")
            onErrorHandler?(raw.isEmpty ? fallback : raw)
            await stop()
        }
    }

    private func handleNonEmptyFinalAndContinue() async {
        // A non-empty final indicates the recognition task ended. Recreate the request/tap and
        // attach a new task so we can keep listening (used by hold-to-talk).
        do {
            task?.cancel()
            task = nil
            try await makeNewRequestAndTap()
            attachRecognitionTask()
        } catch {
            let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = NSLocalizedString("Speech recognition stopped unexpectedly.", comment: "Shown when speech recognition ends without producing a final transcript")
            onErrorHandler?(raw.isEmpty ? fallback : raw)
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
        guard !holdToSpeakActive else { return }
        guard !didEmitFinal else { return }
        // Only consider silence termination after producing non-empty text.
        guard hasRecognizedText, let last = lastSpeechAt else { return }

        // Stay active during the grace period to avoid clipping natural pauses.
        if let graceUntil, Date() < graceUntil { return }

        // Enforce the minimum session length measured from the first recognized text.
        if let firstTextAt {
            let alive = Date().timeIntervalSince(firstTextAt)
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

#endif
