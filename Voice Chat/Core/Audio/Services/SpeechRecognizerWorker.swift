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

enum SpeechRecognitionTaskErrorDisposition: Equatable {
    case restart
    case finish
    case fail
}

enum SpeechRecognitionTaskErrorPolicy {
    private static let assistantErrorDomain = "kAFAssistantErrorDomain"
    private static let noSpeechDetectedCode = 1110

    static func disposition(
        for error: Error,
        didEndAudioForSilence: Bool,
        currentTaskHasRecognizedText: Bool,
        continuesListeningAfterRecognizedText: Bool
    ) -> SpeechRecognitionTaskErrorDisposition {
        let error = error as NSError
        guard error.domain == assistantErrorDomain,
              error.code == noSpeechDetectedCode else {
            return .fail
        }

        if didEndAudioForSilence || (currentTaskHasRecognizedText && !continuesListeningAfterRecognizedText) {
            return .finish
        }
        return .restart
    }
}

#if os(iOS) || os(visionOS)
private final class SpeechRecognitionAudioSessionController: @unchecked Sendable {
    static let shared = SpeechRecognitionAudioSessionController()

    private let configurationQueue = DispatchQueue(
        label: "com.voicechat.speech-recognition.audio-session"
    )

    private init() {}

    func activateForRecognition() async throws {
        let session = AVAudioSession.sharedInstance()
        try await performConfiguration {
            let category: AVAudioSession.Category =
                session.availableCategories.contains(.playAndRecord) ? .playAndRecord : .record
            let mode: AVAudioSession.Mode =
                session.availableModes.contains(.voiceChat) ? .voiceChat : .default

            #if os(iOS)
            let options: AVAudioSession.CategoryOptions = [
                .duckOthers,
                .defaultToSpeaker,
                .allowBluetoothA2DP,
                .allowBluetoothHFP
            ]
            #else
            let options: AVAudioSession.CategoryOptions = []
            #endif

            try session.setCategory(category, mode: mode, options: options)
        }

        if #available(iOS 27.0, visionOS 27.0, *) {
            guard try await session.activate(options: []) else {
                throw ActivationError.rejected
            }
        } else {
            try await performConfiguration {
                try session.setActive(true, options: [])
            }
        }
    }

    func deactivateAfterRecognition() async {
        let session = AVAudioSession.sharedInstance()
        if #available(iOS 27.0, visionOS 27.0, *) {
            _ = try? await session.deactivate(options: [])
        } else {
            try? await performConfiguration {
                try session.setActive(false, options: [])
            }
        }

        try? await performConfiguration {
            guard session.availableCategories.contains(.playback) else { return }
            try session.setCategory(.playback, mode: .default, options: [])
        }
    }

    private func performConfiguration<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            configurationQueue.async {
                continuation.resume(with: Result { try operation() })
            }
        }
    }

    private enum ActivationError: LocalizedError {
        case rejected

        var errorDescription: String? {
            NSLocalizedString(
                "The system did not activate the audio session.",
                comment: "Speech recognition audio-session activation error"
            )
        }
    }
}
#endif

// MARK: - Background recognition worker

actor SpeechRecognizerWorker {

    // MARK: - Internal objects
    private var audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    #if os(iOS) || os(visionOS)
    private let audioSessionController = SpeechRecognitionAudioSessionController.shared
    #endif

    private var tapInstalled = false
    private var audioTap: SpeechAudioTap?

    // MARK: - Callbacks
    private var onPartialHandler: (@Sendable (String) -> Void)?
    private var onFinalHandler: (@Sendable (String) -> Void)?
    private var onSpeechActivityStartedHandler: (@Sendable () -> Void)?
    private var onErrorHandler: (@Sendable (String) -> Void)?
    private var motionAudioSource: VoiceMicrophoneAudioSource?

    // MARK: - End-of-speech detection
    /// Timestamp of the most recent detected speech activity; remains nil until speech is detected.
    private var lastSpeechAt: Date?
    private var silenceLimit: TimeInterval = 1.2
    private var monitorTask: Task<Void, Never>?

    // Energy threshold (linear amplitude, roughly -44 dB). Lower values make voice detection more sensitive.
    private let vadLevelThreshold: Float = 0.006
    private let speechActivityStartMinimumDuration: TimeInterval = 0.25
    private let speechActivityStartMinimumSamples = 4
    private let speechActivityResetLevelThreshold: Float = 0.003
    private var didEndAudioForSilence = false

    /// Grace period after non-empty text is recognized; silence will not end the session during this window.
    private let postPartialGrace: TimeInterval = 0.6
    private var graceUntil: Date?

    /// Timestamp of the first non-empty transcript; used to guarantee a minimum session length.
    private var firstTextAt: Date?
    /// Minimum time to keep the session open after the first text to avoid clipping natural pauses.
    private let minActiveAfterFirstText: TimeInterval = 1.0

    /// Silence-based termination is allowed only after the session produces non-empty text.
    private var sessionHasRecognizedText = false
    /// Tracks text produced by the active recognition task, independently of earlier task rollovers.
    private var currentTaskHasRecognizedText = false
    private var didNotifySpeechActivityStarted = false
    private var sustainedSpeechActivityStartedAt: Date?
    private var sustainedSpeechActivitySampleCount = 0

    // MARK: - Misc state
    private var lastNonEmptyText = ""
    private var didEmitFinal = false
    private var isStopping = false
    private var isRestartingRecognitionTask = false
    private var recognitionTaskGeneration = 0
    private let microphoneTapBufferSize: AVAudioFrameCount = 512

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
               onSpeechActivityStarted: @Sendable @escaping () -> Void,
               motionAudioSource: VoiceMicrophoneAudioSource,
               onError: @Sendable @escaping (String) -> Void) async throws {
        // Stop any existing session before starting a new one.
        if audioEngine.isRunning || tapInstalled || request != nil || task != nil {
            await stop()
        }

        onPartialHandler = onPartial
        onFinalHandler = onFinal
        onSpeechActivityStartedHandler = onSpeechActivityStarted
        onErrorHandler = onError
        self.motionAudioSource = motionAudioSource
        motionAudioSource.reset()
        lastNonEmptyText = ""
        holdToSpeakAccumulatedText = ""
        didEmitFinal = false
        isStopping = false
        isRestartingRecognitionTask = false

        // Important: silence cannot end the session until real speech has been heard.
        lastSpeechAt = nil
        sessionHasRecognizedText = false
        currentTaskHasRecognizedText = false
        didNotifySpeechActivityStarted = false
        resetSustainedSpeechActivity()
        didEndAudioForSilence = false
        graceUntil = nil
        firstTextAt = nil

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }
        self.recognizer = recognizer

        #if os(iOS) || os(visionOS)
        try await audioSessionController.activateForRecognition()
        #endif

        // A long-lived engine can retain the client format of an input device that has
        // since disconnected. Build the I/O graph from the current route for each session.
        audioEngine = AVAudioEngine()
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

        audioTap?.replaceRecognitionRequest(nil)
        request?.endAudio()
        request = nil

        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
            audioTap = nil
        }

        if audioEngine.isRunning { audioEngine.stop() }

        #if os(iOS) || os(visionOS)
        await audioSessionController.deactivateAfterRecognition()
        #endif

        recognizer = nil
        onPartialHandler = nil
        onFinalHandler = nil
        onSpeechActivityStartedHandler = nil
        onErrorHandler = nil
        motionAudioSource?.reset()
        motionAudioSource = nil

        monitorTask?.cancel()
        monitorTask = nil

        didEndAudioForSilence = false
        sessionHasRecognizedText = false
        currentTaskHasRecognizedText = false
        didNotifySpeechActivityStarted = false
        resetSustainedSpeechActivity()
        lastSpeechAt = nil
        graceUntil = nil
        firstTextAt = nil
        isRestartingRecognitionTask = false
    }

    // MARK: - Internal setup helpers

    private func makeNewRequestAndTap() async throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        self.request = request

        if let audioTap {
            audioTap.replaceRecognitionRequest(request)
            return
        }

        guard let motionAudioSource else {
            throw SpeechError.engineStartFailed(
                "Voice Motion audio source is unavailable."
            )
        }
        let inputNode = audioEngine.inputNode
        let tap = SpeechAudioTap(
            request: request,
            motionAudioSource: motionAudioSource
        )
        tap.amplitudeHandler = { [weak self] level in
            guard let self else { return }
            Task { await self.handleAmplitude(level) }
        }
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw SpeechError.engineStartFailed("Microphone format is unavailable.")
        }
        inputNode.installTap(
            onBus: 0,
            bufferSize: microphoneTapBufferSize,
            format: nil
        ) { [tap] buffer, _ in
            tap.handle(buffer: buffer)
        }
        audioTap = tap
        tapInstalled = true
    }

    /// Establishes the recognition task.
    private func attachRecognitionTask() {
        guard let recognizer, let request else { return }
        currentTaskHasRecognizedText = false
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
        switch SpeechRecognitionTaskErrorPolicy.disposition(
            for: error,
            didEndAudioForSilence: didEndAudioForSilence,
            currentTaskHasRecognizedText: currentTaskHasRecognizedText,
            continuesListeningAfterRecognizedText: holdToSpeakActive
        ) {
        case .restart:
            if currentTaskHasRecognizedText && holdToSpeakActive {
                holdToSpeakAccumulatedText = lastNonEmptyText
                emitPartial(lastNonEmptyText)
            }
            await restartRecognitionTask()
        case .finish:
            await finishRecognitionSession()
        case .fail:
            isStopping = true
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                onErrorHandler?(message)
            }
            await stop()
        }
    }

    private func restartRecognitionTask() async {
        guard !isRestartingRecognitionTask else { return }
        isRestartingRecognitionTask = true
        defer { isRestartingRecognitionTask = false }

        isStopping = true
        recognitionTaskGeneration &+= 1
        task?.cancel()
        task = nil
        audioTap?.replaceRecognitionRequest(nil)
        request?.endAudio()
        request = nil

        currentTaskHasRecognizedText = false
        didEndAudioForSilence = false
        if !sessionHasRecognizedText {
            lastSpeechAt = nil
            didNotifySpeechActivityStarted = false
            resetSustainedSpeechActivity()
            graceUntil = nil
            firstTextAt = nil
        }

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
        registerVoiceActivity(level)
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

        currentTaskHasRecognizedText = true
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
        sessionHasRecognizedText = true
        lastSpeechAt = .now
        notifySpeechActivityStartedIfNeeded()
        graceUntil = Date().addingTimeInterval(postPartialGrace)
        if firstTextAt == nil { firstTextAt = .now }
    }

    private func registerVoiceActivity(_ level: Float) {
        // Track only the timestamps to avoid ending the session early due to background noise.
        let now = Date()
        if level >= vadLevelThreshold {
            lastSpeechAt = now
            registerSustainedSpeechActivity(now: now)
        } else if level < speechActivityResetLevelThreshold {
            resetSustainedSpeechActivity()
        }
    }

    private func registerSustainedSpeechActivity(now: Date) {
        guard !didNotifySpeechActivityStarted else { return }
        if sustainedSpeechActivityStartedAt == nil {
            sustainedSpeechActivityStartedAt = now
            sustainedSpeechActivitySampleCount = 0
        }
        sustainedSpeechActivitySampleCount += 1

        guard let startedAt = sustainedSpeechActivityStartedAt else { return }
        guard sustainedSpeechActivitySampleCount >= speechActivityStartMinimumSamples else { return }
        guard now.timeIntervalSince(startedAt) >= speechActivityStartMinimumDuration else { return }
        notifySpeechActivityStartedIfNeeded()
    }

    private func resetSustainedSpeechActivity() {
        sustainedSpeechActivityStartedAt = nil
        sustainedSpeechActivitySampleCount = 0
    }

    private func notifySpeechActivityStartedIfNeeded() {
        guard !didNotifySpeechActivityStarted else { return }
        didNotifySpeechActivityStarted = true
        resetSustainedSpeechActivity()
        onSpeechActivityStartedHandler?()
    }

    private func finishRecognitionSession() async {
        if !didEmitFinal {
            didEmitFinal = true
            onFinalHandler?(lastNonEmptyText)
        }
        await stop()
    }

    /// When an empty final result arrives, restart recognition instead of ending the session.
    private func handleEmptyFinalAndRestart() async {
        // Only restart if the session wasn't intentionally ended due to silence after valid text.
        if didEndAudioForSilence {
            await finishRecognitionSession()
            return
        }
        await restartRecognitionTask()
    }

    private func handleNonEmptyFinalAndContinue() async {
        await restartRecognitionTask()
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
        guard sessionHasRecognizedText, let last = lastSpeechAt else { return }

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
