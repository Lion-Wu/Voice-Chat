//
//  SpeechInputManager.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/20.
//

#if os(iOS) || os(macOS) || os(visionOS)

import Foundation
import Combine
import Speech

#if os(iOS) || os(visionOS)
import AVFoundation
#endif

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

    /// When enabled, dictation will not auto-finalize on silence. The UI uses this to implement
    /// "hold-to-talk" (press and hold to keep listening; release to finalize).
    @Published private(set) var isHoldToSpeakActive: Bool = false

    /// True while the system permission prompt may be on-screen and we're awaiting user input.
    @Published private(set) var isRequestingPermissions: Bool = false

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
                        onFinal:   @escaping @MainActor (String) -> Void,
                        onSpeechActivityStarted: @escaping @MainActor () -> Void = {}) async {
        lastError = nil

        // Stop any active recording before starting a new session.
        if isRecording || currentSessionID != nil {
            await worker.stop()
            isRecording = false
            currentSessionID = nil
            currentOnFinal   = nil
            lastStableText   = ""
            inputLevel       = 0
            levelEMA         = 0
        }

        isRequestingPermissions = true
        let permissionOK = await requestPermissions()
        isRequestingPermissions = false

        // If the calling task was cancelled (e.g. user released long-press or dismissed the overlay),
        // don't surface permission errors or continue bootstrapping speech recognition.
        guard !Task.isCancelled else { return }

        guard permissionOK else {
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

        let speechActivityStartedWrapper: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.currentSessionID == newID else { return }
                onSpeechActivityStarted()
            }
        }

        let errorWrapper: @Sendable (String) -> Void = { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                guard self.currentSessionID == newID else { return }
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                self.lastError = trimmed
                self.isRecording       = false
                self.currentSessionID  = nil
                self.currentOnFinal    = nil
                self.lastStableText    = ""
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
            guard !Task.isCancelled else {
                if self.currentSessionID == newID {
                    await worker.stop()
                    isRecording = false
                    currentSessionID = nil
                    currentOnFinal   = nil
                    lastStableText   = ""
                    inputLevel       = 0
                    levelEMA         = 0
                }
                return
            }

            try await worker.start(
                locale: pickLang.locale,
                onPartial: partialWrapper,
                onFinal:   finalWrapper,
                onSpeechActivityStarted: speechActivityStartedWrapper,
                onLevel:   levelWrapper,
                onError:   errorWrapper
            )
            guard !Task.isCancelled, self.currentSessionID == newID else {
                // Start completed after the caller already stopped/cancelled. Ensure we don't leave
                // the audio engine running or publish `isRecording = true` for a dead session.
                if self.currentSessionID == newID {
                    await worker.stop()
                    isRecording = false
                    currentSessionID = nil
                    currentOnFinal   = nil
                    lastStableText   = ""
                    inputLevel       = 0
                    levelEMA         = 0
                }
                return
            }
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
    nonisolated func stopRecording(finalize: Bool = true) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let capturedID = self.currentSessionID
            let capturedFinal = self.currentOnFinal

            await self.worker.stop()

            // Allow any pending main-actor updates from the recognition callbacks to land.
            await Task.yield()

            let stableText = self.lastStableText.trimmingCharacters(in: .whitespacesAndNewlines)
            let workerText = await self.worker.lastNonEmptyTextSnapshot()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bestText: String = {
                if stableText.isEmpty { return workerText }
                if workerText.isEmpty { return stableText }
                // Prefer the longer transcript in case the UI state lagged behind.
                return (workerText.count > stableText.count) ? workerText : stableText
            }()

            if finalize,
               let capturedFinal,
               let capturedID,
               !bestText.isEmpty,
               self.currentSessionID == capturedID {
                capturedFinal(bestText)
            }

            self.isRecording      = false
            self.currentSessionID = nil
            self.currentOnFinal   = nil
            self.lastStableText   = ""
            self.inputLevel       = 0
            self.levelEMA         = 0
        }
    }

    /// Toggles "hold-to-talk" behaviour for the active recording session.
    /// When enabled, silence-based termination is suspended so the recognizer keeps listening.
    func setHoldToSpeakActive(_ active: Bool) {
        isHoldToSpeakActive = active
        Task { await worker.setHoldToSpeakActive(active) }
    }

    // MARK: - Permissions

    private func requestPermissions() async -> Bool {
        let speechOK = await requestSpeechRecognitionPermission()

        #if os(iOS) || os(visionOS)
        let micOK = await requestMicrophonePermission()
        return speechOK && micOK
        #elseif os(macOS)
        // macOS exposes only speech recognition permission; microphone prompts are system-driven.
        return speechOK
        #endif
    }

    private func requestSpeechRecognitionPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                // TCC may invoke the callback on a background queue; detach to avoid tripping
                // main-actor isolation checks in Swift 6 and hop back only to resume.
                Task.detached {
                    SFSpeechRecognizer.requestAuthorization { status in
                        cont.resume(returning: status == .authorized)
                    }
                }
            }
        @unknown default:
            return false
        }
    }

    #if os(iOS) || os(visionOS)
    private func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                Task.detached {
                    AVAudioApplication.requestRecordPermission { ok in
                        cont.resume(returning: ok)
                    }
                }
            }
        @unknown default:
            return false
        }
    }
    #endif
}

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
    @Published private(set) var isHoldToSpeakActive: Bool = false
    @Published private(set) var isRequestingPermissions: Bool = false

    func startRecording(language: DictationLanguage? = nil,
                        onPartial: @escaping @MainActor (String) -> Void,
                        onFinal:   @escaping @MainActor (String) -> Void,
                        onSpeechActivityStarted: @escaping @MainActor () -> Void = {}) async {
        lastError = NSLocalizedString("Speech input is not supported on this platform.", comment: "Shown when speech input is unavailable")
    }

    func setHoldToSpeakActive(_ active: Bool) {
        isHoldToSpeakActive = active
    }

    nonisolated func stopRecording(finalize: Bool = true) {}
}

#endif
