import SwiftUI
import XCTest
@testable import SwiftStreamingMarkdown

#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class MarkdownRenderingRegressionTests: XCTestCase {
  func testInlineDollarMathIsWrappedForRaTeXRendering() {
    let processor = LaTexPreProcessorImpl()

    let processed = processor.processInlineMath(input: "Inline $x^2 + y^2$ text")

    XCTAssertEqual(processed, #"Inline `\(x^2 + y^2\)` text"#)
  }

  func testInlineDollarMathDoesNotConsumeEscapedOrBlockDollarDelimiters() {
    let processor = LaTexPreProcessorImpl()

    let processed = processor.processInlineMath(input: #"Cost is \$5 and block $$x^2$$ stays block"#)

    XCTAssertEqual(processed, #"Cost is \$5 and block $$x^2$$ stays block"#)
  }

  func testInlineDollarMathPreservesCurrencyText() {
    let processor = LaTexPreProcessorImpl()
    let input = "Cost is $5-$10/month and revenue moved from $1,200 to $1,500."

    let processed = processor.processInlineMath(input: input)

    XCTAssertEqual(processed, input)
  }

  func testDisplayEnvironmentMathWithoutDelimitersBecomesBlockMath() {
    let processor = LaTexPreProcessorImpl()

    let processed = processor.process(input: #"""
\begin{align}
a&=b+c\\
d&=e
\end{align}

\begin{cases}
x, & x > 0\\
0, & x \le 0
\end{cases}
"""#)

    XCTAssertTrue(processed.contains("```blockmath\n\\begin{align}"))
    XCTAssertTrue(processed.contains("\\end{align}\n```"))
    XCTAssertTrue(processed.contains("```blockmath\n\\begin{cases}"))
    XCTAssertTrue(processed.contains("\\end{cases}\n```"))
  }

  func testDelimitedDisplayEnvironmentDoesNotBecomeNestedBlockMath() {
    let processor = LaTexPreProcessorImpl()

    let processed = processor.process(input: #"""
\[
\begin{align}
a&=b
\end{align}
\]
"""#)

    XCTAssertEqual(processed.components(separatedBy: "```blockmath").count - 1, 1)
    XCTAssertTrue(processed.contains("\\begin{align}"))
    XCTAssertFalse(processed.contains("```blockmath\n```blockmath"))
  }

  func testLatexPreprocessorPreservesCodeAndLinkLiterals() {
    let processor = LaTexPreProcessorImpl()

    let input = #"""
`let price = "$5"` and inline \(code)

```swift
let formula = "$x^2$"
let slash = "\(x)"
```

[math link](https://example.com/$x$/\(y\))

Actual math $x^2$ and \(y^2\).
"""#

    let processed = processor.process(input: input)

    XCTAssertTrue(processed.contains(#"`let price = "$5"` and inline \(code)"#))
    XCTAssertTrue(processed.contains(#"let formula = "$x^2$""#))
    XCTAssertTrue(processed.contains(#"let slash = "\(x)""#))
    XCTAssertTrue(processed.contains(#"[math link](https://example.com/$x$/\(y\))"#))
    XCTAssertTrue(processed.contains(#"Actual math `\(x^2\)` and `\(y^2\)`."#))
  }

  func testBoxedLatexIsPreservedForRaTeX() {
    let processor = LaTexPreProcessorImpl()

    let processed = processor.processBlockMath(input: #"\[\boxed{E = mc^2}\]"#)

    XCTAssertTrue(processed.contains(#"\boxed{E = mc^2}"#))
  }

  func testRaTeXResolvesDynamicPrimaryTextColorForAppearance() {
    let color = MarkdownRenderConfig.defaultPrimaryTextColor

    let light = RaTeXMathRendering.ratexColor(from: color, colorScheme: .light)
    XCTAssertLessThan(light.red, 0.2)
    XCTAssertLessThan(light.green, 0.2)
    XCTAssertLessThan(light.blue, 0.2)

    let dark = RaTeXMathRendering.ratexColor(from: color, colorScheme: .dark)
    XCTAssertGreaterThan(dark.red, 0.8)
    XCTAssertGreaterThan(dark.green, 0.8)
    XCTAssertGreaterThan(dark.blue, 0.8)
  }

  func testCodeBlockSearchHighlightMarksMatchingRuns() throws {
    let attributed = AttributedString("let token = token")
      .applyingSearchHighlight(query: "token")
    guard let range = attributed.range(of: "token") else {
      return XCTFail("Expected a token match")
    }

    XCTAssertNotNil(attributed[range].backgroundColor)
  }

  @MainActor
  func testTableHeaderWithAttachmentUsesAttachmentCapableContent() {
    let attachmentHeading = NSMutableAttributedString(string: "x ")
    attachmentHeading.append(NSAttributedString(attachment: NSTextAttachment()))

    let table = TableView(
      headings: [attachmentHeading],
      rows: [[NSMutableAttributedString(string: "value")]]
    )

    guard case .containsAttachment = table.headings[0] else {
      return XCTFail("Expected table heading with attachment to use ParagraphView-capable content")
    }
  }

  func testBuiltInLabelsDoNotRequirePackageResources() {
    XCTAssertEqual(String.codeCopyLabel, "Copy")
    XCTAssertEqual(String.codeCopiedLabel, "Copied")
    XCTAssertEqual(String.markdownList(length: "3"), "List with 3 items")
  }

  func testCompletedParseDoesNotSpeculativelyRewriteIdentifiersOrLiteralPipes() async {
    let parser = MarkdownParserImpl()
    let markdown = """
Set OPENAI_API_KEY

| grep token
"""

    let renderable = await parser.parse(text: markdown, config: .default)
    let renderedText = renderable.attributedStrings
      .map(\.string)
      .joined(separator: "\n")

    XCTAssertTrue(renderedText.contains("OPENAI_API_KEY"))
    XCTAssertTrue(renderedText.contains("| grep token"))
  }

  func testImageInlineNodePreservesAltTextAndLink() async {
    let parser = MarkdownParserImpl()
    let renderable = await parser.parse(
      text: "Before ![Chart](https://example.com/chart.png) after",
      config: .default
    )

    let attributed = renderable.attributedStrings
      .first { $0.string.contains("Chart") }

    guard let attributed else {
      return XCTFail("Expected image alt text to remain visible")
    }

    let range = (attributed.string as NSString).range(of: "Chart")
    XCTAssertNotEqual(range.location, NSNotFound)
    let link = attributed.attribute(.link, at: range.location, effectiveRange: nil) as? URL
    XCTAssertEqual(link?.absoluteString, "https://example.com/chart.png")
  }

  func testSizeCategoryAffectsParseKey() {
    let normal = MarkdownRenderConfig.defaultConfig(sizeCategory: .large)
    let accessibility = MarkdownRenderConfig.defaultConfig(sizeCategory: .accessibilityExtraExtraLarge)

    XCTAssertNotEqual(normal.parseAffectingKey, accessibility.parseAffectingKey)
  }

  func testColorSchemeAffectsParseKey() {
    let light = MarkdownRenderConfig.default.withColorScheme(value: .light)
    let dark = MarkdownRenderConfig.default.withColorScheme(value: .dark)

    XCTAssertNotEqual(light.parseAffectingKey, dark.parseAffectingKey)
  }

  #if os(macOS)
  func testMacSizeCategoryChangesResolvedFonts() {
    let normal = MarkdownRenderConfig.defaultConfig(sizeCategory: .large)
    let accessibility = MarkdownRenderConfig.defaultConfig(sizeCategory: .accessibilityExtraExtraLarge)

    XCTAssertNotEqual(normal.paragraphStyle.textFonts.normal.pointSize, accessibility.paragraphStyle.textFonts.normal.pointSize)
    XCTAssertNotEqual(normal.inlineStyle.codeTextFont.pointSize, accessibility.inlineStyle.codeTextFont.pointSize)
  }
  #endif

  @MainActor
  func testStreamedParserSpeculativelyRewritesPartialTable() async throws {
    let source = TestStreamedMarkdownSource()
    let controller = StreamedMarkdownController(
      source: source,
      config: MarkdownRenderConfig.default.withSpeculativeRewrite(value: true)
    )
    controller.start()
    defer { controller.end() }

    source.send("""
Intro paragraph.

| Name | Value |
""")

    for _ in 0..<100 {
      let renderedText = controller.markdownToRender.attributedStrings
        .map(\.string)
        .joined(separator: "\n")
      if renderedText.contains("Intro paragraph.") {
        XCTAssertFalse(renderedText.contains("| Name | Value |"))
        return
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTFail("Timed out waiting for streamed markdown render")
  }

  #if os(macOS)
  @MainActor
  func testMacParagraphTextStorageRemovesInternalAttributesBeforeDrawing() {
    let attributed = NSMutableAttributedString(string: "Text")
    attributed.addAttributes([
      .font: Typography.baseTextFonts.normal,
      .foregroundColor: MarkdownRenderConfig.defaultPrimaryTextColor,
      .typography: Typography.baseTextFonts
    ], range: NSRange(location: 0, length: attributed.length))

    let textView = ParagraphNSTextView()
    textView.setParagraphContents(attributed)

    let attributes = textView.textStorage?.attributes(at: 0, effectiveRange: nil) ?? [:]
    XCTAssertNil(attributes[.typography])
    XCTAssertTrue(attributes[.font] is NSFont)
    XCTAssertTrue(attributes[.foregroundColor] is NSColor)
  }
  #endif
}

@MainActor
private final class TestStreamedMarkdownSource: @preconcurrency StreamedMarkdownSource {
  private var latestMarkdown: String?
  private var continuation: AsyncStream<String>.Continuation?

  var text: AsyncStream<String> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      self.continuation = continuation
      if let latestMarkdown {
        continuation.yield(latestMarkdown)
      }
    }
  }

  func send(_ markdown: String) {
    latestMarkdown = markdown
    continuation?.yield(markdown)
  }
}
