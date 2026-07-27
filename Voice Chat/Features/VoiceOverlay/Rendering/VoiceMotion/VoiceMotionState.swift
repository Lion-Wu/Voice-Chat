import Foundation

public enum VoiceMotionState: Int, CaseIterable, Sendable {
    case connecting = 0
    case listening = 1
    case thinking = 2
    case speaking = 3
    case error = 4
}

public struct VoiceAudioLevels: Sendable, Equatable {
    public var rms: Float
    public var low: Float
    public var mid: Float
    public var high: Float

    public static let silent = VoiceAudioLevels(rms: 0, low: 0, mid: 0, high: 0)

    public init(rms: Float, low: Float, mid: Float, high: Float) {
        self.rms = Self.clamp01(rms)
        self.low = Self.clamp01(low)
        self.mid = Self.clamp01(mid)
        self.high = Self.clamp01(high)
    }

    internal var vector: SIMD4<Float> { SIMD4(rms, low, mid, high) }

    private static func clamp01(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

public struct VoiceMotionAppearance: Sendable, Equatable {
    public var accent: SIMD4<Float>
    public var motionScale: Float
    public var glowStrength: Float

    public static let porcelain = VoiceMotionAppearance.sRGB(
        red: 245.0 / 255.0,
        green: 247.0 / 255.0,
        blue: 1,
        alpha: 1
    )

    public init(
        accent: SIMD4<Float> = SIMD4(0.91309863, 0.9301109, 1, 1),
        motionScale: Float = 1,
        glowStrength: Float = 1
    ) {
        self.accent = SIMD4(
            min(1, max(0, accent.x)),
            min(1, max(0, accent.y)),
            min(1, max(0, accent.z)),
            min(1, max(0, accent.w))
        )
        self.motionScale = min(2, max(0, motionScale.isFinite ? motionScale : 0))
        self.glowStrength = min(2, max(0, glowStrength.isFinite ? glowStrength : 0))
    }

    public static func sRGB(
        red: Float,
        green: Float,
        blue: Float,
        alpha: Float = 1,
        motionScale: Float = 1,
        glowStrength: Float = 1
    ) -> VoiceMotionAppearance {
        VoiceMotionAppearance(
            accent: SIMD4(
                linearize(red),
                linearize(green),
                linearize(blue),
                min(1, max(0, alpha))
            ),
            motionScale: motionScale,
            glowStrength: glowStrength
        )
    }

    private static func linearize(_ channel: Float) -> Float {
        let value = min(1, max(0, channel))
        return value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }
}

public enum VoiceMotionError: Error, LocalizedError {
    case metalUnavailable
    case shaderLibraryUnavailable
    case shaderFunctionMissing(String)
    case commandQueueUnavailable
    case microphoneFormatUnavailable

    public var errorDescription: String? {
        switch self {
        case .metalUnavailable:
            return "Metal is unavailable on this device."
        case .shaderLibraryUnavailable:
            return "The Voice Motion Metal shader library could not be loaded."
        case .shaderFunctionMissing(let name):
            return "The Metal shader function “\(name)” is missing."
        case .commandQueueUnavailable:
            return "A Metal command queue could not be created."
        case .microphoneFormatUnavailable:
            return "A valid microphone input format is unavailable."
        }
    }
}

internal struct VoiceMotionUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var stateTime: Float
    var stateWeights: SIMD4<Float>
    var stateData: SIMD4<Float>
    var audio: SIMD4<Float>
    var accent: SIMD4<Float>
    var controls: SIMD4<Float>
    var layout: SIMD4<Float>
}

public struct VoiceMotionSnapshot: Sendable {
    public let state: VoiceMotionState
    public let stateTime: Float
    public let stateWeights: SIMD4<Float>
    public let errorWeight: Float
    public let errorApertureProgress: Float
    internal let speakingLayoutAnchorPhase: Float
    internal let speakingLayoutCode: Float
    public let audio: VoiceAudioLevels
    public let appearance: VoiceMotionAppearance
}
