//
//  VoiceChatOverlayViewModel+VisionCapture.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension VoiceChatOverlayViewModel {
    func presentVisionCapture() {
        guard isPresented else { return }
        guard isVisionCaptureAvailable else {
            pushRealtimeVoiceError(NSLocalizedString(
                "The selected model does not support image input.",
                comment: "Shown when voice vision is requested with a text-only model"
            ))
            return
        }
        _ = visionCaptureCoordinator.present(
            isAvailable: true,
            isRecording: speechInputManager.isRecording,
            isSendSuppressed: isSendSuppressed
        )
        publishVisionCaptureState()
    }

    func dismissVisionCapture() {
        visionCaptureCoordinator.dismiss()
        publishVisionCaptureState()
    }

    func handleVisionCaptureSample(data: Data, mimeType: String?) {
        visionCaptureCoordinator.appendSample(
            data: data,
            mimeType: mimeType,
            isAvailable: isVisionCaptureAvailable
        )
        publishVisionCaptureState()
    }

    func beginVisionCaptureUtteranceIfNeeded() {
        visionCaptureCoordinator.beginUtteranceIfNeeded(
            isAvailable: isVisionCaptureAvailable,
            isSendSuppressed: isSendSuppressed
        )
        publishVisionCaptureState()
    }

    func updateVisionCaptureRecordingState(isRecording: Bool) {
        visionCaptureCoordinator.updateRecordingState(
            isRecording: isRecording,
            isAvailable: isVisionCaptureAvailable,
            isSendSuppressed: isSendSuppressed
        )
        publishVisionCaptureState()
    }

    func selectedVisionAttachmentsForCurrentUtterance() -> [ChatImageAttachment] {
        visionCaptureCoordinator.selectedAttachments(isAvailable: isVisionCaptureAvailable)
    }

    func resetVisionCaptureSamples() {
        visionCaptureCoordinator.resetSamples()
        publishVisionCaptureState()
    }

    func publishVisionCaptureState() {
        let captureState = visionCaptureCoordinator.state
        isVisionCapturePresented = captureState.isPresented
        isVisionCaptureRecording = captureState.isRecording
        visionCaptureSampleCount = captureState.sampleCount
        visionCaptureResetID = captureState.resetID
    }
}
