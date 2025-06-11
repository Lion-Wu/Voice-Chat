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

    // MARK: - 对外状态
    @Published var isShowingAudioPlayer = false
    @Published var isAudioPlaying      = false
    @Published var currentTime: TimeInterval = 0
    @Published var isLoading  = false
    @Published var isBuffering = false
    @Published var errorMessage: String? = nil

    // MARK: - 播放器 & 计时器
    private var audioPlayer: AVAudioPlayer?
    private var nextAudioPlayer: AVAudioPlayer?
    private var audioTimer: Timer?

    // MARK: - 分段缓存
    private var textSegments:   [String]       = []
    private var audioChunks:    [Data?]        = [] // 每段音频数据或 nil
    private var chunkDurations: [TimeInterval] = [] // 每段时长
    private var totalDuration:  TimeInterval   = 0

    private var currentChunkIndex:   Int = 0 // 下一段请求索引
    private var currentPlayingIndex: Int = 0 // 当前播放段索引

    private var dataTasks: [URLSessionDataTask] = []

    // MARK: - Seek 状态
    private var seekTime: TimeInterval?
    private var isSeeking = false

    // MARK: - 配置
    private let settingsManager = SettingsManager.shared
    var mediaType: String = "wav"

    // MARK: - 辅助：构造 TTS URL
    private func constructTTSURL() -> URL? {
        let addr = settingsManager.serverSettings.serverAddress
        return URL(string: "\(addr)/tts")
    }

    // MARK: - 辅助：时间 ↔️ 段索引
    private func findSegmentIndex(for time: TimeInterval) -> Int {
        var cum: TimeInterval = 0
        for i in 0..<chunkDurations.count {
            let dur = chunkDurations[i]
            if dur == 0 { return i }
            if time < cum + dur { return i }
            cum += dur
        }
        return max(0, chunkDurations.count - 1)
    }
    private func startTime(forSegment idx: Int) -> TimeInterval {
        guard idx > 0 else { return 0 }
        return chunkDurations[0..<idx].reduce(0, +)
    }

    private func allChunksLoaded() -> Bool {
        !audioChunks.contains(where: { $0 == nil })
    }
    private func playbackFinished() -> Bool {
        allChunksLoaded() && currentTime >= totalDuration - 0.05
    }

    // MARK: - ⓵ 开始处理文本
    func startProcessing(text: String) {
        resetPlayer()
        isShowingAudioPlayer = true
        isLoading            = true
        isAudioPlaying       = true
        currentTime          = 0

        let v = settingsManager.voiceSettings
        textSegments = v.enableStreaming
            ? splitTextIntoMeaningfulSegments(text)
            : [text]

        let n = textSegments.count
        audioChunks    = Array(repeating: nil, count: n)
        chunkDurations = Array(repeating: 0,   count: n)
        totalDuration  = 0

        currentChunkIndex   = 0
        currentPlayingIndex = 0

        sendNextSegment()
    }

    // MARK: - ⓶ 顺序请求 TTS
    private func sendNextSegment() {
        guard currentChunkIndex < textSegments.count else { return }
        let idx = currentChunkIndex
        currentChunkIndex += 1
        sendTTSRequest(for: textSegments[idx], index: idx)
    }

    private func sendTTSRequest(for segmentText: String, index: Int) {
        guard let url = constructTTSURL() else {
            self.errorMessage = "Unable to construct TTS URL"
            return
        }

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
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let task = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self else { return }
            defer { DispatchQueue.main.async { self.sendNextSegment() } }

            if let err = error {
                DispatchQueue.main.async { self.errorMessage = err.localizedDescription }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { self.errorMessage = "No data received" }
                return
            }

            DispatchQueue.main.async {
                if index < self.audioChunks.count {
                    self.audioChunks[index] = data
                    if let p = try? AVAudioPlayer(data: data) {
                        self.chunkDurations[index] = p.duration
                        self.totalDuration = self.chunkDurations.reduce(0, +)
                    }
                }

                if index == 0 || index == self.currentPlayingIndex {
                    self.isLoading = false
                    self.playAudioChunk(at: index,
                                        fromTime: self.seekTime,
                                        shouldPlay: self.isAudioPlaying)
                    self.seekTime = nil
                }

                if self.isBuffering && index == self.currentPlayingIndex {
                    self.playAudioChunk(at: index,
                                        fromTime: self.seekTime,
                                        shouldPlay: self.isAudioPlaying)
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

    // MARK: - ⓷ 播放 & 预载
    private func prepareNextAudioChunk(at index: Int) {
        guard let chunkOpt = audioChunks[safe: index],
              let data     = chunkOpt else { return }
        if let p = try? AVAudioPlayer(data: data) {
            p.delegate = self
            p.prepareToPlay()
            nextAudioPlayer = p
        }
    }

    @discardableResult
    private func playAudioChunk(at index: Int,
                                fromTime t: TimeInterval? = nil,
                                shouldPlay: Bool = true) -> Bool
    {
        guard let chunkOpt = audioChunks[safe: index],
              let data     = chunkOpt else {
            isBuffering = true
            stopAudioTimer()
            return false
        }

        do {
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            p.prepareToPlay()
            audioPlayer = p

            let segStart = startTime(forSegment: index)
            let local    = max(0, min((t ?? 0) - segStart, p.duration))
            p.currentTime = local

            if shouldPlay {
                p.play()
                startAudioTimer()
            } else {
                stopAudioTimer()
            }

            isBuffering = false
            isSeeking   = false
            currentPlayingIndex = index

            prepareNextAudioChunk(at: index + 1)
            return true
        } catch {
            self.errorMessage = "Failed to start audio playback: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - ⓸ 播放/暂停
    func togglePlayback() {
        if !isAudioPlaying && playbackFinished() {
            currentPlayingIndex = 0
            currentTime         = 0
        }

        if !isAudioPlaying {
            isAudioPlaying = true
            if let chunkOpt = audioChunks[safe: currentPlayingIndex],
               let _        = chunkOpt {
                playAudioChunk(at: currentPlayingIndex,
                               fromTime: currentTime,
                               shouldPlay: true)
            } else {
                isBuffering = true
            }
        } else {
            isAudioPlaying = false
            audioPlayer?.pause()
            stopAudioTimer()
            isBuffering = false
        }
    }

    // MARK: - ⓹ 快进/后退
    func forward15Seconds()  { seek(to: currentTime + 15, shouldPlay: isAudioPlaying) }
    func backward15Seconds() { seek(to: currentTime - 15, shouldPlay: isAudioPlaying) }

    // MARK: - ⓺ Seek
    func seek(to time: TimeInterval, shouldPlay: Bool = false) {
        guard totalDuration > 0 else { return }
        let newT = max(0, min(time, totalDuration))
        currentTime = newT

        let target = findSegmentIndex(for: newT)
        if target != currentPlayingIndex {
            audioPlayer?.stop()
            audioPlayer = nil
            currentPlayingIndex = target
        }

        if let chunkOpt = audioChunks[safe: target],
           let _        = chunkOpt {
            playAudioChunk(at: target,
                           fromTime: newT,
                           shouldPlay: shouldPlay)
        } else {
            isBuffering = shouldPlay
            isSeeking   = true
            seekTime    = newT
            stopAudioTimer()
        }
    }

    // MARK: - ⓻ AVAudioPlayerDelegate
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            currentPlayingIndex += 1

            if currentPlayingIndex >= audioChunks.count {
                currentPlayingIndex = audioChunks.count - 1
                currentTime         = totalDuration
                isAudioPlaying      = false
                stopAudioTimer()
                return
            }

            if let next = nextAudioPlayer {
                audioPlayer = next
                nextAudioPlayer = nil
                audioPlayer?.delegate = self
                if isAudioPlaying {
                    audioPlayer?.play()
                    startAudioTimer()
                }
                prepareNextAudioChunk(at: currentPlayingIndex + 1)
            } else {
                if let chunkOpt = audioChunks[safe: currentPlayingIndex],
                   let _        = chunkOpt {
                    playAudioChunk(at: currentPlayingIndex,
                                   fromTime: startTime(forSegment: currentPlayingIndex),
                                   shouldPlay: isAudioPlaying)
                } else {
                    isBuffering = isAudioPlaying
                    stopAudioTimer()
                }
            }
        }
    }

    // MARK: - ⓼ 计时器
    private func startAudioTimer() {
        stopAudioTimer()
        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      let p = self.audioPlayer,
                      !self.isBuffering else { return }
                let segStart = self.startTime(forSegment: self.currentPlayingIndex)
                self.currentTime = segStart + p.currentTime
            }
        }
        if let timer = audioTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    private func stopAudioTimer() {
        audioTimer?.invalidate()
        audioTimer = nil
    }

    // MARK: - ⓽ 关闭 / 重置
    func closeAudioPlayer() {
        resetPlayer()
        isAudioPlaying       = false
        isShowingAudioPlayer = false
        isLoading            = false
    }

    private func resetPlayer() {
        dataTasks.forEach { $0.cancel() }
        dataTasks.removeAll()

        audioPlayer?.stop()
        audioPlayer = nil
        nextAudioPlayer?.stop()
        nextAudioPlayer = nil
        stopAudioTimer()

        textSegments.removeAll()
        audioChunks.removeAll()
        chunkDurations.removeAll()
        totalDuration = 0

        currentChunkIndex   = 0
        currentPlayingIndex = 0
        currentTime         = 0
        isBuffering         = false
        isSeeking           = false
        seekTime            = nil
        errorMessage        = nil
    }

    // MARK: - ⓾ 文本拆分逻辑 (完整实现)
    private func splitTextIntoMeaningfulSegments(_ text: String,
                                                 minSize: Int = 10,
                                                 maxSize: Int = 100) -> [String] {
        let modified = text
            .replacingOccurrences(of: #"\.\n"#, with: ". ")
            .replacingOccurrences(of: #"。\n"#,  with: "")
            .replacingOccurrences(of: "\n",      with: " ")

        var segs: [String] = []
        var current = ""
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = modified
        var found = false

        tokenizer.enumerateTokens(in: modified.startIndex..<modified.endIndex) { range, _ in
            found = true
            let sentence = String(modified[range])
            let lang = detectLanguage(for: sentence)

            if getCount(for: current + " " + sentence, language: lang) > maxSize {
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
                current += " " + sentence
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

        segs.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return segs
    }

    private func detectLanguage(for text: String) -> String {
        let r = NLLanguageRecognizer(); r.processString(text)
        return r.dominantLanguage?.rawValue ?? "unknown"
    }

    private func languageIsWordBased(_ lang: String) -> Bool {
        ["en","fr","de","es","it","pt","ru","ja","ko"].contains(lang)
    }

    private func wordCount(in text: String) -> Int {
        let t = NLTokenizer(unit: .word); t.string = text
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
                    if getCount(for: buf + " " + part, language: language) <= maxSize {
                        buf += " " + part
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
            buf += " " + conj
            last = r.location + r.length
        }

        let remRange = NSRange(location: last, length: ns.length - last)
        if remRange.length > 0 {
            let rem = ns.substring(with: remRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !rem.isEmpty {
                if getCount(for: buf + " " + rem, language: language) <= maxSize {
                    buf += " " + rem
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
        return segments
    }
}

// MARK: - Array 安全下标
private extension Array {
    subscript(safe idx: Int) -> Element? {
        indices.contains(idx) ? self[idx] : nil
    }
}
