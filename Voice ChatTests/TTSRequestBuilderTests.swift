import AVFoundation
import XCTest
@testable import Voice_Chat

final class TTSRequestBuilderTests: XCTestCase {
    func testMakeRequestEncodesConfiguredSynthParameters() throws {
        let configuration = TTSSynthesisConfiguration(
            serverAddress: "localhost:9880",
            url: try XCTUnwrap(URL(string: "http://localhost:9880/tts")),
            textLanguage: "zh",
            referenceAudioPath: "/tmp/ref.wav",
            promptText: "reference prompt",
            promptLanguage: "en",
            textSplitMethod: "cut0",
            mediaType: "wav",
            usesStreamingSegments: true
        )

        let request = try TTSRequestBuilder.makeRequest(
            for: "hello world",
            configuration: configuration
        )

        XCTAssertEqual(request.url, configuration.url)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 60)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["text"] as? String, "hello world")
        XCTAssertEqual(json["text_lang"] as? String, "zh")
        XCTAssertEqual(json["ref_audio_path"] as? String, "/tmp/ref.wav")
        XCTAssertEqual(json["prompt_text"] as? String, "reference prompt")
        XCTAssertEqual(json["prompt_lang"] as? String, "en")
        XCTAssertEqual(json["batch_size"] as? Int, 1)
        XCTAssertEqual(json["media_type"] as? String, "wav")
        XCTAssertEqual(json["text_split_method"] as? String, "cut0")
    }

    func testMakeRequestRejectsAppleSpeechProvider() {
        let configuration = TTSSynthesisConfiguration(
            provider: .appleSpeech,
            appleSpeechVoiceIdentifier: nil,
            usesStreamingSegments: true
        )

        XCTAssertThrowsError(
            try TTSRequestBuilder.makeRequest(for: "hello", configuration: configuration)
        ) { error in
            XCTAssertEqual(error as? TTSRequestBuilderError, .unsupportedProvider)
        }
    }

    func testSpeechProvidersExposeAppleSpeechAndPersonalVoiceSeparately() {
        XCTAssertEqual(
            TTSProvider.allCases,
            [.gptSoVITS, .appleSpeech, .personalVoice]
        )
        XCTAssertTrue(TTSProvider.appleSpeech.usesAppleSpeechSynthesizer)
        XCTAssertTrue(TTSProvider.personalVoice.usesAppleSpeechSynthesizer)
        XCTAssertFalse(TTSProvider.personalVoice.requiresNetworkTTSService)
    }

    func testAppleSpeechVoiceCatalogMarksPersonalVoices() throws {
        let systemVoices = AVSpeechSynthesisVoice.speechVoices()
        let options = AppleSpeechVoiceOption.installedVoices(locale: Locale(identifier: "en_US"))

        XCTAssertEqual(options.count, systemVoices.count)
        for voice in systemVoices {
            let option = try XCTUnwrap(options.first(where: { $0.id == voice.identifier }))
            XCTAssertEqual(
                option.isPersonalVoice,
                voice.voiceTraits.contains(.isPersonalVoice),
                "Voice trait mismatch for \(voice.identifier)"
            )
        }

        let firstNonPersonalIndex = options.firstIndex(where: { !$0.isPersonalVoice }) ?? options.endIndex
        XCTAssertTrue(options[..<firstNonPersonalIndex].allSatisfy(\.isPersonalVoice))
        XCTAssertTrue(options[firstNonPersonalIndex...].allSatisfy { !$0.isPersonalVoice })
    }

    @MainActor
    func testAppleSpeechSessionProducesPlayableAudio() async throws {
        guard let voice = AVSpeechSynthesisVoice.speechVoices().first else {
            throw XCTSkip("No Apple speech voices are installed on this system")
        }

        let completed = expectation(description: "Apple Speech synthesis completed")
        var synthesisResult: Result<Data, AppleSpeechSynthesisError>?
        let session = AppleSpeechSynthesisSession.start(
            text: "Voice Chat Apple Speech integration test.",
            voiceIdentifier: voice.identifier,
            provider: voice.voiceTraits.contains(.isPersonalVoice) ? .personalVoice : .appleSpeech
        ) { result in
            synthesisResult = result
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 20)
        let data = try XCTUnwrap(synthesisResult).get()
        let player = try AVAudioPlayer(data: data)

        XCTAssertFalse(data.isEmpty)
        XCTAssertGreaterThan(player.duration, 0)
        withExtendedLifetime(session) {}
    }
}
