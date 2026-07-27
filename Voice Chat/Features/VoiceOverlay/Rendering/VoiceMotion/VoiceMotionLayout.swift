import Foundation

internal struct VoiceMotionViewportLayout: Sendable, Equatable {
    static let centered = VoiceMotionViewportLayout(
        normalizedCenter: SIMD2(repeating: 0.5),
        normalizedControlDiameter: 2.0 / 3.0
    )

    let normalizedCenter: SIMD2<Float>
    let normalizedControlDiameter: Float

    init(
        normalizedCenter: SIMD2<Float>,
        normalizedControlDiameter: Float
    ) {
        self.normalizedCenter = SIMD2(
            normalizedCenter.x.isFinite ? normalizedCenter.x : 0.5,
            normalizedCenter.y.isFinite ? normalizedCenter.y : 0.5
        )
        self.normalizedControlDiameter = max(
            0,
            normalizedControlDiameter.isFinite
                ? normalizedControlDiameter
                : 0
        )
    }

    var shaderParameters: SIMD4<Float> {
        SIMD4(
            normalizedCenter.x,
            normalizedCenter.y,
            normalizedControlDiameter,
            VoiceMotionLayout.presentationScale
        )
    }
}

internal enum VoiceMotionLayout {
    static let phaseSeed: Float = 0.61803398875
    static let presentationScale: Float = 2.4
    static let errorOuterRadius: Float = 0.116
    static let errorMessageClearance: CGFloat = 28
    static let morphCellCount = 5
    static let speakingBarCount = 4
    static let speakingLayoutCodeMax: UInt32 = (1 << (morphCellCount * 2)) - 1

    static func errorMessageTopOffset(
        viewportHeight: CGFloat,
        controlDiameter: CGFloat
    ) -> CGFloat {
        viewportHeight / 2
            + controlDiameter
                * CGFloat(presentationScale * errorOuterRadius)
            + errorMessageClearance
    }

    static func viewportLayout(
        controlFrame: CGRect,
        viewportSize: CGSize,
        visualScale: CGFloat
    ) -> VoiceMotionViewportLayout {
        let width = max(1, viewportSize.width)
        let height = max(1, viewportSize.height)
        let minimumDimension = min(width, height)
        let controlDiameter = max(
            0,
            min(controlFrame.width, controlFrame.height) * visualScale
        )
        return VoiceMotionViewportLayout(
            normalizedCenter: SIMD2(
                Float(controlFrame.midX / width),
                Float(controlFrame.midY / height)
            ),
            normalizedControlDiameter: Float(
                controlDiameter / minimumDimension
            )
        )
    }

    private struct AssignmentPoint {
        let index: Int
        let point: SIMD2<Float>
    }

    static func wrapOrbitPhase(_ phase: Float) -> Float {
        guard phase.isFinite else { return 0 }
        let tau = Float.pi * 2
        let wrapped = phase.truncatingRemainder(dividingBy: tau)
        return wrapped < 0 ? wrapped + tau : wrapped
    }

    static func sharedOrbitPhase(
        time: Float,
        motionScale: Float,
        seed: Float = phaseSeed
    ) -> Float {
        let safeTime = time.isFinite ? max(0, time) : 0
        let motion = motionScale.isFinite ? min(2, max(0, motionScale)) : 0
        let primary = min(1, max(0, motion))
        let boost = min(1, max(0, motion - 1))
        let speed = 0.52 + (1.02 - 0.52) * primary + 0.16 * boost
        let clockwisePhase = safeTime * speed
            + 0.05 * sin(safeTime * 0.47 + 0.2) * motion
        return wrapOrbitPhase(
            seed * Float.pi * 2 - clockwisePhase
        )
    }

    static func thinkingAssignmentPoint(
        cellIndex: Int,
        phase: Float
    ) -> SIMD2<Float> {
        let index = ((cellIndex % morphCellCount) + morphCellCount) % morphCellCount
        let angle = wrapOrbitPhase(phase)
            + Float.pi * 2 * Float(index) / Float(morphCellCount)
        return SIMD2(cos(angle), sin(angle))
    }

    static func adaptiveSpeakingBarMapping(anchorPhase: Float) -> [Int] {
        let ordered = (0..<morphCellCount).map { index in
            AssignmentPoint(
                index: index,
                point: thinkingAssignmentPoint(cellIndex: index, phase: anchorPhase)
            )
        }.sorted(by: comesBefore)

        var mapping = [Int](repeating: 0, count: morphCellCount)
        for (rank, item) in ordered.enumerated() {
            switch rank {
            case 0:
                mapping[item.index] = 0
            case 1:
                mapping[item.index] = 1
            case 2:
                mapping[item.index] = item.point.x < 0 ? 1 : 2
            case 3:
                mapping[item.index] = 2
            default:
                mapping[item.index] = 3
            }
        }
        return mapping
    }

    static func adaptiveSpeakingBarIndex(
        cellIndex: Int,
        anchorPhase: Float
    ) -> Int {
        let index = ((cellIndex % morphCellCount) + morphCellCount) % morphCellCount
        return adaptiveSpeakingBarMapping(anchorPhase: anchorPhase)[index]
    }

    static func speakingLayoutCode(anchorPhase: Float) -> Float {
        let mapping = adaptiveSpeakingBarMapping(anchorPhase: anchorPhase)
        var code: UInt32 = 0
        for cellIndex in 0..<morphCellCount {
            code |= UInt32(mapping[cellIndex]) << UInt32(cellIndex * 2)
        }
        return Float(code)
    }

    static func decodeSpeakingBarIndex(layoutCode: Float, cellIndex: Int) -> Int {
        let safeCode: UInt32
        if layoutCode.isFinite {
            safeCode = UInt32(
                min(
                    Float(speakingLayoutCodeMax),
                    max(0, layoutCode.rounded())
                )
            )
        } else {
            safeCode = 0
        }
        let index = ((cellIndex % morphCellCount) + morphCellCount) % morphCellCount
        return Int((safeCode >> UInt32(index * 2)) & 0b11)
    }

    private static func comesBefore(_ left: AssignmentPoint, _ right: AssignmentPoint) -> Bool {
        if left.point.x < right.point.x { return true }
        if left.point.x > right.point.x { return false }
        if left.point.y < right.point.y { return true }
        if left.point.y > right.point.y { return false }
        return left.index < right.index
    }
}
