#if os(iOS) || os(macOS)

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
@preconcurrency import AVFoundation

#if os(iOS)
struct VoiceVisionCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onVideoOrientationChange: (VoiceVisionVideoOrientation) -> Void

    func makeUIView(context: Context) -> VoiceVisionPreviewView {
        let view = VoiceVisionPreviewView()
        view.onVideoOrientationChange = onVideoOrientationChange
        view.setSession(session)
        return view
    }

    func updateUIView(_ uiView: VoiceVisionPreviewView, context: Context) {
        uiView.onVideoOrientationChange = onVideoOrientationChange
        uiView.setSession(session)
        uiView.updateVideoOrientation()
    }
}

final class VoiceVisionPreviewView: UIView {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    var onVideoOrientationChange: ((VoiceVisionVideoOrientation) -> Void)?
    private var lastVideoOrientation: VoiceVisionVideoOrientation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        updateVideoOrientation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateVideoOrientation()
    }

    func setSession(_ session: AVCaptureSession) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        updateVideoOrientation()
    }

    func updateVideoOrientation() {
        let orientation = VoiceVisionVideoOrientation(interfaceOrientation: window?.windowScene?.interfaceOrientation)
        guard let connection = previewLayer.connection else {
            publishVideoOrientationIfNeeded(orientation)
            return
        }
        connection.applyVoiceVisionOrientation(orientation)
        publishVideoOrientationIfNeeded(orientation)
    }

    private func configure() {
        backgroundColor = .black
        layer.addSublayer(previewLayer)
        previewLayer.videoGravity = .resizeAspectFill
    }

    private func publishVideoOrientationIfNeeded(_ orientation: VoiceVisionVideoOrientation) {
        guard lastVideoOrientation != orientation else { return }
        lastVideoOrientation = orientation
        onVideoOrientationChange?(orientation)
    }
}
#elseif os(macOS)
struct VoiceVisionCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> VoiceVisionPreviewView {
        let view = VoiceVisionPreviewView()
        view.setSession(session)
        return view
    }

    func updateNSView(_ nsView: VoiceVisionPreviewView, context: Context) {
        nsView.setSession(session)
    }
}

final class VoiceVisionPreviewView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }

    func setSession(_ session: AVCaptureSession) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }
    }

    private func configure() {
        wantsLayer = true
        layer = previewLayer
        previewLayer.videoGravity = .resizeAspectFill
    }
}
#endif

#endif
