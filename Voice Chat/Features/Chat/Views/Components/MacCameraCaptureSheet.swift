#if os(macOS)

import SwiftUI
import AppKit
@preconcurrency import AVFoundation

struct MacCameraCaptureSheet: View {
    let onCapture: (Data, String?) -> Void
    let onFailure: () -> Void
    let onDismiss: () -> Void

    @StateObject private var controller = MacCameraCaptureController()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                MacCameraPreviewRepresentable(session: controller.session)
                    .opacity(controller.isPreviewVisible ? 1 : 0.001)

                if let statusMessage = controller.statusMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(statusMessage)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }
                    .padding(24)
                } else if !controller.isPreviewVisible {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .frame(minWidth: 700, minHeight: 460)
            .background(Color.black.opacity(0.92))

            Divider()

            HStack {
                Button("Cancel") {
                    onDismiss()
                }

                if controller.cameraOptions.count > 1 {
                    Picker("Camera", selection: cameraSelectionBinding) {
                        ForEach(controller.cameraOptions) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280, alignment: .leading)
                }

                Spacer()

                Button("Take Photo") {
                    controller.capturePhoto()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!controller.canCapture)
            }
            .padding(16)
        }
        .frame(minWidth: 700, minHeight: 520)
        .onAppear {
            controller.onCapture = { data, mimeType in
                onCapture(data, mimeType)
            }
            controller.onFailure = {
                onFailure()
            }
            controller.start()
        }
        .onDisappear {
            controller.stop()
        }
    }

    private var cameraSelectionBinding: Binding<String> {
        Binding(
            get: { controller.selectedCameraID ?? "" },
            set: { newValue in
                controller.selectCamera(id: newValue)
            }
        )
    }
}

private struct MacCameraPreviewRepresentable: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> MacCameraPreviewView {
        let view = MacCameraPreviewView()
        view.setSession(session)
        return view
    }

    func updateNSView(_ nsView: MacCameraPreviewView, context: Context) {
        nsView.setSession(session)
    }
}

private final class MacCameraPreviewView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = previewLayer
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = previewLayer
        previewLayer.videoGravity = .resizeAspectFill
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
}

private enum MacCameraCaptureError: LocalizedError {
    case noCameraAvailable
    case unableToCreateInput
    case unableToAddInput
    case unableToAddOutput

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable:
            return NSLocalizedString("No camera was found for photo capture.", comment: "Shown in the macOS camera sheet when no camera device is available")
        case .unableToCreateInput, .unableToAddInput, .unableToAddOutput:
            return NSLocalizedString("Camera Capture Failed", comment: "Title shown when the system camera UI returns no usable photo")
        }
    }
}

private final class StartupCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var isMarkedCancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isMarkedCancelled
    }

    func cancel() {
        lock.lock()
        isMarkedCancelled = true
        lock.unlock()
    }
}

private final class MacCameraCaptureController: NSObject, ObservableObject, @unchecked Sendable {
    struct CameraOption: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
    }

    let session = AVCaptureSession()

    @Published private(set) var statusMessage: String?
    @Published private(set) var canCapture: Bool = false
    @Published private(set) var isPreviewVisible: Bool = false
    @Published private(set) var cameraOptions: [CameraOption] = []
    @Published private(set) var selectedCameraID: String?

    var onCapture: ((Data, String?) -> Void)?
    var onFailure: (() -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.lionwu.voicechat.mac-camera-capture", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var currentVideoInput: AVCaptureDeviceInput?
    private var availableDevices: [AVCaptureDevice] = []
    private var startupTask: Task<Void, Never>?
    private var startupCancellation: StartupCancellation?

    func start() {
        cancelStartup()
        updateUI(statusMessage: nil, canCapture: false, isPreviewVisible: false)

        let cancellation = StartupCancellation()
        startupCancellation = cancellation

        startupTask = Task { [weak self] in
            guard let self else { return }
            defer { self.clearStartupIfCurrent(cancellation) }

            guard !cancellation.isCancelled else { return }
            guard await requestAuthorizationIfNeeded() else {
                guard !cancellation.isCancelled else { return }
                updateUI(
                    statusMessage: NSLocalizedString(
                        "Allow camera access in System Settings and try again.",
                        comment: "Shown in the macOS camera sheet when camera permission has not been granted"
                    ),
                    canCapture: false,
                    isPreviewVisible: false
                )
                return
            }

            do {
                refreshAvailableCameras()
                try await configureAndStartSessionIfNeeded(cancellation: cancellation)
                guard !cancellation.isCancelled else { return }
                updateUI(statusMessage: nil, canCapture: true, isPreviewVisible: true)
            } catch is CancellationError {
                return
            } catch {
                guard !cancellation.isCancelled else { return }
                updateUI(
                    statusMessage: error.localizedDescription,
                    canCapture: false,
                    isPreviewVisible: false
                )
            }
        }
    }

    func selectCamera(id: String) {
        guard !id.isEmpty else { return }
        guard id != selectedCameraID else { return }
        updateSelectedCamera(id: id)

        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.switchCameraIfNeeded(to: id)
                self.updateUI(statusMessage: nil, canCapture: self.session.isRunning, isPreviewVisible: self.session.isRunning)
            } catch {
                self.updateUI(
                    statusMessage: error.localizedDescription,
                    canCapture: false,
                    isPreviewVisible: false
                )
            }
        }
    }

    func stop() {
        cancelStartup()
        updateUI(statusMessage: nil, canCapture: false, isPreviewVisible: false)

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func capturePhoto() {
        guard canCapture else { return }
        updateUI(statusMessage: nil, canCapture: false, isPreviewVisible: true)

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
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

    private func configureAndStartSessionIfNeeded(cancellation: StartupCancellation) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: MacCameraCaptureError.unableToCreateInput)
                    return
                }
                guard !cancellation.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                do {
                    if !self.isConfigured {
                        try self.configureCaptureSession()
                        self.isConfigured = true
                    }
                    guard !cancellation.isCancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    guard !cancellation.isCancelled else {
                        if self.session.isRunning {
                            self.session.stopRunning()
                        }
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configureCaptureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        for input in session.inputs {
            session.removeInput(input)
        }

        for output in session.outputs {
            session.removeOutput(output)
        }

        refreshAvailableCameras()

        guard let device = preferredCaptureDevice() else {
            throw MacCameraCaptureError.noCameraAvailable
        }

        currentVideoInput = try makeAndAddInput(for: device, to: session)

        guard session.canAddOutput(photoOutput) else {
            throw MacCameraCaptureError.unableToAddOutput
        }
        session.addOutput(photoOutput)
    }

    private func preferredCaptureDevice() -> AVCaptureDevice? {
        if let selectedCameraID,
           let selected = availableDevices.first(where: { $0.uniqueID == selectedCameraID }) {
            return selected
        }

        if let preferred = AVCaptureDevice.systemPreferredCamera,
           availableDevices.contains(where: { $0.uniqueID == preferred.uniqueID }) {
            return preferred
        }

        if let device = AVCaptureDevice.default(for: .video),
           availableDevices.contains(where: { $0.uniqueID == device.uniqueID }) {
            return device
        }

        return availableDevices.first
    }

    private func refreshAvailableCameras() {
        let discoveredDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices

        availableDevices = discoveredDevices

        let options = discoveredDevices.map {
            CameraOption(id: $0.uniqueID, name: $0.localizedName)
        }

        let preferredID = preferredCaptureDeviceID(in: discoveredDevices)
        updateCameraOptions(options, selectedCameraID: preferredID)
    }

    private func preferredCaptureDeviceID(in devices: [AVCaptureDevice]) -> String? {
        if let selectedCameraID,
           devices.contains(where: { $0.uniqueID == selectedCameraID }) {
            return selectedCameraID
        }

        if let preferred = AVCaptureDevice.systemPreferredCamera,
           devices.contains(where: { $0.uniqueID == preferred.uniqueID }) {
            return preferred.uniqueID
        }

        if let fallback = devices.first {
            return fallback.uniqueID
        }

        return nil
    }

    private func makeAndAddInput(for device: AVCaptureDevice, to session: AVCaptureSession) throws -> AVCaptureDeviceInput {
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw MacCameraCaptureError.unableToCreateInput
        }

        guard session.canAddInput(input) else {
            throw MacCameraCaptureError.unableToAddInput
        }

        session.addInput(input)
        updateSelectedCamera(id: device.uniqueID)
        return input
    }

    private func switchCameraIfNeeded(to cameraID: String) throws {
        guard let device = availableDevices.first(where: { $0.uniqueID == cameraID }) else {
            throw MacCameraCaptureError.noCameraAvailable
        }

        guard currentVideoInput?.device.uniqueID != cameraID else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let existingInput = currentVideoInput
        if let existingInput {
            session.removeInput(existingInput)
        }

        do {
            currentVideoInput = try makeAndAddInput(for: device, to: session)
        } catch {
            if let existingInput, session.canAddInput(existingInput) {
                session.addInput(existingInput)
                currentVideoInput = existingInput
                updateSelectedCamera(id: existingInput.device.uniqueID)
            }
            throw error
        }
    }

    private func updateUI(statusMessage: String?, canCapture: Bool, isPreviewVisible: Bool) {
        DispatchQueue.main.async {
            self.statusMessage = statusMessage
            self.canCapture = canCapture
            self.isPreviewVisible = isPreviewVisible
        }
    }

    private func updateCameraOptions(_ options: [CameraOption], selectedCameraID: String?) {
        DispatchQueue.main.async {
            self.cameraOptions = options
            self.selectedCameraID = selectedCameraID
        }
    }

    private func updateSelectedCamera(id: String?) {
        DispatchQueue.main.async {
            self.selectedCameraID = id
        }
    }

    private func cancelStartup() {
        startupCancellation?.cancel()
        startupCancellation = nil
        startupTask?.cancel()
        startupTask = nil
    }

    private func clearStartupIfCurrent(_ cancellation: StartupCancellation) {
        if startupCancellation === cancellation {
            startupCancellation = nil
            startupTask = nil
        }
    }
}

extension MacCameraCaptureController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if error != nil {
            updateUI(statusMessage: nil, canCapture: true, isPreviewVisible: true)
            DispatchQueue.main.async {
                self.onFailure?()
            }
            return
        }

        guard let data = photo.fileDataRepresentation(), !data.isEmpty else {
            updateUI(statusMessage: nil, canCapture: true, isPreviewVisible: true)
            DispatchQueue.main.async {
                self.onFailure?()
            }
            return
        }

        DispatchQueue.main.async {
            self.onCapture?(data, "image/jpeg")
        }
    }
}

#endif
