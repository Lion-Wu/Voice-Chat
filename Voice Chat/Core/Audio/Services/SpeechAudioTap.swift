//
//  SpeechAudioTap.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

#if os(iOS) || os(macOS) || os(visionOS)

import AVFoundation
import Foundation
import Speech

/// Feeds audio buffers into the recognition request and reports amplitude.
final class SpeechAudioTap: @unchecked Sendable {
    private let requestLock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private let motionAudioSource: VoiceMicrophoneAudioSource
    var amplitudeHandler: (@Sendable (Float) -> Void)?

    init(
        request: SFSpeechAudioBufferRecognitionRequest,
        motionAudioSource: VoiceMicrophoneAudioSource
    ) {
        self.request = request
        self.motionAudioSource = motionAudioSource
    }

    func replaceRecognitionRequest(
        _ request: SFSpeechAudioBufferRecognitionRequest?
    ) {
        requestLock.lock()
        self.request = request
        requestLock.unlock()
    }

    func handle(buffer: AVAudioPCMBuffer) {
        let rms = motionAudioSource.append(buffer)

        requestLock.lock()
        request?.append(buffer)
        requestLock.unlock()

        amplitudeHandler?(rms)
    }
}

#endif
