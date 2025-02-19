//
//  GlobalAudioManager.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import Foundation
import AVFoundation
import Combine
import NaturalLanguage

@MainActor
class GlobalAudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = GlobalAudioManager()

    @Published var isShowingAudioPlayer = false
    @Published var isAudioPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var isLoading = false
    @Published var isBuffering = false
    @Published var errorMessage: String? = nil

    private var audioPlayer: AVAudioPlayer?
    private var audioTimer: Timer?
    var mediaType: String = "wav"

    // Segments and audio chunk handling
    private var textSegments: [String] = []
    private var audioChunks: [Data?] = []
    private var chunkDurations: [TimeInterval] = []
    private var chunkStartTimes: [TimeInterval] = []
    private var totalDuration: TimeInterval = 0
    private var currentChunkIndex: Int = 0
    private var currentPlayingIndex: Int = 0
    private var requestsInFlight: Int = 0
    private let maxRequestsInFlight = 2

    private var dataTasks: [URLSessionDataTask] = []
    private var nextAudioPlayer: AVAudioPlayer?

    private var seekTime: TimeInterval?
    private var isSeeking: Bool = false

    private let settingsManager = SettingsManager.shared

    func startProcessing(text: String) {
        resetPlayer()
        isLoading = true
        isShowingAudioPlayer = true
        currentTime = 0
        totalDuration = 0
        errorMessage = nil

        let voiceSettings = settingsManager.voiceSettings
        if voiceSettings.enableStreaming {
            self.textSegments = splitTextIntoMeaningfulSegments(text)
        } else {
            self.textSegments = [text]
        }

        let segmentCount = textSegments.count
        self.audioChunks = Array(repeating: nil, count: segmentCount)
        self.chunkDurations = Array(repeating: 0, count: segmentCount)
        self.chunkStartTimes = Array(repeating: 0, count: segmentCount)
        self.currentChunkIndex = 0
        self.currentPlayingIndex = 0
        self.requestsInFlight = 0

        sendNextSegment()
        if segmentCount > 1 {
            sendNextSegment()
        }
    }

    private func sendNextSegment() {
        guard currentChunkIndex < textSegments.count else { return }
        guard requestsInFlight < maxRequestsInFlight else { return }

        let index = currentChunkIndex
        currentChunkIndex += 1
        requestsInFlight += 1

        let segmentText = textSegments[index]
        sendTTSRequest(for: segmentText, index: index)
    }

    private func sendTTSRequest(for segmentText: String, index: Int) {
        guard let url = constructTTSURL() else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Unable to construct TTS URL"
            }
            return
        }

        let serverSettings = settingsManager.serverSettings
        let modelSettings = settingsManager.modelSettings
        let voiceSettings = settingsManager.voiceSettings

        var parameters: [String: Any] = [
            "text": segmentText,
            "text_lang": serverSettings.textLang,
            "ref_audio_path": serverSettings.refAudioPath,
            "prompt_text": serverSettings.promptText,
            "prompt_lang": serverSettings.promptLang,
            "batch_size": 1,
            "media_type": mediaType
        ]

        if voiceSettings.enableStreaming {
            parameters["text_split_method"] = "cut0"
        } else {
            parameters["text_split_method"] = modelSettings.autoSplit
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: parameters, options: []) else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Unable to serialize JSON"
            }
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            defer {
                DispatchQueue.main.async {
                    self.requestsInFlight -= 1
                    self.sendNextSegment()
                }
            }

            if let error = error {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Audio request failed: \(error.localizedDescription)"
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "No data received"
                }
                return
            }

            DispatchQueue.main.async {
                if index >= self.audioChunks.count { return }
                self.audioChunks[index] = data

                if let player = try? AVAudioPlayer(data: data) {
                    let segmentDuration = player.duration
                    self.chunkDurations[index] = segmentDuration
                    self.calculateChunkStartTimesAndTotalDuration()
                }

                if index == self.currentPlayingIndex {
                    self.isLoading = false
                    self.isBuffering = false
                    self.playAudioChunk(at: index, fromTime: self.seekTime, shouldPlay: true)
                    self.seekTime = nil
                } else if self.isBuffering && self.isSeeking {
                    self.playAudioChunk(at: self.currentPlayingIndex, fromTime: self.seekTime, shouldPlay: self.isAudioPlaying)
                    self.seekTime = nil
                } else if self.isBuffering && index == self.currentPlayingIndex + 1 {
                    self.prepareNextAudioChunk(at: index)
                } else if index == self.currentPlayingIndex + 1 {
                    self.prepareNextAudioChunk(at: index)
                }
            }
        }
        task.resume()
        dataTasks.append(task)
    }

    private func calculateChunkStartTimesAndTotalDuration() {
        var cumulativeTime: TimeInterval = 0
        for i in 0..<chunkDurations.count {
            let duration = chunkDurations.indices.contains(i) ? chunkDurations[i] : 0
            chunkStartTimes[i] = cumulativeTime
            cumulativeTime += duration
        }
        totalDuration = cumulativeTime
    }

    private func prepareNextAudioChunk(at index: Int) {
        guard audioChunks.indices.contains(index), let data = audioChunks[index] else { return }
        do {
            nextAudioPlayer = try AVAudioPlayer(data: data)
            nextAudioPlayer?.delegate = self
            nextAudioPlayer?.prepareToPlay()
        } catch {
            print("Failed to prepare next audio: \(error)")
        }
    }

    private func playAudioChunk(at index: Int, fromTime time: TimeInterval? = nil, shouldPlay: Bool = true) {
        guard audioChunks.indices.contains(index) else {
            // No more chunks to play
            return
        }

        guard let data = audioChunks[index] else {
            isAudioPlaying = false
            isBuffering = true
            stopAudioTimer()
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()

            let startTime: TimeInterval = {
                guard let t = time else { return 0 }
                let relativeTime = t - self.chunkStartTimes[index]
                return max(0, min(relativeTime, audioPlayer?.duration ?? 0))
            }()

            if currentTime >= totalDuration {
                isAudioPlaying = false
                audioPlayer?.stop()
                stopAudioTimer()
                return
            }

            audioPlayer?.currentTime = startTime
            if shouldPlay {
                audioPlayer?.play()
                isAudioPlaying = true
                startAudioTimer()
            } else {
                isAudioPlaying = false
            }

            isBuffering = false
            isSeeking = false

            let nextIndex = index + 1
            if nextIndex < audioChunks.count, audioChunks[nextIndex] != nil {
                prepareNextAudioChunk(at: nextIndex)
            }
        } catch {
            print("Failed to start audio playback: \(error)")
            errorMessage = "Failed to start audio playback: \(error.localizedDescription)"
        }
    }

    func togglePlayback() {
        if isBuffering { return }

        if isAudioPlaying {
            audioPlayer?.pause()
            isAudioPlaying = false
            stopAudioTimer()
        } else {
            if currentTime >= totalDuration {
                seek(to: 0, shouldPlay: true)
            } else {
                audioPlayer?.play()
                isAudioPlaying = true
                startAudioTimer()
            }
        }
    }

    func forward15Seconds() {
        let newTime = currentTime + 15
        seek(to: newTime, shouldPlay: isAudioPlaying)
    }

    func backward15Seconds() {
        let newTime = currentTime - 15
        seek(to: newTime, shouldPlay: isAudioPlaying)
    }

    func seek(to time: TimeInterval, shouldPlay: Bool = false) {
        guard totalDuration > 0 else { return }
        let newTime = max(0, min(time, totalDuration))
        currentTime = newTime

        var targetChunkIndex = 0
        for i in 0..<chunkStartTimes.count {
            if chunkStartTimes[i] > newTime {
                targetChunkIndex = max(0, i - 1)
                break
            }
            if i == chunkStartTimes.count - 1 {
                targetChunkIndex = i
            }
        }

        if targetChunkIndex != currentPlayingIndex {
            audioPlayer?.stop()
            audioPlayer = nil
            currentPlayingIndex = targetChunkIndex
        }

        if let _ = audioChunks[safe: currentPlayingIndex] {
            playAudioChunk(at: currentPlayingIndex, fromTime: currentTime, shouldPlay: shouldPlay)
            isBuffering = false
        } else {
            isBuffering = true
            seekTime = currentTime
            stopAudioTimer()
        }

        if newTime >= totalDuration {
            isAudioPlaying = false
            audioPlayer?.stop()
            stopAudioTimer()
        }
    }

    func closeAudioPlayer() {
        resetPlayer()
        isAudioPlaying = false
        isShowingAudioPlayer = false
        isLoading = false
    }

    private func resetPlayer() {
        dataTasks.forEach { $0.cancel() }
        dataTasks.removeAll()

        audioPlayer?.stop()
        audioPlayer = nil
        nextAudioPlayer?.stop()
        nextAudioPlayer = nil
        currentTime = 0
        totalDuration = 0
        stopAudioTimer()
        textSegments.removeAll()
        audioChunks.removeAll()
        chunkDurations.removeAll()
        chunkStartTimes.removeAll()
        currentChunkIndex = 0
        currentPlayingIndex = 0
        requestsInFlight = 0
        isBuffering = false
        isSeeking = false
        seekTime = nil
        errorMessage = nil
    }

    private func startAudioTimer() {
        stopAudioTimer()
        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, !self.isBuffering else { return }
            if let player = self.audioPlayer {
                let chunkStartTime = self.chunkStartTimes[safe: self.currentPlayingIndex] ?? 0
                let playerCurrentTime = player.currentTime
                self.currentTime = chunkStartTime + playerCurrentTime
                if self.currentTime >= self.totalDuration {
                    self.currentTime = self.totalDuration
                    self.isAudioPlaying = false
                    player.stop()
                    self.stopAudioTimer()
                }
            }
        }
        if let audioTimer = audioTimer {
            RunLoop.current.add(audioTimer, forMode: .common)
        }
    }

    private func stopAudioTimer() {
        audioTimer?.invalidate()
        audioTimer = nil
    }

    private func constructTTSURL() -> URL? {
        let serverSettings = settingsManager.serverSettings
        let urlString = "\(serverSettings.serverAddress)/tts"
        return URL(string: urlString)
    }

    // MARK: AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        currentPlayingIndex += 1
        if currentTime >= totalDuration {
            currentTime = totalDuration
            isAudioPlaying = false
            stopAudioTimer()
            return
        }

        if let nextPlayer = nextAudioPlayer {
            audioPlayer = nextPlayer
            nextAudioPlayer = nil
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isAudioPlaying = true
            startAudioTimer()

            let nextIndex = currentPlayingIndex + 1
            if nextIndex < audioChunks.count, audioChunks[nextIndex] != nil {
                prepareNextAudioChunk(at: nextIndex)
            }
        } else if currentPlayingIndex < audioChunks.count {
            if audioChunks[currentPlayingIndex] != nil {
                playAudioChunk(at: currentPlayingIndex, fromTime: currentTime, shouldPlay: true)
            } else {
                isBuffering = true
                stopAudioTimer()
            }
        } else {
            isAudioPlaying = false
            currentTime = totalDuration
            stopAudioTimer()
        }
    }

    // MARK: Text Splitting Functions

    private func splitTextIntoMeaningfulSegments(_ text: String, minSize: Int = 10, maxSize: Int = 100) -> [String] {
        let modifiedText = text
            .replacingOccurrences(of: #"\.\n"#, with: ". ")
            .replacingOccurrences(of: #"。\n"#, with: "")
            .replacingOccurrences(of: "\n", with: " ")

        var segments: [String] = []
        var currentSegment = ""
        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = modifiedText
        var sentenceFound = false
        sentenceTokenizer.enumerateTokens(in: modifiedText.startIndex..<modifiedText.endIndex) { sentenceRange, _ in
            sentenceFound = true
            let sentence = String(modifiedText[sentenceRange])
            let language = detectLanguage(for: sentence)
            if getCount(for: currentSegment + " " + sentence, language: language) > maxSize {
                if !currentSegment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(currentSegment.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentSegment = ""
                }
                if let splitSentences = splitSentenceAtConjunctions(sentence, language: language, minSize: minSize, maxSize: maxSize) {
                    segments.append(contentsOf: splitSentences)
                } else {
                    let splitSegments = splitSentence(sentence, language: language, minSize: minSize, maxSize: maxSize)
                    segments.append(contentsOf: splitSegments)
                }
            } else {
                currentSegment += " " + sentence
            }
            return true
        }

        if !sentenceFound {
            let language = detectLanguage(for: modifiedText)
            if let splitText = splitSentenceAtConjunctions(modifiedText, language: language, minSize: minSize, maxSize: maxSize) {
                segments.append(contentsOf: splitText)
            } else {
                let splitSegments = splitSentence(modifiedText, language: language, minSize: minSize, maxSize: maxSize)
                segments.append(contentsOf: splitSegments)
            }
        }

        if !currentSegment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(currentSegment.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        segments.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return segments
    }

    private func detectLanguage(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "unknown"
    }

    private func languageIsWordBased(_ language: String) -> Bool {
        let wordBasedLanguages = ["en", "fr", "de", "es", "it", "pt", "ru", "ja", "ko"]
        return wordBasedLanguages.contains(language)
    }

    private func wordCount(in text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    private func characterCount(in text: String) -> Int {
        return text.count
    }

    private func getCount(for text: String, language: String) -> Int {
        if languageIsWordBased(language) {
            return wordCount(in: text)
        } else {
            return characterCount(in: text)
        }
    }

    private func splitSentenceAtConjunctions(_ sentence: String, language: String, minSize: Int, maxSize: Int) -> [String]? {
        guard languageIsWordBased(language) else { return nil }

        let nsSentence = sentence as NSString
        let tagger = NSLinguisticTagger(tagSchemes: [.lexicalClass], options: 0)
        tagger.string = sentence
        var conjunctionRanges: [NSRange] = []
        tagger.enumerateTags(in: NSRange(location: 0, length: nsSentence.length), unit: .word, scheme: .lexicalClass) { tag, tokenRange, _ in
            if tag == .conjunction {
                conjunctionRanges.append(tokenRange)
            }
        }

        if conjunctionRanges.isEmpty { return nil }

        var splitSegments: [String] = []
        var lastSplitIndex = 0
        var buffer = ""

        for tokenRange in conjunctionRanges {
            let splitRange = NSRange(location: lastSplitIndex, length: tokenRange.location - lastSplitIndex)
            if splitRange.length > 0 {
                let segment = nsSentence.substring(with: splitRange).trimmingCharacters(in: .whitespacesAndNewlines)
                if !segment.isEmpty {
                    if getCount(for: buffer + " " + segment, language: language) <= maxSize {
                        buffer += " " + segment
                    } else {
                        if !buffer.isEmpty {
                            splitSegments.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                            buffer = ""
                        }
                        if let splitSentences = splitSentenceAtConjunctions(segment, language: language, minSize: minSize, maxSize: maxSize) {
                            splitSegments.append(contentsOf: splitSentences)
                        } else {
                            let furtherSplits = splitSentence(segment, language: language, minSize: minSize, maxSize: maxSize)
                            splitSegments.append(contentsOf: furtherSplits)
                        }
                    }
                }
            }

            let conjunction = nsSentence.substring(with: tokenRange).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer += " " + conjunction
            lastSplitIndex = tokenRange.location + tokenRange.length
        }

        let remainingRange = NSRange(location: lastSplitIndex, length: nsSentence.length - lastSplitIndex)
        if remainingRange.length > 0 {
            let remainingSegment = nsSentence.substring(with: remainingRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainingSegment.isEmpty {
                if getCount(for: buffer + " " + remainingSegment, language: language) <= maxSize {
                    buffer += " " + remainingSegment
                } else {
                    if !buffer.isEmpty {
                        splitSegments.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    splitSegments.append(remainingSegment)
                }
            }
        }

        if !buffer.isEmpty {
            splitSegments.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var finalSegments: [String] = []
        for seg in splitSegments {
            let segCount = getCount(for: seg, language: language)
            if segCount > maxSize {
                let furtherSplits = splitSentence(seg, language: language, minSize: minSize, maxSize: maxSize)
                finalSegments.append(contentsOf: furtherSplits)
            } else if segCount >= minSize {
                finalSegments.append(seg)
            } else {
                if let last = finalSegments.popLast() {
                    finalSegments.append(last + " " + seg)
                } else {
                    finalSegments.append(seg)
                }
            }
        }
        return finalSegments
    }

    private func splitSentence(_ sentence: String, language: String, minSize: Int, maxSize: Int) -> [String] {
        var splitSegments: [String] = []
        if languageIsWordBased(language) {
            let words = sentence.split { $0.isWhitespace }
            var current = ""
            for word in words {
                let wordStr = String(word)
                let potential = current.isEmpty ? wordStr : "\(current) \(wordStr)"
                if wordCount(in: potential) > maxSize {
                    if !current.isEmpty {
                        splitSegments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                        current = wordStr
                    } else {
                        splitSegments.append(wordStr)
                        current = ""
                    }
                } else {
                    current = potential
                }
            }
            if !current.isEmpty {
                splitSegments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } else {
            var current = ""
            for char in sentence {
                let charStr = String(char)
                let potential = current + charStr
                if characterCount(in: potential) > maxSize {
                    if !current.isEmpty {
                        splitSegments.append(current)
                        current = charStr
                    } else {
                        splitSegments.append(charStr)
                        current = ""
                    }
                } else {
                    current = potential
                }
            }
            if !current.isEmpty {
                splitSegments.append(current)
            }
        }
        return splitSegments
    }
}

// Safe array indexing
private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
