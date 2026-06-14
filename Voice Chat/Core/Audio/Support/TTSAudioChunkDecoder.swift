//
//  TTSAudioChunkDecoder.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import AVFoundation
import Foundation

struct TTSAudioChunk: Equatable {
    let data: Data
    let duration: TimeInterval
}

enum TTSAudioChunkDecodeFailure: Error, Equatable {
    case emptyData
    case unsupportedAudioData

    var disposition: TTSFailureDisposition {
        switch self {
        case .emptyData:
            return .transient
        case .unsupportedAudioData:
            return .content
        }
    }

    var message: String {
        switch self {
        case .emptyData:
            return NSLocalizedString("No data received", comment: "Shown when the TTS server returns an empty body")
        case .unsupportedAudioData:
            return NSLocalizedString("Received audio data could not be played.", comment: "Shown when AVAudioPlayer fails to read TTS audio data")
        }
    }
}

enum TTSAudioChunkDecoder {
    static func decode(_ data: Data) throws -> TTSAudioChunk {
        guard !data.isEmpty else {
            throw TTSAudioChunkDecodeFailure.emptyData
        }

        do {
            let player = try AVAudioPlayer(data: data)
            return TTSAudioChunk(data: data, duration: max(0, player.duration))
        } catch {
            throw TTSAudioChunkDecodeFailure.unsupportedAudioData
        }
    }
}
