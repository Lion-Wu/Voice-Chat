//
//  MarkdownAttributedStringRenderer.swift
//  Voice Chat
//

@preconcurrency import Foundation
import Markdown

#if os(iOS) || os(tvOS) || os(watchOS)
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
    private let style: MarkdownStyle
    private let maxImageWidth: CGFloat?
    private var attachments: [MarkdownAttachment] = []

    init(style: MarkdownStyle, maxImageWidth: CGFloat?) {
        self.style = style
        self.maxImageWidth = maxImageWidth
    }

    func render(markdown: String) -> MarkdownRenderResult {
        let document = Document(parsing: markdown)
        let output = NSMutableAttributedString()
        renderChildrenBlocks(document, into: output, listDepth: 0, baseAttributes: style.baseAttributes)
        finalizeRenderedOutput(output)
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

    private func renderBlock(
        _ markup: Markup,
        into output: NSMutableAttributedString,
        listDepth: Int,
        baseAttributes: [NSAttributedString.Key: Any]
    ) {
        if let paragraph = markup as? Paragraph {
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
            content.addAttribute(
                .paragraphStyle,
                value: style.paragraphStyle(spacingBefore: 0, spacingAfter: style.paragraphSpacing),
                range: NSRange(location: 0, length: content.length)
            )
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
        context: InlineRenderContext = .standard
    ) -> NSMutableAttributedString {
        let output = NSMutableAttributedString()
        for child in parent.children {
            output.append(renderInline(child, attributes: attributes, context: context))
        }
        return output
    }

    private func renderInline(
        _ markup: Markup,
        attributes: [NSAttributedString.Key: Any],
        context: InlineRenderContext
    ) -> NSAttributedString {
        if let text = markup as? Markdown.Text {
            return NSAttributedString(string: text.string, attributes: attributes)
        } else if let custom = markup as? CustomInline {
            return NSAttributedString(string: custom.text, attributes: attributes)
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
            return renderInlineChildren(emphasis, attributes: attrs, context: context)
        } else if let strong = markup as? Strong {
            var attrs = attributes
            if let font = attributes[.font] as? MarkdownPlatformFont {
                attrs[.font] = boldFont(from: font)
            }
            return renderInlineChildren(strong, attributes: attrs, context: context)
        } else if let strike = markup as? Strikethrough {
            var attrs = attributes
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.strikethroughColor] = style.secondaryColor
            return renderInlineChildren(strike, attributes: attrs, context: context)
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
            return renderInlineChildren(link, attributes: attrs, context: context)
        } else if let inlineAttributes = markup as? InlineAttributes {
            return renderInlineChildren(inlineAttributes, attributes: attributes, context: context)
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
            return renderInlineChildren(markup, attributes: attributes, context: context)
        }
    }

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

    private func listItemPrefix(for item: ListItem, base: String) -> String {
        guard let checkbox = item.checkbox else { return base }
        let marker = checkbox == .checked ? "[x]" : "[ ]"
        return "\(base) \(marker)"
    }

    private func listParagraphStyle(prefix: String, depth: Int) -> NSMutableParagraphStyle {
        let indentBase = style.listIndent * CGFloat(depth)
        let prefixWidth = measureTextWidth(prefix, font: style.baseFont)
        return style.paragraphStyle(
            spacingBefore: 0,
            spacingAfter: style.paragraphSpacing,
            firstLineHeadIndent: indentBase,
            headIndent: indentBase + prefixWidth
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
            let cells = buildTableCells(
                from: headerCells,
                columnCount: columnCount,
                attributes: headerAttributes,
                alignments: alignments
            )
            rows.append(MarkdownTableRow(cells: cells, isHeader: true))
        }

        for row in table.body.rows {
            let rowCells = row.children.compactMap { $0 as? Markdown.Table.Cell }
            let cells = buildTableCells(
                from: rowCells,
                columnCount: columnCount,
                attributes: baseAttributes,
                alignments: alignments
            )
            rows.append(MarkdownTableRow(cells: cells, isHeader: false))
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
