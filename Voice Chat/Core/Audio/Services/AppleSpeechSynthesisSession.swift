//
//  AppleSpeechSynthesisSession.swift
//  Voice Chat
//
//  Created by Codex on 2026/7/28.
//

import AVFoundation
import Foundation

enum AppleSpeechSynthesisError: LocalizedError, Equatable, Sendable {
    case cancelled
    case emptyText
    case voiceUnavailable
    case unexpectedBuffer
    case audioFileFailure
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return NSLocalizedString("Apple Speech synthesis was cancelled.", comment: "Apple speech synthesis cancellation")
        case .emptyText:
            return NSLocalizedString("There is no text to speak.", comment: "Apple speech synthesis received empty text")
        case .voiceUnavailable:
            return NSLocalizedString("The selected Apple voice is not installed or is unavailable.", comment: "Selected Apple speech voice cannot be used")
        case .unexpectedBuffer:
            return NSLocalizedString("Apple Speech returned an unsupported audio format.", comment: "Apple speech returned a non-PCM audio buffer")
        case .audioFileFailure:
            return NSLocalizedString("Apple Speech audio could not be prepared for playback.", comment: "Apple speech audio file conversion failed")
        case .emptyAudio:
            return NSLocalizedString("Apple Speech did not produce any audio.", comment: "Apple speech synthesis returned no audio frames")
        }
    }

    var disposition: TTSFailureDisposition {
        switch self {
        case .cancelled:
            return .fatal
        case .emptyText, .voiceUnavailable:
            return .fatal
        case .unexpectedBuffer, .audioFileFailure, .emptyAudio:
            return .transient
        }
    }
}

/// Owns one `AVSpeechSynthesizer.write` operation and converts its PCM buffers into
/// a self-contained CAF payload that the existing audio queue can play and seek.
final class AppleSpeechSynthesisSession: @unchecked Sendable {
    typealias Completion = @MainActor @Sendable (Result<Data, AppleSpeechSynthesisError>) -> Void

    private let lock = NSLock()
    private let temporaryURL: URL
    private let completion: Completion
    private var synthesizer: AVSpeechSynthesizer?
    private var audioFile: AVAudioFile?
    private var audioFileSettings: [String: Any] = [:]
    private var isCompleted = false
    private var wroteAudioFrames = false

    private init(completion: @escaping Completion) {
        self.completion = completion
        self.temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceChat-AppleSpeech-\(UUID().uuidString)")
            .appendingPathExtension("caf")
    }

    static func start(
        text: String,
        voiceIdentifier: String?,
        provider: TTSProvider,
        completion: @escaping Completion
    ) -> AppleSpeechSynthesisSession {
        let session = AppleSpeechSynthesisSession(completion: completion)
        session.start(text: text, voiceIdentifier: voiceIdentifier, provider: provider)
        return session
    }

    func cancel() {
        lock.lock()
        let activeSynthesizer = synthesizer
        lock.unlock()

        _ = activeSynthesizer?.stopSpeaking(at: .immediate)
        finish(with: .failure(.cancelled))
    }

    private func start(
        text: String,
        voiceIdentifier: String?,
        provider: TTSProvider
    ) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            finish(with: .failure(.emptyText))
            return
        }

        let selectedIdentifier = voiceIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let voice: AVSpeechSynthesisVoice?
        if let selectedIdentifier, !selectedIdentifier.isEmpty {
            voice = AVSpeechSynthesisVoice(identifier: selectedIdentifier)
        } else {
            voice = AVSpeechSynthesisVoice.speechVoices().first {
                !$0.voiceTraits.contains(.isPersonalVoice)
                    && $0.language == AVSpeechSynthesisVoice.currentLanguageCode()
            } ?? AVSpeechSynthesisVoice.speechVoices().first {
                !$0.voiceTraits.contains(.isPersonalVoice)
            }
        }

        guard let voice,
              (provider == .personalVoice) == voice.voiceTraits.contains(.isPersonalVoice) else {
            finish(with: .failure(.voiceUnavailable))
            return
        }

        let utterance = AVSpeechUtterance(string: trimmedText)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        let newSynthesizer = AVSpeechSynthesizer()
        lock.lock()
        synthesizer = newSynthesizer
        audioFileSettings = voice.audioFileSettings
        lock.unlock()

        newSynthesizer.write(utterance) { [weak self] buffer in
            self?.consume(buffer)
        }
    }

    private func consume(_ buffer: AVAudioBuffer) {
        guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
            finish(with: .failure(.unexpectedBuffer))
            return
        }

        guard pcmBuffer.frameLength > 0 else {
            finishFromAudioFile()
            return
        }

        var writeFailure: AppleSpeechSynthesisError?
        lock.lock()
        if !isCompleted {
            do {
                if audioFile == nil {
                    audioFile = try AVAudioFile(
                        forWriting: temporaryURL,
                        settings: audioFileSettings
                    )
                }
                try audioFile?.write(from: pcmBuffer)
                wroteAudioFrames = true
            } catch {
                writeFailure = .audioFileFailure
            }
        }
        lock.unlock()

        if let writeFailure {
            finish(with: .failure(writeFailure))
        }
    }

    private func finishFromAudioFile() {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        guard wroteAudioFrames else {
            lock.unlock()
            finish(with: .failure(.emptyAudio))
            return
        }

        isCompleted = true
        audioFile = nil
        synthesizer = nil
        lock.unlock()

        let result: Result<Data, AppleSpeechSynthesisError>
        do {
            let data = try Data(contentsOf: temporaryURL)
            result = data.isEmpty ? .failure(.emptyAudio) : .success(data)
        } catch {
            result = .failure(.audioFileFailure)
        }
        removeTemporaryFile()
        deliver(result)
    }

    private func finish(with result: Result<Data, AppleSpeechSynthesisError>) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        isCompleted = true
        audioFile = nil
        synthesizer = nil
        lock.unlock()

        removeTemporaryFile()
        deliver(result)
    }

    private func deliver(_ result: Result<Data, AppleSpeechSynthesisError>) {
        Task { @MainActor [completion] in
            completion(result)
        }
    }

    private func removeTemporaryFile() {
        try? FileManager.default.removeItem(at: temporaryURL)
    }
}
