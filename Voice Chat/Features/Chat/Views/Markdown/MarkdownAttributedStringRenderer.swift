//
//  MarkdownAttributedStringRenderer.swift
//  Voice Chat
//

@preconcurrency import Foundation
import Markdown

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

struct MarkdownRenderResult: @unchecked Sendable {
    let attributedString: NSAttributedString
    let attachments: [MarkdownAttachment]
}

#if os(macOS)
@MainActor
#endif
final class MarkdownAttributedStringRenderer {
    // Prefix table-cell text so the Markdown parser stays in paragraph/inline mode.
    private static let tableCellInlinePrefix = "\u{E002}"
    private let style: MarkdownStyle
    private let maxImageWidth: CGFloat?
    private var attachments: [MarkdownAttachment] = []
    private var mathResult = MarkdownMathPreprocessor.Result(markdown: "", segments: [])

    init(style: MarkdownStyle, maxImageWidth: CGFloat?) {
        self.style = style
        self.maxImageWidth = maxImageWidth
    }

    func render(markdown: String) -> MarkdownRenderResult {
        attachments = []
        mathResult = MarkdownMathPreprocessor.preprocess(markdown)
        let parsedDocument = Document(parsing: mathResult.markdown)
        let document = restoreNonTextMathFields(in: parsedDocument)
        let output = NSMutableAttributedString()
        renderChildrenBlocks(document, into: output, listDepth: 0, baseAttributes: style.baseAttributes)
        finalizeRenderedOutput(output)
        return MarkdownRenderResult(attributedString: output, attachments: attachments)
    }

    func renderTableCell(
        markdown: String,
        attributes: [NSAttributedString.Key: Any],
        alignment: NSTextAlignment
    ) -> MarkdownRenderResult {
        attachments = []
        mathResult = MarkdownMathPreprocessor.preprocess(markdown)
        // Keep the first line from being reinterpreted as a block-level Markdown construct.
        let parsedDocument = Document(parsing: Self.tableCellInlinePrefix + mathResult.markdown)
        let document = restoreNonTextMathFields(in: parsedDocument)
        let output = NSMutableAttributedString()
        var didRenderChild = false

        for child in document.children {
            if didRenderChild {
                output.append(NSAttributedString(string: " ", attributes: attributes))
            }

            if let paragraph = child as? Paragraph {
                output.append(renderInlineChildren(paragraph, attributes: attributes, context: .table))
            } else if let heading = child as? Heading {
                output.append(renderInlineChildren(heading, attributes: attributes, context: .table))
            } else if let customBlock = child as? CustomBlock {
                output.append(renderInlineChildren(customBlock, attributes: attributes, context: .table))
            } else {
                output.append(renderInlineChildren(child, attributes: attributes, context: .table))
            }
            didRenderChild = true
        }

        if output.string.hasPrefix(Self.tableCellInlinePrefix) {
            output.deleteCharacters(
                in: NSRange(location: 0, length: Self.tableCellInlinePrefix.utf16.count)
            )
        }

        if output.length == 0 {
            output.append(NSAttributedString(string: markdown, attributes: attributes))
        }

        let paragraphStyle = tableCellParagraphStyle(alignment: alignment)
        output.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: output.length))
        return MarkdownRenderResult(attributedString: output, attachments: attachments)
    }

    private func renderChildrenBlocks(
        _ parent: Markup,
        into output: NSMutableAttributedString,
        listDepth: Int,
        baseAttributes: [NSAttributedString.Key: Any]
    ) {
        var isFirst = true
        for child in parent.children {
            if !isFirst {
                output.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
            renderBlock(child, into: output, listDepth: listDepth, baseAttributes: baseAttributes)
            isFirst = false
        }
    }

    private func restoreNonTextMathFields(in document: Document) -> Document {
        guard !mathResult.segments.isEmpty else { return document }
        var restorer = MarkdownMathFieldRestorer(mathResult: mathResult)
        return restorer.visit(document) as? Document ?? document
    }

    private func renderBlock(
        _ markup: Markup,
        into output: NSMutableAttributedString,
        listDepth: Int,
        baseAttributes: [NSAttributedString.Key: Any]
    ) {
        if let paragraph = markup as? Paragraph {
            if let displayMath = renderStandaloneDisplayMathParagraph(paragraph, baseAttributes: baseAttributes) {
                output.append(displayMath)
                return
            }
            let content = renderInlineChildren(paragraph, attributes: baseAttributes)
            content.addAttribute(
                .paragraphStyle,
                value: style.paragraphStyle(),
                range: NSRange(location: 0, length: content.length)
            )
            output.append(content)
        } else if let heading = markup as? Heading {
            var attrs = baseAttributes
            attrs[.font] = style.headingFont(level: heading.level)
            let content = renderInlineChildren(heading, attributes: attrs)
            content.addAttribute(
                .paragraphStyle,
                value: style.paragraphStyle(spacingBefore: style.blockSpacing, spacingAfter: style.paragraphSpacing),
                range: NSRange(location: 0, length: content.length)
            )
            output.append(content)
        } else if let codeBlock = markup as? CodeBlock {
            let rawLanguage = codeBlock.language?.trimmingCharacters(in: .whitespacesAndNewlines)
            let localeCode = currentLanguageCode()
            let usesChinese = localeCode.hasPrefix("zh")
            let defaultLanguageLabel = usesChinese ? "代码" : "CODE"
            let copyLabel = usesChinese ? "复制" : "Copy"
            let languageLabel = rawLanguage?.isEmpty == false ? rawLanguage! : defaultLanguageLabel
            let codeString = codeBlock.code.trimmingCharacters(in: .newlines)
            let headerFontSize = max(11, style.baseFont.pointSize * 0.75)
            let headerFont = MarkdownPlatformFont.systemFont(ofSize: headerFontSize, weight: .semibold)
            let codeStyle = MarkdownCodeBlockStyle(
                codeFont: style.codeFont,
                headerFont: headerFont,
                textColor: style.baseColor,
                headerTextColor: style.secondaryColor,
                backgroundColor: style.codeBlockBackground,
                headerBackground: style.codeBlockBackground,
                borderColor: style.tableBorderColor,
                copyTextColor: style.secondaryColor,
                copyBackground: MarkdownPlatformColor.clear,
                borderWidth: style.tableBorderWidth,
                cornerRadius: 10,
                codePadding: CGSize(width: 14, height: 12),
                headerPadding: CGSize(width: 12, height: 6)
            )
            let attachment = MarkdownCodeBlockAttachment(
                code: codeString,
                languageLabel: languageLabel,
                copyLabel: copyLabel,
                style: codeStyle,
                maxWidth: maxImageWidth ?? 0
            )
            attachments.append(attachment)
            primeAttachmentForMac(attachment)
            let result = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
            let paragraph = style.paragraphStyle(spacingBefore: style.blockSpacing, spacingAfter: style.blockSpacing)
            result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
            output.append(result)
        } else if let htmlBlock = markup as? HTMLBlock {
            var attrs = baseAttributes
            attrs[.font] = style.codeFont
            attrs[.foregroundColor] = style.baseColor
            attrs[.backgroundColor] = style.codeBlockBackground
            let paragraphStyle = style.paragraphStyle(
                spacingBefore: style.blockSpacing,
                spacingAfter: style.blockSpacing,
                firstLineHeadIndent: style.listIndent,
                headIndent: style.listIndent
            )
            attrs[.paragraphStyle] = paragraphStyle
            let htmlString = htmlBlock.rawHTML.trimmingCharacters(in: .newlines)
            output.append(NSAttributedString(string: htmlString, attributes: attrs))
        } else if let quote = markup as? BlockQuote {
            var attrs = baseAttributes
            let quoteTextColor = style.baseColor
            attrs[.foregroundColor] = quoteTextColor
            let content = NSMutableAttributedString()
            renderChildrenBlocks(quote, into: content, listDepth: listDepth, baseAttributes: attrs)
            let quoteStyle = MarkdownQuoteStyle(
                textColor: quoteTextColor,
                borderColor: style.quoteBorderColor,
                borderWidth: 3,
                padding: CGSize(width: 12, height: 6)
            )
            let attachment = MarkdownQuoteAttachment(
                content: content,
                style: quoteStyle,
                maxWidth: maxImageWidth ?? 0
            )
            attachments.append(attachment)
            primeAttachmentForMac(attachment)
            let result = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
            let paragraph = style.paragraphStyle(spacingBefore: style.blockSpacing, spacingAfter: style.blockSpacing)
            result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
            output.append(result)
        } else if let list = markup as? OrderedList {
            let items = list.children.compactMap { $0 as? ListItem }
            renderList(
                items,
                ordered: true,
                startIndex: Int(list.startIndex),
                into: output,
                listDepth: listDepth,
                baseAttributes: baseAttributes
            )
        } else if let list = markup as? UnorderedList {
            let items = list.children.compactMap { $0 as? ListItem }
            renderList(items, ordered: false, into: output, listDepth: listDepth, baseAttributes: baseAttributes)
        } else if let table = markup as? Markdown.Table {
            renderTable(table, into: output, baseAttributes: baseAttributes)
        } else if let customBlock = markup as? CustomBlock {
            renderChildrenBlocks(customBlock, into: output, listDepth: listDepth, baseAttributes: baseAttributes)
        } else if markup is ThematicBreak {
            let attachment = MarkdownRuleAttachment(
                color: style.ruleColor,
                thickness: style.tableBorderWidth,
                verticalPadding: max(4, style.baseFont.pointSize * 0.4),
                maxWidth: maxImageWidth ?? 0
            )
            attachments.append(attachment)
            primeAttachmentForMac(attachment)
            let result = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
            let paragraph = style.paragraphStyle(spacingBefore: style.blockSpacing, spacingAfter: style.blockSpacing)
            result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
            output.append(result)
        } else {
            let content = renderInlineChildren(markup, attributes: baseAttributes)
            if content.length > 0 {
                content.addAttribute(
                    .paragraphStyle,
                    value: style.paragraphStyle(),
                    range: NSRange(location: 0, length: content.length)
                )
                output.append(content)
            }
        }
    }

    private enum InlineRenderContext {
        case standard
        case table
    }

    private func renderInlineChildren(
        _ parent: Markup,
        attributes: [NSAttributedString.Key: Any],
        context: InlineRenderContext = .standard,
        rendersMath: Bool = true
    ) -> NSMutableAttributedString {
        let output = NSMutableAttributedString()
        var htmlLiteralDepth = 0
        for child in parent.children {
            let childRendersMath = rendersMath && htmlLiteralDepth == 0
            output.append(
                renderInline(
                    child,
                    attributes: attributes,
                    context: context,
                    rendersMath: childRendersMath
                )
            )
            if let inlineHTML = child as? InlineHTML {
                htmlLiteralDepth = max(0, htmlLiteralDepth + inlineHTMLLiteralDepthDelta(for: inlineHTML.rawHTML))
            }
        }
        return output
    }

    private func renderInline(
        _ markup: Markup,
        attributes: [NSAttributedString.Key: Any],
        context: InlineRenderContext,
        rendersMath: Bool
    ) -> NSAttributedString {
        if let text = markup as? Markdown.Text {
            if rendersMath {
                return renderTextWithMathPlaceholders(text.string, attributes: attributes, context: context)
            }
            let literal = mathResult.restoringOriginalMarkup(in: text.string) ?? text.string
            return NSAttributedString(string: literal, attributes: attributes)
        } else if let custom = markup as? CustomInline {
            if rendersMath {
                return renderTextWithMathPlaceholders(custom.text, attributes: attributes, context: context)
            }
            let literal = mathResult.restoringOriginalMarkup(in: custom.text) ?? custom.text
            return NSAttributedString(string: literal, attributes: attributes)
        } else if markup is SoftBreak {
            return NSAttributedString(string: " ", attributes: attributes)
        } else if markup is LineBreak {
            return NSAttributedString(string: "\n", attributes: attributes)
        } else if let html = markup as? InlineHTML {
            var attrs = attributes
            attrs[.font] = style.codeFont
            attrs[.backgroundColor] = style.inlineCodeBackground
            return NSAttributedString(string: html.rawHTML, attributes: attrs)
        } else if let emphasis = markup as? Emphasis {
            var attrs = attributes
            if let font = attributes[.font] as? MarkdownPlatformFont {
                attrs[.font] = italicFont(from: font)
            }
            return renderInlineChildren(emphasis, attributes: attrs, context: context, rendersMath: rendersMath)
        } else if let strong = markup as? Strong {
            var attrs = attributes
            if let font = attributes[.font] as? MarkdownPlatformFont {
                attrs[.font] = boldFont(from: font)
            }
            return renderInlineChildren(strong, attributes: attrs, context: context, rendersMath: rendersMath)
        } else if let strike = markup as? Strikethrough {
            var attrs = attributes
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.strikethroughColor] = style.secondaryColor
            return renderInlineChildren(strike, attributes: attrs, context: context, rendersMath: rendersMath)
        } else if let inlineCode = markup as? InlineCode {
            var attrs = attributes
            attrs[.font] = style.codeFont
            attrs[.backgroundColor] = style.inlineCodeBackground
            return NSAttributedString(string: inlineCode.code, attributes: attrs)
        } else if let symbolLink = markup as? SymbolLink {
            var attrs = attributes
            attrs[.font] = style.codeFont
            attrs[.foregroundColor] = style.linkColor
            return NSAttributedString(string: symbolLink.destination ?? "", attributes: attrs)
        } else if let link = markup as? Markdown.Link {
            var attrs = attributes
            attrs[.foregroundColor] = style.linkColor
            if let destination = link.destination {
                if let url = URL(string: destination) {
                    attrs[.link] = url
                } else {
                    attrs[.link] = destination
                }
            }
            return renderInlineChildren(link, attributes: attrs, context: context, rendersMath: rendersMath)
        } else if let inlineAttributes = markup as? InlineAttributes {
            return renderInlineChildren(inlineAttributes, attributes: attributes, context: context, rendersMath: rendersMath)
        } else if let image = markup as? Markdown.Image {
            let altText = plainTextFromMarkup(image).trimmingCharacters(in: .whitespacesAndNewlines)
            if context == .table {
                return NSAttributedString(string: altText, attributes: attributes)
            }
            let source = image.source ?? ""
            if source.isEmpty {
                return NSAttributedString(string: altText, attributes: attributes)
            }
            let attachment = MarkdownImageAttachment(
                source: source,
                altText: altText,
                maxWidth: maxImageWidth ?? 240
            )
            attachments.append(attachment)
            let result = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
            let paragraph = style.paragraphStyle(spacingBefore: style.blockSpacing, spacingAfter: style.blockSpacing)
            result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
            return result
        } else {
            return renderInlineChildren(markup, attributes: attributes, context: context, rendersMath: rendersMath)
        }
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

    private func renderList(
        _ items: [ListItem],
        ordered: Bool,
        startIndex: Int = 1,
        into output: NSMutableAttributedString,
        listDepth: Int,
        baseAttributes: [NSAttributedString.Key: Any]
    ) {
        var index = startIndex
        for (offset, item) in items.enumerated() {
            if offset > 0 {
                output.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
            let prefix = ordered ? "\(index)." : "•"
            let itemString = renderListItem(
                item,
                prefix: prefix,
                listDepth: listDepth,
                baseAttributes: baseAttributes
            )
            output.append(itemString)
            index += 1
        }
    }

    private func renderListItem(
        _ item: ListItem,
        prefix: String,
        listDepth: Int,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let prefixText = listItemPrefix(for: item, base: prefix) + " "
        var wroteContent = false
        for child in item.children {
            if wroteContent {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
            if let paragraph = child as? Paragraph {
                if let displayMath = renderListDisplayMathParagraph(
                    paragraph,
                    prefix: prefixText,
                    includeMarker: !wroteContent,
                    depth: listDepth,
                    baseAttributes: baseAttributes
                ) {
                    result.append(displayMath)
                    wroteContent = true
                    continue
                }
                let line = NSMutableAttributedString()
                line.append(NSAttributedString(string: prefixText, attributes: baseAttributes))
                line.append(renderInlineChildren(paragraph, attributes: baseAttributes))
                line.addAttribute(
                    .paragraphStyle,
                    value: listParagraphStyle(prefix: prefixText, depth: listDepth),
                    range: NSRange(location: 0, length: line.length)
                )
                result.append(line)
                wroteContent = true
            } else {
                let block = NSMutableAttributedString()
                renderBlock(child, into: block, listDepth: listDepth + 1, baseAttributes: baseAttributes)
                result.append(block)
                wroteContent = true
            }
        }
        if !wroteContent {
            let line = NSMutableAttributedString(string: prefixText, attributes: baseAttributes)
            line.addAttribute(
                .paragraphStyle,
                value: listParagraphStyle(prefix: prefixText, depth: listDepth),
                range: NSRange(location: 0, length: line.length)
            )
            result.append(line)
        }
        return result
    }

    private func renderListDisplayMathParagraph(
        _ paragraph: Paragraph,
        prefix: String,
        includeMarker: Bool,
        depth: Int,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString? {
        let displayMathStyle = listDisplayMathParagraphStyle(prefix: prefix, depth: depth)
        guard let displayMath = renderStandaloneDisplayMathParagraph(
            paragraph,
            baseAttributes: baseAttributes,
            paragraphStyle: displayMathStyle
        ) else {
            return nil
        }

        guard includeMarker else {
            return displayMath
        }

        let prefixLine = NSMutableAttributedString(string: prefix, attributes: baseAttributes)
        prefixLine.addAttribute(
            .paragraphStyle,
            value: listPrefixOnlyParagraphStyle(prefix: prefix, depth: depth),
            range: NSRange(location: 0, length: prefixLine.length)
        )

        let result = NSMutableAttributedString(attributedString: prefixLine)
        result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
        result.append(displayMath)
        return result
    }

    private func listItemPrefix(for item: ListItem, base: String) -> String {
        guard let checkbox = item.checkbox else { return base }
        let marker = checkbox == .checked ? "[x]" : "[ ]"
        return "\(base) \(marker)"
    }

    private func listIndentation(prefix: String, depth: Int) -> (base: CGFloat, content: CGFloat) {
        let indentBase = style.listIndent * CGFloat(depth)
        let prefixWidth = measureTextWidth(prefix, font: style.baseFont)
        return (indentBase, indentBase + prefixWidth)
    }

    private func listParagraphStyle(prefix: String, depth: Int) -> NSMutableParagraphStyle {
        let indentation = listIndentation(prefix: prefix, depth: depth)
        return style.paragraphStyle(
            spacingBefore: 0,
            spacingAfter: style.paragraphSpacing,
            firstLineHeadIndent: indentation.base,
            headIndent: indentation.content
        )
    }

    private func listPrefixOnlyParagraphStyle(prefix: String, depth: Int) -> NSMutableParagraphStyle {
        let indentation = listIndentation(prefix: prefix, depth: depth)
        return style.paragraphStyle(
            spacingBefore: 0,
            spacingAfter: 0,
            firstLineHeadIndent: indentation.base,
            headIndent: indentation.content
        )
    }

    private func listDisplayMathParagraphStyle(prefix: String, depth: Int) -> NSMutableParagraphStyle {
        let indentation = listIndentation(prefix: prefix, depth: depth)
        return style.paragraphStyle(
            spacingBefore: 0,
            spacingAfter: style.blockSpacing,
            firstLineHeadIndent: indentation.content,
            headIndent: indentation.content,
            alignment: .center
        )
    }

    private func renderTable(
        _ table: Markdown.Table,
        into output: NSMutableAttributedString,
        baseAttributes: [NSAttributedString.Key: Any]
    ) {
        let columnCount = table.maxColumnCount
        guard columnCount > 0 else { return }

        let alignments = table.columnAlignments
        var rows: [MarkdownTableRow] = []

        let headerCells = table.head.children.compactMap { $0 as? Markdown.Table.Cell }
        if !headerCells.isEmpty {
            var headerAttributes = baseAttributes
            if let font = baseAttributes[.font] as? MarkdownPlatformFont {
                headerAttributes[.font] = boldFont(from: font)
            }
            let headerSourceMarkdown = sourceMarkdown(for: table.head)
            let cells = buildTableCells(
                from: headerCells,
                columnCount: columnCount,
                attributes: headerAttributes,
                alignments: alignments
            )
            rows.append(MarkdownTableRow(cells: cells, isHeader: true, sourceMarkdown: headerSourceMarkdown))
        }

        for row in table.body.rows {
            let rowCells = row.children.compactMap { $0 as? Markdown.Table.Cell }
            let rowSourceMarkdown = sourceMarkdown(for: row)
            let cells = buildTableCells(
                from: rowCells,
                columnCount: columnCount,
                attributes: baseAttributes,
                alignments: alignments
            )
            rows.append(MarkdownTableRow(cells: cells, isHeader: false, sourceMarkdown: rowSourceMarkdown))
        }

        guard !rows.isEmpty else { return }

        let tableStyle = MarkdownTableStyle(
            baseFont: style.baseFont,
            headerBackground: style.tableHeaderBackground,
            stripeBackground: style.tableStripeBackground,
            borderColor: style.tableBorderColor,
            borderWidth: style.tableBorderWidth,
            cellPadding: style.tableCellPadding
        )
        let attachment = MarkdownTableAttachment(rows: rows, style: tableStyle, maxWidth: maxImageWidth ?? 0)
        attachments.append(attachment)
        primeAttachmentForMac(attachment)

        let result = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        let paragraph = style.paragraphStyle(spacingBefore: style.blockSpacing, spacingAfter: style.blockSpacing)
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        output.append(result)
    }

    private func sourceMarkdown(for markup: Markup) -> String? {
        guard let range = markup.range,
              let source = sourceMarkdownSubstring(in: mathResult.markdown, range: range)
        else { return nil }

        return mathResult.restoringOriginalMarkup(in: source)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sourceMarkdownSubstring(in source: String, range: SourceRange) -> String? {
        let lineStartOffsets = sourceUTF8LineStartOffsets(in: source)
        let totalLength = source.utf8.count
        guard let lowerBound = utf8Offset(
            for: range.lowerBound,
            lineStartOffsets: lineStartOffsets,
            totalLength: totalLength
        ),
        let upperBound = utf8Offset(
            for: range.upperBound,
            lineStartOffsets: lineStartOffsets,
            totalLength: totalLength
        ) else { return nil }

        let utf8 = source.utf8
        guard let lowerIndex = utf8.index(utf8.startIndex, offsetBy: lowerBound, limitedBy: utf8.endIndex),
              let upperIndex = utf8.index(utf8.startIndex, offsetBy: upperBound, limitedBy: utf8.endIndex) else {
            return nil
        }
        return String(decoding: utf8[lowerIndex..<upperIndex], as: UTF8.self)
    }

    private func sourceUTF8LineStartOffsets(in source: String) -> [Int] {
        var offsets: [Int] = [0]
        var utf8Offset = 0
        for byte in source.utf8 {
            utf8Offset += 1
            if byte == 0x0A {
                offsets.append(utf8Offset)
            }
        }
        return offsets
    }

    private func utf8Offset(
        for location: SourceLocation,
        lineStartOffsets: [Int],
        totalLength: Int
    ) -> Int? {
        guard location.line > 0,
              location.column > 0,
              location.line <= lineStartOffsets.count
        else { return nil }

        let lineStartOffset = lineStartOffsets[location.line - 1]
        let offset = lineStartOffset + location.column - 1
        guard offset >= 0, offset <= totalLength else { return nil }
        return offset
    }

    private func buildTableCells(
        from cells: [Markdown.Table.Cell],
        columnCount: Int,
        attributes: [NSAttributedString.Key: Any],
        alignments: [Markdown.Table.ColumnAlignment?]
    ) -> [NSAttributedString] {
        var result: [NSAttributedString] = []
        result.reserveCapacity(columnCount)
        for column in 0..<columnCount {
            let cell = column < cells.count ? cells[column] : nil
            let alignment = tableAlignment(column < alignments.count ? alignments[column] : nil)
            result.append(tableCellAttributedString(cell, attributes: attributes, alignment: alignment))
        }
        return result
    }

    private func tableCellAttributedString(
        _ cell: Markdown.Table.Cell?,
        attributes: [NSAttributedString.Key: Any],
        alignment: NSTextAlignment
    ) -> NSAttributedString {
        let content: NSMutableAttributedString
        if let cell {
            content = renderInlineChildren(cell, attributes: attributes, context: .table)
        } else {
            content = NSMutableAttributedString(string: "", attributes: attributes)
        }
        let paragraphStyle = tableCellParagraphStyle(alignment: alignment)
        content.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: content.length))
        return content
    }

    private func tableCellParagraphStyle(alignment: NSTextAlignment) -> NSMutableParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = style.lineSpacing
        return paragraphStyle
    }

    private func tableAlignment(_ alignment: Markdown.Table.ColumnAlignment?) -> NSTextAlignment {
        switch alignment {
        case .left:
            return .left
        case .center:
            return .center
        case .right:
            return .right
        case .none:
            return .natural
        }
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

    private func renderStandaloneDisplayMathParagraph(
        _ paragraph: Paragraph,
        baseAttributes: [NSAttributedString.Key: Any],
        paragraphStyle: NSParagraphStyle? = nil
    ) -> NSAttributedString? {
        guard paragraph.children.allSatisfy({ standaloneDisplayMathChildCanBypassInlineRendering($0) }) else {
            return nil
        }

        let plain = plainTextFromMarkup(paragraph)
        let runs = mathResult.runs(in: plain)
        guard runs.contains(where: {
            if case .segment = $0 { return true }
            return false
        }) else {
            return nil
        }

        for run in runs {
            switch run {
            case let .text(text):
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continue
                }
                return nil
            case let .segment(segment):
                guard segment.displayMode else { return nil }
            }
        }

        let resolvedParagraphStyle = paragraphStyle ?? style.paragraphStyle(
            spacingBefore: style.blockSpacing,
            spacingAfter: style.blockSpacing,
            alignment: .center
        )
        let output = NSMutableAttributedString()
        var isFirst = true
        for run in runs {
            guard case let .segment(segment) = run else { continue }
            if !isFirst {
                output.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
            let attachment = makeMathAttachment(segment: segment, attributes: baseAttributes, displayMode: true)
            let math = attributedMathAttachment(attachment, inheritedAttributes: baseAttributes)
            math.addAttribute(
                .paragraphStyle,
                value: resolvedParagraphStyle,
                range: NSRange(location: 0, length: math.length)
            )
            output.append(math)
            isFirst = false
        }
        return output
    }

    private func standaloneDisplayMathChildCanBypassInlineRendering(_ child: Markup) -> Bool {
        child is Markdown.Text ||
        child is CustomInline ||
        child is SoftBreak ||
        child is LineBreak
    }

    private func renderTextWithMathPlaceholders(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        context: InlineRenderContext
    ) -> NSAttributedString {
        let runs = mathResult.runs(in: text)
        guard runs.contains(where: {
            if case .segment = $0 { return true }
            return false
        }) else {
            return NSAttributedString(string: text, attributes: attributes)
        }

        let restoredText = mathResult.restoringOriginalMarkup(in: text) ?? text
        if let linkAware = renderTextByPreservingDetectedLinks(
            placeholderRuns: runs,
            literalText: restoredText,
            attributes: attributes,
            context: context
        ) {
            return linkAware
        }

        let output = NSMutableAttributedString()
        for run in runs {
            switch run {
            case let .text(fragment):
                if !fragment.isEmpty {
                    output.append(NSAttributedString(string: fragment, attributes: attributes))
                }
            case let .segment(segment):
                let attachment = makeMathAttachment(
                    segment: segment,
                    attributes: attributes,
                    // Mixed-content paragraphs are laid out inline, so display delimiters
                    // must degrade to inline math unless the paragraph was handled by the
                    // standalone display-math path above.
                    displayMode: false
                )
                let inlineMath = attributedMathAttachment(attachment, inheritedAttributes: attributes)
                if context == .table {
                    inlineMath.addAttribute(
                        .paragraphStyle,
                        value: tableCellParagraphStyle(alignment: .left),
                        range: NSRange(location: 0, length: inlineMath.length)
                    )
                }
                output.append(inlineMath)
            }
        }
        return output
    }

    private func renderTextByPreservingDetectedLinks(
        placeholderRuns: [MarkdownMathPreprocessor.Result.PlaceholderRun],
        literalText: String,
        attributes: [NSAttributedString.Key: Any],
        context: InlineRenderContext
    ) -> NSAttributedString? {
        guard let detector = Self.linkDetector else { return nil }
        let fullRange = NSRange(location: 0, length: (literalText as NSString).length)
        let matches = detector.matches(in: literalText, options: [], range: fullRange)
        guard !matches.isEmpty else { return nil }

        let linkRanges = matches.compactMap { Range($0.range, in: literalText) }
        let output = NSMutableAttributedString()
        var cursor = literalText.startIndex

        for run in placeholderRuns {
            let renderedText: String
            switch run {
            case let .text(text):
                renderedText = text
            case let .segment(segment):
                renderedText = segment.source
            }

            guard !renderedText.isEmpty else { continue }
            let nextCursor = literalText.index(cursor, offsetBy: renderedText.count)
            let runRange = cursor..<nextCursor

            switch run {
            case .text:
                output.append(NSAttributedString(string: renderedText, attributes: attributes))
            case let .segment(segment):
                if linkRanges.contains(where: { $0.overlaps(runRange) }) {
                    output.append(NSAttributedString(string: renderedText, attributes: attributes))
                } else {
                    let attachment = makeMathAttachment(
                        segment: segment,
                        attributes: attributes,
                        displayMode: false
                    )
                    let inlineMath = attributedMathAttachment(attachment, inheritedAttributes: attributes)
                    if context == .table {
                        inlineMath.addAttribute(
                            .paragraphStyle,
                            value: tableCellParagraphStyle(alignment: .left),
                            range: NSRange(location: 0, length: inlineMath.length)
                        )
                    }
                    output.append(inlineMath)
                }
            }

            cursor = nextCursor
        }

        return output
    }

    private static let linkDetector: NSDataDetector? = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    private func makeMathAttachment(
        segment: MarkdownMathSegment,
        attributes: [NSAttributedString.Key: Any],
        displayMode: Bool
    ) -> MarkdownMathAttachment {
        let baseFont = (attributes[.font] as? MarkdownPlatformFont) ?? style.baseFont
        let textColor = (attributes[.foregroundColor] as? MarkdownPlatformColor) ?? style.baseColor
        let attachment = MarkdownMathAttachment(
            segment: segment,
            style: MarkdownMathStyle(baseFont: baseFont, textColor: textColor),
            displayMode: displayMode,
            maxWidth: maxImageWidth ?? 0
        )
        attachments.append(attachment)
        primeAttachmentForMac(attachment)
        return attachment
    }

    private func attributedMathAttachment(
        _ attachment: MarkdownMathAttachment,
        inheritedAttributes: [NSAttributedString.Key: Any]
    ) -> NSMutableAttributedString {
        let output = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        guard !inheritedAttributes.isEmpty else { return output }
        var attachmentAttributes = inheritedAttributes
        attachmentAttributes.removeValue(forKey: .attachment)
        output.addAttributes(attachmentAttributes, range: NSRange(location: 0, length: output.length))
        return output
    }

    private func measureTextWidth(_ text: String, font: MarkdownPlatformFont) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attrs).width
    }

    private func primeAttachmentForMac(_ attachment: MarkdownAttachment) {
        #if os(macOS)
        guard !attachment.allowsTextAttachmentView else { return }
        let preferred = maxImageWidth ?? 320
        let width = preferred > 1 ? preferred : 320
        _ = attachment.attachmentBounds(
            for: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: width, height: 0),
            glyphPosition: .zero,
            characterIndex: 0
        )
        #else
        _ = attachment
        #endif
    }

    private func finalizeRenderedOutput(_ output: NSMutableAttributedString) {
        trimTrailingWhitespaceAndNewlines(output)
        removeTrailingParagraphSpacing(output)
    }

    private func trimTrailingWhitespaceAndNewlines(_ output: NSMutableAttributedString) {
        let whitespace = CharacterSet.whitespacesAndNewlines
        while output.length > 0 {
            let lastChar = (output.string as NSString).character(at: output.length - 1)
            guard let scalar = UnicodeScalar(UInt32(lastChar)),
                  whitespace.contains(scalar) else { break }
            output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
        }
    }

    private func removeTrailingParagraphSpacing(_ output: NSMutableAttributedString) {
        guard output.length > 0 else { return }
        let nsString = output.string as NSString
        let lastNewline = nsString.range(of: "\n", options: .backwards)
        let paragraphStart = (lastNewline.location == NSNotFound) ? 0 : (lastNewline.location + 1)
        guard paragraphStart < output.length else { return }

        let lastIndex = output.length - 1
        let paragraphStyle = (output.attribute(.paragraphStyle, at: lastIndex, effectiveRange: nil) as? NSParagraphStyle)
        let mutable = (paragraphStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? style.paragraphStyle()
        mutable.paragraphSpacing = 0
        output.addAttribute(
            .paragraphStyle,
            value: mutable,
            range: NSRange(location: paragraphStart, length: output.length - paragraphStart)
        )
    }
}

private struct MarkdownMathFieldRestorer: MarkupRewriter {
    let mathResult: MarkdownMathPreprocessor.Result
    private var restoresTextInCurrentBranch = false

    init(mathResult: MarkdownMathPreprocessor.Result) {
        self.mathResult = mathResult
    }

    mutating func visitLink(_ link: Link) -> Markup? {
        let previousRestoresText = restoresTextInCurrentBranch
        restoresTextInCurrentBranch = linkRequiresTextRestoration(link)
        defer { restoresTextInCurrentBranch = previousRestoresText }

        guard var rewritten = defaultVisit(link) as? Link else { return nil }
        rewritten.destination = mathResult.restoringOriginalMarkup(in: rewritten.destination)
        rewritten.title = mathResult.restoringOriginalMarkup(in: rewritten.title)
        return rewritten
    }

    mutating func visitImage(_ image: Image) -> Markup? {
        let previousRestoresText = restoresTextInCurrentBranch
        restoresTextInCurrentBranch = true
        defer { restoresTextInCurrentBranch = previousRestoresText }

        guard var rewritten = defaultVisit(image) as? Image else { return nil }
        rewritten.source = mathResult.restoringOriginalMarkup(in: rewritten.source)
        rewritten.title = mathResult.restoringOriginalMarkup(in: rewritten.title)
        return rewritten
    }

    mutating func visitText(_ text: Text) -> Markup? {
        guard restoresTextInCurrentBranch,
              let restored = mathResult.restoringOriginalMarkup(in: text.string),
              restored != text.string
        else {
            return text
        }

        var rewritten = text
        rewritten.string = restored
        return rewritten
    }

    mutating func visitCustomInline(_ customInline: CustomInline) -> Markup? {
        guard restoresTextInCurrentBranch,
              let restored = mathResult.restoringOriginalMarkup(in: customInline.text),
              restored != customInline.text
        else {
            return customInline
        }

        return CustomInline(restored)
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> Markup? {
        var rewritten = inlineHTML
        rewritten.rawHTML = mathResult.restoringOriginalMarkup(in: inlineHTML.rawHTML) ?? inlineHTML.rawHTML
        return rewritten
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> Markup? {
        var rewritten = html
        rewritten.rawHTML = mathResult.restoringOriginalMarkup(in: html.rawHTML) ?? html.rawHTML
        return rewritten
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> Markup? {
        var rewritten = symbolLink
        rewritten.destination = mathResult.restoringOriginalMarkup(in: symbolLink.destination)
        return rewritten
    }

    private func linkRequiresTextRestoration(_ link: Link) -> Bool {
        guard let destination = link.destination, link.childCount == 1 else { return false }
        let restoredDestination = mathResult.restoringOriginalMarkup(in: destination) ?? destination

        if let text = link.child(at: 0) as? Text {
            let restoredChild = mathResult.restoringOriginalMarkup(in: text.string) ?? text.string
            return restoredChild == restoredDestination
        }

        if let customInline = link.child(at: 0) as? CustomInline {
            let restoredChild = mathResult.restoringOriginalMarkup(in: customInline.text) ?? customInline.text
            return restoredChild == restoredDestination
        }

        return false
    }
}
