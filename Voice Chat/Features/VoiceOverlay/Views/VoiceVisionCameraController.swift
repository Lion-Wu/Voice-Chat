#if os(iOS) || os(macOS)

import Combine
import Foundation
@preconcurrency import AVFoundation

final class VoiceVisionCameraController: NSObject, ObservableObject, @unchecked Sendable {
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

    var onSampleCapture: ((Data, String?, VoiceVisionVisualFingerprint?) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.lionwu.voicechat.voice-vision-camera", qos: .userInitiated)
    private let sampleQueue = DispatchQueue(label: "com.lionwu.voicechat.voice-vision-sampling", qos: .utility)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let frameSampler = VoiceVisionFrameSampler()
    private var currentInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var availableDevices: [AVCaptureDevice] = []
#if os(iOS)
    private var videoOrientation: VoiceVisionVideoOrientation = .portrait
#endif
    private var isConfigured = false
    private var isSamplingActive = false
    private var isFrameEncodingInFlight = false
    private var samplingGeneration: UInt64 = 0
    private var lastSampleCaptureAt = DispatchTime(uptimeNanoseconds: 0)
    private let lifecycleLock = NSLock()
    private var isStartRequested = false
    private var startupTask: Task<Void, Never>?

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
            self.samplingGeneration &+= 1
            if active {
                self.lastSampleCaptureAt = DispatchTime(uptimeNanoseconds: 0)
            }
            self.isFrameEncodingInFlight = false
        }
    }

    func resetVisualHistory() {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.frameSampler.resetVisualHistory()
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

    private func sampleCaptureGeneration(now: DispatchTime) -> UInt64? {
        guard isSamplingActive else { return nil }
        guard !isFrameEncodingInFlight else { return nil }
        let elapsed = now.uptimeNanoseconds - lastSampleCaptureAt.uptimeNanoseconds
        guard elapsed >= VoiceVisionCaptureTuning.sampleIntervalNanoseconds else { return nil }
        lastSampleCaptureAt = now
        isFrameEncodingInFlight = true
        return samplingGeneration
    }

    private func finishSampleEncoding(sample: VoiceVisionEncodedSample?, generation: UInt64) {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            guard self.samplingGeneration == generation else { return }
            self.isFrameEncodingInFlight = false

            guard self.isSamplingActive, let sample else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onSampleCapture?(sample.data, "image/jpeg", sample.visualFingerprint)
            }
        }
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
        guard let generation = sampleCaptureGeneration(now: .now()) else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            finishSampleEncoding(sample: nil, generation: generation)
            return
        }

        finishSampleEncoding(sample: frameSampler.encodedAcceptedSample(from: pixelBuffer), generation: generation)
    }
}

#endif
