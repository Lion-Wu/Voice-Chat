#if os(iOS) || os(macOS)

import SwiftUI
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import AVFoundation

struct VoiceVisionCameraView: View {
    @ObservedObject var viewModel: VoiceChatOverlayViewModel
    var isCompactLayout = false
    var topTrailingReservedWidth: CGFloat = 0
    @StateObject private var controller = VoiceVisionCameraController()

    var body: some View {
        ZStack {
            Color.black

            Group {
                #if os(iOS)
                VoiceVisionCameraPreview(session: controller.session) { orientation in
                    controller.updateVideoOrientation(orientation)
                }
                #else
                VoiceVisionCameraPreview(session: controller.session)
                #endif
            }
            .opacity(controller.isPreviewVisible ? 1 : 0.001)

            if let statusMessage = controller.statusMessage {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 42, weight: .semibold))
                    Text(statusMessage)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .foregroundStyle(.white.opacity(0.86))
                .padding(24)
            } else if !controller.isPreviewVisible {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            VStack {
                topBar
                Spacer()
            }
            .padding(.horizontal, topBarHorizontalPadding)
            .padding(.vertical, topBarVerticalPadding)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .onAppear {
            controller.onSampleCapture = { data, mimeType in
                viewModel.handleVisionCaptureSample(data: data, mimeType: mimeType)
            }
            controller.resetVisualHistory()
            controller.start()
            controller.setSamplingActive(viewModel.isVisionCaptureRecording)
        }
        .onDisappear {
            controller.stop()
        }
        .onChange(of: viewModel.isVisionCaptureRecording) { _, isActive in
            controller.setSamplingActive(isActive)
        }
        .onChange(of: viewModel.visionCaptureResetID) { _, _ in
            controller.resetVisualHistory()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                viewModel.dismissVisionCapture()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: controlButtonSize, height: controlButtonSize)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel("Close camera")

            Spacer()

#if os(macOS)
            if controller.cameraOptions.count > 1 {
                Menu {
                    ForEach(controller.cameraOptions) { option in
                        Button(option.name) {
                            controller.selectCamera(id: option.id)
                        }
                    }
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: controlButtonSize, height: controlButtonSize)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel("Camera")
            }
#else
            Button {
                controller.flipCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: controlButtonSize, height: controlButtonSize)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(controller.canFlipCamera ? .white : .white.opacity(0.35))
            .disabled(!controller.canFlipCamera)
            .accessibilityLabel("Flip camera")

#if os(iOS)
            Button {
                controller.toggleFlash()
            } label: {
                Image(systemName: controller.isFlashEnabled ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: controlButtonSize, height: controlButtonSize)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(controller.canUseFlash ? .white : .white.opacity(0.35))
            .disabled(!controller.canUseFlash)
            .accessibilityLabel(controller.isFlashEnabled ? "Turn flash off" : "Turn flash on")
#endif
#endif

            if topTrailingReservedWidth > 0 {
                Color.clear
                    .frame(width: topTrailingReservedWidth, height: controlButtonSize)
                    .accessibilityHidden(true)
            }
        }
    }

    private var cornerRadius: CGFloat {
        isCompactLayout ? 18 : 28
    }

    private var controlButtonSize: CGFloat {
        isCompactLayout ? 38 : 44
    }

    private var topBarHorizontalPadding: CGFloat {
        isCompactLayout ? 10 : 22
    }

    private var topBarVerticalPadding: CGFloat {
        isCompactLayout ? 8 : 18
    }
}

#if os(iOS)
private enum VoiceVisionVideoOrientation: Equatable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight

    init(interfaceOrientation: UIInterfaceOrientation?) {
        switch interfaceOrientation {
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeLeft
        case .landscapeRight:
            self = .landscapeRight
        case .unknown, .none:
            self = .portrait
        @unknown default:
            self = .portrait
        }
    }

    var rotationAngle: CGFloat {
        switch self {
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return 270
        case .landscapeRight:
            return 0
        case .landscapeLeft:
            return 180
        }
    }
}

private extension AVCaptureConnection {
    func applyVoiceVisionOrientation(_ orientation: VoiceVisionVideoOrientation) {
        let angle = orientation.rotationAngle
        if isVideoRotationAngleSupported(angle) {
            videoRotationAngle = angle
        }
    }
}

private struct VoiceVisionCameraPreview: UIViewRepresentable {
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

private final class VoiceVisionPreviewView: UIView {
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
private struct VoiceVisionCameraPreview: NSViewRepresentable {
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

private final class VoiceVisionPreviewView: NSView {
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

private final class VoiceVisionCameraController: NSObject, ObservableObject, @unchecked Sendable {
    struct CameraOption: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
    }

    let session = AVCaptureSession()

    @Published private(set) var statusMessage: String?
    @Published private(set) var isPreviewVisible = false
    @Published private(set) var canFlipCamera = false
    @Published private(set) var canUseFlash = false
    @Published private(set) var isFlashEnabled = false
    @Published private(set) var cameraOptions: [CameraOption] = []
    @Published private(set) var selectedCameraID: String?

    var onSampleCapture: ((Data, String?) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.lionwu.voicechat.voice-vision-camera", qos: .userInitiated)
    private let sampleQueue = DispatchQueue(label: "com.lionwu.voicechat.voice-vision-sampling", qos: .utility)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var currentInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var availableDevices: [AVCaptureDevice] = []
    private var recentAcceptedFingerprints: [VisualFingerprint] = []
#if os(iOS)
    private var videoOrientation: VoiceVisionVideoOrientation = .portrait
#endif
    private var isConfigured = false
    private var isSamplingActive = false
    private var isFrameEncodingInFlight = false
    private var lastSampleCaptureAt = DispatchTime(uptimeNanoseconds: 0)
    private let lifecycleLock = NSLock()
    private var isStartRequested = false
    private var startupTask: Task<Void, Never>?

    private static let sampleInterval: TimeInterval = 1.0
    private static let sampleIntervalNanoseconds = UInt64(sampleInterval * 1_000_000_000)
    private static let sampledImageMaxPixelSize: CGFloat = 960
    private static let jpegCompressionQuality: CGFloat = 0.68
    private static let fingerprintGridDimension = 8
    private static let visualChangeThreshold: Double = 10.0
    private static let maxRecentAcceptedFingerprints = 9

    private struct VisualFingerprint {
        let luminance: [UInt8]
    }

    func start() {
        startupTask?.cancel()
        setStartRequested(true)
        updateUI(statusMessage: nil, isPreviewVisible: false)
        startupTask = Task { [weak self] in
            let isAuthorized = await Self.requestCameraAuthorizationIfNeeded()
            guard let self else { return }
            guard isAuthorized else {
                guard !Task.isCancelled, self.shouldContinueStarting else { return }
                self.updateUI(
                    statusMessage: NSLocalizedString(
                        "Allow camera access in Settings and try again.",
                        comment: "Shown when voice vision camera access has not been granted"
                    ),
                    isPreviewVisible: false
                )
                return
            }
            guard !Task.isCancelled, self.shouldContinueStarting else { return }

            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                guard self.shouldContinueStarting else { return }
                do {
                    try self.configureSessionIfNeeded()
                    guard self.shouldContinueStarting else { return }
                    self.session.startRunning()
                    guard self.shouldContinueStarting else {
                        if self.session.isRunning {
                            self.session.stopRunning()
                        }
                        self.updateUI(statusMessage: nil, isPreviewVisible: false)
                        return
                    }
                    self.updateCapabilities()
                    self.updateUI(statusMessage: nil, isPreviewVisible: true)
                } catch {
                    self.updateUI(statusMessage: error.localizedDescription, isPreviewVisible: false)
                }
            }
        }
    }

    func stop() {
        startupTask?.cancel()
        startupTask = nil
        setStartRequested(false)
        setSamplingActive(false)
        resetVisualHistory()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.turnOffTorchIfNeeded()
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.updateUI(statusMessage: nil, isPreviewVisible: false)
        }
        updateUI(statusMessage: nil, isPreviewVisible: false)
    }

    private var shouldContinueStarting: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return isStartRequested
    }

    private func setStartRequested(_ isRequested: Bool) {
        lifecycleLock.lock()
        isStartRequested = isRequested
        lifecycleLock.unlock()
    }

    func setSamplingActive(_ active: Bool) {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            guard self.isSamplingActive != active else { return }
            self.isSamplingActive = active
            if active {
                self.lastSampleCaptureAt = DispatchTime(uptimeNanoseconds: 0)
                self.isFrameEncodingInFlight = false
            } else {
                self.isFrameEncodingInFlight = false
            }
        }
    }

    func resetVisualHistory() {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.recentAcceptedFingerprints.removeAll()
        }
    }

#if os(iOS)
    func updateVideoOrientation(_ orientation: VoiceVisionVideoOrientation) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.videoOrientation != orientation else { return }
            self.videoOrientation = orientation
            self.configureVideoOutputConnection()
        }
    }
#endif

    func toggleFlash() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.currentInput?.device, device.hasTorch else { return }
            let shouldEnable = !self.isFlashEnabled
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if shouldEnable {
                    try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    device.torchMode = .off
                }
                DispatchQueue.main.async { [weak self] in
                    self?.isFlashEnabled = shouldEnable
                }
            } catch {
                self.updateUI(statusMessage: error.localizedDescription, isPreviewVisible: self.session.isRunning)
            }
        }
    }

    private func turnOffTorchIfNeeded() {
        guard let device = currentInput?.device, device.hasTorch else {
            updateFlashEnabled(false)
            return
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.torchMode != .off {
                device.torchMode = .off
            }
            updateFlashEnabled(false)
        } catch {
            updateUI(statusMessage: error.localizedDescription, isPreviewVisible: session.isRunning)
        }
    }

    private func updateFlashEnabled(_ isEnabled: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isFlashEnabled = isEnabled
        }
    }

    func selectCamera(id: String) {
        guard !id.isEmpty else { return }
        guard id != selectedCameraID else { return }
        updateSelectedCamera(id: id)

        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                guard let device = self.availableDevices.first(where: { $0.uniqueID == id }) else {
                    throw VoiceVisionCameraError.noCameraAvailable
                }
                try self.switchCamera(to: device)
                self.updateCapabilities()
                self.updateUI(statusMessage: nil, isPreviewVisible: self.session.isRunning)
            } catch {
                self.updateCapabilities()
                self.updateUI(statusMessage: error.localizedDescription, isPreviewVisible: self.session.isRunning)
            }
        }
    }

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let target: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back
            do {
                guard let device = try self.cameraDevice(position: target) else { return }
                try self.switchCamera(to: device)
                self.updateCapabilities()
            } catch {
                self.updateUI(statusMessage: error.localizedDescription, isPreviewVisible: self.session.isRunning)
            }
        }
    }

    private func configureSessionIfNeeded() throws {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        defer { session.commitConfiguration() }

        refreshAvailableCameras()
        let device = try preferredCameraDevice().orThrow(VoiceVisionCameraError.noCameraAvailable)
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw VoiceVisionCameraError.unableToAddInput }
        session.addInput(input)
        currentInput = input
        currentPosition = device.position
        updateSelectedCamera(id: device.uniqueID)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        guard session.canAddOutput(videoOutput) else { throw VoiceVisionCameraError.unableToAddOutput }
        session.addOutput(videoOutput)
        videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
        configureVideoOutputConnection()
        isConfigured = true
    }

    private func switchCamera(to device: AVCaptureDevice) throws {
        let newInput = try AVCaptureDeviceInput(device: device)
        turnOffTorchIfNeeded()

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if let currentInput {
            session.removeInput(currentInput)
        }

        if session.canAddInput(newInput) {
            session.addInput(newInput)
            currentInput = newInput
            currentPosition = device.position
            updateSelectedCamera(id: device.uniqueID)
            configureVideoOutputConnection()
            resetVisualHistory()
        } else if let currentInput {
            session.addInput(currentInput)
            throw VoiceVisionCameraError.unableToAddInput
        }
    }

    private func configureVideoOutputConnection() {
        guard let connection = videoOutput.connection(with: .video) else { return }
#if os(iOS)
        connection.applyVoiceVisionOrientation(videoOrientation)
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = currentPosition == .front
        }
#endif
    }

    private func shouldCaptureSample(now: DispatchTime) -> Bool {
        guard isSamplingActive else { return false }
        guard !isFrameEncodingInFlight else { return false }
        let elapsed = now.uptimeNanoseconds - lastSampleCaptureAt.uptimeNanoseconds
        guard elapsed >= Self.sampleIntervalNanoseconds else { return false }
        lastSampleCaptureAt = now
        isFrameEncodingInFlight = true
        return true
    }

    private func finishSampleEncoding(data: Data?) {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.isFrameEncodingInFlight = false
        }

        guard let data, !data.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onSampleCapture?(data, "image/jpeg")
        }
    }

    private func encodedJPEGData(from pixelBuffer: CVPixelBuffer) -> Data? {
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        let longestSide = max(image.extent.width, image.extent.height)
        if longestSide > Self.sampledImageMaxPixelSize {
            let scale = Self.sampledImageMaxPixelSize / longestSide
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        guard let cgImage = ciContext.createCGImage(image, from: image.extent.integral) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let options = [
            kCGImageDestinationLossyCompressionQuality as String: Self.jpegCompressionQuality
        ] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func visualFingerprint(from pixelBuffer: CVPixelBuffer) -> VisualFingerprint? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let grid = Self.fingerprintGridDimension
        var luminance: [UInt8] = []
        luminance.reserveCapacity(grid * grid)

        for row in 0..<grid {
            let y = min(height - 1, (height * ((row * 2) + 1)) / (grid * 2))
            for column in 0..<grid {
                let x = min(width - 1, (width * ((column * 2) + 1)) / (grid * 2))
                let offset = (y * bytesPerRow) + (x * 4)
                let blue = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let red = Int(bytes[offset + 2])
                let value = (77 * red + 150 * green + 29 * blue) >> 8
                luminance.append(UInt8(clamping: value))
            }
        }

        return VisualFingerprint(luminance: luminance)
    }

    private func shouldAcceptVisualFingerprint(_ fingerprint: VisualFingerprint?) -> Bool {
        guard let fingerprint else { return true }
        guard !recentAcceptedFingerprints.isEmpty else { return true }

        let nearestDistance = recentAcceptedFingerprints
            .map { visualDistance(fingerprint, $0) }
            .min() ?? .greatestFiniteMagnitude
        return nearestDistance >= Self.visualChangeThreshold
    }

    private func recordAcceptedVisualFingerprint(_ fingerprint: VisualFingerprint?) {
        guard let fingerprint else { return }
        recentAcceptedFingerprints.append(fingerprint)
        if recentAcceptedFingerprints.count > Self.maxRecentAcceptedFingerprints {
            recentAcceptedFingerprints.removeFirst(recentAcceptedFingerprints.count - Self.maxRecentAcceptedFingerprints)
        }
    }

    private func visualDistance(_ lhs: VisualFingerprint, _ rhs: VisualFingerprint) -> Double {
        guard lhs.luminance.count == rhs.luminance.count, !lhs.luminance.isEmpty else {
            return .greatestFiniteMagnitude
        }

        let totalDifference = zip(lhs.luminance, rhs.luminance).reduce(0) { result, pair in
            result + abs(Int(pair.0) - Int(pair.1))
        }
        return Double(totalDifference) / Double(lhs.luminance.count)
    }

    private func updateCapabilities() {
        refreshAvailableCameras()
        let options = availableDevices.map {
            CameraOption(id: $0.uniqueID, name: $0.localizedName)
        }
        let selectedID = currentInput?.device.uniqueID ?? preferredCameraDeviceID(in: availableDevices)
#if os(iOS)
        let hasBack = (try? cameraDevice(position: .back)) != nil
        let hasFront = (try? cameraDevice(position: .front)) != nil
#else
        let hasBack = false
        let hasFront = false
#endif
        let flashAvailable = currentInput?.device.hasTorch == true
        DispatchQueue.main.async { [weak self] in
            self?.canFlipCamera = hasBack && hasFront
            self?.canUseFlash = flashAvailable
            self?.cameraOptions = options
            self?.selectedCameraID = selectedID
            if !flashAvailable {
                self?.isFlashEnabled = false
            }
        }
    }

    private func updateUI(statusMessage: String?, isPreviewVisible: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = statusMessage
            self?.isPreviewVisible = isPreviewVisible
        }
    }

    private func refreshAvailableCameras() {
        availableDevices = cameraDevices()
    }

    private func preferredCameraDevice() -> AVCaptureDevice? {
        if let selectedCameraID,
           let selected = availableDevices.first(where: { $0.uniqueID == selectedCameraID }) {
            return selected
        }

#if os(macOS)
        if let preferred = AVCaptureDevice.systemPreferredCamera,
           availableDevices.contains(where: { $0.uniqueID == preferred.uniqueID }) {
            return preferred
        }
#endif

#if os(iOS)
        if let backCamera = try? cameraDevice(position: .back) {
            return backCamera
        }
        if let frontCamera = try? cameraDevice(position: .front) {
            return frontCamera
        }
#endif

        if let defaultCamera = AVCaptureDevice.default(for: .video),
           availableDevices.contains(where: { $0.uniqueID == defaultCamera.uniqueID }) {
            return defaultCamera
        }

        return availableDevices.first
    }

    private func preferredCameraDeviceID(in devices: [AVCaptureDevice]) -> String? {
        if let selectedCameraID,
           devices.contains(where: { $0.uniqueID == selectedCameraID }) {
            return selectedCameraID
        }

#if os(macOS)
        if let preferred = AVCaptureDevice.systemPreferredCamera,
           devices.contains(where: { $0.uniqueID == preferred.uniqueID }) {
            return preferred.uniqueID
        }
#endif

        return devices.first?.uniqueID
    }

    private func updateSelectedCamera(id: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.selectedCameraID = id
        }
    }

    private func cameraDevice(position: AVCaptureDevice.Position) throws -> AVCaptureDevice? {
#if os(iOS)
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTripleCamera],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first
#else
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first
#endif
    }

    private func cameraDevices() -> [AVCaptureDevice] {
#if os(macOS)
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
#else
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTripleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
#endif
    }

    private static func requestCameraAuthorizationIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

extension VoiceVisionCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard shouldCaptureSample(now: .now()) else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            finishSampleEncoding(data: nil)
            return
        }

        let fingerprint = visualFingerprint(from: pixelBuffer)
        guard shouldAcceptVisualFingerprint(fingerprint) else {
            finishSampleEncoding(data: nil)
            return
        }

        let data = encodedJPEGData(from: pixelBuffer)
        if !(data?.isEmpty ?? true) {
            recordAcceptedVisualFingerprint(fingerprint)
        }
        finishSampleEncoding(data: data)
    }
}

private enum VoiceVisionCameraError: LocalizedError {
    case noCameraAvailable
    case unableToAddInput
    case unableToAddOutput

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable:
            return NSLocalizedString("No camera was found for photo capture.", comment: "Shown when voice vision camera cannot find a camera")
        case .unableToAddInput, .unableToAddOutput:
            return NSLocalizedString("Camera Capture Failed", comment: "Title shown when the camera cannot be configured")
        }
    }
}

private extension Optional {
    func orThrow(_ error: any Error) throws -> Wrapped {
        guard let self else { throw error }
        return self
    }
}

#endif
