import AVFoundation
import Accelerate
import Foundation

protocol VoiceMotionAudioSource: AnyObject, Sendable {
    func audioLevels(deltaTime: TimeInterval) -> VoiceAudioLevels
}

final class VoiceAudioLevelStore: VoiceMotionAudioSource, @unchecked Sendable {
    private let lock = NSLock()
    private var levels = VoiceAudioLevels.silent

    func store(_ levels: VoiceAudioLevels) {
        lock.lock()
        self.levels = levels
        lock.unlock()
    }

    func audioLevels(deltaTime: TimeInterval) -> VoiceAudioLevels {
        lock.lock()
        let snapshot = levels
        lock.unlock()
        return snapshot
    }
}

final class VoiceMicrophoneAudioSource: VoiceMotionAudioSource, @unchecked Sendable {
    private static let fftSize = 512
    private static let frequencyBinCount = fftSize / 2
    private static let spectrumSmoothing: Float = 0.46

    private let captureLock = NSLock()
    private let analysisLock = NSLock()

    private var ring = [Float](repeating: 0, count: fftSize)
    private var writeIndex = 0
    private var availableSampleCount = 0
    private var sampleRate = 48_000.0

    private var timeDomain = [Float](repeating: 0, count: fftSize)
    private var window = [Float](repeating: 0, count: fftSize)
    private var inputReal = [Float](repeating: 0, count: frequencyBinCount)
    private var inputImaginary = [Float](repeating: 0, count: frequencyBinCount)
    private var outputReal = [Float](repeating: 0, count: frequencyBinCount)
    private var outputImaginary = [Float](repeating: 0, count: frequencyBinCount)
    private var smoothedSpectrum = [Float](repeating: 0, count: frequencyBinCount)
    private var analysisSampleRate = 48_000.0
    private var current = VoiceAudioLevels.silent
    private let fftSetup: vDSP_DFT_Setup?

    init() {
        fftSetup = vDSP_DFT_zrop_CreateSetup(
            nil,
            vDSP_Length(Self.fftSize),
            vDSP_DFT_Direction.FORWARD
        )
        for index in 0..<Self.fftSize {
            let phase = 2 * Float.pi * Float(index) / Float(Self.fftSize)
            window[index] = 0.42
                - 0.5 * cos(phase)
                + 0.08 * cos(2 * phase)
        }
    }

    deinit {
        if let fftSetup {
            vDSP_DFT_DestroySetup(fftSetup)
        }
    }

    @discardableResult
    func append(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return 0 }

        var allChannelEnergy: Float = 0
        captureLock.lock()
        sampleRate = buffer.format.sampleRate
        for frame in 0..<frameCount {
            var mono: Float = 0
            for channel in 0..<channelCount {
                let sample = channels[channel][frame]
                mono += sample
                allChannelEnergy += sample * sample
            }
            mono /= Float(channelCount)
            ring[writeIndex] = mono
            writeIndex = (writeIndex + 1) % Self.fftSize
            availableSampleCount = min(Self.fftSize, availableSampleCount + 1)
        }
        captureLock.unlock()

        return sqrt(allChannelEnergy / Float(frameCount * channelCount))
    }

    func reset() {
        analysisLock.lock()
        captureLock.lock()
        ring = [Float](repeating: 0, count: Self.fftSize)
        writeIndex = 0
        availableSampleCount = 0
        sampleRate = 48_000
        captureLock.unlock()

        timeDomain = [Float](repeating: 0, count: Self.fftSize)
        inputReal = [Float](repeating: 0, count: Self.frequencyBinCount)
        inputImaginary = [Float](repeating: 0, count: Self.frequencyBinCount)
        outputReal = [Float](repeating: 0, count: Self.frequencyBinCount)
        outputImaginary = [Float](repeating: 0, count: Self.frequencyBinCount)
        smoothedSpectrum = [Float](repeating: 0, count: Self.frequencyBinCount)
        analysisSampleRate = 48_000
        current = .silent
        analysisLock.unlock()
    }

    func audioLevels(deltaTime: TimeInterval) -> VoiceAudioLevels {
        let dt = min(0.1, max(0, Float(deltaTime.isFinite ? deltaTime : 0)))

        analysisLock.lock()
        defer { analysisLock.unlock() }

        copyLatestTimeDomainWindow()

        var sumSquares: Float = 0
        vDSP_svesq(
            timeDomain,
            1,
            &sumSquares,
            vDSP_Length(Self.fftSize)
        )
        let rawRMS = sqrt(sumSquares / Float(Self.fftSize))
        let rms = normalize(rawRMS, floor: 0.007, gain: 8.7)

        let bands = frequencyBands()
        let target = VoiceAudioLevels(
            rms: rms,
            low: bands.low,
            mid: bands.mid,
            high: bands.high
        )
        current = VoiceAudioLevels(
            rms: envelope(
                current: current.rms,
                target: target.rms,
                dt: dt,
                attack: 0.025,
                release: 0.170
            ),
            low: envelope(
                current: current.low,
                target: target.low,
                dt: dt,
                attack: 0.035,
                release: 0.220
            ),
            mid: envelope(
                current: current.mid,
                target: target.mid,
                dt: dt,
                attack: 0.028,
                release: 0.190
            ),
            high: envelope(
                current: current.high,
                target: target.high,
                dt: dt,
                attack: 0.022,
                release: 0.140
            )
        )
        return current
    }

    private func copyLatestTimeDomainWindow() {
        captureLock.lock()
        let count = availableSampleCount
        let missing = Self.fftSize - count
        if missing > 0 {
            for index in 0..<missing {
                timeDomain[index] = 0
            }
        }
        let oldest = (writeIndex - count + Self.fftSize) % Self.fftSize
        for offset in 0..<count {
            timeDomain[missing + offset] = ring[
                (oldest + offset) % Self.fftSize
            ]
        }
        analysisSampleRate = sampleRate
        captureLock.unlock()
    }

    private func frequencyBands() -> (
        low: Float,
        mid: Float,
        high: Float
    ) {
        guard let fftSetup else { return (0, 0, 0) }

        for index in 0..<Self.frequencyBinCount {
            inputReal[index] = timeDomain[index * 2] * window[index * 2]
            inputImaginary[index] = timeDomain[index * 2 + 1]
                * window[index * 2 + 1]
        }

        vDSP_DFT_Execute(
            fftSetup,
            inputReal,
            inputImaginary,
            &outputReal,
            &outputImaginary
        )

        let fftScale = Float(0.5 / Double(Self.fftSize))
        for index in 0..<Self.frequencyBinCount {
            let magnitude: Float
            if index == 0 {
                magnitude = abs(outputReal[0]) * fftScale
            } else {
                magnitude = hypot(
                    outputReal[index],
                    outputImaginary[index]
                ) * fftScale
            }
            smoothedSpectrum[index] =
                Self.spectrumSmoothing * smoothedSpectrum[index]
                + (1 - Self.spectrumSmoothing) * magnitude
        }

        let binHz = Float(analysisSampleRate) / Float(Self.fftSize)
        return (
            bandEnergy(startHz: 80, endHz: 250, binHz: binHz),
            bandEnergy(startHz: 250, endHz: 2_000, binHz: binHz),
            bandEnergy(
                startHz: 2_000,
                endHz: min(8_000, Float(analysisSampleRate) * 0.5),
                binHz: binHz
            )
        )
    }

    private func bandEnergy(
        startHz: Float,
        endHz: Float,
        binHz: Float
    ) -> Float {
        guard binHz > 0 else { return 0 }
        let first = max(0, Int(floor(startHz / binHz)))
        let last = min(
            Self.frequencyBinCount - 1,
            Int(ceil(endHz / binHz))
        )
        guard last >= first else { return 0 }

        var sum: Float = 0
        for index in first...last {
            sum += smoothedSpectrum[index]
        }
        let average = sum / Float(last - first + 1)
        return normalize(average, floor: 0.0009, gain: 10.2)
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

    private func normalize(
        _ value: Float,
        floor: Float,
        gain: Float
    ) -> Float {
        min(1, max(0, (value - floor) * gain))
    }
}

final class VoiceAudioFeatureExtractor: @unchecked Sendable {
    private var lowState: Float = 0
    private var midState: Float = 0

    func reset() {
        lowState = 0
        midState = 0
    }

    func process(
        samples: UnsafePointer<Float>,
        frameCount: Int,
        sampleRate: Double
    ) -> VoiceAudioLevels {
        guard frameCount > 0, sampleRate > 0 else { return .silent }

        let lowCoefficient = Float(1 - exp(-2 * Double.pi * 250 / sampleRate))
        let midCoefficient = Float(1 - exp(-2 * Double.pi * 2_000 / sampleRate))
        var fullEnergy: Float = 0
        var lowEnergy: Float = 0
        var midEnergy: Float = 0
        var highEnergy: Float = 0

        for index in 0..<frameCount {
            let sample = samples[index]
            lowState += lowCoefficient * (sample - lowState)
            midState += midCoefficient * (sample - midState)
            let low = lowState
            let mid = midState - lowState
            let high = sample - midState
            fullEnergy += sample * sample
            lowEnergy += low * low
            midEnergy += mid * mid
            highEnergy += high * high
        }

        let inverseCount = 1 / Float(frameCount)
        return VoiceAudioLevels(
            rms: normalize(
                sqrt(fullEnergy * inverseCount),
                floor: 0.007,
                gain: 8.7
            ),
            low: normalize(
                sqrt(lowEnergy * inverseCount),
                floor: 0.003,
                gain: 10.5
            ),
            mid: normalize(
                sqrt(midEnergy * inverseCount),
                floor: 0.002,
                gain: 13.0
            ),
            high: normalize(
                sqrt(highEnergy * inverseCount),
                floor: 0.0015,
                gain: 14.0
            )
        )
    }

    private func normalize(_ value: Float, floor: Float, gain: Float) -> Float {
        min(1, max(0, (value - floor) * gain))
    }
}

struct VoiceAudioTimeline: Sendable {
    let frames: [VoiceAudioLevels]
    let frameDuration: TimeInterval

    func levels(at time: TimeInterval) -> VoiceAudioLevels {
        guard !frames.isEmpty, frameDuration > 0 else { return .silent }
        let index = min(
            frames.count - 1,
            max(0, Int(max(0, time) / frameDuration))
        )
        return frames[index]
    }
}

enum VoiceAudioTimelineDecoder {
    private static let analysisFrameCount: AVAudioFrameCount = 512

    static func decode(
        data: Data,
        fileExtension: String
    ) -> VoiceAudioTimeline? {
        guard !data.isEmpty else { return nil }

        let safeExtension = fileExtension
            .lowercased()
            .filter(\.isLetter)
        let suffix = safeExtension.isEmpty ? "audio" : safeExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-chat-motion-\(UUID().uuidString)")
            .appendingPathExtension(suffix)

        do {
            try data.write(to: url, options: .atomic)
            defer { try? FileManager.default.removeItem(at: url) }

            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard format.sampleRate > 0,
                  format.channelCount > 0,
                  let buffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: analysisFrameCount
                  )
            else { return nil }

            let extractor = VoiceAudioFeatureExtractor()
            var frames: [VoiceAudioLevels] = []
            frames.reserveCapacity(
                max(1, Int(file.length) / Int(analysisFrameCount))
            )

            while file.framePosition < file.length {
                buffer.frameLength = 0
                try file.read(into: buffer, frameCount: analysisFrameCount)
                let count = Int(buffer.frameLength)
                guard count > 0 else { break }
                guard let samples = buffer.floatChannelData?.pointee else {
                    return nil
                }
                frames.append(
                    extractor.process(
                        samples: samples,
                        frameCount: count,
                        sampleRate: format.sampleRate
                    )
                )
            }

            guard !frames.isEmpty else { return nil }
            return VoiceAudioTimeline(
                frames: frames,
                frameDuration: Double(analysisFrameCount) / format.sampleRate
            )
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }
}
