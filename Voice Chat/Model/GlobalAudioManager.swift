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
final class GlobalAudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = GlobalAudioManager()

    // MARK: - Public State
    @Published var isShowingAudioPlayer: Bool = false
    @Published var isAudioPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var isLoading: Bool = false
    @Published var isBuffering: Bool = false
    @Published var errorMessage: String?

    // MARK: - Players & Timers
    private var audioPlayer: AVAudioPlayer?
    private var nextAudioPlayer: AVAudioPlayer?
    private var audioTimer: Timer?

    // Watchdog
    private var stallWatchdog: Timer?
    private var lastObservedPlaybackTime: TimeInterval = 0
    private var lastProgressTimestamp: Date = .init()

    // MARK: - Segmented Buffer
    private var textSegments: [String] = []
    private var audioChunks: [Data?] = []
    private var chunkDurations: [TimeInterval] = []
    private var totalDuration: TimeInterval = 0

    private var currentChunkIndex: Int = 0
    private var currentPlayingIndex: Int = 0

    private var dataTasks: [URLSessionDataTask] = []
    private var inFlightIndexes: Set<Int> = []

    // MARK: - Seek State
    private var seekTime: TimeInterval?
    private var isSeeking: Bool = false

    // MARK: - Config
    private let settingsManager = SettingsManager.shared
    var mediaType: String = "wav"

    // MARK: - Constants
    private let endEpsilon: TimeInterval = 0.03

    // MARK: - URL Builder
    private func constructTTSURL() -> URL? {
        let addr = settingsManager.serverSettings.serverAddress
        return URL(string: "\(addr)/tts")
    }

    // MARK: - Segment Time Helpers
    private func findSegmentIndex(for time: TimeInterval) -> Int {
        if chunkDurations.isEmpty { return 0 }
        var cum: TimeInterval = 0
        for i in 0..<chunkDurations.count {
            let dur = max(0, chunkDurations[i])
            if dur == 0 {
                if time <= cum + 0.001 { return i }
            } else {
                if time < cum + dur { return i }
                cum += dur
            }
        }
        return max(0, chunkDurations.count - 1)
    }

    private func startTime(forSegment idx: Int) -> TimeInterval {
        guard idx > 0, idx <= chunkDurations.count else { return 0 }
        var sum: TimeInterval = 0
        for i in 0..<idx {
            sum += max(0, chunkDurations[i])
        }
        return sum
    }

    private func allChunksLoaded() -> Bool {
        !audioChunks.contains(where: { $0 == nil })
    }

    private func playbackFinished() -> Bool {
        totalDuration > 0 && allChunksLoaded() && currentTime >= max(0, totalDuration - endEpsilon)
    }

    private func recalcTotalDuration() {
        totalDuration = chunkDurations.reduce(0) { $0 + max(0, $1) }
    }

    // MARK: - Finish
    private func finishPlayback() {
        currentPlayingIndex = max(0, audioChunks.count - 1)
        currentTime = max(currentTime, totalDuration)
        isAudioPlaying = false
        isBuffering = false
        isSeeking = false
        seekTime = nil

        audioPlayer?.stop()
        audioPlayer = nil
        nextAudioPlayer?.stop()
        nextAudioPlayer = nil

        stopAudioTimer()
        stopStallWatchdog()
    }

    // MARK: - Entry
    func startProcessing(text: String) {
        resetPlayer()
        isShowingAudioPlayer = true
        isLoading = true
        isAudioPlaying = true
        currentTime = 0

        let v = settingsManager.voiceSettings
        textSegments = v.enableStreaming ? splitTextIntoMeaningfulSegments(text) : [text]

        let n = textSegments.count
        audioChunks = Array(repeating: nil, count: n)
        chunkDurations = Array(repeating: 0, count: n)
        totalDuration = 0

        currentChunkIndex = 0
        currentPlayingIndex = 0

        sendNextSegment()
    }

    // MARK: - Request Queue
    private func sendNextSegment() {
        guard currentChunkIndex < textSegments.count else { return }
        let idx = currentChunkIndex
        currentChunkIndex += 1
        sendTTSRequest(for: textSegments[idx], index: idx)
    }

    private func sendTTSRequest(for segmentText: String, index: Int) {
        guard !inFlightIndexes.contains(index) else { return }
        guard let url = constructTTSURL() else {
            self.errorMessage = "Unable to construct TTS URL"
            return
        }
        inFlightIndexes.insert(index)

        let s = settingsManager
        var params: [String: Any] = [
            "text": segmentText,
            "text_lang": s.serverSettings.textLang,
            "ref_audio_path": s.serverSettings.refAudioPath,
            "prompt_text": s.serverSettings.promptText,
            "prompt_lang": s.serverSettings.promptLang,
            "batch_size": 1,
            "media_type": mediaType
        ]
        params["text_split_method"] = s.voiceSettings.enableStreaming ? "cut0" : s.modelSettings.autoSplit

        guard let body = try? JSONSerialization.data(withJSONObject: params) else {
            self.errorMessage = "Unable to serialize JSON"
            inFlightIndexes.remove(index)
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let task = URLSession.shared.dataTask(with: req) { [weak self] data, resp, error in
            guard let self = self else { return }
            defer {
                DispatchQueue.main.async {
                    self.inFlightIndexes.remove(index)
                    self.sendNextSegment()
                }
            }

            if let err = error as NSError? {
                DispatchQueue.main.async {
                    self.errorMessage = err.localizedDescription
                }
                return
            }

            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                DispatchQueue.main.async {
                    self.errorMessage = "TTS server error: \(http.statusCode)"
                }
                return
            }

            guard let data = data, !data.isEmpty else {
                DispatchQueue.main.async { self.errorMessage = "No data received" }
                return
            }

            DispatchQueue.main.async {
                if index < self.audioChunks.count {
                    self.audioChunks[index] = data
                    if let p = try? AVAudioPlayer(data: data) {
                        self.chunkDurations[index] = max(0, p.duration)
                    } else {
                        self.chunkDurations[index] = 0
                    }
                    self.recalcTotalDuration()
                }

                if self.playbackFinished() {
                    self.finishPlayback()
                    return
                }

                if index == 0 || index == self.currentPlayingIndex {
                    self.isLoading = false
                    _ = self.playAudioChunk(at: index, fromTime: self.seekTime, shouldPlay: self.isAudioPlaying)
                    self.seekTime = nil
                }

                if self.isBuffering && index == self.currentPlayingIndex {
                    _ = self.playAudioChunk(at: index, fromTime: self.seekTime ?? self.currentTime, shouldPlay: self.isAudioPlaying)
                    self.seekTime = nil
                }

                if index == self.currentPlayingIndex + 1 {
                    self.prepareNextAudioChunk(at: index)
                }
            }
        }
        task.resume()
        dataTasks.append(task)
    }

    // MARK: - Playback
    private func prepareNextAudioChunk(at index: Int) {
        guard let chunkOpt = audioChunks[safe: index], let data = chunkOpt else { return }
        if let p = try? AVAudioPlayer(data: data) {
            p.delegate = self
            p.prepareToPlay()
            nextAudioPlayer = p
        }
    }

    @discardableResult
    private func playAudioChunk(at index: Int, fromTime t: TimeInterval? = nil, shouldPlay: Bool = true) -> Bool {
        guard index >= 0, index < audioChunks.count else {
            isBuffering = false
            return false
        }
        guard let chunkOpt = audioChunks[safe: index], let data = chunkOpt else {
            isBuffering = true
            stopAudioTimer()
            startStallWatchdog()
            return false
        }

        do {
            if playbackFinished() || (allChunksLoaded() && currentTime >= totalDuration - endEpsilon) {
                finishPlayback()
                return false
            }

            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            p.prepareToPlay()
            audioPlayer?.stop()
            audioPlayer = p

            let segStart = startTime(forSegment: index)

            let localTime: TimeInterval
            if let global = t {
                let mapped = max(0, global - segStart)
                localTime = min(max(0, mapped), max(0, p.duration))
            } else {
                localTime = 0
            }

            let atSegmentEnd = localTime >= max(0, p.duration - endEpsilon)
            let atGlobalEnd = allChunksLoaded() && (segStart + localTime) >= (totalDuration - endEpsilon)
            if atSegmentEnd && atGlobalEnd {
                finishPlayback()
                return false
            }

            p.currentTime = localTime

            currentPlayingIndex = index
            isBuffering = false
            isSeeking = false

            if shouldPlay {
                if allChunksLoaded() && (segStart + p.currentTime) >= (totalDuration - endEpsilon) {
                    finishPlayback()
                    return false
                }
                let didPlay = p.play()
                if !didPlay { _ = p.play() }
                startAudioTimer()
                startStallWatchdog()
            } else {
                stopAudioTimer()
                startStallWatchdog()
            }

            prepareNextAudioChunk(at: index + 1)
            return true
        } catch {
            self.errorMessage = "Failed to start audio playback: \(error.localizedDescription)"
            isBuffering = true
            startStallWatchdog()
            return false
        }
    }

    // MARK: - Play/Pause
    func togglePlayback() {
        if !isAudioPlaying && playbackFinished() {
            currentPlayingIndex = 0
            currentTime = 0
        }

        if !isAudioPlaying {
            isAudioPlaying = true
            if playbackFinished() {
                isAudioPlaying = false
                return
            }
            if let chunkOpt = audioChunks[safe: currentPlayingIndex], let _ = chunkOpt {
                _ = playAudioChunk(at: currentPlayingIndex, fromTime: currentTime, shouldPlay: true)
            } else {
                isBuffering = true
                startStallWatchdog()
            }
        } else {
            isAudioPlaying = false
            audioPlayer?.pause()
            stopAudioTimer()
            startStallWatchdog()
            isBuffering = false
        }
    }

    // MARK: - Seek
    func forward15Seconds() { seek(to: currentTime + 15, shouldPlay: isAudioPlaying) }
    func backward15Seconds() { seek(to: currentTime - 15, shouldPlay: isAudioPlaying) }

    func seek(to time: TimeInterval, shouldPlay: Bool = false) {
        guard totalDuration > 0 || !chunkDurations.isEmpty else { return }

        let maxKnown = max(totalDuration, startTime(forSegment: chunkDurations.count))
        var newT = time
        if maxKnown > 0 {
            newT = max(0, min(time, maxKnown))
        } else {
            newT = max(0, time)
        }
        currentTime = newT

        if allChunksLoaded() && currentTime >= totalDuration - endEpsilon {
            currentTime = totalDuration
            finishPlayback()
            return
        }

        let target = findSegmentIndex(for: newT)

        if target != currentPlayingIndex {
            audioPlayer?.stop()
            audioPlayer = nil
            currentPlayingIndex = target
        }

        if let chunkOpt = audioChunks[safe: target], let _ = chunkOpt {
            _ = playAudioChunk(at: target, fromTime: newT, shouldPlay: shouldPlay)
        } else {
            isBuffering = shouldPlay
            isSeeking = true
            seekTime = newT
            stopAudioTimer()
            startStallWatchdog()
            if !inFlightIndexes.contains(target) {
                sendTTSRequest(for: textSegments[target], index: target)
            }
        }
    }

    // MARK: - AVAudioPlayerDelegate
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedID = ObjectIdentifier(player)
        Task { @MainActor in
            guard let current = self.audioPlayer,
                  ObjectIdentifier(current) == finishedID else { return }

            self.currentPlayingIndex += 1

            if self.currentPlayingIndex >= self.audioChunks.count {
                self.recalcTotalDuration()
                self.currentTime = self.totalDuration
                self.finishPlayback()
                return
            }

            if let next = self.nextAudioPlayer {
                self.audioPlayer = next
                self.nextAudioPlayer = nil
                self.audioPlayer?.delegate = self

                let segStart = self.startTime(forSegment: self.currentPlayingIndex)
                self.currentTime = segStart

                if self.isAudioPlaying {
                    self.audioPlayer?.currentTime = 0
                    self.audioPlayer?.play()
                    self.startAudioTimer()
                    self.startStallWatchdog()
                }
                self.prepareNextAudioChunk(at: self.currentPlayingIndex + 1)
            } else {
                if let chunkOpt = self.audioChunks[safe: self.currentPlayingIndex], let _ = chunkOpt {
                    _ = self.playAudioChunk(at: self.currentPlayingIndex,
                                            fromTime: self.startTime(forSegment: self.currentPlayingIndex),
                                            shouldPlay: self.isAudioPlaying)
                } else {
                    self.isBuffering = self.isAudioPlaying
                    self.stopAudioTimer()
                    self.startStallWatchdog()
                }
            }
        }
    }

    // MARK: - Timers
    private func startAudioTimer() {
        stopAudioTimer()
        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      let p = self.audioPlayer,
                      !self.isBuffering else { return }

                let segStart = self.startTime(forSegment: self.currentPlayingIndex)
                var newTime = segStart + p.currentTime

                if self.allChunksLoaded() && newTime >= (self.totalDuration - self.endEpsilon) {
                    self.currentTime = self.totalDuration
                    self.finishPlayback()
                    return
                }

                if newTime + 0.0005 >= self.currentTime {
                    self.currentTime = newTime
                } else {
                    self.currentTime = max(self.currentTime, newTime)
                }

                self.lastObservedPlaybackTime = p.currentTime
                self.lastProgressTimestamp = Date()
            }
        }
        if let timer = audioTimer {
            timer.tolerance = 0.02
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    private func stopAudioTimer() {
        audioTimer?.invalidate()
        audioTimer = nil
    }

    private func startStallWatchdog() {
        stopStallWatchdog()
        stallWatchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                if self.playbackFinished() {
                    self.finishPlayback()
                    return
                }

                if self.isBuffering {
                    let elapsed = Date().timeIntervalSince(self.lastProgressTimestamp)
                    if elapsed > 8 {
                        let idx = self.currentPlayingIndex
                        if self.audioChunks[safe: idx] == nil && !self.inFlightIndexes.contains(idx) {
                            self.sendTTSRequest(for: self.textSegments[idx], index: idx)
                        }
                        self.lastProgressTimestamp = Date()
                    }
                    return
                }

                if self.isAudioPlaying, let p = self.audioPlayer {
                    let elapsedNoProgress = Date().timeIntervalSince(self.lastProgressTimestamp)
                    let isNotAdvancing = abs(p.currentTime - self.lastObservedPlaybackTime) < 0.01
                    let isNotPlaying = !p.isPlaying

                    if (isNotPlaying || isNotAdvancing) && elapsedNoProgress > 2 {
                        let segStart = self.startTime(forSegment: self.currentPlayingIndex)
                        let projectedGlobal = segStart + p.currentTime
                        if self.allChunksLoaded() && projectedGlobal >= (self.totalDuration - self.endEpsilon) {
                            self.finishPlayback()
                            return
                        }

                        p.stop()
                        let resumeGlobal = max(segStart, self.currentTime)
                        _ = self.playAudioChunk(at: self.currentPlayingIndex,
                                                fromTime: resumeGlobal,
                                                shouldPlay: self.isAudioPlaying)
                        self.lastProgressTimestamp = Date()
                    }
                }
            }
        }
        if let t = stallWatchdog {
            t.tolerance = 0.2
            RunLoop.current.add(t, forMode: .common)
        }
    }

    private func stopStallWatchdog() {
        stallWatchdog?.invalidate()
        stallWatchdog = nil
    }

    // MARK: - Reset / Close
    func closeAudioPlayer() {
        resetPlayer()
        isAudioPlaying = false
        isShowingAudioPlayer = false
        isLoading = false
    }

    private func resetPlayer() {
        dataTasks.forEach { $0.cancel() }
        dataTasks.removeAll()
        inFlightIndexes.removeAll()

        audioPlayer?.stop()
        audioPlayer = nil
        nextAudioPlayer?.stop()
        nextAudioPlayer = nil

        stopAudioTimer()
        stopStallWatchdog()

        textSegments.removeAll()
        audioChunks.removeAll()
        chunkDurations.removeAll()
        totalDuration = 0

        currentChunkIndex = 0
        currentPlayingIndex = 0
        currentTime = 0
        isBuffering = false
        isSeeking = false
        seekTime = nil
        errorMessage = nil

        lastObservedPlaybackTime = 0
        lastProgressTimestamp = Date()
    }

    // MARK: - Text Segmentation
    private func splitTextIntoMeaningfulSegments(_ text: String,
                                                 minSize: Int = 10,
                                                 maxSize: Int = 100) -> [String] {
        var modified = text
        let patterns: [String] = [
            #"([。！？?!…])\s*\n+"#,
            #"(\.)\s*\n+"#
        ]
        for pat in patterns {
            modified = modified.replacingOccurrences(
                of: pat,
                with: "$1 ",
                options: .regularExpression
            )
        }
        modified = modified.replacingOccurrences(of: #"\n+"#, with: " ", options: .regularExpression)
        modified = modified.replacingOccurrences(of: #"[\u{00A0}\s]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var segs: [String] = []
        var current = ""
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = modified
        var found = false

        tokenizer.enumerateTokens(in: modified.startIndex..<modified.endIndex) { range, _ in
            found = true
            let sentence = String(modified[range])
            let lang = detectLanguage(for: sentence)
            let candidate = (current.isEmpty ? "" : current + " ") + sentence
            if getCount(for: candidate, language: lang) > maxSize {
                if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segs.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = ""
                }
                if let sub = splitSentenceAtConjunctions(sentence, language: lang,
                                                         minSize: minSize, maxSize: maxSize) {
                    segs.append(contentsOf: sub)
                } else {
                    segs.append(contentsOf: splitSentence(sentence, language: lang,
                                                          minSize: minSize, maxSize: maxSize))
                }
            } else {
                current = candidate
            }
            return true
        }

        if !found {
            let lang = detectLanguage(for: modified)
            if let sub = splitSentenceAtConjunctions(modified, language: lang,
                                                     minSize: minSize, maxSize: maxSize) {
                segs.append(contentsOf: sub)
            } else {
                segs.append(contentsOf: splitSentence(modified, language: lang,
                                                      minSize: minSize, maxSize: maxSize))
            }
        }

        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segs.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        segs = segs.compactMap {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return segs
    }

    private func detectLanguage(for text: String) -> String {
        let r = NLLanguageRecognizer()
        r.processString(text)
        return r.dominantLanguage?.rawValue ?? "unknown"
    }

    private func languageIsWordBased(_ lang: String) -> Bool {
        ["en","fr","de","es","it","pt","ru","ja","ko"].contains(lang)
    }

    private func wordCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let t = NLTokenizer(unit: .word)
        t.string = text
        var c = 0
        t.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in c += 1; return true }
        return c
    }

    private func characterCount(in text: String) -> Int { text.count }

    private func getCount(for text: String, language: String) -> Int {
        languageIsWordBased(language) ? wordCount(in: text) : characterCount(in: text)
    }

    private func splitSentenceAtConjunctions(_ sentence: String,
                                             language: String,
                                             minSize: Int,
                                             maxSize: Int) -> [String]? {
        guard languageIsWordBased(language) else { return nil }

        let ns = sentence as NSString
        let tagger = NSLinguisticTagger(tagSchemes: [.lexicalClass], options: 0)
        tagger.string = sentence

        var conjRanges: [NSRange] = []
        tagger.enumerateTags(in: NSRange(location: 0, length: ns.length),
                             unit: .word,
                             scheme: .lexicalClass) { tag, range, _ in
            if tag == .conjunction { conjRanges.append(range) }
        }
        guard !conjRanges.isEmpty else { return nil }

        var segments: [String] = []
        var last = 0
        var buf = ""

        for r in conjRanges {
            let splitRange = NSRange(location: last, length: r.location - last)
            if splitRange.length > 0 {
                let part = ns.substring(with: splitRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !part.isEmpty {
                    if getCount(for: (buf.isEmpty ? part : buf + " " + part), language: language) <= maxSize {
                        buf = (buf.isEmpty ? part : buf + " " + part)
                    } else {
                        if !buf.isEmpty {
                            segments.append(buf.trimmingCharacters(in: .whitespacesAndNewlines))
                            buf = ""
                        }
                        if let sub = splitSentenceAtConjunctions(part, language: language,
                                                                 minSize: minSize, maxSize: maxSize) {
                            segments.append(contentsOf: sub)
                        } else {
                            segments.append(contentsOf: splitSentence(part, language: language,
                                                                      minSize: minSize, maxSize: maxSize))
                        }
                    }
                }
            }
            let conj = ns.substring(with: r)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            buf += (buf.isEmpty ? conj : " " + conj)
            last = r.location + r.length
        }

        let remRange = NSRange(location: last, length: ns.length - last)
        if remRange.length > 0 {
            let rem = ns.substring(with: remRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !rem.isEmpty {
                if getCount(for: (buf.isEmpty ? rem : buf + " " + rem), language: language) <= maxSize {
                    buf = (buf.isEmpty ? rem : buf + " " + rem)
                } else {
                    if !buf.isEmpty {
                        segments.append(buf.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    segments.append(rem)
                    buf = ""
                }
            }
        }
        if !buf.isEmpty {
            segments.append(buf.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var final: [String] = []
        for seg in segments {
            let cnt = getCount(for: seg, language: language)
            if cnt > maxSize {
                final.append(contentsOf: splitSentence(seg, language: language,
                                                       minSize: minSize, maxSize: maxSize))
            } else if cnt >= minSize {
                final.append(seg)
            } else {
                if var lastSeg = final.popLast() {
                    lastSeg += " " + seg
                    final.append(lastSeg)
                } else {
                    final.append(seg)
                }
            }
        }
        return final
    }

    private func splitSentence(_ sentence: String,
                               language: String,
                               minSize: Int,
                               maxSize: Int) -> [String] {
        guard !sentence.isEmpty else { return [] }
        var segments: [String] = []
        if languageIsWordBased(language) {
            let words = sentence.split { $0.isWhitespace }
            var cur = ""
            for w in words {
                let s = String(w)
                let pot = cur.isEmpty ? s : "\(cur) \(s)"
                if wordCount(in: pot) > maxSize {
                    if !cur.isEmpty {
                        segments.append(cur.trimmingCharacters(in: .whitespacesAndNewlines))
                        cur = s
                    } else {
                        segments.append(s)
                        cur = ""
                    }
                } else {
                    cur = pot
                }
            }
            if !cur.isEmpty {
                segments.append(cur.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } else {
            var cur = ""
            for c in sentence {
                let s = String(c)
                let pot = cur + s
                if pot.count > maxSize {
                    if !cur.isEmpty {
                        segments.append(cur)
                        cur = s
                    } else {
                        segments.append(s)
                        cur = ""
                    }
                } else {
                    cur = pot
                }
            }
            if !cur.isEmpty {
                segments.append(cur)
            }
        }
        if segments.count > 1 {
            var merged: [String] = []
            for seg in segments {
                if getCount(for: seg, language: language) < minSize, var last = merged.popLast() {
                    last += " " + seg
                    merged.append(last.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    merged.append(seg.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            return merged
        }
        return segments
    }
}

// MARK: - Array Safe Subscript
private extension Array {
    subscript(safe idx: Int) -> Element? {
        (indices.contains(idx) ? self[idx] : nil)
    }
}
