#if os(iOS) || os(macOS)

import SwiftUI

struct VoiceVisionCameraView: View {
    @ObservedObject var viewModel: VoiceChatOverlayViewModel
    var isCompactLayout = false
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
            controller.onSampleCapture = { data, mimeType, visualFingerprint in
                viewModel.handleVisionCaptureSample(
                    data: data,
                    mimeType: mimeType,
                    visualFingerprint: visualFingerprint
                )
            }
            controller.resetVisualHistory()
            controller.start()
            controller.setSamplingActive(viewModel.isVisionCaptureSamplingActive)
        }
        .onDisappear {
            controller.stop()
        }
        .onChange(of: viewModel.isVisionCaptureSamplingActive) { _, isActive in
            controller.setSamplingActive(isActive)
        }
        .onChange(of: viewModel.visionCaptureResetID) { _, _ in
            controller.resetVisualHistory()
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            dismissCameraButton
            cameraAdjustmentControls
            Spacer()
        }
    }

    private var dismissCameraButton: some View {
        Button {
            viewModel.dismissVisionCapture()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: cameraControlHitSize, height: cameraControlHitSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.ultraThinMaterial, in: Circle())
        .accessibilityLabel("Close camera")
    }

    private var cameraAdjustmentControls: some View {
        HStack(spacing: 2) {
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
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: cameraControlHitSize, height: cameraControlHitSize)
                        .contentShape(Rectangle())
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
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: cameraControlHitSize, height: cameraControlHitSize)
                    .contentShape(Rectangle())
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
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: cameraControlHitSize, height: cameraControlHitSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(controller.canUseFlash ? .white : .white.opacity(0.35))
            .disabled(!controller.canUseFlash)
            .accessibilityLabel(Text(controller.isFlashEnabled
                ? LocalizedStringKey("Turn flash off")
                : LocalizedStringKey("Turn flash on")))
            #endif
            #endif
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
    }

    private var cornerRadius: CGFloat {
        isCompactLayout ? 18 : 28
    }

    private var cameraControlHitSize: CGFloat {
        isCompactLayout ? 36 : 40
    }

    private var topBarHorizontalPadding: CGFloat {
        isCompactLayout ? 10 : 22
    }

    private var topBarVerticalPadding: CGFloat {
        isCompactLayout ? 8 : 18
    }
}

#endif
