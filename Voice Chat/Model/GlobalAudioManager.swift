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

    // Properties for handling segments and requests
    var textSegments: [String] = []
    var audioChunks: [Data?] = []
    var chunkDurations: [TimeInterval] = [] // Durations of each audio chunk
    var chunkStartTimes: [TimeInterval] = [] // Start times of each chunk
    var totalDuration: TimeInterval = 0 // Total duration of the audio
    var currentChunkIndex: Int = 0
    var currentPlayingIndex: Int = 0
    var requestsInFlight: Int = 0
    let maxRequestsInFlight = 2

    // For canceling in-flight requests
    var dataTasks: [URLSessionDataTask] = []

    // New properties for playback optimization
    private var nextAudioPlayer: AVAudioPlayer?

    // Seeking properties
    private var seekTime: TimeInterval?
    private var isSeeking: Bool = false

    func startProcessing(text: String) {
        // Reset before starting a new request
        resetPlayer()
        isLoading = true
        isShowingAudioPlayer = true

        // Reset cumulative properties
        currentTime = 0
        totalDuration = 0
        errorMessage = nil

        // Fetch the latest settings
        let settingsManager = SettingsManager.shared
        let voiceSettings = settingsManager.voiceSettings

        if voiceSettings.enableStreaming {
            // Streaming enabled: split text locally
            self.textSegments = splitTextIntoMeaningfulSegments(text)
        } else {
            // Streaming disabled: do not split text locally
            self.textSegments = [text]
        }

        // Initialize arrays with fixed sizes
        let segmentCount = textSegments.count
        self.audioChunks = Array(repeating: nil, count: segmentCount)
        self.chunkDurations = Array(repeating: 0, count: segmentCount)
        self.chunkStartTimes = Array(repeating: 0, count: segmentCount)
        // Initialize indices
        self.currentChunkIndex = 0
        self.currentPlayingIndex = 0
        // Initialize requestsInFlight
        self.requestsInFlight = 0

        // Start sending requests for segments
        sendNextSegment()
        if textSegments.count > 1 {
            sendNextSegment()
        }
    }

    private func sendNextSegment() {
        guard currentChunkIndex < textSegments.count else {
            return
        }
        guard requestsInFlight < maxRequestsInFlight else {
            return
        }
        let index = currentChunkIndex
        currentChunkIndex += 1
        requestsInFlight += 1

        let segmentText = textSegments[index]
        // Send TTS request for segmentText
        sendTTSRequest(for: segmentText, index: index)
    }

    private func sendTTSRequest(for segmentText: String, index: Int) {
        // Build TTS request URL
        guard let url = constructTTSURL() else {
            print("Unable to construct TTS URL")
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Unable to construct TTS URL"
            }
            return
        }

        // Fetch the latest settings
        let settingsManager = SettingsManager.shared
        let modelSettings = settingsManager.modelSettings
        let serverSettings = settingsManager.serverSettings
        let voiceSettings = settingsManager.voiceSettings

        // Prepare parameters
        var parameters: [String: Any] = [
            "text": segmentText,
            "text_lang": serverSettings.textLang,
            "ref_audio_path": serverSettings.refAudioPath,
            "prompt_text": serverSettings.promptText,
            "prompt_lang": serverSettings.promptLang,
            "batch_size": 1,
            "media_type": mediaType
        ]

        // Set 'text_split_method' based on streaming status
        if voiceSettings.enableStreaming {
            // Streaming enabled: force 'cut0' (no server-side splitting)
            parameters["text_split_method"] = "cut0"
        } else {
            // Streaming disabled: use user-selected 'autoSplit' value
            parameters["text_split_method"] = modelSettings.autoSplit
        }

        // Convert parameters to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: parameters, options: []) else {
            print("Unable to serialize JSON")
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Unable to serialize JSON"
            }
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60 // Adjust as needed
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // Create URLSession data task
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            defer {
                DispatchQueue.main.async {
                    self.requestsInFlight -= 1
                    self.sendNextSegment()
                }
            }

            if let error = error {
                print("Audio request failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Audio request failed: \(error.localizedDescription)"
                }
                return
            }

            guard let data = data else {
                print("No data received")
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "No data received"
                }
                return
            }

            DispatchQueue.main.async {
                // Check if audioChunks array has been reset
                if index >= self.audioChunks.count {
                    return
                }
                self.audioChunks[index] = data

                // Save duration of the audio segment
                if let player = try? AVAudioPlayer(data: data) {
                    let segmentDuration = player.duration
                    self.chunkDurations[index] = segmentDuration

                    // Recalculate chunk start times and total duration
                    self.calculateChunkStartTimesAndTotalDuration()
                }

                if index == self.currentPlayingIndex {
                    // First segment is ready
                    self.isLoading = false
                    self.isBuffering = false
                    // **Automatically start playback for the first chunk**
                    self.playAudioChunk(at: index, fromTime: self.seekTime, shouldPlay: true)
                    self.seekTime = nil
                } else if self.isBuffering && self.isSeeking {
                    // If buffering and seeking, attempt to play from seek position
                    self.playAudioChunk(at: self.currentPlayingIndex, fromTime: self.seekTime, shouldPlay: self.isAudioPlaying)
                    self.seekTime = nil
                } else if self.isBuffering && index == self.currentPlayingIndex + 1 {
                    // If buffering and the next chunk is now available, prepare next chunk
                    self.prepareNextAudioChunk(at: index)
                } else if index == self.currentPlayingIndex + 1 {
                    // Preload next audio segment
                    self.prepareNextAudioChunk(at: index)
                }
            }
        }
        task.resume()
        dataTasks.append(task)
    }

    // Recalculate chunk start times and total duration
    private func calculateChunkStartTimesAndTotalDuration() {
        var cumulativeTime: TimeInterval = 0
        for i in 0..<self.chunkDurations.count {
            let duration = self.chunkDurations[i]
            self.chunkStartTimes[i] = cumulativeTime
            cumulativeTime += duration
        }
        self.totalDuration = cumulativeTime
    }

    // Prepare the next audio segment
    private func prepareNextAudioChunk(at index: Int) {
        guard index < audioChunks.count else { return }
        guard let data = audioChunks[index] else { return }

        do {
            nextAudioPlayer = try AVAudioPlayer(data: data)
            nextAudioPlayer?.delegate = self
            nextAudioPlayer?.prepareToPlay()
        } catch {
            print("Failed to prepare next audio: \(error)")
        }
    }

    // Start playback from the given chunk index and time
    private func playAudioChunk(at index: Int, fromTime time: TimeInterval? = nil, shouldPlay: Bool = true) {
        guard index < audioChunks.count else {
            // All chunks have been played
            // Do not hide the player interface
            return
        }
        guard let data = audioChunks[index] else {
            // Audio data not yet available, wait
            // Show buffering indicator
            isAudioPlaying = false
            isBuffering = true
            stopAudioTimer()
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()

            var startTime: TimeInterval = 0
            if let time = time {
                startTime = time - self.chunkStartTimes[index]
                if startTime < 0 {
                    startTime = 0
                } else if startTime > audioPlayer?.duration ?? 0 {
                    startTime = audioPlayer?.duration ?? 0
                }
            }

            // Prevent playback if seeking to totalDuration
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

            // Preload next segment if available
            let nextIndex = index + 1
            if nextIndex < audioChunks.count, let _ = audioChunks[nextIndex] {
                prepareNextAudioChunk(at: nextIndex)
            }
        } catch {
            print("Failed to start audio playback: \(error)")
            errorMessage = "Failed to start audio playback: \(error.localizedDescription)"
        }
    }

    // Toggle playback
    func togglePlayback() {
        if isBuffering {
            // Do not allow toggling playback while buffering
            return
        }

        if isAudioPlaying {
            audioPlayer?.pause()
            isAudioPlaying = false
            stopAudioTimer()
        } else {
            if currentTime >= totalDuration {
                // Audio has finished playing; reset to beginning and start playback
                seek(to: 0, shouldPlay: true)
            } else {
                audioPlayer?.play()
                isAudioPlaying = true
                startAudioTimer()
            }
        }
    }

    // Fast forward 15 seconds
    func forward15Seconds() {
        let newTime = currentTime + 15
        seek(to: newTime, shouldPlay: isAudioPlaying)
    }

    // Rewind 15 seconds
    func backward15Seconds() {
        let newTime = currentTime - 15
        seek(to: newTime, shouldPlay: isAudioPlaying)
    }

    // Seek to a specific time with optional playback control
    func seek(to time: TimeInterval, shouldPlay: Bool = false) {
        guard totalDuration > 0 else { return }
        let newTime = max(0, min(time, totalDuration))
        currentTime = newTime

        // Find the chunk index for the requested time
        var targetChunkIndex = 0
        for i in 0..<chunkStartTimes.count {
            if chunkStartTimes[i] > currentTime {
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

        // If the chunk is available, set up the player
        if let _ = audioChunks[currentPlayingIndex] {
            playAudioChunk(at: currentPlayingIndex, fromTime: currentTime, shouldPlay: shouldPlay)
            isBuffering = false
        } else {
            // Otherwise, set buffering state and wait for the chunk
            isBuffering = true
            seekTime = currentTime
            stopAudioTimer()
        }

        // If seeking to or beyond totalDuration, stop playback
        if newTime >= totalDuration {
            isAudioPlaying = false
            audioPlayer?.stop()
            stopAudioTimer()
        }
    }

    // Close audio player
    func closeAudioPlayer() {
        resetPlayer()
        isAudioPlaying = false
        isShowingAudioPlayer = false
        isLoading = false
    }

    // Reset player
    private func resetPlayer() {
        // Cancel all in-flight requests
        for task in dataTasks {
            task.cancel()
        }
        dataTasks.removeAll()

        audioPlayer?.stop()
        audioPlayer = nil
        nextAudioPlayer?.stop()
        nextAudioPlayer = nil
        currentTime = 0
        totalDuration = 0
        stopAudioTimer()
        textSegments = []
        audioChunks = []
        chunkDurations = []
        chunkStartTimes = []
        currentChunkIndex = 0
        currentPlayingIndex = 0
        requestsInFlight = 0
        isBuffering = false
        isSeeking = false
        seekTime = nil
        errorMessage = nil
    }

    // Start audio timer
    private func startAudioTimer() {
        stopAudioTimer()
        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { [weak self] timer in
            guard let self = self else { return }
            if self.isBuffering {
                // Do not update currentTime during buffering
                return
            }
            if let player = self.audioPlayer {
                let chunkStartTime = self.chunkStartTimes[self.currentPlayingIndex]
                let playerCurrentTime = player.currentTime
                self.currentTime = chunkStartTime + playerCurrentTime
                if self.currentTime >= self.totalDuration {
                    // Audio has finished playing
                    self.currentTime = self.totalDuration
                    self.isAudioPlaying = false
                    self.audioPlayer?.stop()
                    self.stopAudioTimer()
                }
            }
        })
        RunLoop.current.add(audioTimer!, forMode: .common)
    }

    // Stop audio timer
    private func stopAudioTimer() {
        audioTimer?.invalidate()
        audioTimer = nil
    }

    // Construct TTS URL
    private func constructTTSURL() -> URL? {
        // Fetch the latest server settings
        let serverSettings = SettingsManager.shared.serverSettings
        let urlString = "\(serverSettings.serverAddress)/tts"
        return URL(string: urlString)
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Move to next chunk
        currentPlayingIndex += 1

        if currentTime >= totalDuration {
            // Audio playback has finished
            currentTime = totalDuration
            isAudioPlaying = false
            stopAudioTimer()
            return
        }

        if let nextPlayer = nextAudioPlayer {
            // Start next audio
            audioPlayer = nextPlayer
            nextAudioPlayer = nil
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isAudioPlaying = true

            startAudioTimer()

            // Preload the subsequent segment
            let nextIndex = currentPlayingIndex + 1
            if nextIndex < audioChunks.count, let _ = audioChunks[nextIndex] {
                prepareNextAudioChunk(at: nextIndex)
            }
        } else if currentPlayingIndex < audioChunks.count {
            // Check if next chunk is available
            if let _ = audioChunks[currentPlayingIndex] {
                playAudioChunk(at: currentPlayingIndex, fromTime: currentTime, shouldPlay: true)
            } else {
                // Next chunk not yet available
                isBuffering = true
                stopAudioTimer()
            }
        } else {
            // No more chunks
            isAudioPlaying = false
            currentTime = totalDuration
            stopAudioTimer()
        }
    }

    // Text Splitting Functions
    func splitTextIntoMeaningfulSegments(_ text: String, minSize: Int = 10, maxSize: Int = 100) -> [String] {
        let modifiedText = text.replacingOccurrences(of: #"\.\n"#, with: ". ")
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

    func detectLanguage(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let language = recognizer.dominantLanguage {
            return language.rawValue
        }
        return "unknown"
    }

    func languageIsWordBased(_ language: String) -> Bool {
        let wordBasedLanguages = ["en", "fr", "de", "es", "it", "pt", "ru", "ja", "ko"]
        return wordBasedLanguages.contains(language)
    }

    func wordCount(in text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    func characterCount(in text: String) -> Int {
        return text.count
    }

    func getCount(for text: String, language: String) -> Int {
        if languageIsWordBased(language) {
            return wordCount(in: text)
        } else {
            return characterCount(in: text)
        }
    }

    func splitSentenceAtConjunctions(_ sentence: String, language: String, minSize: Int, maxSize: Int) -> [String]? {
        var splitSegments: [String] = []
        if languageIsWordBased(language) {
            let nsSentence = sentence as NSString
            let tagger = NSLinguisticTagger(tagSchemes: [.lexicalClass], options: 0)
            tagger.string = sentence
            var conjunctionRanges: [NSRange] = []
            tagger.enumerateTags(in: NSRange(location: 0, length: nsSentence.length), unit: .word, scheme: .lexicalClass) { tag, tokenRange, _ in
                if tag == .conjunction {
                    conjunctionRanges.append(tokenRange)
                }
            }
            if conjunctionRanges.isEmpty {
                return nil
            }
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
                                let splitSegmentsFurther = splitSentence(segment, language: language, minSize: minSize, maxSize: maxSize)
                                splitSegments.append(contentsOf: splitSegmentsFurther)
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
        return nil
    }

    func splitSentence(_ sentence: String, language: String, minSize: Int, maxSize: Int) -> [String] {
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
