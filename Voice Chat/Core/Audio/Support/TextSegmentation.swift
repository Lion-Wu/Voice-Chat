//
//  TextSegmentation.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation
import NaturalLanguage

enum SpeechTextSegmentation {
    static let wordsPerSecond = 2.8
    static let cjkCharactersPerSecond = 4.5
    static let approximateCharactersPerWord = 5.5

    static let softPunctuation: Set<Character> = Set(",，、:：;；")

    private struct DurationCounts {
        var cjkCharacters = 0
        var nonCJKWords = 0
        var nonCJKAlphanumerics = 0
    }

    struct DurationIndex {
        private let prefixCounts: [String.Index: DurationCounts]

        init(text: String) {
            let tokenizer = SpeechTextSegmentation.tokenizer(unit: .word, for: text)
            var nonCJKWordEnds: [String.Index: Int] = [:]
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                let tokenContainsNonCJKAlphanumeric = text[range].contains { character in
                    !SpeechTextSegmentation.isCJKCharacter(character) &&
                        character.unicodeScalars.contains {
                            CharacterSet.alphanumerics.contains($0)
                        }
                }
                if tokenContainsNonCJKAlphanumeric {
                    nonCJKWordEnds[range.upperBound, default: 0] += 1
                }
                return true
            }

            var counts = DurationCounts()
            var countsByIndex: [String.Index: DurationCounts] = [text.startIndex: counts]
            var index = text.startIndex
            while index < text.endIndex {
                let character = text[index]
                let nextIndex = text.index(after: index)
                if SpeechTextSegmentation.isCJKCharacter(character) {
                    counts.cjkCharacters += 1
                } else {
                    counts.nonCJKAlphanumerics += character.unicodeScalars.reduce(into: 0) {
                        count, scalar in
                        if CharacterSet.alphanumerics.contains(scalar) {
                            count += 1
                        }
                    }
                }
                counts.nonCJKWords += nonCJKWordEnds[nextIndex, default: 0]
                countsByIndex[nextIndex] = counts
                index = nextIndex
            }
            prefixCounts = countsByIndex
        }

        func estimatedSeconds(from start: String.Index, to end: String.Index) -> Double {
            guard let startCounts = prefixCounts[start],
                  let endCounts = prefixCounts[end] else {
                return 0
            }

            let cjkCount = max(0, endCounts.cjkCharacters - startCounts.cjkCharacters)
            let wordCount = max(0, endCounts.nonCJKWords - startCounts.nonCJKWords)
            let alphanumericCount = max(
                0,
                endCounts.nonCJKAlphanumerics - startCounts.nonCJKAlphanumerics
            )
            let approximateWordCount = Int(
                (Double(alphanumericCount) / approximateCharactersPerWord).rounded(.up)
            )
            let cjkSeconds = Double(cjkCount) / cjkCharactersPerSecond
            let wordSeconds = Double(max(wordCount, approximateWordCount)) / wordsPerSecond
            return cjkSeconds + wordSeconds
        }

        func containsCJK(from start: String.Index, to end: String.Index) -> Bool {
            guard let startCounts = prefixCounts[start],
                  let endCounts = prefixCounts[end] else {
                return false
            }
            return endCounts.cjkCharacters > startCounts.cjkCharacters
        }
    }

    static func estimatedSeconds(for text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let durationIndex = DurationIndex(text: trimmed)
        return durationIndex.estimatedSeconds(from: trimmed.startIndex, to: trimmed.endIndex)
    }

    static func punctuationBoundaries(in text: String, includeTerminal: Bool = true) -> [String.Index] {
        var boundaries = includeTerminal ? sentenceBoundaries(in: text) : []
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            guard softPunctuation.contains(character) || character.isNewline else {
                index = text.index(after: index)
                continue
            }

            let boundary = text.index(after: index)
            boundaries.append(boundary)
            index = boundary
        }
        return sortedUniqueBoundaries(boundaries)
    }

    static func terminalBoundaries(in text: String) -> [String.Index] {
        var boundaries = sentenceBoundaries(in: text)
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            guard character.isNewline || character == ";" || character == "；" else {
                index = text.index(after: index)
                continue
            }

            let boundary = text.index(after: index)
            boundaries.append(boundary)
            index = boundary
        }
        return sortedUniqueBoundaries(boundaries)
    }

    static func sentenceBoundaries(in text: String) -> [String.Index] {
        let sentenceTokenizer = tokenizer(unit: .sentence, for: text)
        var boundaries: [String.Index] = []
        var pendingBoundary: String.Index?

        sentenceTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            // NLTokenizer always returns the trailing buffered text as a sentence token,
            // even when that sentence is still streaming. Seeing the next sentence token
            // confirms the preceding boundary without second-guessing Apple's semantics.
            if let pendingBoundary, pendingBoundary > text.startIndex {
                boundaries.append(pendingBoundary)
            }
            pendingBoundary = boundaryBeforeTrailingWhitespace(range.upperBound, in: text)
            return true
        }

        if let pendingBoundary,
           pendingBoundary == text.endIndex,
           hasExplicitSentenceTerminator(before: pendingBoundary, in: text) {
            boundaries.append(pendingBoundary)
        }
        return boundaries
    }

    private static func boundaryBeforeTrailingWhitespace(
        _ boundary: String.Index,
        in text: String
    ) -> String.Index {
        var result = boundary
        while result > text.startIndex {
            let previous = text.index(before: result)
            guard text[previous].isWhitespace else { break }
            result = previous
        }
        return result
    }

    private static func hasExplicitSentenceTerminator(
        before boundary: String.Index,
        in text: String
    ) -> Bool {
        var cursor = boundary
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            let character = text[previous]
            if character.unicodeScalars.allSatisfy({ scalar in
                scalar.properties.isQuotationMark ||
                    scalar.properties.generalCategory == .closePunctuation ||
                    scalar.properties.generalCategory == .finalPunctuation
            }) {
                cursor = previous
                continue
            }
            return character.unicodeScalars.contains {
                $0.properties.isTerminalPunctuation
            }
        }
        return false
    }

    static func wordBoundaries(in text: String, excludingEnd: Bool) -> [String.Index] {
        let tokenizer = tokenizer(unit: .word, for: text)
        var boundaries: [String.Index] = []

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if !excludingEnd || range.upperBound < text.endIndex {
                boundaries.append(range.upperBound)
            }
            return true
        }
        return boundaries
    }

    private static func tokenizer(unit: NLTokenUnit, for text: String) -> NLTokenizer {
        let tokenizer = NLTokenizer(unit: unit)
        tokenizer.string = text
        if let language = NLLanguageRecognizer.dominantLanguage(for: text) {
            tokenizer.setLanguage(language)
        }
        return tokenizer
    }

    private static func isCJKCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            if scalar.properties.isIdeographic { return true }
            switch scalar.value {
            case 0x3040...0x30FF, 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }

    private static func sortedUniqueBoundaries(
        _ boundaries: [String.Index]
    ) -> [String.Index] {
        var result: [String.Index] = []
        for boundary in boundaries.sorted() where result.last != boundary {
            result.append(boundary)
        }
        return result
    }
}

actor TextSegmentationWorker {
    static let shared = TextSegmentationWorker()

    private let minimumSeconds = 8.0
    private let preferredSeconds = 11.5
    private let maximumSeconds = 15.0

    func splitTextIntoMeaningfulSegments(_ rawText: String) -> [String] {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let durationIndex = SpeechTextSegmentation.DurationIndex(text: text)
        let sentenceBoundaries = SpeechTextSegmentation.sentenceBoundaries(in: text)
        let punctuationBoundaries = SpeechTextSegmentation.punctuationBoundaries(
            in: text,
            includeTerminal: false
        )
        let wordBoundaries = SpeechTextSegmentation.wordBoundaries(
            in: text,
            excludingEnd: true
        )
        var segments: [String] = []
        var segmentStart = text.startIndex

        while durationIndex.estimatedSeconds(from: segmentStart, to: text.endIndex) > maximumSeconds {
            guard let boundary = preferredBoundary(
                after: segmentStart,
                in: text,
                durationIndex: durationIndex,
                sentenceBoundaries: sentenceBoundaries,
                punctuationBoundaries: punctuationBoundaries,
                wordBoundaries: wordBoundaries
            ) else {
                break
            }
            let prefix = String(text[segmentStart..<boundary])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty else { break }
            segments.append(prefix)
            segmentStart = boundary
        }

        let tail = String(text[segmentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            segments.append(tail)
        }
        return segments
    }

    private func preferredBoundary(
        after segmentStart: String.Index,
        in text: String,
        durationIndex: SpeechTextSegmentation.DurationIndex,
        sentenceBoundaries: [String.Index],
        punctuationBoundaries: [String.Index],
        wordBoundaries: [String.Index]
    ) -> String.Index? {
        let sentence = bestBoundary(
            sentenceBoundaries,
            after: segmentStart,
            durationIndex: durationIndex,
            minimumDuration: minimumSeconds
        )
        if let sentence { return sentence }

        let punctuation = bestBoundary(
            punctuationBoundaries,
            after: segmentStart,
            durationIndex: durationIndex,
            minimumDuration: minimumSeconds
        )
        if let punctuation { return punctuation }

        let word = bestBoundary(
            wordBoundaries,
            after: segmentStart,
            durationIndex: durationIndex,
            minimumDuration: minimumSeconds
        )
        if let word { return word }

        guard durationIndex.containsCJK(from: segmentStart, to: text.endIndex) else {
            return nil
        }
        return bestCharacterBoundary(
            after: segmentStart,
            in: text,
            durationIndex: durationIndex
        )
    }

    private func bestBoundary(
        _ boundaries: [String.Index],
        after segmentStart: String.Index,
        durationIndex: SpeechTextSegmentation.DurationIndex,
        minimumDuration: Double
    ) -> String.Index? {
        var best: (index: String.Index, score: Double)?
        var boundaryIndex = firstBoundaryIndex(after: segmentStart, in: boundaries)

        while boundaryIndex < boundaries.count {
            let boundary = boundaries[boundaryIndex]
            let duration = durationIndex.estimatedSeconds(from: segmentStart, to: boundary)
            if duration > maximumSeconds { break }
            if duration >= minimumDuration {
                let score = abs(duration - preferredSeconds)
                if best == nil || score < best!.score {
                    best = (boundary, score)
                }
            }
            boundaryIndex += 1
        }
        return best?.index
    }

    private func firstBoundaryIndex(
        after index: String.Index,
        in boundaries: [String.Index]
    ) -> Int {
        var lowerBound = 0
        var upperBound = boundaries.count
        while lowerBound < upperBound {
            let midpoint = lowerBound + (upperBound - lowerBound) / 2
            if boundaries[midpoint] <= index {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }
        return lowerBound
    }

    private func bestCharacterBoundary(
        after segmentStart: String.Index,
        in text: String,
        durationIndex: SpeechTextSegmentation.DurationIndex
    ) -> String.Index? {
        var best: (index: String.Index, score: Double)?
        var index = text.index(after: segmentStart)

        while index < text.endIndex {
            let duration = durationIndex.estimatedSeconds(from: segmentStart, to: index)
            if duration > maximumSeconds { break }
            let score = abs(duration - preferredSeconds)
            if best == nil || score < best!.score {
                best = (index, score)
            }
            index = text.index(after: index)
        }
        return best?.index
    }

}
