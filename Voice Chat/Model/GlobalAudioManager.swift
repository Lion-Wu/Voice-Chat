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
    
    // MARK: - 对外公布的状态
    @Published var isShowingAudioPlayer = false
    
    /**
     isAudioPlaying 表示“用户想播放”，不代表播放器此刻必然在发声。
     - 如果 isAudioPlaying = true，但还没音频数据到，就会进入 buffering。
     - 如果 isAudioPlaying = false，则一定不发声、也不再 buffering。
     */
    @Published var isAudioPlaying = false
    
    /// currentTime: 播放进度（秒）
    @Published var currentTime: TimeInterval = 0
    
    /// isLoading: 是否在全局加载（例如第一段音频时）
    @Published var isLoading = false
    
    /// isBuffering: 是否在缓冲（= 用户想播 + 目标分片数据尚未到）
    @Published var isBuffering = false
    
    /// 出错信息
    @Published var errorMessage: String? = nil

    // MARK: - 播放器/计时器
    private var audioPlayer: AVAudioPlayer?
    private var audioTimer: Timer?

    // MARK: - 分段逻辑
    private var textSegments: [String] = []         // 切分后的文本段
    private var audioChunks: [Data?] = []           // 每段音频 (Data?)
    private var chunkDurations: [TimeInterval] = [] // 每段音频时长
    private var chunkStartTimes: [TimeInterval] = []// 每段起始时间（累加）
    private var totalDuration: TimeInterval = 0     // 所有已知段的总长

    /**
     currentChunkIndex: 下一个要请求 TTS 的文本段下标
     currentPlayingIndex: 当前播放器正在播哪个段
     */
    private var currentChunkIndex: Int = 0
    private var currentPlayingIndex: Int = 0

    /// 并发请求数和最大并发
    private var requestsInFlight: Int = 0
    private let maxRequestsInFlight = 2

    /// 正在执行的网络请求
    private var dataTasks: [URLSessionDataTask] = []

    /// 下一个预载的播放器
    private var nextAudioPlayer: AVAudioPlayer?

    // MARK: - Seek / 状态
    /// 用户刚刚 seek 到的目标时间，等待对应音频片段到达时恢复
    private var seekTime: TimeInterval?
    /// 标记正在因为 seek 而产生的缓冲
    private var isSeeking: Bool = false

    // MARK: - 配置
    private let settingsManager = SettingsManager.shared
    var mediaType: String = "wav"

    // MARK: - 1. startProcessing
    func startProcessing(text: String) {
        resetPlayer()
        isShowingAudioPlayer = true
        isLoading = true   // 首次请求音频，显示“加载中”
        currentTime = 0
        totalDuration = 0
        errorMessage = nil

        // 文本分段
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

        currentChunkIndex = 0
        currentPlayingIndex = 0
        requestsInFlight = 0

        // 用户意图：立即播放
        isAudioPlaying = true

        // 这里依然保留了「同时发送两个请求」的做法，以便并发加速。
        // 但是我们保证：只要第 0 段先回来了，就立马开始播放。
        sendNextSegment() // 请求第 0 段
        if segmentCount > 1 {
            sendNextSegment() // 请求第 1 段
        }
    }

    // MARK: - 2. 并发 TTS 请求
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

        // 构造参数
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
                // 请求结束后 -1，并尝试请求下一段
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

            // 音频数据到达
            DispatchQueue.main.async {
                if index >= self.audioChunks.count { return }
                self.audioChunks[index] = data

                // 计算此段时长，更新 totalDuration
                if let player = try? AVAudioPlayer(data: data) {
                    let segDuration = player.duration
                    self.chunkDurations[index] = segDuration
                    self.calculateChunkStartTimesAndTotalDuration()
                }

                // =============================
                // 这里是关键逻辑修复：
                // ——只要第 0 段 (index == 0) 到了，就立马关闭“加载中”并尝试播放。
                // ——或者正好到了 currentPlayingIndex 这一段，也要去尝试播放。
                // =============================
                if index == 0 {
                    // 首段到 -> 即便并发还在继续，这里也先不再是 loading 了
                    self.isLoading = false

                    // 如果用户此时确实想播放，就立即播
                    if self.isAudioPlaying {
                        self.playAudioChunk(
                            at: 0,
                            fromTime: self.seekTime,
                            shouldPlay: true
                        )
                        self.seekTime = nil
                    }
                }
                else if index == self.currentPlayingIndex {
                    // 如果正好是当前要播的分片，也把 isLoading 去掉
                    self.isLoading = false

                    // 如果用户此时确实想播放
                    if self.isAudioPlaying {
                        self.playAudioChunk(
                            at: index,
                            fromTime: self.seekTime,
                            shouldPlay: true
                        )
                        self.seekTime = nil
                    }
                }

                // 如果是当前分片的下一段 -> 预加载
                if index == self.currentPlayingIndex + 1 {
                    self.prepareNextAudioChunk(at: index)
                }

                // 如果当前正在缓冲，且到达的正好是 currentPlayingIndex
                // 也要恢复播放（保证快进后能自动恢复）
                if self.isBuffering,
                   index == self.currentPlayingIndex,
                   self.isAudioPlaying
                {
                    self.playAudioChunk(
                        at: self.currentPlayingIndex,
                        fromTime: self.seekTime,
                        shouldPlay: true
                    )
                    self.seekTime = nil
                }
            }
        }
        task.resume()
        dataTasks.append(task)
    }

    // MARK: - 计算 chunkStartTimes & totalDuration
    private func calculateChunkStartTimesAndTotalDuration() {
        var cumulative: TimeInterval = 0
        for i in 0..<chunkDurations.count {
            let dur = chunkDurations[safe: i] ?? 0
            chunkStartTimes[i] = cumulative
            cumulative += dur
        }
        totalDuration = cumulative
    }

    // MARK: - 预载下一个分片
    private func prepareNextAudioChunk(at index: Int) {
        guard let chunkOpt = audioChunks[safe: index], let data = chunkOpt else { return }
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            nextAudioPlayer = player
        } catch {
            print("prepareNextAudioChunk error: \(error)")
        }
    }

    // MARK: - 播放指定分片
    @discardableResult
    private func playAudioChunk(at index: Int,
                                fromTime time: TimeInterval? = nil,
                                shouldPlay: Bool = true) -> Bool
    {
        // 若该分片越界 -> 播不动
        guard audioChunks.indices.contains(index) else { return false }

        // 若该分片数据为空 -> 需要缓冲
        guard let data = audioChunks[index] else {
            isBuffering = true
            stopAudioTimer()
            return false
        }

        // 构造播放器
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()

            self.audioPlayer = player

            // 在该分片内的起始位置
            let startTime: TimeInterval = {
                guard let t = time else { return 0 }
                let rel = t - (chunkStartTimes[safe: index] ?? 0)
                return max(0, min(rel, player.duration))
            }()
            player.currentTime = startTime

            if shouldPlay {
                player.play()
                startAudioTimer()
            }

            // 数据已到 -> 不再缓冲
            isBuffering = false
            isSeeking = false

            // 如果下一个分片已经到 -> 先预载
            let nextIndex = index + 1
            if let nextData = audioChunks[safe: nextIndex], nextData != nil {
                prepareNextAudioChunk(at: nextIndex)
            }

            currentPlayingIndex = index
            return true
        } catch {
            self.errorMessage = "Failed to start audio playback: \(error.localizedDescription)"
            print(errorMessage ?? "")
            return false
        }
    }

    // MARK: - 播放 / 暂停
    func togglePlayback() {
        // === 修复第二个问题点（当播放完最后一段后，再次点击“播放”，要从头开始） ===
        // 如果已经播完了（currentTime 已经到 totalDuration 或超过），
        // 则重置到起点(0段、0秒)。
        if !isAudioPlaying && currentTime >= totalDuration {
            currentPlayingIndex = 0
            currentTime = 0
        }
        
        // 若当前为“暂停” -> 切换成“想播放”
        if !isAudioPlaying {
            isAudioPlaying = true

            // 如果当前分片有数据，直接播放
            if let _ = audioChunks[safe: currentPlayingIndex] {
                playAudioChunk(
                    at: currentPlayingIndex,
                    fromTime: currentTime,
                    shouldPlay: true
                )
            } else {
                // 否则需要缓冲
                isBuffering = true
            }
        } else {
            // 若当前为“想播放” -> 切换成“暂停”
            isAudioPlaying = false
            audioPlayer?.pause()
            stopAudioTimer()
            // 不再需要缓冲
            isBuffering = false
        }
    }

    // MARK: - 快进 / 后退 15 秒
    func forward15Seconds() {
        seek(to: currentTime + 15, shouldPlay: isAudioPlaying)
    }

    func backward15Seconds() {
        seek(to: currentTime - 15, shouldPlay: isAudioPlaying)
    }

    // MARK: - seek
    func seek(to time: TimeInterval, shouldPlay: Bool = false) {
        guard totalDuration > 0 else { return }

        let newTime = max(0, min(time, totalDuration))
        currentTime = newTime

        // 找到对应分片下标
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

        // 如果切换了分片，就停止当前的播放
        if targetChunkIndex != currentPlayingIndex {
            audioPlayer?.stop()
            audioPlayer = nil
            currentPlayingIndex = targetChunkIndex
        }

        // 如果分片已经下载完，则直接播放/暂停
        if let _ = audioChunks[safe: currentPlayingIndex] {
            playAudioChunk(
                at: currentPlayingIndex,
                fromTime: newTime,
                shouldPlay: shouldPlay
            )
        } else {
            // 没下载 => 缓冲
            isBuffering = shouldPlay
            isSeeking = true
            seekTime = newTime
            stopAudioTimer()
        }

        // 如果用户 seek 到了 totalDuration 且已经是最后一段，也可能直接结束
        if newTime >= totalDuration,
           currentPlayingIndex >= audioChunks.count - 1,
           audioChunks[audioChunks.count - 1] != nil
        {
            isAudioPlaying = false
            audioPlayer?.stop()
            stopAudioTimer()
            currentTime = totalDuration
        }
    }

    // MARK: - 关闭
    func closeAudioPlayer() {
        resetPlayer()
        isAudioPlaying = false
        isShowingAudioPlayer = false
        isLoading = false
    }

    // MARK: - 重置
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
        chunkStartTimes.removeAll()

        currentChunkIndex = 0
        currentPlayingIndex = 0
        requestsInFlight = 0
        totalDuration = 0
        currentTime = 0

        isBuffering = false
        isSeeking = false
        seekTime = nil
        errorMessage = nil
    }

    // MARK: - 计时器
    private func startAudioTimer() {
        stopAudioTimer()
        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 若在缓冲，就不更新 currentTime
            if self.isBuffering { return }

            if let player = self.audioPlayer {
                let chunkStartTime = self.chunkStartTimes[safe: self.currentPlayingIndex] ?? 0
                let localTime = player.currentTime

                // 更新 currentTime
                self.currentTime = chunkStartTime + localTime

                // 如果已经播到 totalDuration，就真正结束
                if self.currentTime >= self.totalDuration {
                    // 如果已经加载完所有分片，则停止
                    if self.allChunksLoaded() {
                        self.currentTime = self.totalDuration
                        self.isAudioPlaying = false
                        player.stop()
                        self.stopAudioTimer()
                    } else {
                        // 如果并未全部加载完，就进入缓冲等待新的音频
                        self.isBuffering = self.isAudioPlaying
                        player.pause()
                    }
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

    private func allChunksLoaded() -> Bool {
        // 若还有某段是 nil，就表示没下载完
        return !audioChunks.contains(where: { $0 == nil })
    }

    // MARK: - 构造 TTS URL
    private func constructTTSURL() -> URL? {
        let serverSettings = settingsManager.serverSettings
        let urlString = "\(serverSettings.serverAddress)/tts"
        return URL(string: urlString)
    }

    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        currentPlayingIndex += 1

        // 若已经是最后一个分片，则说明真正播完
        if currentPlayingIndex >= audioChunks.count {
            currentPlayingIndex = audioChunks.count - 1
            currentTime = totalDuration
            isAudioPlaying = false
            stopAudioTimer()
            return
        }

        // 如果 nextAudioPlayer 已经准备好了，就直接切过去
        if let next = nextAudioPlayer {
            audioPlayer = next
            nextAudioPlayer = nil
            audioPlayer?.delegate = self

            if isAudioPlaying {
                audioPlayer?.play()
                startAudioTimer()
            }

            // 再预载下一个
            let nextIndex = currentPlayingIndex + 1
            if nextIndex < audioChunks.count,
               audioChunks[nextIndex] != nil
            {
                prepareNextAudioChunk(at: nextIndex)
            }
        } else {
            // 没有预载好的播放器
            if let _ = audioChunks[safe: currentPlayingIndex] {
                // 该分片数据已到 => 立即播
                if isAudioPlaying {
                    playAudioChunk(
                        at: currentPlayingIndex,
                        fromTime: chunkStartTimes[currentPlayingIndex],
                        shouldPlay: true
                    )
                }
            } else {
                // 数据没到 => 进入缓冲
                if isAudioPlaying {
                    isBuffering = true
                }
                stopAudioTimer()
            }
        }
    }

    // MARK: - 文本拆分逻辑（和之前一样）
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
                    let subSegs = splitSentence(sentence, language: language, minSize: minSize, maxSize: maxSize)
                    segments.append(contentsOf: subSegs)
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
                let subSegs = splitSentence(modifiedText, language: language, minSize: minSize, maxSize: maxSize)
                segments.append(contentsOf: subSegs)
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
        tagger.enumerateTags(in: NSRange(location: 0, length: nsSentence.length),
                             unit: .word,
                             scheme: .lexicalClass)
        { tag, tokenRange, _ in
            if tag == .conjunction {
                conjunctionRanges.append(tokenRange)
            }
        }

        if conjunctionRanges.isEmpty { return nil }

        var splitSegments: [String] = []
        var lastSplitIndex = 0
        var buffer = ""

        for tokenRange in conjunctionRanges {
            let splitRange = NSRange(location: lastSplitIndex,
                                     length: tokenRange.location - lastSplitIndex)
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
                        if let subSplit = splitSentenceAtConjunctions(segment, language: language, minSize: minSize, maxSize: maxSize) {
                            splitSegments.append(contentsOf: subSplit)
                        } else {
                            let further = splitSentence(segment, language: language, minSize: minSize, maxSize: maxSize)
                            splitSegments.append(contentsOf: further)
                        }
                    }
                }
            }
            let conj = nsSentence.substring(with: tokenRange).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer += " " + conj
            lastSplitIndex = tokenRange.location + tokenRange.length
        }

        // 收尾
        let remainingRange = NSRange(location: lastSplitIndex,
                                     length: nsSentence.length - lastSplitIndex)
        if remainingRange.length > 0 {
            let remainingSegment = nsSentence.substring(with: remainingRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainingSegment.isEmpty {
                if getCount(for: buffer + " " + remainingSegment, language: language) <= maxSize {
                    buffer += " " + remainingSegment
                } else {
                    if !buffer.isEmpty {
                        splitSegments.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    splitSegments.append(remainingSegment)
                    buffer = ""
                }
            }
        }

        if !buffer.isEmpty {
            splitSegments.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var final: [String] = []
        for seg in splitSegments {
            let segCount = getCount(for: seg, language: language)
            if segCount > maxSize {
                let further = splitSentence(seg, language: language, minSize: minSize, maxSize: maxSize)
                final.append(contentsOf: further)
            } else if segCount >= minSize {
                final.append(seg)
            } else {
                if let last = final.popLast() {
                    final.append(last + " " + seg)
                } else {
                    final.append(seg)
                }
            }
        }
        return final
    }

    private func splitSentence(_ sentence: String, language: String, minSize: Int, maxSize: Int) -> [String] {
        var splitSegments: [String] = []
        if languageIsWordBased(language) {
            let words = sentence.split { $0.isWhitespace }
            var current = ""
            for w in words {
                let wordStr = String(w)
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
            // 非词汇型语言，按字符数分
            var current = ""
            for c in sentence {
                let charStr = String(c)
                let pot = current + charStr
                if characterCount(in: pot) > maxSize {
                    if !current.isEmpty {
                        splitSegments.append(current)
                        current = charStr
                    } else {
                        splitSegments.append(charStr)
                        current = ""
                    }
                } else {
                    current = pot
                }
            }
            if !current.isEmpty {
                splitSegments.append(current)
            }
        }
        return splitSegments
    }
}

// 安全下标
private extension Array {
    subscript(safe i: Int) -> Element? {
        return indices.contains(i) ? self[i] : nil
    }
}
