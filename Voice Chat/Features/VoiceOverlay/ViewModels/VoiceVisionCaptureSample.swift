//
//  VoiceVisionCaptureSample.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct VoiceVisionVisualFingerprint: Equatable, Sendable {
    let luminance: [UInt8]
}

struct VoiceVisionCaptureSample: Equatable, Sendable {
    let capturedAt: Date
    let attachment: ChatImageAttachment
    let visualFingerprint: VoiceVisionVisualFingerprint?

    init(
        capturedAt: Date,
        attachment: ChatImageAttachment,
        visualFingerprint: VoiceVisionVisualFingerprint? = nil
    ) {
        self.capturedAt = capturedAt
        self.attachment = attachment
        self.visualFingerprint = visualFingerprint
    }
}
