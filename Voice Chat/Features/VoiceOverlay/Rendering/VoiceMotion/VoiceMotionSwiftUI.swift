#if canImport(SwiftUI)
import SwiftUI

#if os(iOS) || os(tvOS) || os(visionOS)
public struct VoiceMotionSurface: UIViewRepresentable {
    public let controller: VoiceMotionController
    let viewportLayout: VoiceMotionViewportLayout

    public init(controller: VoiceMotionController) {
        self.controller = controller
        viewportLayout = .centered
    }

    init(
        controller: VoiceMotionController,
        viewportLayout: VoiceMotionViewportLayout
    ) {
        self.controller = controller
        self.viewportLayout = viewportLayout
    }

    public func makeUIView(context: Context) -> VoiceMotionMTKView {
        VoiceMotionMTKView(
            controller: controller,
            viewportLayout: viewportLayout
        )
    }

    public func updateUIView(_ view: VoiceMotionMTKView, context: Context) {
        view.setViewportLayout(viewportLayout)
    }
}
#elseif os(macOS)
public struct VoiceMotionSurface: NSViewRepresentable {
    public let controller: VoiceMotionController
    let viewportLayout: VoiceMotionViewportLayout

    public init(controller: VoiceMotionController) {
        self.controller = controller
        viewportLayout = .centered
    }

    init(
        controller: VoiceMotionController,
        viewportLayout: VoiceMotionViewportLayout
    ) {
        self.controller = controller
        self.viewportLayout = viewportLayout
    }

    public func makeNSView(context: Context) -> VoiceMotionMTKView {
        VoiceMotionMTKView(
            controller: controller,
            viewportLayout: viewportLayout
        )
    }

    public func updateNSView(_ view: VoiceMotionMTKView, context: Context) {
        view.setViewportLayout(viewportLayout)
    }
}
#endif
#endif
