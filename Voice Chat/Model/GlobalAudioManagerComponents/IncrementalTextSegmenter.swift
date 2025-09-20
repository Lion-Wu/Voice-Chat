//
//  IncrementalTextSegmenter.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation

/// 将“流式增量文本”组装为可朗读的完整片段：
/// - 忽略 <think>…</think> 内的内容；只输出正文部分；
/// - 以句末标点（中英文 . ! ? 。！？；…）或换行为切分点；
/// - 若迟迟无标点，按长度阈值强制切分（避免长时间憋段）。
struct IncrementalTextSegmenter {

    private var buffer: String = ""
    private var inThink: Bool = false

    // 阈值（经验值）：英文按单词数估，中文按字符数估
    private let maxCJKChars: Int = 80
    private let maxENWords: Int = 30

    // 句末标点
    private let terminalSet: Set<Character> = Set("。！？!?……;；.。")
    // 软断行（\n 也视作断点）
    private let newline: Character = "\n"

    mutating func reset() {
        buffer = ""
        inThink = false
    }

    /// 追加一段增量，返回可立即朗读的片段数组
    mutating func append(_ delta: String) -> [String] {
        guard !delta.isEmpty else { return [] }

        var produced: [String] = []
        var i = delta.startIndex

        while i < delta.endIndex {
            // 处理 think 标签的进入/退出
            if delta[i...].hasPrefix("<think>") {
                inThink = true
                i = delta.index(i, offsetBy: 7)
                continue
            }
            if delta[i...].hasPrefix("</think>") {
                inThink = false
                i = delta.index(i, offsetBy: 8)
                continue
            }

            // 非 think 内容才进入 buffer
            let ch = delta[i]
            if !inThink {
                buffer.append(ch)

                // 换行或句末标点 -> 直接切分
                if ch == newline || terminalSet.contains(ch) {
                    let seg = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !seg.isEmpty {
                        produced.append(seg)
                    }
                    buffer = ""
                } else {
                    // 无标点情况下的长度强切
                    if shouldForceSplit(buffer) {
                        let seg = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !seg.isEmpty {
                            produced.append(seg)
                        }
                        buffer = ""
                    }
                }
            }

            i = delta.index(after: i)
        }

        return produced
    }

    /// 流结束：把剩余未切分的尾巴吐出
    mutating func finalize() -> [String] {
        guard !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return [tail]
    }

    // MARK: - Helpers

    /// 简易的英文单词/中文字符计数强切逻辑
    private func shouldForceSplit(_ text: String) -> Bool {
        // 是否包含 CJK
        let hasCJK = text.unicodeScalars.contains { $0.properties.isIdeographic }
        if hasCJK {
            return text.count >= maxCJKChars
        } else {
            let words = text.split { $0.isWhitespace || $0.isNewline }
            return words.count >= maxENWords
        }
    }
}
