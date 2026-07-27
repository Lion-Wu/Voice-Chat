import AVFoundation
import XCTest
@testable import Voice_Chat

final class SpeechInputSeamTests: XCTestCase {
    func testTranscriptMergerKeepsCJKContinuousAndSpacesEnglish() {
        XCTAssertEqual(SpeechTranscriptMerger.merge("你好", "世界"), "你好世界")
        XCTAssertEqual(SpeechTranscriptMerger.merge("こんにちは", "世界"), "こんにちは世界")
        XCTAssertEqual(SpeechTranscriptMerger.merge("Hello", "world"), "Hello world")
        XCTAssertEqual(SpeechTranscriptMerger.merge("你好", "world"), "你好 world")
        XCTAssertEqual(SpeechTranscriptMerger.merge("Hello.", "world"), "Hello. world")
    }

    func testTranscriptMergerTrimsEmptySides() {
        XCTAssertEqual(SpeechTranscriptMerger.merge("  ", " next "), "next")
        XCTAssertEqual(SpeechTranscriptMerger.merge(" first ", "  "), "first")
    }

    func testRecognitionTaskErrorDisposition() {
        let noSpeech = NSError(domain: "kAFAssistantErrorDomain", code: 1110)
        let interrupted = NSError(domain: "kAFAssistantErrorDomain", code: 1107)
        let cases: [(Error, Bool, Bool, Bool, SpeechRecognitionTaskErrorDisposition)] = [
            (noSpeech, false, false, false, .restart),
            (noSpeech, true, false, false, .finish),
            (noSpeech, false, true, true, .restart),
            (noSpeech, false, true, false, .finish),
            (interrupted, false, false, false, .fail)
        ]

        for (error, endedForSilence, taskHasText, continuesListening, expected) in cases {
            XCTAssertEqual(
                SpeechRecognitionTaskErrorPolicy.disposition(
                    for: error,
                    didEndAudioForSilence: endedForSilence,
                    currentTaskHasRecognizedText: taskHasText,
                    continuesListeningAfterRecognizedText: continuesListening
                ),
                expected
            )
        }
    }

    func testVoiceMotionMicrophonePathUsesBothReferenceEnvelopesPerRenderFrame() throws {
        let sampleRate = 48_000.0
        let format = try XCTUnwrap(
            AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            )
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: 512
            )
        )
        buffer.frameLength = 512
        let samples = try XCTUnwrap(buffer.floatChannelData?.pointee)
        for index in 0..<512 {
            samples[index] = 1
        }

        let source = VoiceMicrophoneAudioSource()
        source.append(buffer)
        let controller = VoiceMotionController(initialState: .listening)
        controller.setAudioSource(source)

        let delta = 1.0 / 60.0
        let snapshot = controller.advance(deltaTime: delta)
        let analyserEnvelope = 1 - exp(-Float(delta) / 0.025)
        let rendererEnvelope = 1 - exp(-Float(delta) / 0.030)

        XCTAssertEqual(
            snapshot.audio.rms,
            analyserEnvelope * rendererEnvelope,
            accuracy: 0.000_01
        )
    }

    func testVoiceMotionLevelStoreAlwaysReturnsLatestValue() {
        let source = VoiceAudioLevelStore()
        source.store(.init(rms: 0.1, low: 0.2, mid: 0.3, high: 0.4))
        source.store(.init(rms: 0.8, low: 0.7, mid: 0.6, high: 0.5))

        XCTAssertEqual(
            source.audioLevels(deltaTime: 1.0 / 120.0),
            .init(rms: 0.8, low: 0.7, mid: 0.6, high: 0.5)
        )
    }

    func testVoiceMotionMicrophoneFFTMatchesReferenceSpectrum() throws {
        let sampleRate = 48_000.0
        let format = try XCTUnwrap(
            AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            )
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: 512
            )
        )
        buffer.frameLength = 512
        let samples = try XCTUnwrap(buffer.floatChannelData?.pointee)
        var referenceSamples = [Float](repeating: 0, count: 512)
        for index in 0..<512 {
            let time = Float(index) / Float(sampleRate)
            let sample =
                0.08 * sin(2 * Float.pi * 187.5 * time)
                + 0.10 * sin(2 * Float.pi * 1_000 * time)
                + 0.25 * sin(2 * Float.pi * 4_500 * time)
            samples[index] = sample
            referenceSamples[index] = sample
        }

        let delta: Float = 1.0 / 60.0
        let expected = referenceAnalyserFrame(
            samples: referenceSamples,
            sampleRate: Float(sampleRate),
            deltaTime: delta
        )
        let source = VoiceMicrophoneAudioSource()
        source.append(buffer)
        let actual = source.audioLevels(deltaTime: TimeInterval(delta))

        XCTAssertEqual(actual.rms, expected.rms, accuracy: 0.000_01)
        XCTAssertEqual(actual.low, expected.low, accuracy: 0.000_01)
        XCTAssertEqual(actual.mid, expected.mid, accuracy: 0.000_01)
        XCTAssertEqual(actual.high, expected.high, accuracy: 0.000_01)
    }

    func testVoiceMotionViewportLayoutPreservesBodySizeAcrossWindowSizes() {
        let compact = VoiceMotionLayout.viewportLayout(
            controlFrame: CGRect(x: 70, y: 70, width: 280, height: 280),
            viewportSize: CGSize(width: 420, height: 420),
            visualScale: 1
        )
        let expanded = VoiceMotionLayout.viewportLayout(
            controlFrame: CGRect(x: 460, y: 260, width: 280, height: 280),
            viewportSize: CGSize(width: 1_200, height: 800),
            visualScale: 1
        )
        let shorterThanControl = VoiceMotionLayout.viewportLayout(
            controlFrame: CGRect(x: -20, y: -50, width: 280, height: 280),
            viewportSize: CGSize(width: 240, height: 180),
            visualScale: 1
        )

        let compactBodyScale = compact.normalizedControlDiameter
            * 420
            * VoiceMotionLayout.presentationScale
        let expandedBodyScale = expanded.normalizedControlDiameter
            * 800
            * VoiceMotionLayout.presentationScale
        let shortBodyScale = shorterThanControl.normalizedControlDiameter
            * 180
            * VoiceMotionLayout.presentationScale

        XCTAssertEqual(compact.normalizedCenter, SIMD2(repeating: 0.5))
        XCTAssertEqual(expanded.normalizedCenter, SIMD2(repeating: 0.5))
        XCTAssertEqual(compactBodyScale, expandedBodyScale, accuracy: 0.000_1)
        XCTAssertEqual(compactBodyScale, shortBodyScale, accuracy: 0.000_1)
        XCTAssertEqual(compactBodyScale, 672, accuracy: 0.000_1)
    }

    func testVoiceMotionViewportLayoutTracksControlPositionAndScale() {
        let layout = VoiceMotionLayout.viewportLayout(
            controlFrame: CGRect(x: 80, y: 120, width: 280, height: 280),
            viewportSize: CGSize(width: 1_000, height: 800),
            visualScale: 1.1
        )

        XCTAssertEqual(layout.normalizedCenter.x, 0.22, accuracy: 0.000_01)
        XCTAssertEqual(layout.normalizedCenter.y, 0.325, accuracy: 0.000_01)
        XCTAssertEqual(
            layout.normalizedControlDiameter,
            308.0 / 800.0,
            accuracy: 0.000_01
        )
    }

    func testVoiceMotionErrorMessageSitsBelowVisibleRing() {
        let viewportHeight: CGFloat = 800
        let controlDiameter: CGFloat = 280
        let ringBottom = viewportHeight / 2
            + controlDiameter
                * CGFloat(
                    VoiceMotionLayout.presentationScale
                        * VoiceMotionLayout.errorOuterRadius
                )
        let messageTop = VoiceMotionLayout.errorMessageTopOffset(
            viewportHeight: viewportHeight,
            controlDiameter: controlDiameter
        )

        XCTAssertEqual(
            messageTop - ringBottom,
            VoiceMotionLayout.errorMessageClearance,
            accuracy: 0.000_1
        )
        XCTAssertLessThan(messageTop, viewportHeight / 2 + controlDiameter / 2)
    }

    private func referenceAnalyserFrame(
        samples: [Float],
        sampleRate: Float,
        deltaTime: Float
    ) -> VoiceAudioLevels {
        let count = samples.count
        var sumSquares: Float = 0
        var windowed = [Float](repeating: 0, count: count)
        for index in samples.indices {
            let sample = samples[index]
            sumSquares += sample * sample
            let phase = 2 * Float.pi * Float(index) / Float(count)
            let blackman = 0.42
                - 0.5 * cos(phase)
                + 0.08 * cos(2 * phase)
            windowed[index] = sample * blackman
        }

        var spectrum = [Float](repeating: 0, count: count / 2)
        for bin in spectrum.indices {
            var real: Float = 0
            var imaginary: Float = 0
            for index in windowed.indices {
                let phase =
                    2 * Float.pi * Float(bin * index) / Float(count)
                real += windowed[index] * cos(phase)
                imaginary -= windowed[index] * sin(phase)
            }
            spectrum[bin] = 0.54
                * hypot(real, imaginary)
                / Float(count)
        }

        let binHz = sampleRate / Float(count)
        func band(_ startHz: Float, _ endHz: Float) -> Float {
            let first = max(0, Int(floor(startHz / binHz)))
            let last = min(
                spectrum.count - 1,
                Int(ceil(endHz / binHz))
            )
            let average = spectrum[first...last].reduce(0, +)
                / Float(last - first + 1)
            return min(1, max(0, (average - 0.0009) * 10.2))
        }

        func envelope(_ target: Float, attack: Float) -> Float {
            target * (1 - exp(-deltaTime / attack))
        }

        let rms = min(
            1,
            max(0, (sqrt(sumSquares / Float(count)) - 0.007) * 8.7)
        )
        return VoiceAudioLevels(
            rms: envelope(rms, attack: 0.025),
            low: envelope(
                band(80, 250),
                attack: 0.035
            ),
            mid: envelope(
                band(250, 2_000),
                attack: 0.028
            ),
            high: envelope(
                band(2_000, min(8_000, sampleRate * 0.5)),
                attack: 0.022
            )
        )
    }
}
