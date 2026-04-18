//
//  MarkdownMathPreprocessor.swift
//  Voice Chat
//

@preconcurrency import Foundation
import Markdown

struct MarkdownMathSegment: Sendable, Equatable {
    let placeholderIndex: Int
    let latex: String
    let source: String
    let displayMode: Bool
}

enum MarkdownMathPlaceholder {
    static let start = "\u{E000}"
    static let end = "\u{E001}"

    static func token(for index: Int) -> String {
        "\(start)\(index)\(end)"
    }

    static func runs(
        in text: String,
        segments: [MarkdownMathSegment]
    ) -> [MarkdownMathPreprocessor.Result.PlaceholderRun] {
        guard text.contains(start) else {
            return [.text(text)]
        }

        var runs: [MarkdownMathPreprocessor.Result.PlaceholderRun] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            guard let startIndex = text[cursor...].firstIndex(of: Character(start)) else {
                let tail = String(text[cursor...])
                if !tail.isEmpty {
                    runs.append(.text(tail))
                }
                break
            }

            if startIndex > cursor {
                runs.append(.text(String(text[cursor..<startIndex])))
            }

            let numberStart = text.index(after: startIndex)
            guard let endIndex = text[numberStart...].firstIndex(of: Character(end)) else {
                runs.append(.text(String(text[startIndex...])))
                break
            }

            let numberText = String(text[numberStart..<endIndex])
            guard let index = Int(numberText),
                  index >= 0,
                  index < segments.count
            else {
                runs.append(.text(String(text[startIndex...endIndex])))
                cursor = text.index(after: endIndex)
                continue
            }

            runs.append(.segment(segments[index]))
            cursor = text.index(after: endIndex)
        }

        return runs
    }
}

enum MarkdownMathPreprocessor {
    struct Result: Sendable, Equatable {
        enum PlaceholderRun: Sendable, Equatable {
            case text(String)
            case segment(MarkdownMathSegment)
        }

        let markdown: String
        let segments: [MarkdownMathSegment]

        func runs(in text: String) -> [PlaceholderRun] {
            MarkdownMathPlaceholder.runs(in: text, segments: segments)
        }

        func restoringOriginalMarkup(in text: String?) -> String? {
            guard let text else { return nil }
            guard text.contains(MarkdownMathPlaceholder.start) else { return text }

            let placeholderRuns = runs(in: text)
            var restored = ""
            var replacedSegment = false

            for run in placeholderRuns {
                switch run {
                case let .text(fragment):
                    restored.append(fragment)
                case let .segment(segment):
                    restored.append(segment.source)
                    replacedSegment = true
                }
            }

            return replacedSegment ? restored : text
        }
    }

    private static let potentialMathMarkers = [
        "$",
        "\\(",
        "\\)",
        "\\[",
        "\\]",
        "\\begin{",
        "\\end{"
    ]

    static func containsPotentialMathSyntax(_ markdown: String) -> Bool {
        potentialMathMarkers.contains { markdown.contains($0) }
    }

    static func containsPotentialMathSyntaxAcrossBoundary(prefix: String, suffix: String) -> Bool {
        guard !prefix.isEmpty, !suffix.isEmpty else { return false }
        for marker in potentialMathMarkers {
            guard marker.count > 1 else { continue }
            for splitIndex in 1..<marker.count {
                let markerPrefix = String(marker.prefix(splitIndex))
                let markerSuffix = String(marker.suffix(marker.count - splitIndex))
                if prefix.hasSuffix(markerPrefix), suffix.hasPrefix(markerSuffix) {
                    return true
                }
            }
        }
        return false
    }

    static func containsUnterminatedMathSyntax(_ markdown: String) -> Bool {
        guard containsPotentialMathSyntax(markdown) else { return false }

        var parser = Parser(source: markdown)
        return parser.containsUnterminatedMathSegments()
    }

    static func containsRenderableMath(_ markdown: String) -> Bool {
        !preprocess(markdown).segments.isEmpty
    }

    static func endsWithStandaloneDisplayMathParagraph(_ markdown: String) -> Bool {
        let result = preprocess(markdown)
        guard !result.segments.isEmpty else { return false }

        let document = Document(parsing: result.markdown)
        guard let lastBlock = document.child(at: document.childCount - 1) else { return false }
        let lastParagraph = trailingParagraph(in: lastBlock)
        guard let lastParagraph else { return false }

        let plain = plainTextFromMarkup(lastParagraph)
        let runs = result.runs(in: plain)
        guard runs.contains(where: {
            if case .segment = $0 { return true }
            return false
        }) else {
            return false
        }

        for run in runs {
            switch run {
            case let .text(text):
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continue
                }
                return false
            case let .segment(segment):
                guard segment.displayMode else { return false }
            }
        }

        return true
    }

    static func preprocess(_ markdown: String) -> Result {
        guard containsPotentialMathSyntax(markdown) else {
            return Result(markdown: markdown, segments: [])
        }

        if let cached = MarkdownMathPreprocessorCache.shared.result(for: markdown) {
            return cached
        }

        var parser = Parser(source: markdown)
        let result = parser.parse()
        MarkdownMathPreprocessorCache.shared.insert(result, for: markdown)
        return result
    }
}

private func trailingParagraph(in markup: Markup) -> Paragraph? {
    if let paragraph = markup as? Paragraph {
        return paragraph
    }

    guard markup.childCount > 0 else { return nil }
    guard let lastChild = markup.child(at: markup.childCount - 1) else { return nil }
    return trailingParagraph(in: lastChild)
}

private func plainTextFromMarkup(_ markup: Markup) -> String {
    if let text = markup as? Markdown.Text {
        return text.string
    } else if let custom = markup as? CustomInline {
        return custom.text
    } else if markup is SoftBreak {
        return " "
    } else if markup is LineBreak {
        return "\n"
    } else if let html = markup as? InlineHTML {
        return html.rawHTML
    } else if let inlineCode = markup as? InlineCode {
        return inlineCode.code
    } else if let symbolLink = markup as? SymbolLink {
        return symbolLink.destination ?? ""
    } else {
        var combined = ""
        for child in markup.children {
            combined += plainTextFromMarkup(child)
        }
        return combined
    }
}

private final class MarkdownMathPreprocessorCache: @unchecked Sendable {
    static let shared = MarkdownMathPreprocessorCache()

    private final class Entry: NSObject {
        let result: MarkdownMathPreprocessor.Result

        init(result: MarkdownMathPreprocessor.Result) {
            self.result = result
        }
    }

    private let cache = NSCache<NSString, Entry>()

    private init() {
        cache.countLimit = 48
        cache.totalCostLimit = 4 * 1024 * 1024
    }

    func result(for markdown: String) -> MarkdownMathPreprocessor.Result? {
        cache.object(forKey: markdown as NSString)?.result
    }

    func insert(_ result: MarkdownMathPreprocessor.Result, for markdown: String) {
        cache.setObject(
            Entry(result: result),
            forKey: markdown as NSString,
            cost: markdown.utf16.count
        )
    }
}

private struct MarkdownMathPreprocessorScanner {
    private let characters: [Character]
    private let characterStartUTF8Offsets: [Int]
    private let lineStartUTF8Offsets: [Int]

    init(_ source: String) {
        var characters: [Character] = []
        var characterStartUTF8Offsets: [Int] = []
        var lineStartUTF8Offsets: [Int] = [0]
        var utf8Offset = 0

        for character in source {
            characters.append(character)
            characterStartUTF8Offsets.append(utf8Offset)
            utf8Offset += String(character).utf8.count
            if character == "\n" {
                lineStartUTF8Offsets.append(utf8Offset)
            }
        }

        characterStartUTF8Offsets.append(utf8Offset)
        self.characters = characters
        self.characterStartUTF8Offsets = characterStartUTF8Offsets
        self.lineStartUTF8Offsets = lineStartUTF8Offsets
    }

    var count: Int { characters.count }

    subscript(index: Int) -> Character {
        characters[index]
    }

    func substring(_ range: Range<Int>) -> String {
        String(characters[range])
    }

    func hasPrefix(_ prefix: String, at index: Int) -> Bool {
        guard index >= 0 else { return false }
        let chars = Array(prefix)
        guard index + chars.count <= characters.count else { return false }
        for offset in chars.indices where characters[index + offset] != chars[offset] {
            return false
        }
        return true
    }

    func isEscaped(at index: Int) -> Bool {
        guard index > 0 else { return false }
        var slashCount = 0
        var cursor = index - 1
        while cursor >= 0, characters[cursor] == "\\" {
            slashCount += 1
            if cursor == 0 { break }
            cursor -= 1
        }
        return slashCount % 2 == 1
    }

    func characterRange(from sourceRange: SourceRange) -> Range<Int>? {
        guard let lowerBound = characterIndex(for: sourceRange.lowerBound),
              let upperBound = characterIndex(for: sourceRange.upperBound),
              lowerBound <= upperBound
        else {
            return nil
        }
        return lowerBound..<upperBound
    }

    private func characterIndex(for location: SourceLocation) -> Int? {
        guard location.line > 0, location.column > 0 else { return nil }
        guard location.line <= lineStartUTF8Offsets.count else { return nil }
        let lineStartOffset = lineStartUTF8Offsets[location.line - 1]
        let utf8Offset = lineStartOffset + location.column - 1
        guard utf8Offset >= 0,
              let totalUTF8Length = characterStartUTF8Offsets.last,
              utf8Offset <= totalUTF8Length
        else {
            return nil
        }
        return characterIndex(forUTF8Offset: utf8Offset)
    }

    private func characterIndex(forUTF8Offset utf8Offset: Int) -> Int? {
        var lowerBound = 0
        var upperBound = characterStartUTF8Offsets.count

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            let candidate = characterStartUTF8Offsets[middle]
            if candidate == utf8Offset {
                return middle
            }
            if candidate < utf8Offset {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        return nil
    }
}

private struct MarkdownCodeRangeCollector: MarkupWalker {
    private let scanner: MarkdownMathPreprocessorScanner
    private(set) var excludedRanges: [Range<Int>] = []

    init(scanner: MarkdownMathPreprocessorScanner) {
        self.scanner = scanner
    }

    static func excludedRanges(in source: String, scanner: MarkdownMathPreprocessorScanner) -> [Range<Int>] {
        var collector = MarkdownCodeRangeCollector(scanner: scanner)
        let document = Document(parsing: source)
        collector.recordExcludedRanges(in: document)
        return merge(collector.excludedRanges)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        recordRange(of: codeBlock)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        recordRange(of: inlineCode)
    }

    private mutating func recordExcludedRanges(in markup: Markup) {
        if markup is CodeBlock || markup is InlineCode || markup is HTMLBlock {
            recordRange(of: markup)
            return
        }

        recordInlineHTMLLiteralRanges(in: markup)

        if let link = markup as? Link {
            recordExcludedRangeForLinkDestination(link)
        } else if let image = markup as? Image {
            recordExcludedRangeForInlineContainerSuffix(image)
        }

        for child in markup.children {
            recordExcludedRanges(in: child)
        }
    }

    private mutating func recordRange(of markup: Markup) {
        guard let sourceRange = markup.range,
              let characterRange = scanner.characterRange(from: sourceRange),
              !characterRange.isEmpty
        else {
            return
        }
        excludedRanges.append(characterRange)
    }

    private mutating func recordInlineHTMLLiteralRanges(in markup: Markup) {
        guard markup.childCount > 0 else { return }

        var inlineHTMLDepth = 0
        for child in markup.children {
            if child is InlineHTML {
                recordRange(of: child)
            } else if inlineHTMLDepth > 0 {
                recordRange(of: child)
            }

            if let inlineHTML = child as? InlineHTML {
                inlineHTMLDepth = max(
                    0,
                    inlineHTMLDepth + inlineHTMLLiteralDepthDelta(for: inlineHTML.rawHTML)
                )
            }
        }
    }

    private mutating func recordExcludedRangeForLinkDestination(_ link: Link) {
        guard let wholeRange = characterRange(of: link) else { return }

        if isAutoLink(link, wholeRange: wholeRange) {
            excludedRanges.append(wholeRange)
            return
        }

        recordExcludedRangeForInlineContainerSuffix(link)
    }

    private mutating func recordExcludedRangeForInlineContainerSuffix(_ markup: Markup) {
        guard let wholeRange = characterRange(of: markup) else { return }

        let childUpperBound = markup.children.compactMap { characterRange(of: $0)?.upperBound }.max()
        let suffixStart = childUpperBound ?? wholeRange.lowerBound
        guard suffixStart < wholeRange.upperBound else { return }
        excludedRanges.append(suffixStart..<wholeRange.upperBound)
    }

    private func isAutoLink(_ link: Link, wholeRange: Range<Int>) -> Bool {
        let source = scanner.substring(wholeRange)
        guard source.hasPrefix("<"), source.hasSuffix(">") else { return false }
        guard let destination = link.destination,
              link.childCount == 1,
              let text = link.child(at: 0) as? Text
        else {
            return false
        }
        return text.string == destination
    }

    private func characterRange(of markup: Markup) -> Range<Int>? {
        guard let sourceRange = markup.range else { return nil }
        return scanner.characterRange(from: sourceRange)
    }

    private func inlineHTMLLiteralDepthDelta(for rawHTML: String) -> Int {
        let trimmed = rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">") else { return 0 }
        if trimmed.hasPrefix("</") { return -1 }
        if trimmed.hasPrefix("<!--") || trimmed.hasPrefix("<!") || trimmed.hasPrefix("<?") || trimmed.hasSuffix("/>") {
            return 0
        }

        let tagName = trimmed
            .dropFirst()
            .prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" }
            .lowercased()

        guard !tagName.isEmpty else { return 0 }
        if Self.inlineHTMLVoidTags.contains(tagName) {
            return 0
        }
        return 1
    }

    private static let inlineHTMLVoidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]

    private static func merge(_ ranges: [Range<Int>]) -> [Range<Int>] {
        guard !ranges.isEmpty else { return [] }
        let sorted = ranges.sorted { lhs, rhs in
            if lhs.lowerBound != rhs.lowerBound {
                return lhs.lowerBound < rhs.lowerBound
            }
            return lhs.upperBound < rhs.upperBound
        }

        var merged: [Range<Int>] = [sorted[0]]
        for range in sorted.dropFirst() {
            let lastIndex = merged.count - 1
            if range.lowerBound <= merged[lastIndex].upperBound {
                merged[lastIndex] = merged[lastIndex].lowerBound..<max(merged[lastIndex].upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}

private struct Parser {
    private let scanner: MarkdownMathPreprocessorScanner
    private let excludedRanges: [Range<Int>]
    private var index: Int = 0
    private var output: String = ""
    private var segments: [MarkdownMathSegment] = []
    private var nextExcludedRangeIndex: Int = 0

    init(source: String) {
        let scanner = MarkdownMathPreprocessorScanner(source)
        self.scanner = scanner
        self.excludedRanges = MarkdownCodeRangeCollector.excludedRanges(in: source, scanner: scanner)
    }

    mutating func parse() -> MarkdownMathPreprocessor.Result {
        while index < scanner.count {
            if let excludedRange = currentExcludedRange() {
                appendRaw(range: excludedRange)
                index = excludedRange.upperBound
                continue
            }

            if let match = mathSegmentIfNeeded() {
                appendMathSegment(match)
                index = match.range.upperBound
                continue
            }

            appendRaw(range: index..<(index + 1))
            index += 1
        }

        return MarkdownMathPreprocessor.Result(markdown: output, segments: segments)
    }

    mutating func containsMathSegments() -> Bool {
        while index < scanner.count {
            if let excludedRange = currentExcludedRange() {
                index = excludedRange.upperBound
                continue
            }

            if mathSegmentIfNeeded() != nil {
                return true
            }

            index += 1
        }

        return false
    }

    mutating func containsUnterminatedMathSegments() -> Bool {
        while index < scanner.count {
            if let excludedRange = currentExcludedRange() {
                index = excludedRange.upperBound
                continue
            }

            if let match = mathSegmentIfNeeded() {
                index = match.range.upperBound
                continue
            }

            if startsUnterminatedMathSegment() {
                return true
            }

            index += 1
        }

        return false
    }

    private struct MathMatch {
        let range: Range<Int>
        let latexRange: Range<Int>
        let displayMode: Bool
    }

    private static let displayMathEnvironments: Set<String> = [
        "align",
        "alignat",
        "alignat*",
        "aligned",
        "alignedat",
        "alignedat*",
        "align*",
        "array",
        "Bmatrix",
        "bmatrix",
        "cases",
        "equation",
        "equation*",
        "gather",
        "gathered",
        "gather*",
        "matrix",
        "multline",
        "multline*",
        "pmatrix",
        "smallmatrix",
        "split",
        "Vmatrix",
        "vmatrix"
    ]

    private mutating func appendRaw(range: Range<Int>) {
        guard !range.isEmpty else { return }
        let chunk = scanner.substring(range)
        output.append(chunk)
    }

    private mutating func appendMathSegment(_ match: MathMatch) {
        let rawSource = scanner.substring(match.range)
        let rawLatex = scanner.substring(match.latexRange)
        let latex: String
        if match.displayMode {
            latex = rawLatex.trimmingCharacters(in: .newlines)
        } else {
            latex = rawLatex
        }
        let segment = MarkdownMathSegment(
            placeholderIndex: segments.count,
            latex: latex,
            source: rawSource,
            displayMode: match.displayMode
        )
        segments.append(segment)
        output.append(MarkdownMathPlaceholder.token(for: segment.placeholderIndex))
    }

    private mutating func currentExcludedRange() -> Range<Int>? {
        while nextExcludedRangeIndex < excludedRanges.count,
              excludedRanges[nextExcludedRangeIndex].upperBound <= index {
            nextExcludedRangeIndex += 1
        }

        guard nextExcludedRangeIndex < excludedRanges.count else { return nil }
        let range = excludedRanges[nextExcludedRangeIndex]
        guard range.lowerBound <= index, index < range.upperBound else { return nil }
        return range
    }

    private func mathSegmentIfNeeded() -> MathMatch? {
        guard index < scanner.count else { return nil }

        if let environmentMatch = displayEnvironmentMathMatch() {
            return environmentMatch
        }

        if scanner.hasPrefix("\\(", at: index), !scanner.isEscaped(at: index) {
            return escapedMathMatch(openLength: 2, closeSequence: "\\)", displayMode: false)
        }
        if scanner.hasPrefix("\\[", at: index), !scanner.isEscaped(at: index) {
            return escapedMathMatch(openLength: 2, closeSequence: "\\]", displayMode: true)
        }

        guard scanner[index] == "$", !scanner.isEscaped(at: index) else { return nil }

        if index + 1 < scanner.count, scanner[index + 1] == "$" {
            return dollarMathMatch(displayMode: true)
        }
        return dollarMathMatch(displayMode: false)
    }

    private func startsUnterminatedMathSegment() -> Bool {
        guard index < scanner.count else { return false }

        if startsDisplayEnvironmentMath(), displayEnvironmentMathMatch() == nil {
            return true
        }

        if scanner.hasPrefix("\\(", at: index), !scanner.isEscaped(at: index) {
            return escapedMathMatch(openLength: 2, closeSequence: "\\)", displayMode: false) == nil
        }

        if scanner.hasPrefix("\\[", at: index), !scanner.isEscaped(at: index) {
            return escapedMathMatch(openLength: 2, closeSequence: "\\]", displayMode: true) == nil
        }

        guard scanner[index] == "$", !scanner.isEscaped(at: index) else { return false }

        if index + 1 < scanner.count, scanner[index + 1] == "$" {
            return dollarMathMatch(displayMode: true) == nil
        }

        guard couldStartInlineDollarMath() else { return false }
        return dollarMathMatch(displayMode: false) == nil
    }

    private func startsDisplayEnvironmentMath() -> Bool {
        guard scanner.hasPrefix("\\begin{", at: index), !scanner.isEscaped(at: index) else { return false }
        guard isLineDelimitedMathStart(at: index) else { return false }

        let nameStart = index + 7
        var nameEnd = nameStart
        while nameEnd < scanner.count, scanner[nameEnd] != "}" {
            nameEnd += 1
        }
        guard nameEnd < scanner.count else { return false }

        let environmentName = scanner.substring(nameStart..<nameEnd)
        return Self.displayMathEnvironments.contains(environmentName)
    }

    private func displayEnvironmentMathMatch() -> MathMatch? {
        guard startsDisplayEnvironmentMath() else { return nil }

        let nameStart = index + 7
        var nameEnd = nameStart
        while nameEnd < scanner.count, scanner[nameEnd] != "}" {
            nameEnd += 1
        }
        let environmentName = scanner.substring(nameStart..<nameEnd)

        let endMarker = "\\end{\(environmentName)}"
        var cursor = nameEnd + 1
        while cursor < scanner.count {
            if scanner.hasPrefix(endMarker, at: cursor), !scanner.isEscaped(at: cursor) {
                let end = cursor + endMarker.count
                guard isLineDelimitedMathEnd(at: end) else { return nil }
                return MathMatch(
                    range: index..<end,
                    latexRange: index..<end,
                    displayMode: true
                )
            }
            cursor += 1
        }

        return nil
    }

    private func isLineDelimitedMathStart(at index: Int) -> Bool {
        var lineStart = index
        while lineStart > 0, scanner[lineStart - 1] != "\n" {
            lineStart -= 1
        }

        var cursor = lineStart
        while cursor < index {
            consumeHorizontalWhitespace(upTo: index, cursor: &cursor)
            guard cursor < index else { return true }

            if scanner[cursor] == ">" {
                cursor += 1
                if cursor < index, scanner[cursor] == " " {
                    cursor += 1
                }
                continue
            }

            if consumeListMarker(upTo: index, cursor: &cursor) {
                continue
            }

            return false
        }

        return true
    }

    private func isLineDelimitedMathEnd(at index: Int) -> Bool {
        var cursor = index
        while cursor < scanner.count {
            let character = scanner[cursor]
            if character == "\n" {
                return true
            }
            if character != " " && character != "\t" {
                return false
            }
            cursor += 1
        }
        return true
    }

    private func consumeHorizontalWhitespace(upTo limit: Int, cursor: inout Int) {
        while cursor < limit {
            let character = scanner[cursor]
            guard character == " " || character == "\t" else { break }
            cursor += 1
        }
    }

    private func consumeListMarker(upTo limit: Int, cursor: inout Int) -> Bool {
        guard cursor < limit else { return false }

        let marker = scanner[cursor]
        if marker == "-" || marker == "+" || marker == "*" {
            let separatorIndex = cursor + 1
            guard separatorIndex < limit else { return false }
            let separator = scanner[separatorIndex]
            guard separator == " " || separator == "\t" else { return false }
            cursor = separatorIndex + 1
            _ = consumeTaskListCheckbox(upTo: limit, cursor: &cursor)
            return true
        }

        guard marker.wholeNumberValue != nil else { return false }
        var digitsEnd = cursor
        while digitsEnd < limit, scanner[digitsEnd].wholeNumberValue != nil {
            digitsEnd += 1
        }
        guard digitsEnd < limit else { return false }

        let delimiter = scanner[digitsEnd]
        guard delimiter == "." || delimiter == ")" else { return false }

        let separatorIndex = digitsEnd + 1
        guard separatorIndex < limit else { return false }
        let separator = scanner[separatorIndex]
        guard separator == " " || separator == "\t" else { return false }

        cursor = separatorIndex + 1
        _ = consumeTaskListCheckbox(upTo: limit, cursor: &cursor)
        return true
    }

    private func consumeTaskListCheckbox(upTo limit: Int, cursor: inout Int) -> Bool {
        let checkboxEnd = cursor + 2
        guard checkboxEnd < limit else { return false }
        guard scanner[cursor] == "[", scanner[checkboxEnd] == "]" else { return false }

        let state = scanner[cursor + 1]
        guard state == " " || state == "x" || state == "X" else { return false }

        let separatorIndex = checkboxEnd + 1
        guard separatorIndex < limit else { return false }
        let separator = scanner[separatorIndex]
        guard separator == " " || separator == "\t" else { return false }

        cursor = separatorIndex + 1
        return true
    }

    private func escapedMathMatch(
        openLength: Int,
        closeSequence: String,
        displayMode: Bool
    ) -> MathMatch? {
        let contentStart = index + openLength
        var cursor = contentStart

        while cursor < scanner.count {
            if scanner.hasPrefix(closeSequence, at: cursor), !scanner.isEscaped(at: cursor) {
                let range = index..<(cursor + closeSequence.count)
                return MathMatch(
                    range: range,
                    latexRange: contentStart..<cursor,
                    displayMode: displayMode
                )
            }
            cursor += 1
        }

        return nil
    }

    private func dollarMathMatch(displayMode: Bool) -> MathMatch? {
        let openingLength = displayMode ? 2 : 1
        let contentStart = index + openingLength
        guard contentStart < scanner.count else { return nil }

        if !displayMode {
            guard couldStartInlineDollarMath() else { return nil }
        }

        var cursor = contentStart
        while cursor < scanner.count {
            if displayMode {
                if scanner[cursor] == "$",
                   cursor + 1 < scanner.count,
                   scanner[cursor + 1] == "$",
                   !scanner.isEscaped(at: cursor) {
                    let range = index..<(cursor + 2)
                    return MathMatch(
                        range: range,
                        latexRange: contentStart..<cursor,
                        displayMode: true
                    )
                }
            } else if scanner[cursor] == "\n" {
                return nil
            } else if scanner[cursor] == "$", !scanner.isEscaped(at: cursor) {
                let previous = scanner[cursor - 1]
                if previous != " " && previous != "\t" && previous != "\n" {
                    let content = scanner.substring(contentStart..<cursor)
                    let suffix = shellInterpolationSuffix(startingAt: cursor + 1)
                    if looksLikeShellVariableSequence(content: content, suffix: suffix) {
                        cursor += 1
                        continue
                    }
                    if looksLikeCurrencyPair(content: content, suffix: suffix) {
                        cursor += 1
                        continue
                    }
                    let range = index..<(cursor + 1)
                    return MathMatch(
                        range: range,
                        latexRange: contentStart..<cursor,
                        displayMode: false
                    )
                }
            }
            cursor += 1
        }

        return nil
    }

    private func couldStartInlineDollarMath() -> Bool {
        let contentStart = index + 1
        guard contentStart < scanner.count else { return true }

        let next = scanner[contentStart]
        if next == " " || next == "\t" || next == "\n" || next == "$" {
            return false
        }

        if next.wholeNumberValue != nil {
            let trailingContent = scanner.substring(contentStart..<scanner.count)
            if looksLikeCurrencyFragment(trailingContent) {
                return false
            }
        }

        if looksLikeDelimitedLiteralPrefix(startingAt: contentStart) {
            return false
        }

        if looksLikeLiteralDollarPrefix(startingAt: contentStart) {
            return false
        }

        return true
    }

    private func looksLikeLiteralDollarPrefix(startingAt contentStart: Int) -> Bool {
        var tokenEnd = contentStart
        while tokenEnd < scanner.count {
            let character = scanner[tokenEnd]
            if character == "$" || character == "\n" || character == " " || character == "\t" {
                break
            }
            tokenEnd += 1
        }

        guard tokenEnd > contentStart else { return false }
        let prefix = scanner.substring(contentStart..<tokenEnd)
        guard prefix.allSatisfy(isIdentifierLike) ||
                looksLikeCurrencyAmount(prefix) ||
                looksLikeLiteralPathToken(prefix)
        else {
            return false
        }

        var cursor = tokenEnd
        while cursor < scanner.count {
            let character = scanner[cursor]
            if character == "\n" {
                return true
            }
            if character == "$" {
                return false
            }
            if character != " " && character != "\t" {
                break
            }
            cursor += 1
        }

        guard cursor < scanner.count else { return true }
        let continuation = scanner.substring(cursor..<scanner.count)
        if continuationStartsLikeMath(continuation) {
            return false
        }

        let continuationToken = continuationPrefix(in: continuation)
        return continuationToken.count > 1
    }

    private func looksLikeDelimitedLiteralPrefix(startingAt contentStart: Int) -> Bool {
        guard index > 0 else { return false }

        let previous = scanner[index - 1]
        if literalDollarPrecedingCharacters.contains(previous) {
            let probe = literalTokenProbe(
                startingAt: contentStart,
                extraTerminators: ["\"", "'", "<", ">", ")", "]"]
            )
            return looksLikeLiteralToken(probe.token)
        }

        if previous == ">" {
            let probe = literalTokenProbe(
                startingAt: contentStart,
                extraTerminators: ["<"]
            )
            guard probe.boundary == "<" else { return false }
            return looksLikeLiteralToken(probe.token)
        }

        return false
    }

    private func literalTokenProbe(
        startingAt start: Int,
        extraTerminators: Set<Character>
    ) -> (token: String, boundary: Character?) {
        var end = start
        while end < scanner.count {
            let character = scanner[end]
            if character == "$" || character == "\n" || character == " " || character == "\t" ||
                extraTerminators.contains(character) {
                break
            }
            end += 1
        }

        let token = scanner.substring(start..<end)
        let boundary = end < scanner.count ? scanner[end] : nil
        return (token, boundary)
    }

    private func continuationStartsLikeMath(_ continuation: String) -> Bool {
        guard let first = continuation.first else { return false }
        if first == "\\" {
            return true
        }
        if first.wholeNumberValue != nil {
            return true
        }

        return mathContinuationPrefixes.contains(first)
    }

    private func continuationPrefix(in continuation: String) -> String {
        var token = ""
        for character in continuation {
            guard isIdentifierLike(character) else { break }
            token.append(character)
        }
        return token
    }

    private func shellInterpolationSuffix(startingAt index: Int) -> String {
        guard index < scanner.count else { return "" }
        var cursor = index
        while cursor < scanner.count {
            let character = scanner[cursor]
            guard isIdentifierLike(character) ||
                    character == ":" ||
                    character == "/" ||
                    character == "." ||
                    character == "-"
            else {
                break
            }
            cursor += 1
        }
        guard cursor > index else { return "" }
        return scanner.substring(index..<cursor)
    }

    private func looksLikeShellVariableSequence(
        content: String,
        suffix: String
    ) -> Bool {
        guard !suffix.isEmpty else { return false }
        guard let first = content.first, isIdentifierLike(first) else { return false }
        guard content.contains(where: isShellPathSeparator) else { return false }

        let prefixComponent = content.split(whereSeparator: isShellPathSeparator).first ?? ""
        let suffixComponent = suffix.split(whereSeparator: isShellPathSeparator).first ?? ""
        guard prefixComponent.count > 1, suffixComponent.count > 1 else { return false }

        return content.allSatisfy { character in
            isIdentifierLike(character) || isShellPathSeparator(character)
        } && suffix.allSatisfy { character in
            isIdentifierLike(character) || isShellPathSeparator(character)
        }
    }

    private func looksLikeCurrencyPair(content: String, suffix: String) -> Bool {
        guard let separator = content.last, separator == "-" || separator == "/" else { return false }
        let leadingAmount = String(content.dropLast())
        let trailingAmount = currencyAmountPrefix(in: suffix)
        guard !trailingAmount.isEmpty else { return false }
        return looksLikeCurrencyAmount(leadingAmount) && looksLikeCurrencyAmount(trailingAmount)
    }

    private func looksLikeCurrencyFragment(_ content: String) -> Bool {
        guard !content.isEmpty else { return false }
        if looksLikeCurrencyAmount(content) {
            return true
        }

        guard let separator = content.last, separator == "-" || separator == "/" else { return false }
        return looksLikeCurrencyAmount(String(content.dropLast()))
    }

    private func currencyAmountPrefix(in text: String) -> String {
        guard !text.isEmpty else { return "" }
        var prefix = ""
        var sawDigit = false

        for character in text {
            if character.wholeNumberValue != nil {
                prefix.append(character)
                sawDigit = true
                continue
            }

            if character == "," || character == "." {
                prefix.append(character)
                continue
            }

            break
        }

        return sawDigit ? prefix : ""
    }

    private func looksLikeCurrencyAmount(_ text: String) -> Bool {
        let amount = currencyAmountPrefix(in: text)
        return !amount.isEmpty && amount.count == text.count
    }

    private func isShellPathSeparator(_ character: Character) -> Bool {
        character == ":" || character == "/" || character == "." || character == "-"
    }

    private func isIdentifierLike(_ character: Character) -> Bool {
        character == "_" || character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    private func looksLikeLiteralPathToken(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard text.contains(where: literalPathSeparators.contains) else { return false }
        guard let first = text.first, isIdentifierLike(first) else { return false }
        return text.allSatisfy { isIdentifierLike($0) || literalPathSeparators.contains($0) }
    }

    private func looksLikeLiteralToken(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.allSatisfy(isIdentifierLike) ||
            looksLikeCurrencyAmount(text) ||
            looksLikeLiteralPathToken(text)
    }

    private var literalPathSeparators: Set<Character> {
        [":", "/", ".", "-", "@", "?", "=", "&", "#", "%", "~"]
    }

    private var literalDollarPrecedingCharacters: Set<Character> {
        ["/", ".", "-", ":", "@", "?", "=", "&", "#", "%"]
    }

    private var mathContinuationPrefixes: Set<Character> {
        ["+", "-", "*", "/", "=", "<", ">", "^", "_", "(", "[", "{", "|", "&", ",", ".", "!", "?", ":"]
    }
}
