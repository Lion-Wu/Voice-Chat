//
//  SpeechAudioTap.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

#if os(iOS) || os(macOS) || os(visionOS)

import AVFoundation
import Speech

/// Feeds audio buffers into the recognition request and reports amplitude.
final class SpeechAudioTap: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    var amplitudeHandler: (@Sendable (Float) -> Void)?

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func handle(buffer: AVAudioPCMBuffer) {
        request.append(buffer)

        var rms: Float = 0
        if let channelData = buffer.floatChannelData {
            let frames = Int(buffer.frameLength)
            if frames > 0 {
                var sum: Float = 0
                let channels = Int(buffer.format.channelCount)
                for channel in 0..<channels {
                    let samples = channelData[channel]
                    var index = 0
                    while index < frames {
                        let sample = samples[index]
                        sum += sample * sample
                        index += 1
                    }
                }
                rms = sqrt(sum / Float(frames * max(1, channels)))
            }
        }
        amplitudeHandler?(rms)
    }
}

#endif
