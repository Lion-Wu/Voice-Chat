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

    // MARK: - Lightweight caches (perf)
    private let langCache = NSCache<NSString, NSString>()
    private let wordCountCache = NSCache<NSString, NSNumber>()

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
                let newTime = segStart + p.currentTime

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

    // MARK: - Text Segmentation (unchanged behavior, optimized impl)
    private func splitTextIntoMeaningfulSegments(_ rawText: String) -> [String] {
        // Tunable heuristics
        let targetMinSec: Double = 5.0
        let targetMaxSec: Double = 10.0
        let enWordsPerSec: Double = 2.8   // ~168 wpm
        let zhCharsPerSec: Double = 4.5   // 4–5 cps
        let maxCJKLen = 75
        let maxWordLen = 50

        // 1) Normalize whitespace & add pause punctuation for bare newlines (O(n) single pass)
        let normalized = normalizeLinesAddingPause(rawText)

        // 2) Tokenize into sentences
        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = normalized

        var sentences: [String] = []
        sentenceTokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
            let s = String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { sentences.append(s) }
            return true
        }
        if sentences.isEmpty {
            sentences = [normalized.trimmingCharacters(in: .whitespacesAndNewlines)]
                .compactMap { $0.isEmpty ? nil : $0 }
        }

        // 3) Greedy build segments
        var i = 0
        var segments: [String] = []

        while i < sentences.count {
            let s1 = sentences[i]
            let lang1 = dominantLanguageCached(s1)
            let sec1 = estSeconds(s1, lang: lang1, enWPS: enWordsPerSec, zhCPS: zhCharsPerSec)
            let c1 = countFor(s1, lang: lang1)

            // Overlong -> split down
            if sec1 > targetMaxSec || c1 > hardMax(for: lang1, maxWordLen: maxWordLen, maxCJKLen: maxCJKLen) {
                let pieces = splitOverlongSentence(
                    s1,
                    lang: lang1,
                    maxLen: hardMax(for: lang1, maxWordLen: maxWordLen, maxCJKLen: maxCJKLen),
                    targetMinSec: targetMinSec,
                    targetMaxSec: targetMaxSec,
                    enWPS: enWordsPerSec,
                    zhCPS: zhCharsPerSec
                )
                for p in pieces {
                    let pl = dominantLanguageCached(p)
                    segments.append(ensureTerminalPunctuation(p, lang: pl))
                }
                i += 1
                continue
            }

            // If 5–10s, keep single (prefer short)
            if sec1 >= targetMinSec && sec1 <= targetMaxSec {
                segments.append(ensureTerminalPunctuation(s1, lang: lang1))
                i += 1
                continue
            }

            // If <5s, try merge with next; prefer exactly two sentences within <=10s and under hard cap
            if sec1 < targetMinSec, i + 1 < sentences.count {
                let s2 = sentences[i + 1]
                let merged = (s1 + " " + s2).replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
                let mLang = dominantLanguageCached(merged)
                let mSec = estSeconds(merged, lang: mLang, enWPS: enWordsPerSec, zhCPS: zhCharsPerSec)
                let mCount = countFor(merged, lang: mLang)
                if mSec <= targetMaxSec &&
                    mCount <= hardMax(for: mLang, maxWordLen: maxWordLen, maxCJKLen: maxCJKLen) {
                    segments.append(ensureTerminalPunctuation(merged, lang: mLang))
                    i += 2
                    continue
                } else {
                    segments.append(ensureTerminalPunctuation(s1, lang: lang1))
                    i += 1
                    continue
                }
            }

            // Fallback
            segments.append(ensureTerminalPunctuation(s1, lang: lang1))
            i += 1
        }

        // 4) Clean
        let cleaned = segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return cleaned
    }

    // MARK: - Normalization (single pass, no regex loops)
    private func normalizeLinesAddingPause(_ text: String) -> String {
        // 合并多余空白但先保留换行
        var base = text
        base = base.replacingOccurrences(of: #"[ \t\u{00A0}]{2,}"#, with: " ", options: .regularExpression)
        // 分割行，重组时在“裸换行”处插入轻停顿（，/ ,），避免连读
        let lines = base.split(whereSeparator: \.isNewline).map { String($0) }

        if lines.isEmpty { return text.trimmingCharacters(in: .whitespacesAndNewlines) }

        var out = lines[0]
        for idx in 1..<lines.count {
            // 查看 out 当前末尾的“最后一个非空白字符”
            let trimmedOut = out.trimmingCharacters(in: .whitespacesAndNewlines)
            let lastScalar = trimmedOut.unicodeScalars.last
            let lastChar = lastScalar.map { Character($0) }

            // 终止/停顿/逗号等集合
            let terminals: Set<Character> = ["。","！","？",".","!","?","…","；",";","．"]
            let commaLikes: Set<Character> = ["，",",","、",":","：","；",";"]

            let needPause: Bool
            if let lc = lastChar {
                needPause = !(terminals.contains(lc) || commaLikes.contains(lc))
            } else {
                needPause = true
            }

            if needPause {
                let comma = isCJKChar(lastScalar) ? "，" : ","
                out += comma
            }
            out += "\n" + lines[idx]
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Language & counting helpers (cached)
    private func dominantLanguageCached(_ text: String) -> String {
        let key = text as NSString
        if let v = langCache.object(forKey: key) { return v as String }
        let r = NLLanguageRecognizer()
        r.processString(text)
        let lang = (r.dominantLanguage?.rawValue) ?? "und"
        langCache.setObject(lang as NSString, forKey: key)
        return lang
    }

    private func isWordLanguage(_ lang: String) -> Bool {
        // Treat ja/ko/zh as non-word-based; others as word-based
        return !["ja","ko","zh-Hans","zh-Hant","zh"].contains(lang)
    }

    private func wordCountCached(_ text: String) -> Int {
        let key = text as NSString
        if let v = wordCountCache.object(forKey: key) { return v.intValue }
        let t = NLTokenizer(unit: .word)
        t.string = text
        var c = 0
        t.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in c += 1; return true }
        wordCountCache.setObject(NSNumber(value: c), forKey: key)
        return c
    }

    private func countFor(_ text: String, lang: String) -> Int {
        isWordLanguage(lang) ? wordCountCached(text) : text.count
    }

    private func estSeconds(_ text: String, lang: String, enWPS: Double, zhCPS: Double) -> Double {
        if isWordLanguage(lang) {
            return Double(wordCountCached(text)) / enWPS
        } else {
            return Double(text.count) / zhCPS
        }
    }

    private func hardMax(for lang: String, maxWordLen: Int, maxCJKLen: Int) -> Int {
        isWordLanguage(lang) ? maxWordLen : maxCJKLen
    }

    private func ensureTerminalPunctuation(_ text: String, lang: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.unicodeScalars.last else { return trimmed }
        let lastCh = Character(last)
        let terminal: Set<Character> = ["。","！","？",".","!","?","…","；",";","．"]
        if terminal.contains(lastCh) { return trimmed }
        // 如果是逗号/冒号/顿号结尾，也补一个终止符
        let commaLike: Set<Character> = ["，",",","、",":","：","；",";"]
        if commaLike.contains(lastCh) {
            return trimmed + (isWordLanguage(lang) ? "." : "。")
        }
        // 默认补终止符
        return trimmed + (isWordLanguage(lang) ? "." : "。")
    }

    private func isCJKChar(_ scalarOpt: UnicodeScalar?) -> Bool {
        guard let s = scalarOpt else { return false }
        switch s.value {
        case 0x4E00...0x9FFF, // CJK Unified Ideographs
             0x3400...0x4DBF, // CJK Extension A
             0x20000...0x2A6DF, // Extension B
             0x2A700...0x2B73F, // Extension C
             0x2B740...0x2B81F, // Extension D
             0x2B820...0x2CEAF, // Extension E
             0xF900...0xFAFF: // Compatibility Ideographs
            return true
        default:
            return false
        }
    }

    // 句子过长时的分割：先按逗号/分号/冒号/顿号等，再按词边界强切
    private func splitOverlongSentence(_ sentence: String,
                                       lang: String,
                                       maxLen: Int,
                                       targetMinSec: Double,
                                       targetMaxSec: Double,
                                       enWPS: Double,
                                       zhCPS: Double) -> [String] {
        // 1) 优先按较弱停顿标点切分
        let midPunctPattern = #"[,，、;；:：]"#
        var parts = sentence.split(usingRegex: midPunctPattern)
        if parts.isEmpty { parts = [sentence] }

        // 2) 合并/再切，确保每段不超 maxLen，且大致不超过 10s
        var reduced: [String] = []
        var buffer = ""

        func secs(_ s: String, _ l: String) -> Double {
            isWordLanguage(l) ? Double(wordCountCached(s)) / enWPS : Double(s.count) / zhCPS
        }

        for p in parts {
            let candidate = buffer.isEmpty ? p : (buffer + " " + p)
            let l = dominantLanguageCached(candidate)
            let c = countFor(candidate, lang: l)
            if c <= maxLen && secs(candidate, l) <= max(targetMaxSec * 1.15, targetMaxSec) {
                buffer = candidate
            } else {
                if !buffer.isEmpty { reduced.append(buffer) }
                buffer = p
            }
        }
        if !buffer.isEmpty { reduced.append(buffer) }

        // 3) 对仍然超长/超时的片段，用词边界强切
        var finalPieces: [String] = []
        for piece in reduced {
            let l = dominantLanguageCached(piece)
            let needForce =
                (!isWordLanguage(l) && piece.count > maxLen) ||
                (isWordLanguage(l) && wordCountCached(piece) > maxLen) ||
                secs(piece, l) > targetMaxSec

            if needForce {
                finalPieces.append(contentsOf:
                    forceSplitByWordBoundary(piece, lang: l, maxLen: maxLen)
                )
            } else {
                finalPieces.append(piece)
            }
        }
        return finalPieces
    }

    /// 使用 Apple 内置的 NLTokenizer(.word) 在词边界上强制切分，避免把“你好”切成“你，好”
    private func forceSplitByWordBoundary(_ text: String, lang: String, maxLen: Int) -> [String] {
        var pieces: [String] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var current = ""
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range])
            let candidate = current.isEmpty ? token : (current + (needsSpaceBetween(current, token) ? " " : "") + token)

            let currentLen: Int = isWordLanguage(lang) ? wordCountCached(candidate) : candidate.count
            if currentLen > maxLen {
                if !current.isEmpty { pieces.append(current) }
                current = token
            } else {
                current = candidate
            }
            return true
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    private func needsSpaceBetween(_ a: String, _ b: String) -> Bool {
        // CJK 与 CJK 不加空格；字母/数字与字母/数字之间加空格
        let aLast = a.unicodeScalars.last
        let bFirst = b.unicodeScalars.first
        let aCJK = isCJKChar(aLast)
        let bCJK = isCJKChar(bFirst)
        if aCJK || bCJK { return false }
        return true
    }
}

// MARK: - Array Safe Subscript
private extension Array {
    subscript(safe idx: Int) -> Element? {
        (indices.contains(idx) ? self[idx] : nil)
    }
}

// MARK: - String helpers
private extension String {
    /// Split by regex separators and keep content pieces (separators dropped).
    func split(usingRegex pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [self] }
        let ns = self as NSString
        var last = 0
        var parts: [String] = []
        for m in regex.matches(in: self, options: [], range: NSRange(location: 0, length: ns.length)) {
            let r = NSRange(location: last, length: m.range.location - last)
            if r.length > 0 {
                let sub = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sub.isEmpty { parts.append(sub) }
            }
            last = m.range.location + m.range.length
        }
        let tail = NSRange(location: last, length: ns.length - last)
        if tail.length > 0 {
            let sub = ns.substring(with: tail).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sub.isEmpty { parts.append(sub) }
        }
        return parts
    }
}
