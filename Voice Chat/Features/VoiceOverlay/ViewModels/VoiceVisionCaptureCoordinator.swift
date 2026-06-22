//
//  VoiceVisionCaptureCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import Foundation

struct VoiceVisionCaptureState {
    var isPresented = false
    var isRecording = false
    var sampleCount = 0
    var resetID = UUID()
}

@MainActor
struct VoiceVisionCaptureCoordinator {
    private(set) var state = VoiceVisionCaptureState()
    private var messageStartedAt: Date?
    private var samples: [VoiceVisionCaptureSample] = []

    mutating func present(
        isAvailable: Bool,
        isRecording: Bool,
        isSendSuppressed: Bool,
        now: Date = Date()
    ) -> Bool {
        guard isAvailable else { return false }
        state.isPresented = true
        if isRecording {
            beginUtteranceIfNeeded(
                isAvailable: isAvailable,
                isSendSuppressed: isSendSuppressed,
                now: now
            )
        } else {
            updateRecordingState(
                isRecording: false,
                isAvailable: isAvailable,
                isSendSuppressed: isSendSuppressed
            )
        }
        return true
    }

    mutating func dismiss() {
        state.isPresented = false
        resetSamples()
    }

    mutating func appendSample(
        data: Data,
        mimeType: String?,
        visualFingerprint: VoiceVisionVisualFingerprint? = nil,
        isAvailable: Bool,
        now: Date = Date()
    ) {
        guard state.isPresented else { return }
        guard state.isRecording else { return }
        guard isAvailable else { return }
        guard !data.isEmpty else { return }

        let attachment = ChatImageAttachment(
            mimeType: VoiceVisionSampleSelector.normalizedMIMEType(mimeType),
            data: data
        )
        samples.append(.init(
            capturedAt: now,
            attachment: attachment,
            visualFingerprint: visualFingerprint
        ))
        if samples.count > VoiceVisionSampleSelector.maxStoredSamples {
            samples = VoiceVisionSampleSelector.evenlyDownsampled(
                samples,
                limit: VoiceVisionSampleSelector.maxStoredSamples
            )
        }
        state.sampleCount = estimatedAttachmentCount(isAvailable: isAvailable, now: now)
    }

    mutating func beginUtteranceIfNeeded(
        isAvailable: Bool,
        isSendSuppressed: Bool,
        now: Date = Date()
    ) {
        updateRecordingState(
            isRecording: true,
            isAvailable: isAvailable,
            isSendSuppressed: isSendSuppressed
        )
        guard state.isRecording else { return }
        // A held voice message can restart recording after a speech pause; keep its samples together.
        guard !isSendSuppressed || messageStartedAt == nil else { return }
        messageStartedAt = now
        samples.removeAll()
        state.sampleCount = 0
        state.resetID = UUID()
    }

    mutating func updateRecordingState(
        isRecording: Bool,
        isAvailable: Bool,
        isSendSuppressed: Bool
    ) {
        let shouldRecord = state.isPresented && isAvailable && isRecording
        state.isRecording = shouldRecord
        if !shouldRecord && !isRecording && !isSendSuppressed {
            messageStartedAt = nil
        }
    }

    func selectedAttachments(isAvailable: Bool, now: Date = Date()) -> [ChatImageAttachment] {
        VoiceVisionSampleSelector.selectedAttachments(
            from: samples,
            startedAt: messageStartedAt,
            now: now,
            isAvailable: isAvailable
        )
    }

    mutating func resetSamples() {
        messageStartedAt = nil
        samples.removeAll()
        state.sampleCount = 0
        state.isRecording = false
        state.resetID = UUID()
    }

    private func estimatedAttachmentCount(isAvailable: Bool, now: Date = Date()) -> Int {
        VoiceVisionSampleSelector.estimatedAttachmentCount(
            from: samples,
            startedAt: messageStartedAt,
            now: now,
            isAvailable: isAvailable
        )
    }
}
