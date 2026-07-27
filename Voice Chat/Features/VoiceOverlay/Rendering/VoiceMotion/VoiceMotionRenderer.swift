import Foundation
import Metal
import MetalKit
import QuartzCore

public final class VoiceMotionRenderer: NSObject, MTKViewDelegate {
    public let controller: VoiceMotionController

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let viewportLayoutLock = NSLock()
    private var viewportLayout = VoiceMotionViewportLayout.centered
    private var lastTimestamp: CFTimeInterval = 0
    private var elapsedTime: Float = 0

    @MainActor
    public init(view: MTKView, controller: VoiceMotionController) throws {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice() else {
            throw VoiceMotionError.metalUnavailable
        }
        view.device = device
        guard let commandQueue = device.makeCommandQueue() else {
            throw VoiceMotionError.commandQueueUnavailable
        }

        guard let library = device.makeDefaultLibrary() else {
            throw VoiceMotionError.shaderLibraryUnavailable
        }
        guard let vertex = library.makeFunction(name: "voiceMotionVertex") else {
            throw VoiceMotionError.shaderFunctionMissing("voiceMotionVertex")
        }
        guard let fragment = library.makeFunction(name: "voiceMotionFragment") else {
            throw VoiceMotionError.shaderFunctionMissing("voiceMotionFragment")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Voice Chat Motion Pipeline"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        self.commandQueue = commandQueue
        self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        self.controller = controller
        super.init()
        view.delegate = self
    }

    public func resetClock() {
        lastTimestamp = 0
    }

    func setViewportLayout(_ layout: VoiceMotionViewportLayout) {
        viewportLayoutLock.lock()
        viewportLayout = layout
        viewportLayoutLock.unlock()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        autoreleasepool {
            guard let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
            else { return }

            let timestamp = CACurrentMediaTime()
            let delta = lastTimestamp == 0 ? 1.0 / 60.0 : min(0.1, max(0, timestamp - lastTimestamp))
            lastTimestamp = timestamp
            elapsedTime += Float(delta)
            let snapshot = controller.advance(deltaTime: delta)
            let size = view.drawableSize
            viewportLayoutLock.lock()
            let viewportLayout = viewportLayout
            viewportLayoutLock.unlock()
            var uniforms = VoiceMotionUniforms(
                resolution: SIMD2(Float(size.width), Float(size.height)),
                time: elapsedTime,
                stateTime: snapshot.stateTime,
                stateWeights: snapshot.stateWeights,
                stateData: SIMD4(
                    snapshot.errorWeight,
                    Float(snapshot.state.rawValue),
                    snapshot.speakingLayoutCode,
                    snapshot.errorApertureProgress
                ),
                audio: snapshot.audio.vector,
                accent: snapshot.appearance.accent,
                controls: SIMD4(
                    snapshot.appearance.motionScale,
                    snapshot.appearance.glowStrength,
                    VoiceMotionLayout.phaseSeed,
                    0
                ),
                layout: viewportLayout.shaderParameters
            )

            commandBuffer.label = "Voice Chat Motion Frame"
            encoder.label = "Voice Chat Motion Encoder"
            encoder.setRenderPipelineState(pipelineState)
            encoder.setFragmentBytes(
                &uniforms,
                length: MemoryLayout<VoiceMotionUniforms>.stride,
                index: 0
            )
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
