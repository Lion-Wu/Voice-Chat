import MetalKit
import QuartzCore

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public final class VoiceMotionMTKView: MTKView {
    public let controller: VoiceMotionController
    public private(set) var voiceRenderer: VoiceMotionRenderer?
    public private(set) var setupError: Error?
    private var viewportLayout: VoiceMotionViewportLayout

    public init(
        frame: CGRect = .zero,
        controller: VoiceMotionController = VoiceMotionController()
    ) {
        self.controller = controller
        viewportLayout = .centered
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        configure()
    }

    init(
        frame: CGRect = .zero,
        controller: VoiceMotionController,
        viewportLayout: VoiceMotionViewportLayout
    ) {
        self.controller = controller
        self.viewportLayout = viewportLayout
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        configure()
    }

    public required init(coder: NSCoder) {
        controller = VoiceMotionController()
        viewportLayout = .centered
        super.init(coder: coder)
        device = device ?? MTLCreateSystemDefaultDevice()
        configure()
    }

    private func configure() {
        isPaused = true
        enableSetNeedsDisplay = false
        updatePreferredFrameRate()
        framebufferOnly = true
        autoResizeDrawable = true
        colorPixelFormat = .rgba16Float
        #if os(macOS)
        colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        #else
        (layer as? CAMetalLayer)?.colorspace = CGColorSpace(
            name: CGColorSpace.extendedLinearSRGB
        )
        #endif
        depthStencilPixelFormat = .invalid
        sampleCount = 1
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        #if os(iOS) || os(tvOS) || os(visionOS)
        isOpaque = false
        backgroundColor = .clear
        #elseif os(macOS)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        #endif

        do {
            voiceRenderer = try VoiceMotionRenderer(view: self, controller: controller)
            voiceRenderer?.setViewportLayout(viewportLayout)
            isPaused = window == nil
        } catch {
            setupError = error
            isPaused = true
        }
    }

    func setViewportLayout(_ layout: VoiceMotionViewportLayout) {
        viewportLayout = layout
        voiceRenderer?.setViewportLayout(layout)
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePreferredFrameRate()
        updateLifecycleState()
    }
    #elseif os(macOS)
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePreferredFrameRate()
        updateLifecycleState()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updatePreferredFrameRate()
    }
    #endif

    private func updatePreferredFrameRate() {
        #if os(visionOS)
        preferredFramesPerSecond = 60
        #elseif os(iOS) || os(tvOS)
        let screen = window?.windowScene?.screen ?? UIScreen.main
        preferredFramesPerSecond = max(60, screen.maximumFramesPerSecond)
        #elseif os(macOS)
        let screen = window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        preferredFramesPerSecond = max(60, screen?.maximumFramesPerSecond ?? 60)
        #endif
    }

    private func updateLifecycleState() {
        guard setupError == nil else { return }
        isPaused = window == nil
        if window != nil { voiceRenderer?.resetClock() }
    }
}
