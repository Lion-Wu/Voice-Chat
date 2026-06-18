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

  nonisolated(unsafe) static let latexRef = Reference(Substring.self)
  nonisolated(unsafe) static let latexOpenIndentation = Reference(Substring.self)

  nonisolated(unsafe) static let dollarBlockMath = Regex {
    Anchor.startOfLine
    Capture(as: latexOpenIndentation) {
      ZeroOrMore(.horizontalWhitespace)
    }
    "$$"
    Capture(as: latexRef) {
      OneOrMore(.any, .reluctant)
    }
    ZeroOrMore(.horizontalWhitespace)
    "$$"
    ZeroOrMore(.horizontalWhitespace)
    Anchor.endOfLine
  }

  nonisolated(unsafe) static let slashBracketMath = Regex {
    Anchor.startOfLine
    Capture(as: latexOpenIndentation) {
      ZeroOrMore(.horizontalWhitespace)
    }
    "\\["
    Capture(as: latexRef) {
      OneOrMore(.any, .reluctant)
    }
    ZeroOrMore(.horizontalWhitespace)
    "\\]"
    ZeroOrMore(.horizontalWhitespace)
    Anchor.endOfLine
  }

  nonisolated(unsafe) static let inlineParenthesisMath = Regex {
    "\\("
    Capture(as: latexRef) {
      OneOrMore(.any, .reluctant)
    }
    "\\)"
  }

  nonisolated(unsafe) static let dfracLatex = Regex {
    Capture {
      "\\dfrac"
    }
  }

  nonisolated(unsafe) static let tfracLatex = Regex {
    Capture {
      "\\tfrac"
    }
  }

  nonisolated(unsafe) static let bracketSize = Regex {
    Capture {
      ChoiceOf {
        "\\bigl"
        "\\biggl"
        "\\Bigl"
        "\\Biggl"
        "\\bigr"
        "\\biggr"
        "\\Bigr"
        "\\Biggr"
        "\\big"
      }
    }
  }

  nonisolated(unsafe) static let primeLatex = Regex {
    Capture {
      "'"
    }
  }

  nonisolated(unsafe) static let vectorLatex = Regex {
    Capture {
      "\\overrightarrow"
    }
  }

  nonisolated(unsafe) static let rightArrowLatex = Regex {
    Capture {
      "\\implies"
    }
  }

  nonisolated(unsafe) static let harpoonsLatex = Regex {
    Capture {
      "\\rightleftharpoons"
    }
  }

  nonisolated(unsafe) static let dotsLatex = Regex {
    Capture {
      "\\dots"
    }
  }

  static let customCodeType = "blockmath"
  static let inlineCodePrefix = "\\("
  static let inlineCodeSuffix = "\\)"
  static let newline = "\n"
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
  private static let literalPathSeparators: Set<Character> = [":", "/", ".", "-", "@", "?", "=", "&", "#", "%", "~"]
  private static let literalDollarPrecedingCharacters: Set<Character> = ["/", ".", "-", ":", "@", "?", "=", "&", "#", "%"]
  private static let mathContinuationPrefixes: Set<Character> = ["+", "-", "*", "/", "=", "<", ">", "^", "_", "(", "[", "{", "|", "&", ",", ".", "!", "?", ":"]

  init() {}

  func process(input: String, matchingRules: [MarkdownParseOption.LatexMatching]) -> String {
    let rules = Set(matchingRules)
    guard !rules.isEmpty, Self.containsLatexCandidate(in: input, rules: rules) else {
      return input
    }

    var result = input
    if Self.containsBlockLatexCandidate(in: result, rules: rules) {
      result = Self.processingUnprotectedMarkdownSegments(in: result) { segment in
        processBlockMath(input: segment, rules: rules)
      }
    }
    if Self.containsInlineLatexCandidate(in: result, rules: rules) {
      result = Self.processingUnprotectedMarkdownSegments(in: result) { segment in
        processInlineMath(input: segment, rules: rules)
      }
    }
    return result
  }

  /// This replace block math with a special code block node. By treating it as a code block it will avoid over escaping characters within latex.
  func processBlockMath(input: String, rules: Set<MarkdownParseOption.LatexMatching>) -> String {
    var result = input
    if rules.contains(.blockDollar) {
      result.replace(Self.dollarBlockMath, with: { match in
        let indentation = match[Self.latexOpenIndentation]
        let latex = match[Self.latexRef]
        return Self.buildCodeBlock(indentation: indentation, latex: latex)
      })
    }

    if rules.contains(.blockSlashBracket) {
      result.replace(Self.slashBracketMath, with: { match in
        let indentation = match[Self.latexOpenIndentation]
        let latex = match[Self.latexRef]
        return Self.buildCodeBlock(indentation: indentation, latex: latex)
      })
    }
    if result.range(of: "\\begin{") != nil {
      result = Self.processingUnprotectedMarkdownSegments(in: result) { segment in
        Self.replacingDisplayEnvironmentMath(in: segment)
      }
    }
    return result
  }

  /// This wraps inline math as inline code to avoid over-unescaping issue
  func processInlineMath(input: String, rules: Set<MarkdownParseOption.LatexMatching>) -> String {
    var result = input
    if rules.contains(.inlineSlashBracket) {
      result = result.replacing(Self.inlineParenthesisMath, with: { match in
        let latex = String(match[Self.latexRef]).filteringUnsupportedSyntaxes()
        return "`\\(\(latex)\\)`"
      })
    }
    if rules.contains(.inlineDollar) {
      result = Self.replacingInlineDollarMath(in: result)
    }
    return result
  }

  // MARK: - Convenience overloads (default to every supported rule)

  func processBlockMath(input: String) -> String {
    return processBlockMath(input: input, rules: Set(MarkdownParseOption.LatexMatching.allCases))
  }

  func processInlineMath(input: String) -> String {
    return processInlineMath(input: input, rules: Set(MarkdownParseOption.LatexMatching.allCases))
  }

  private static func buildCodeBlock(indentation: Substring, latex: Substring) -> String {
    let processedLatex = latex.trimmingCharacters(in: .newlines).filteringUnsupportedSyntaxes()
    let nextLineIntendation = latex.hasPrefix(Self.newline) ? "" : indentation
    return "\(indentation)```\(Self.customCodeType)\(Self.newline)\(nextLineIntendation)\(processedLatex)\(Self.newline)\(indentation)```"
  }

  private static func replacingInlineDollarMath(in input: String) -> String {
    var output = ""
    output.reserveCapacity(input.count)
    var index = input.startIndex

    while index < input.endIndex {
      guard input[index] == "$",
            !isEscapedDollar(at: index, in: input),
            !isDoubleDollar(at: index, in: input),
            couldStartInlineDollarMath(at: index, in: input) else {
        output.append(input[index])
        index = input.index(after: index)
        continue
      }

      let contentStart = input.index(after: index)
      var scanIndex = contentStart
      var closingDollar: String.Index?

      while scanIndex < input.endIndex {
        if input[scanIndex] == "\n" {
          break
        }
        if input[scanIndex] == "$",
           !isEscapedDollar(at: scanIndex, in: input),
           !isDoubleDollar(at: scanIndex, in: input) {
          let previous = input.index(before: scanIndex)
          if input[previous].isWhitespace {
            scanIndex = input.index(after: scanIndex)
            continue
          }
          let content = String(input[contentStart..<scanIndex])
          let suffix = shellInterpolationSuffix(in: input, startingAt: input.index(after: scanIndex))
          if looksLikeShellVariableSequence(content: content, suffix: suffix) ||
              looksLikeCurrencyPair(content: content, suffix: suffix) {
            scanIndex = input.index(after: scanIndex)
            continue
          }
          closingDollar = scanIndex
          break
        }
        scanIndex = input.index(after: scanIndex)
      }

      guard let closingDollar, closingDollar > contentStart else {
        output.append(input[index])
        index = input.index(after: index)
        continue
      }

      let latex = String(input[contentStart..<closingDollar]).filteringUnsupportedSyntaxes()
      output.append("`\\(\(latex)\\)`")
      index = input.index(after: closingDollar)
    }

    return output
  }

  private static func replacingDisplayEnvironmentMath(in input: String) -> String {
    var output = ""
    output.reserveCapacity(input.count)
    var cursor = input.startIndex

    while cursor < input.endIndex {
      guard let beginRange = input.range(of: "\\begin{", range: cursor..<input.endIndex) else {
        output.append(contentsOf: input[cursor..<input.endIndex])
        break
      }

      guard !isEscapedCharacter(at: beginRange.lowerBound, in: input),
            isLineDelimitedMathStart(at: beginRange.lowerBound, in: input),
            let environment = displayEnvironmentName(startingAt: beginRange.upperBound, in: input),
            displayMathEnvironments.contains(environment.name),
            let matchEnd = displayEnvironmentEnd(for: environment.name, after: environment.nameEnd, in: input) else {
        output.append(contentsOf: input[cursor..<beginRange.upperBound])
        cursor = beginRange.upperBound
        continue
      }

      output.append(contentsOf: input[cursor..<beginRange.lowerBound])
      let indentation = linePrefix(before: beginRange.lowerBound, in: input)
      output.append(buildCodeBlock(indentation: indentation, latex: input[beginRange.lowerBound..<matchEnd]))
      cursor = matchEnd
    }

    return output
  }

  private static func containsLatexCandidate(in input: String, rules: Set<MarkdownParseOption.LatexMatching>) -> Bool {
    containsBlockLatexCandidate(in: input, rules: rules) || containsInlineLatexCandidate(in: input, rules: rules)
  }

  private static func containsBlockLatexCandidate(in input: String, rules: Set<MarkdownParseOption.LatexMatching>) -> Bool {
    if rules.contains(.blockDollar), input.range(of: "$$") != nil {
      return true
    }
    if rules.contains(.blockSlashBracket), input.range(of: "\\[") != nil {
      return true
    }
    if input.range(of: "\\begin{") != nil {
      return true
    }
    return false
  }

  private static func containsInlineLatexCandidate(in input: String, rules: Set<MarkdownParseOption.LatexMatching>) -> Bool {
    if rules.contains(.inlineDollar), input.contains("$") {
      return true
    }
    if rules.contains(.inlineSlashBracket), input.range(of: "\\(") != nil {
      return true
    }
    return false
  }

  private static func isDoubleDollar(at index: String.Index, in input: String) -> Bool {
    let previousIsDollar = index > input.startIndex && input[input.index(before: index)] == "$"
    let next = input.index(after: index)
    let nextIsDollar = next < input.endIndex && input[next] == "$"
    return previousIsDollar || nextIsDollar
  }

  private static func couldStartInlineDollarMath(at index: String.Index, in input: String) -> Bool {
    let contentStart = input.index(after: index)
    guard contentStart < input.endIndex else { return false }

    let next = input[contentStart]
    if next.isWhitespace || next == "$" {
      return false
    }

    if next.wholeNumberValue != nil {
      let trailingContent = String(input[contentStart..<input.endIndex])
      if looksLikeCurrencyFragment(trailingContent) {
        return false
      }
    }

    if looksLikeDelimitedLiteralPrefix(openingDollar: index, contentStart: contentStart, in: input) {
      return false
    }

    if looksLikeLiteralDollarPrefix(contentStart: contentStart, in: input) {
      return false
    }

    return true
  }

  private static func isEscapedDollar(at index: String.Index, in input: String) -> Bool {
    var backslashCount = 0
    var current = index

    while current > input.startIndex {
      current = input.index(before: current)
      guard input[current] == "\\" else {
        break
      }
      backslashCount += 1
    }

    return backslashCount % 2 == 1
  }

  private static func displayEnvironmentName(
    startingAt nameStart: String.Index,
    in input: String
  ) -> (name: String, nameEnd: String.Index)? {
    guard nameStart < input.endIndex,
          let closingBrace = input[nameStart..<input.endIndex].firstIndex(of: "}") else {
      return nil
    }
    return (String(input[nameStart..<closingBrace]), input.index(after: closingBrace))
  }

  private static func displayEnvironmentEnd(
    for environmentName: String,
    after nameEnd: String.Index,
    in input: String
  ) -> String.Index? {
    let endMarker = "\\end{\(environmentName)}"
    var cursor = nameEnd
    while cursor < input.endIndex {
      guard let endRange = input.range(of: endMarker, range: cursor..<input.endIndex) else {
        return nil
      }
      if !isEscapedCharacter(at: endRange.lowerBound, in: input),
         isLineDelimitedMathEnd(at: endRange.upperBound, in: input) {
        return endRange.upperBound
      }
      cursor = endRange.upperBound
    }
    return nil
  }

  private static func isLineDelimitedMathStart(at index: String.Index, in input: String) -> Bool {
    let prefix = String(linePrefix(before: index, in: input))
    return linePrefixAllowsDisplayMath(prefix)
  }

  private static func isLineDelimitedMathEnd(at index: String.Index, in input: String) -> Bool {
    var cursor = index
    while cursor < input.endIndex {
      let character = input[cursor]
      if character == "\n" {
        return true
      }
      if character != " " && character != "\t" {
        return false
      }
      cursor = input.index(after: cursor)
    }
    return true
  }

  private static func linePrefix(before index: String.Index, in input: String) -> Substring {
    var lineStart = index
    while lineStart > input.startIndex {
      let previous = input.index(before: lineStart)
      guard input[previous] != "\n" else { break }
      lineStart = previous
    }
    return input[lineStart..<index]
  }

  private static func linePrefixAllowsDisplayMath(_ prefix: String) -> Bool {
    var remainder = prefix[...]
    consumeHorizontalWhitespace(in: &remainder)
    guard !remainder.isEmpty else { return true }

    if remainder.first == ">" {
      remainder = remainder.dropFirst()
      if remainder.first == " " || remainder.first == "\t" {
        remainder = remainder.dropFirst()
      }
      return linePrefixAllowsDisplayMath(String(remainder))
    }

    if consumeListMarker(in: &remainder) {
      consumeHorizontalWhitespace(in: &remainder)
      return remainder.isEmpty
    }

    return false
  }

  private static func consumeHorizontalWhitespace(in substring: inout Substring) {
    while let first = substring.first, first == " " || first == "\t" {
      substring = substring.dropFirst()
    }
  }

  private static func consumeListMarker(in substring: inout Substring) -> Bool {
    guard let first = substring.first else { return false }
    if first == "-" || first == "+" || first == "*" {
      let markerEnd = substring.index(after: substring.startIndex)
      guard markerEnd < substring.endIndex,
            substring[markerEnd] == " " || substring[markerEnd] == "\t" else {
        return false
      }
      substring = substring[substring.index(after: markerEnd)..<substring.endIndex]
      _ = consumeTaskListCheckbox(in: &substring)
      return true
    }

    guard first.wholeNumberValue != nil else { return false }
    var digitsEnd = substring.startIndex
    while digitsEnd < substring.endIndex, substring[digitsEnd].wholeNumberValue != nil {
      digitsEnd = substring.index(after: digitsEnd)
    }
    guard digitsEnd < substring.endIndex,
          substring[digitsEnd] == "." || substring[digitsEnd] == ")" else {
      return false
    }
    let separator = substring.index(after: digitsEnd)
    guard separator < substring.endIndex,
          substring[separator] == " " || substring[separator] == "\t" else {
      return false
    }
    substring = substring[substring.index(after: separator)..<substring.endIndex]
    _ = consumeTaskListCheckbox(in: &substring)
    return true
  }

  private static func consumeTaskListCheckbox(in substring: inout Substring) -> Bool {
    guard substring.count >= 3 else { return false }
    let start = substring.startIndex
    let state = substring.index(after: start)
    let close = substring.index(after: state)
    guard substring[start] == "[",
          substring[close] == "]",
          substring[state] == " " || substring[state] == "x" || substring[state] == "X" else {
      return false
    }
    let separator = substring.index(after: close)
    guard separator < substring.endIndex,
          substring[separator] == " " || substring[separator] == "\t" else {
      return false
    }
    substring = substring[substring.index(after: separator)..<substring.endIndex]
    return true
  }

  private static func looksLikeLiteralDollarPrefix(
    contentStart: String.Index,
    in input: String
  ) -> Bool {
    var tokenEnd = contentStart
    while tokenEnd < input.endIndex {
      let character = input[tokenEnd]
      if character == "$" || character.isWhitespace {
        break
      }
      tokenEnd = input.index(after: tokenEnd)
    }

    guard tokenEnd > contentStart else { return false }
    let prefix = String(input[contentStart..<tokenEnd])
    guard prefix.allSatisfy(isIdentifierLike) ||
            looksLikeCurrencyAmount(prefix) ||
            looksLikeLiteralPathToken(prefix) else {
      return false
    }

    var cursor = tokenEnd
    while cursor < input.endIndex {
      let character = input[cursor]
      if character == "\n" {
        return true
      }
      if character == "$" {
        return false
      }
      if character != " " && character != "\t" {
        break
      }
      cursor = input.index(after: cursor)
    }

    guard cursor < input.endIndex else { return true }
    let continuation = String(input[cursor..<input.endIndex])
    if continuationStartsLikeMath(continuation) {
      return false
    }
    return continuationPrefix(in: continuation).count > 1
  }

  private static func looksLikeDelimitedLiteralPrefix(
    openingDollar: String.Index,
    contentStart: String.Index,
    in input: String
  ) -> Bool {
    guard openingDollar > input.startIndex else { return false }
    let previous = input[input.index(before: openingDollar)]

    if literalDollarPrecedingCharacters.contains(previous) {
      let probe = literalTokenProbe(
        startingAt: contentStart,
        in: input,
        extraTerminators: ["\"", "'", "<", ">", ")", "]"]
      )
      return looksLikeLiteralToken(probe.token)
    }

    if previous == ">" {
      let probe = literalTokenProbe(
        startingAt: contentStart,
        in: input,
        extraTerminators: ["<"]
      )
      return probe.boundary == "<" && looksLikeLiteralToken(probe.token)
    }

    return false
  }

  private static func literalTokenProbe(
    startingAt start: String.Index,
    in input: String,
    extraTerminators: Set<Character>
  ) -> (token: String, boundary: Character?) {
    var end = start
    while end < input.endIndex {
      let character = input[end]
      if character == "$" || character.isWhitespace || extraTerminators.contains(character) {
        break
      }
      end = input.index(after: end)
    }
    return (String(input[start..<end]), end < input.endIndex ? input[end] : nil)
  }

  private static func shellInterpolationSuffix(in input: String, startingAt index: String.Index) -> String {
    guard index < input.endIndex else { return "" }
    var cursor = index
    while cursor < input.endIndex {
      let character = input[cursor]
      guard isIdentifierLike(character) || character == ":" || character == "/" || character == "." || character == "-" else {
        break
      }
      cursor = input.index(after: cursor)
    }
    guard cursor > index else { return "" }
    return String(input[index..<cursor])
  }

  private static func looksLikeShellVariableSequence(content: String, suffix: String) -> Bool {
    guard !suffix.isEmpty else { return false }
    guard let first = content.first, isIdentifierLike(first) else { return false }
    guard content.contains(where: isShellPathSeparator) else { return false }

    let prefixComponent = content.split(whereSeparator: isShellPathSeparator).first ?? ""
    let suffixComponent = suffix.split(whereSeparator: isShellPathSeparator).first ?? ""
    guard prefixComponent.count > 1, suffixComponent.count > 1 else { return false }

    return content.allSatisfy { isIdentifierLike($0) || isShellPathSeparator($0) } &&
      suffix.allSatisfy { isIdentifierLike($0) || isShellPathSeparator($0) }
  }

  private static func looksLikeCurrencyPair(content: String, suffix: String) -> Bool {
    guard let separator = content.last, separator == "-" || separator == "/" else { return false }
    let leadingAmount = String(content.dropLast())
    let trailingAmount = currencyAmountPrefix(in: suffix)
    guard !trailingAmount.isEmpty else { return false }
    return looksLikeCurrencyAmount(leadingAmount) && looksLikeCurrencyAmount(trailingAmount)
  }

  private static func looksLikeCurrencyFragment(_ content: String) -> Bool {
    guard !content.isEmpty else { return false }
    if looksLikeCurrencyAmount(content) {
      return true
    }

    guard let separator = content.last, separator == "-" || separator == "/" else { return false }
    return looksLikeCurrencyAmount(String(content.dropLast()))
  }

  private static func currencyAmountPrefix(in text: String) -> String {
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

  private static func looksLikeCurrencyAmount(_ text: String) -> Bool {
    let amount = currencyAmountPrefix(in: text)
    return !amount.isEmpty && amount.count == text.count
  }

  private static func continuationStartsLikeMath(_ continuation: String) -> Bool {
    guard let first = continuation.first else { return false }
    if first == "\\" || first.wholeNumberValue != nil {
      return true
    }
    return mathContinuationPrefixes.contains(first)
  }

  private static func continuationPrefix(in continuation: String) -> String {
    var token = ""
    for character in continuation {
      guard isIdentifierLike(character) else { break }
      token.append(character)
    }
    return token
  }

  private static func isShellPathSeparator(_ character: Character) -> Bool {
    character == ":" || character == "/" || character == "." || character == "-"
  }

  private static func isIdentifierLike(_ character: Character) -> Bool {
    character == "_" || character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
  }

  private static func looksLikeLiteralPathToken(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    guard text.contains(where: literalPathSeparators.contains) else { return false }
    guard let first = text.first, isIdentifierLike(first) else { return false }
    return text.allSatisfy { isIdentifierLike($0) || literalPathSeparators.contains($0) }
  }

  private static func looksLikeLiteralToken(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    return text.allSatisfy(isIdentifierLike) ||
      looksLikeCurrencyAmount(text) ||
      looksLikeLiteralPathToken(text)
  }

  private static func processingUnprotectedMarkdownSegments(
    in input: String,
    transform: (String) -> String
  ) -> String {
    let protectedRanges = mergedProtectedMarkdownRanges(in: input)
    guard !protectedRanges.isEmpty else {
      return transform(input)
    }

    var output = ""
    output.reserveCapacity(input.count)
    var cursor = input.startIndex
    for range in protectedRanges {
      if cursor < range.lowerBound {
        output += transform(String(input[cursor..<range.lowerBound]))
      }
      output += input[range]
      cursor = range.upperBound
    }
    if cursor < input.endIndex {
      output += transform(String(input[cursor..<input.endIndex]))
    }
    return output
  }

  private static func mergedProtectedMarkdownRanges(in input: String) -> [Range<String.Index>] {
    var ranges: [Range<String.Index>] = []
    ranges.append(contentsOf: fencedCodeRanges(in: input))
    ranges.append(contentsOf: inlineCodeRanges(in: input))
    ranges.append(contentsOf: linkDestinationRanges(in: input))
    ranges.append(contentsOf: htmlTagRanges(in: input))

    let sorted = ranges
      .filter { !$0.isEmpty }
      .sorted { $0.lowerBound < $1.lowerBound }

    var merged: [Range<String.Index>] = []
    for range in sorted {
      guard let last = merged.last else {
        merged.append(range)
        continue
      }
      if range.lowerBound <= last.upperBound {
        merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
      } else {
        merged.append(range)
      }
    }
    return merged
  }

  private static func fencedCodeRanges(in input: String) -> [Range<String.Index>] {
    guard input.range(of: "```") != nil || input.range(of: "~~~") != nil else {
      return []
    }

    var ranges: [Range<String.Index>] = []
    var lineStart = input.startIndex

    while lineStart < input.endIndex {
      let lineEnd = input[lineStart...].firstIndex(of: "\n") ?? input.endIndex
      let nextLineStart = lineEnd < input.endIndex ? input.index(after: lineEnd) : input.endIndex

      guard let openingFence = fenceMarker(in: input[lineStart..<lineEnd]) else {
        lineStart = nextLineStart
        continue
      }

      var scanLineStart = nextLineStart
      var rangeEnd = input.endIndex
      while scanLineStart < input.endIndex {
        let scanLineEnd = input[scanLineStart...].firstIndex(of: "\n") ?? input.endIndex
        let afterScanLine = scanLineEnd < input.endIndex ? input.index(after: scanLineEnd) : input.endIndex
        if let closingFence = fenceMarker(in: input[scanLineStart..<scanLineEnd]),
           closingFence.character == openingFence.character,
           closingFence.count >= openingFence.count,
           closingFence.isClosingFence {
          rangeEnd = afterScanLine
          break
        }
        scanLineStart = afterScanLine
      }

      ranges.append(lineStart..<rangeEnd)
      lineStart = rangeEnd
    }

    return ranges
  }

  private static func inlineCodeRanges(in input: String) -> [Range<String.Index>] {
    guard input.contains("`") else {
      return []
    }

    var ranges: [Range<String.Index>] = []
    var index = input.startIndex

    while index < input.endIndex {
      guard input[index] == "`" else {
        index = input.index(after: index)
        continue
      }

      let tickCount = repeatedCharacterCount(from: index, in: input, character: "`")
      let contentStart = input.index(index, offsetBy: tickCount)
      var scanIndex = contentStart
      var closingEnd: String.Index?

      while scanIndex < input.endIndex {
        if input[scanIndex] == "`",
           repeatedCharacterCount(from: scanIndex, in: input, character: "`") == tickCount {
          closingEnd = input.index(scanIndex, offsetBy: tickCount)
          break
        }
        scanIndex = input.index(after: scanIndex)
      }

      guard let closingEnd else {
        index = contentStart
        continue
      }

      ranges.append(index..<closingEnd)
      index = closingEnd
    }

    return ranges
  }

  private static func linkDestinationRanges(in input: String) -> [Range<String.Index>] {
    guard input.range(of: "](") != nil else {
      return []
    }

    var ranges: [Range<String.Index>] = []
    var index = input.startIndex

    while index < input.endIndex {
      guard input[index] == "]" else {
        index = input.index(after: index)
        continue
      }

      let openParen = input.index(after: index)
      guard openParen < input.endIndex, input[openParen] == "(" else {
        index = openParen
        continue
      }

      var depth = 1
      var scanIndex = input.index(after: openParen)
      while scanIndex < input.endIndex {
        if input[scanIndex] == "\n" {
          break
        }
        if input[scanIndex] == "(",
           !isEscapedCharacter(at: scanIndex, in: input) {
          depth += 1
        } else if input[scanIndex] == ")",
                  !isEscapedCharacter(at: scanIndex, in: input) {
          depth -= 1
          if depth == 0 {
            let closeParen = input.index(after: scanIndex)
            ranges.append(openParen..<closeParen)
            index = closeParen
            break
          }
        }
        scanIndex = input.index(after: scanIndex)
      }

      if scanIndex >= input.endIndex || input[scanIndex] == "\n" {
        index = scanIndex
      }
    }

    return ranges
  }

  private static func htmlTagRanges(in input: String) -> [Range<String.Index>] {
    guard input.contains("<") else {
      return []
    }

    var ranges: [Range<String.Index>] = []
    var index = input.startIndex

    while index < input.endIndex {
      guard input[index] == "<",
            !isEscapedCharacter(at: index, in: input) else {
        index = input.index(after: index)
        continue
      }

      let tagStart = input.index(after: index)
      guard tagStart < input.endIndex,
            isLikelyHtmlTagStart(input[tagStart]) else {
        index = tagStart
        continue
      }

      guard let tagEnd = input[tagStart...].firstIndex(of: ">") else {
        index = tagStart
        continue
      }

      ranges.append(index..<input.index(after: tagEnd))
      index = input.index(after: tagEnd)
    }

    return ranges
  }

  private static func fenceMarker(in line: Substring) -> (character: Character, count: Int, isClosingFence: Bool)? {
    var index = line.startIndex
    var spaces = 0
    while index < line.endIndex, line[index] == " ", spaces < 4 {
      spaces += 1
      index = line.index(after: index)
    }
    guard spaces <= 3, index < line.endIndex else {
      return nil
    }

    let marker = line[index]
    guard marker == "`" || marker == "~" else {
      return nil
    }

    var markerEnd = index
    var count = 0
    while markerEnd < line.endIndex, line[markerEnd] == marker {
      count += 1
      markerEnd = line.index(after: markerEnd)
    }
    guard count >= 3 else {
      return nil
    }

    let rest = line[markerEnd..<line.endIndex]
    return (marker, count, rest.allSatisfy(\.isWhitespace))
  }

  private static func repeatedCharacterCount(from index: String.Index, in input: String, character: Character) -> Int {
    var count = 0
    var cursor = index
    while cursor < input.endIndex, input[cursor] == character {
      count += 1
      cursor = input.index(after: cursor)
    }
    return count
  }

  private static func isEscapedCharacter(at index: String.Index, in input: String) -> Bool {
    var backslashCount = 0
    var current = index

    while current > input.startIndex {
      current = input.index(before: current)
      guard input[current] == "\\" else {
        break
      }
      backslashCount += 1
    }

    return backslashCount % 2 == 1
  }

  private static func isLikelyHtmlTagStart(_ character: Character) -> Bool {
    character.isLetter || character == "/" || character == "!" || character == "?"
  }
}

extension String {

  func filteringUnsupportedSyntaxes() -> String {
    return self
      .replacingfrac()
      .replacingPrime()
      .replacingVector()
      .replacingImplies()
      .replacingHarpoons()
      .replacingDots()
      .strippingBracketSizeCommands()
  }

  /// Replacing `dfrac` and `tfac` which is unsupported into simple `frac`
  func replacingfrac() -> String {
    return self
      .replacing(LaTexPreProcessorImpl.dfracLatex, with: "\\frac")
      .replacing(LaTexPreProcessorImpl.tfracLatex, with: "\\frac")
  }

  /// Replacing `'` which is unsupported into `^prime`
  func replacingPrime() -> String {
    return self.replacing(LaTexPreProcessorImpl.primeLatex, with: "^\\prime")
  }

  /// Replacing `overrightarrow` which is unsupported into `vec`
  func replacingVector() -> String {
    return self.replacing(LaTexPreProcessorImpl.vectorLatex, with: "\\vec")
  }

  /// Replacing `implies` which is unsupported into `Rightarrow`
  func replacingImplies() -> String {
    return self.replacing(LaTexPreProcessorImpl.rightArrowLatex, with: "\\Rightarrow")
  }

  /// Replacing `harpoons` which is unsupported into `Leftrightarrow`
  func replacingHarpoons() -> String {
    return self.replacing(LaTexPreProcessorImpl.harpoonsLatex, with: "\\Leftrightarrow")
  }

  /// Replacing `dots` which is unsupported into `ldots`
  func replacingDots() -> String {
    return self.replacing(LaTexPreProcessorImpl.dotsLatex, with: "\\ldots")
  }

  /// Stripping commands to specify bracket sizes(`\Biggl` etc) which is unsupported
  func strippingBracketSizeCommands() -> String {
    return self.replacing(LaTexPreProcessorImpl.bracketSize, with: "")
  }
}
