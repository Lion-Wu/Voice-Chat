//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import RegexBuilder

/// Pre-process the inline and block latex in markdown.
/// This is a less heavy-weight approach than forking commonmark-gfm and swift-markdown to support parsing latex nodes.
protocol LaTexPreProcessor {
  func process(input: String, matchingRules: [MarkdownParseOption.LatexMatching]) -> String
}

extension LaTexPreProcessor {
  func process(input: String) -> String {
    return process(input: input, matchingRules: MarkdownParseOption.LatexMatching.allCases)
  }
}

final class LaTexPreProcessorImpl: LaTexPreProcessor {

  private typealias BlockMathPattern = (
    regex: Regex<(Substring, Substring, Substring)>,
    indentation: Reference<Substring>,
    latex: Reference<Substring>
  )

  private typealias InlineMathPattern = (
    regex: Regex<(Substring, Substring)>,
    latex: Reference<Substring>
  )

  static let customCodeType = "blockmath"
  static let inlineCodePrefix = "\\("
  static let inlineCodeSuffix = "\\)"
  static let newline = "\n"

  init() {}

  func process(input: String, matchingRules: [MarkdownParseOption.LatexMatching]) -> String {
    let rules = Set(matchingRules)
    let result = processBlockMath(input: input, rules: rules)
    return processInlineMath(input: result, rules: rules)
  }

  /// This replace block math with a special code block node. By treating it as a code block it will avoid over escaping characters within latex.
  func processBlockMath(input: String, rules: Set<MarkdownParseOption.LatexMatching>) -> String {
    var result = Self.transformingOutsideCode(in: input) { source in
      var transformed = source
      if rules.contains(.blockDollar) {
        let pattern = Self.dollarBlockMathPattern()
        transformed.replace(pattern.regex, with: { match in
          let indentation = match[pattern.indentation]
          let latex = match[pattern.latex]
          return Self.buildCodeBlock(indentation: indentation, latex: latex)
        })
      }

      if rules.contains(.blockSlashBracket) {
        let pattern = Self.slashBracketMathPattern()
        transformed.replace(pattern.regex, with: { match in
          let indentation = match[pattern.indentation]
          let latex = match[pattern.latex]
          return Self.buildCodeBlock(indentation: indentation, latex: latex)
        })
      }
      return transformed
    }

    if rules.contains(.blockDollar) || rules.contains(.blockSlashBracket) {
      result = Self.transformingOutsideCode(in: result) {
        Self.replacingEmbeddedBlockMath(
          in: $0,
          recognizesDollar: rules.contains(.blockDollar),
          recognizesSlashBracket: rules.contains(.blockSlashBracket)
        )
      }
    }
    return result
  }

  /// This wraps inline math as inline code to avoid over-unescaping issue
  func processInlineMath(input: String, rules: Set<MarkdownParseOption.LatexMatching>) -> String {
    return Self.transformingOutsideCode(in: input) { source in
      var result = source
      if rules.contains(.inlineSlashBracket) {
        let pattern = Self.inlineParenthesisMathPattern()
        result = result.replacing(pattern.regex, with: { match in
          let latex = String(match[pattern.latex])
          return "`\\(\(latex)\\)`"
        })
      }
      if rules.contains(.inlineDollar) {
        result = Self.replacingInlineDollarMath(in: result)
      }
      return result
    }
  }

  // MARK: - Convenience overloads (default to every supported rule)

  func processBlockMath(input: String) -> String {
    return processBlockMath(input: input, rules: Set(MarkdownParseOption.LatexMatching.allCases))
  }

  func processInlineMath(input: String) -> String {
    return processInlineMath(input: input, rules: Set(MarkdownParseOption.LatexMatching.allCases))
  }

  private static func buildCodeBlock(indentation: Substring, latex: Substring) -> String {
    let processedLatex = latex.trimmingCharacters(in: .newlines)
    let nextLineIntendation = latex.hasPrefix(Self.newline) ? "" : indentation
    return "\(indentation)```\(Self.customCodeType)\(Self.newline)\(nextLineIntendation)\(processedLatex)\(Self.newline)\(indentation)```"
  }

  private static func buildCodeBlock(latex: Substring) -> String {
    let processedLatex = latex.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    return "```\(customCodeType)\n\(processedLatex)\n```"
  }

  private static func dollarBlockMathPattern() -> BlockMathPattern {
    let indentation = Reference(Substring.self)
    let latex = Reference(Substring.self)
    let regex = Regex {
      Anchor.startOfLine
      Capture(as: indentation) { ZeroOrMore(.horizontalWhitespace) }
      "$$"
      Capture(as: latex) { OneOrMore(.any, .reluctant) }
      ZeroOrMore(.horizontalWhitespace)
      "$$"
      ZeroOrMore(.horizontalWhitespace)
      Anchor.endOfLine
    }
    return (regex, indentation, latex)
  }

  private static func slashBracketMathPattern() -> BlockMathPattern {
    let indentation = Reference(Substring.self)
    let latex = Reference(Substring.self)
    let regex = Regex {
      Anchor.startOfLine
      Capture(as: indentation) { ZeroOrMore(.horizontalWhitespace) }
      "\\["
      Capture(as: latex) { OneOrMore(.any, .reluctant) }
      ZeroOrMore(.horizontalWhitespace)
      "\\]"
      ZeroOrMore(.horizontalWhitespace)
      Anchor.endOfLine
    }
    return (regex, indentation, latex)
  }

  private static func inlineParenthesisMathPattern() -> InlineMathPattern {
    let latex = Reference(Substring.self)
    let regex = Regex {
      "\\("
      Capture(as: latex) { OneOrMore(.any, .reluctant) }
      "\\)"
    }
    return (regex, latex)
  }

  /// Converts single-dollar math while leaving code spans, escaped dollars,
  /// block delimiters, and incomplete streamed delimiters untouched.
  private static func replacingInlineDollarMath(in input: String) -> String {
    var output = ""
    output.reserveCapacity(input.count)
    var index = input.startIndex

    while index < input.endIndex {
      guard input[index] == "$",
            !isEscapedCharacter(at: index, in: input),
            !isDoubleDollar(at: index, in: input) else {
        output.append(input[index])
        index = input.index(after: index)
        continue
      }

      let contentStart = input.index(after: index)
      guard contentStart < input.endIndex,
            let closingDollar = closingInlineDollar(
              after: contentStart,
              in: input
            ) else {
        output.append(input[index])
        index = contentStart
        continue
      }

      let content = input[contentStart..<closingDollar]
      let hasLeadingPadding = content.first?.isWhitespace == true
      let hasTrailingPadding = content.last?.isWhitespace == true
      let latex = content.trimmingCharacters(in: .whitespaces)
      guard hasLeadingPadding == hasTrailingPadding, !latex.isEmpty else {
        output.append(input[index])
        index = contentStart
        continue
      }
      output.append("`\\(\(latex)\\)`")
      index = input.index(after: closingDollar)
    }

    return output
  }

  private static func closingInlineDollar(
    after contentStart: String.Index,
    in input: String
  ) -> String.Index? {
    var index = contentStart
    while index < input.endIndex {
      if input[index].isNewline || input[index] == "`" {
        return nil
      }
      if input[index] == "$",
         !isEscapedCharacter(at: index, in: input),
         !isDoubleDollar(at: index, in: input) {
        return index
      }
      index = input.index(after: index)
    }
    return nil
  }

  private static func replacingEmbeddedBlockMath(
    in input: String,
    recognizesDollar: Bool,
    recognizesSlashBracket: Bool
  ) -> String {
    let delimiters: [(opening: String, closing: String)] = [
      recognizesDollar ? ("$$", "$$") : nil,
      recognizesSlashBracket ? ("\\[", "\\]") : nil
    ].compactMap { $0 }
    var output = ""
    output.reserveCapacity(input.count)
    var cursor = input.startIndex

    while let match = delimiters.compactMap({ delimiter -> (
      opening: Range<String.Index>,
      closingDelimiter: String
    )? in
      guard let opening = nextUnescapedDelimiter(
        delimiter.opening,
        in: input,
        from: cursor
      ) else {
        return nil
      }
      return (opening, delimiter.closing)
    }).min(by: { $0.opening.lowerBound < $1.opening.lowerBound }) {
      let opening = match.opening
      output.append(contentsOf: input[cursor..<opening.lowerBound])
      let contentStart = opening.upperBound
      guard let closing = nextUnescapedDelimiter(
        match.closingDelimiter,
        in: input,
        from: contentStart
      ) else {
        output.append(contentsOf: input[opening.lowerBound...])
        return output
      }

      let content = input[contentStart..<closing.lowerBound]
      let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        output.append(contentsOf: input[opening.lowerBound..<closing.upperBound])
        cursor = closing.upperBound
        continue
      }

      while output.last == " " || output.last == "\t" {
        output.removeLast()
      }
      if output.last?.isNewline == false {
        output.append("\n")
      }
      output.append(buildCodeBlock(latex: content))
      var suffixStart = closing.upperBound
      while suffixStart < input.endIndex
            && (input[suffixStart] == " " || input[suffixStart] == "\t") {
        suffixStart = input.index(after: suffixStart)
      }
      if suffixStart < input.endIndex,
         !input[suffixStart].isNewline {
        output.append("\n")
      }
      cursor = suffixStart
    }

    output.append(contentsOf: input[cursor...])
    return output
  }

  private static func nextUnescapedDelimiter(
    _ delimiter: String,
    in input: String,
    from start: String.Index
  ) -> Range<String.Index>? {
    var searchStart = start
    while searchStart < input.endIndex,
          let range = input.range(
            of: delimiter,
            range: searchStart..<input.endIndex
          ) {
      if !isEscapedCharacter(at: range.lowerBound, in: input) {
        return range
      }
      searchStart = range.upperBound
    }
    return nil
  }

  private static func transformingOutsideCode(
    in input: String,
    transform: (String) -> String
  ) -> String {
    var output = ""
    output.reserveCapacity(input.count)
    var plainStart = input.startIndex
    var cursor = input.startIndex

    while cursor < input.endIndex {
      guard input[cursor] == "`" else {
        cursor = input.index(after: cursor)
        continue
      }

      let delimiterLength = repeatedCharacterCount(
        from: cursor,
        in: input,
        character: "`"
      )
      let delimiterEnd = input.index(cursor, offsetBy: delimiterLength)
      guard let closingEnd = closingCodeDelimiterEnd(
        in: input,
        after: delimiterEnd,
        length: delimiterLength
      ) else {
        output.append(transform(String(input[plainStart..<cursor])))
        output.append(contentsOf: input[cursor...])
        return output
      }

      output.append(transform(String(input[plainStart..<cursor])))
      output.append(contentsOf: input[cursor..<closingEnd])
      cursor = closingEnd
      plainStart = closingEnd
    }

    output.append(transform(String(input[plainStart...])))
    return output
  }

  private static func closingCodeDelimiterEnd(
    in input: String,
    after start: String.Index,
    length: Int
  ) -> String.Index? {
    var cursor = start
    while cursor < input.endIndex {
      guard input[cursor] == "`" else {
        cursor = input.index(after: cursor)
        continue
      }

      let runLength = repeatedCharacterCount(
        from: cursor,
        in: input,
        character: "`"
      )
      if runLength == length {
        return input.index(cursor, offsetBy: runLength)
      }
      cursor = input.index(cursor, offsetBy: runLength)
    }
    return nil
  }

  private static func isDoubleDollar(
    at index: String.Index,
    in input: String
  ) -> Bool {
    let previousIsDollar = index > input.startIndex
      && input[input.index(before: index)] == "$"
    let next = input.index(after: index)
    let nextIsDollar = next < input.endIndex && input[next] == "$"
    return previousIsDollar || nextIsDollar
  }

  private static func isEscapedCharacter(
    at index: String.Index,
    in input: String
  ) -> Bool {
    var slashCount = 0
    var cursor = index
    while cursor > input.startIndex {
      cursor = input.index(before: cursor)
      guard input[cursor] == "\\" else { break }
      slashCount += 1
    }
    return slashCount.isMultiple(of: 2) == false
  }

  private static func repeatedCharacterCount(
    from index: String.Index,
    in input: String,
    character: Character
  ) -> Int {
    var count = 0
    var cursor = index
    while cursor < input.endIndex, input[cursor] == character {
      count += 1
      cursor = input.index(after: cursor)
    }
    return count
  }
}
