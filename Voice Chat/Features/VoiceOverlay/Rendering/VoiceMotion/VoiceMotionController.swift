import Foundation

public final class VoiceMotionController: @unchecked Sendable {
    private struct SpringTuning {
        let frequencyHz: Float
        let damping: Float
    }

    private static let tuning: [VoiceMotionState: SpringTuning] = [
        .connecting: SpringTuning(frequencyHz: 1.55, damping: 0.94),
        .listening: SpringTuning(frequencyHz: 1.92, damping: 0.90),
        .thinking: SpringTuning(frequencyHz: 1.42, damping: 0.88),
        .speaking: SpringTuning(frequencyHz: 1.78, damping: 0.90),
        .error: SpringTuning(frequencyHz: 1.66, damping: 0.93),
    ]

    private static let errorApertureEnterTuning = SpringTuning(
        frequencyHz: 1.20,
        damping: 1.02
    )
    private static let errorApertureExitTuning = SpringTuning(
        frequencyHz: 1.70,
        damping: 1.00
    )

    private let lock = NSLock()
    private var currentState: VoiceMotionState
    private var stateTime: Float = 0
    private var elapsedTime: Float = 0
    private var weights = [Float](repeating: 0, count: VoiceMotionState.allCases.count)
    private var velocity = [Float](repeating: 0, count: VoiceMotionState.allCases.count)
    private var target = [Float](repeating: 0, count: VoiceMotionState.allCases.count)
    private var targetAudio = VoiceAudioLevels.silent
    private var currentAudio = VoiceAudioLevels.silent
    private var audioSource: (any VoiceMotionAudioSource)?
    private var currentAppearance: VoiceMotionAppearance
    private var reducedMotion = false
    private var speakingLayoutAnchorPhase: Float
    private var speakingLayoutCode: Float
    private var errorApertureProgress: Float
    private var errorApertureVelocity: Float = 0

    public init(
        initialState: VoiceMotionState = .connecting,
        appearance: VoiceMotionAppearance = .porcelain
    ) {
        currentState = initialState
        currentAppearance = appearance
        let initialSpeakingPhase = VoiceMotionLayout.sharedOrbitPhase(
            time: 0,
            motionScale: appearance.motionScale
        )
        speakingLayoutAnchorPhase = initialSpeakingPhase
        speakingLayoutCode = VoiceMotionLayout.speakingLayoutCode(
            anchorPhase: initialSpeakingPhase
        )
        errorApertureProgress = initialState == .error ? 1 : 0
        weights[initialState.rawValue] = 1
        target[initialState.rawValue] = 1
    }

    public var state: VoiceMotionState {
        lock.voiceMotionWithLock { currentState }
    }

    public var appearance: VoiceMotionAppearance {
        get { lock.voiceMotionWithLock { currentAppearance } }
        set { lock.voiceMotionWithLock { currentAppearance = newValue } }
    }

    public var isReducedMotionEnabled: Bool {
        get { lock.voiceMotionWithLock { reducedMotion } }
        set { lock.voiceMotionWithLock { reducedMotion = newValue } }
    }

    public func setState(_ state: VoiceMotionState, immediate: Bool = false) {
        lock.voiceMotionWithLock {
            let previousState = currentState
            let speakingWeight = weights[VoiceMotionState.speaking.rawValue]
            let thinkingWeight = weights[VoiceMotionState.thinking.rawValue]
            let currentPhase = VoiceMotionLayout.sharedOrbitPhase(
                time: elapsedTime,
                motionScale: effectiveMotionScale
            )
            if state == .speaking && (immediate || speakingWeight < 0.08) {
                updateSpeakingLayout(currentPhase)
            } else if state == .thinking,
                      previousState == .speaking,
                      speakingWeight > 0.92,
                      thinkingWeight < 0.08 {
                updateSpeakingLayout(currentPhase)
            }

            currentState = state
            stateTime = 0
            for index in target.indices { target[index] = 0 }
            target[state.rawValue] = 1
            if immediate {
                weights = target
                for index in velocity.indices { velocity[index] = 0 }
                errorApertureProgress = state == .error ? 1 : 0
                errorApertureVelocity = 0
            }
        }
    }

    public func setAudioLevels(_ levels: VoiceAudioLevels) {
        lock.voiceMotionWithLock { targetAudio = levels }
    }

    func setAudioSource(_ source: (any VoiceMotionAudioSource)?) {
        lock.voiceMotionWithLock { audioSource = source }
    }

    public func setAccentLinear(_ rgba: SIMD4<Float>) {
        lock.voiceMotionWithLock {
            currentAppearance = VoiceMotionAppearance(
                accent: rgba,
                motionScale: currentAppearance.motionScale,
                glowStrength: currentAppearance.glowStrength
            )
        }
    }

    public func setAccentSRGB(red: Float, green: Float, blue: Float, alpha: Float = 1) {
        lock.voiceMotionWithLock {
            currentAppearance = .sRGB(
                red: red,
                green: green,
                blue: blue,
                alpha: alpha,
                motionScale: currentAppearance.motionScale,
                glowStrength: currentAppearance.glowStrength
            )
        }
    }

    public func setMotionScale(_ value: Float) {
        lock.voiceMotionWithLock {
            currentAppearance = VoiceMotionAppearance(
                accent: currentAppearance.accent,
                motionScale: value,
                glowStrength: currentAppearance.glowStrength
            )
        }
    }

    public func setGlowStrength(_ value: Float) {
        lock.voiceMotionWithLock {
            currentAppearance = VoiceMotionAppearance(
                accent: currentAppearance.accent,
                motionScale: currentAppearance.motionScale,
                glowStrength: value
            )
        }
    }

    public func snapshotWithoutAdvancing() -> VoiceMotionSnapshot {
        lock.voiceMotionWithLock { makeSnapshot() }
    }

    internal func advance(deltaTime: TimeInterval) -> VoiceMotionSnapshot {
        lock.voiceMotionWithLock {
            let frameDelta = min(
                Float(0.1),
                max(0, Float(deltaTime.isFinite ? deltaTime : 0))
            )
            guard frameDelta > 0 else { return makeSnapshot() }
            let springDelta = min(Float(1.0 / 15.0), frameDelta)
            stateTime += springDelta
            elapsedTime += springDelta

            for state in VoiceMotionState.allCases {
                guard let tuning = Self.tuning[state] else { continue }
                let index = state.rawValue
                let omega = Float.pi * 2 * tuning.frequencyHz
                let x = weights[index]
                let v = velocity[index]
                let goal = target[index]
                let f = 1 + 2 * springDelta * tuning.damping * omega
                let hoo = springDelta * omega * omega
                let hhoo = springDelta * hoo
                let inverse = 1 / (f + hhoo)
                weights[index] = max(
                    0,
                    (
                        f * x
                            + springDelta * v
                            + hhoo * goal
                    ) * inverse
                )
                velocity[index] = (v + hoo * (goal - x)) * inverse
            }

            let apertureGoal: Float = currentState == .error ? 1 : 0
            let apertureTuning = apertureGoal > 0.5
                ? Self.errorApertureEnterTuning
                : Self.errorApertureExitTuning
            let apertureOmega = Float.pi * 2 * apertureTuning.frequencyHz
            let apertureX = errorApertureProgress
            let apertureV = errorApertureVelocity
            let apertureF = 1
                + 2 * springDelta * apertureTuning.damping * apertureOmega
            let apertureHoo = springDelta * apertureOmega * apertureOmega
            let apertureHhoo = springDelta * apertureHoo
            let apertureInverse = 1 / (apertureF + apertureHhoo)
            errorApertureProgress = min(1, max(0, (
                apertureF * apertureX
                    + springDelta * apertureV
                    + apertureHhoo * apertureGoal
            ) * apertureInverse))
            errorApertureVelocity = (
                apertureV + apertureHoo * (apertureGoal - apertureX)
            ) * apertureInverse

            var sum: Float = 0
            for weight in weights { sum += weight }
            if sum > 0.0000001 {
                for index in weights.indices { weights[index] /= sum }
            } else {
                for index in weights.indices { weights[index] = 0 }
                weights[currentState.rawValue] = 1
                for index in velocity.indices { velocity[index] = 0 }
            }

            if let audioSource {
                targetAudio = audioSource.audioLevels(
                    deltaTime: TimeInterval(frameDelta)
                )
            }

            currentAudio = VoiceAudioLevels(
                rms: envelope(
                    current: currentAudio.rms,
                    target: targetAudio.rms,
                    dt: frameDelta,
                    attack: 0.030,
                    release: 0.160
                ),
                low: envelope(
                    current: currentAudio.low,
                    target: targetAudio.low,
                    dt: frameDelta,
                    attack: 0.040,
                    release: 0.210
                ),
                mid: envelope(
                    current: currentAudio.mid,
                    target: targetAudio.mid,
                    dt: frameDelta,
                    attack: 0.030,
                    release: 0.180
                ),
                high: envelope(
                    current: currentAudio.high,
                    target: targetAudio.high,
                    dt: frameDelta,
                    attack: 0.025,
                    release: 0.140
                )
            )
            return makeSnapshot()
        }
    }

    private var effectiveMotionScale: Float {
        currentAppearance.motionScale * (reducedMotion ? 0.18 : 1)
    }

    private func makeSnapshot() -> VoiceMotionSnapshot {
        var appearance = currentAppearance
        if reducedMotion { appearance.motionScale *= 0.18 }
        return VoiceMotionSnapshot(
            state: currentState,
            stateTime: stateTime,
            stateWeights: SIMD4(weights[0], weights[1], weights[2], weights[3]),
            errorWeight: weights[4],
            errorApertureProgress: errorApertureProgress,
            speakingLayoutAnchorPhase: speakingLayoutAnchorPhase,
            speakingLayoutCode: speakingLayoutCode,
            audio: currentAudio,
            appearance: appearance
        )
    }

    private func envelope(
        current: Float,
        target: Float,
        dt: Float,
        attack: Float,
        release: Float
    ) -> Float {
        let timeConstant = target > current ? attack : release
        let blend = 1 - exp(-dt / max(timeConstant, 0.0001))
        return current + (target - current) * blend
    }

    private func updateSpeakingLayout(_ phase: Float) {
        speakingLayoutAnchorPhase = VoiceMotionLayout.wrapOrbitPhase(phase)
        speakingLayoutCode = VoiceMotionLayout.speakingLayoutCode(
            anchorPhase: speakingLayoutAnchorPhase
        )
    }

}

private extension NSLock {
    @discardableResult
    func voiceMotionWithLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
