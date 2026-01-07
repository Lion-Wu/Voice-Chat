#if os(macOS)
@preconcurrency import Foundation
@preconcurrency import AppKit

private final class MarkdownCodeBlockView: NSView {
    private struct Layout {
        let size: CGSize
        let headerFrame: CGRect
        let separatorFrame: CGRect
        let languageFrame: CGRect
        let copyFrame: CGRect
        let scrollFrame: CGRect
        let codeFrame: CGRect
        let contentWidth: CGFloat
    }

    override var isFlipped: Bool { true }

    private let style: MarkdownCodeBlockStyle
    private let code: String
    private let codeAttributed: NSAttributedString
    private let languageText: String
    private let copyText: String

    private let headerView = NSView()
    private let headerSeparator = NSView()
    private let languageLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private let scrollView = NSScrollView()
    private let codeTextView = NSTextView()
    private var cachedLayout: Layout?
    private var cachedWidth: CGFloat = 0

    init(
        code: String,
        languageLabel languageText: String,
        copyLabel: String,
        style: MarkdownCodeBlockStyle,
        codeAttributed: NSAttributedString
    ) {
        self.style = style
        self.code = code
        self.codeAttributed = codeAttributed
        self.languageText = languageText
        self.copyText = copyLabel
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = style.backgroundColor.cgColor
        layer?.cornerRadius = style.cornerRadius
        layer?.borderWidth = style.borderWidth
        layer?.borderColor = style.borderColor.cgColor
        layer?.masksToBounds = true

        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = style.headerBackground.cgColor
        addSubview(headerView)

        headerSeparator.wantsLayer = true
        headerSeparator.layer?.backgroundColor = style.borderColor.cgColor
        addSubview(headerSeparator)

        languageLabel.font = style.headerFont
        languageLabel.textColor = style.headerTextColor
        languageLabel.lineBreakMode = .byTruncatingTail
        languageLabel.stringValue = languageText
        headerView.addSubview(languageLabel)

        copyButton.title = copyText
        copyButton.target = self
        copyButton.action = #selector(handleCopy)
        copyButton.isBordered = false
        copyButton.bezelStyle = .regularSquare
        let copyAttributes: [NSAttributedString.Key: Any] = [
            .font: style.headerFont,
            .foregroundColor: style.copyTextColor
        ]
        copyButton.attributedTitle = NSAttributedString(string: copyText, attributes: copyAttributes)
        headerView.addSubview(copyButton)

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        addSubview(scrollView)

        codeTextView.drawsBackground = false
        codeTextView.isEditable = false
        codeTextView.isSelectable = true
        codeTextView.textContainerInset = .zero
        codeTextView.textContainer?.lineFragmentPadding = 0
        codeTextView.textContainer?.lineBreakMode = .byClipping
        codeTextView.textContainer?.widthTracksTextView = false
        codeTextView.textContainer?.heightTracksTextView = false
        codeTextView.isHorizontallyResizable = true
        codeTextView.isVerticallyResizable = false
        codeTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        codeTextView.minSize = .zero
        codeTextView.textStorage?.setAttributedString(codeAttributed)
        scrollView.documentView = codeTextView
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func sizeThatFitsWidth(_ width: CGFloat) -> CGSize {
        let targetWidth = max(1, width)
        if abs(targetWidth - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: targetWidth)
            cachedWidth = targetWidth
        }
        needsLayout = true
        return cachedLayout?.size ?? CGSize(width: targetWidth, height: 0)
    }

    override func layout() {
        super.layout()
        let width = bounds.width > 0 ? bounds.width : cachedWidth
        if abs(width - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: max(1, width))
            cachedWidth = max(1, width)
        }
        guard let layout = cachedLayout else { return }

        headerView.frame = layout.headerFrame
        headerSeparator.frame = layout.separatorFrame
        languageLabel.frame = layout.languageFrame
        copyButton.frame = layout.copyFrame
        scrollView.frame = layout.scrollFrame
        codeTextView.frame = layout.codeFrame
        if let documentView = scrollView.documentView, documentView.frame.size != layout.codeFrame.size {
            documentView.frame = layout.codeFrame
        }
    }

    @objc private func handleCopy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
    }

    private func computeLayout(width: CGFloat) -> Layout {
        let border = max(1, style.borderWidth)
        let headerPadding = style.headerPadding
        let codePadding = style.codePadding
        let viewportContentWidth = max(1, width - border * 2)

        let headerLineHeight = lineHeight(for: style.headerFont)
        let headerHeight = max(24, headerLineHeight + headerPadding.height * 2)
        let headerFrame = CGRect(x: border, y: border, width: viewportContentWidth, height: headerHeight)
        let separatorFrame = CGRect(x: border, y: headerFrame.maxY - border, width: viewportContentWidth, height: border)

        let copyTextSize = measureText(copyText, font: style.headerFont)
        let copyButtonHeight = max(18, headerLineHeight + headerPadding.height)
        let idealCopyWidth = copyTextSize.width + headerPadding.width * 2
        let availableCopyWidth = max(0, viewportContentWidth - headerPadding.width)
        let copyButtonWidth = min(idealCopyWidth, availableCopyWidth)
        let copyFrame = CGRect(
            x: max(0, viewportContentWidth - copyButtonWidth - headerPadding.width),
            y: (headerHeight - copyButtonHeight) / 2,
            width: min(copyButtonWidth, viewportContentWidth),
            height: copyButtonHeight
        )

        let languageX = headerPadding.width
        let languageWidth = max(0, copyFrame.minX - languageX - headerPadding.width)
        let languageFrame = CGRect(
            x: languageX,
            y: (headerHeight - headerLineHeight) / 2,
            width: languageWidth,
            height: headerLineHeight
        )

        let codeTextSize = measureAttributedText(codeAttributed, width: .greatestFiniteMagnitude)
        let codeHeight = max(codeTextSize.height, lineHeight(for: style.codeFont))
        let viewportCodeWidth = max(1, viewportContentWidth - codePadding.width * 2)
        let contentWidth = max(viewportCodeWidth, codeTextSize.width)
        let scrollFrame = CGRect(
            x: border + codePadding.width,
            y: border + headerHeight + codePadding.height,
            width: viewportCodeWidth,
            height: codeHeight
        )
        let codeFrame = CGRect(x: 0, y: 0, width: contentWidth, height: codeHeight)
        let totalHeight = border * 2 + headerHeight + codePadding.height * 2 + codeHeight
        return Layout(
            size: CGSize(width: width, height: totalHeight),
            headerFrame: headerFrame,
            separatorFrame: separatorFrame,
            languageFrame: languageFrame,
            copyFrame: copyFrame,
            scrollFrame: scrollFrame,
            codeFrame: codeFrame,
            contentWidth: contentWidth
        )
    }

    private func measureText(_ text: String, font: MarkdownPlatformFont) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attrs)
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func lineHeight(for font: MarkdownPlatformFont) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: font)
    }
}

private final class MarkdownTableRowView: NSView {
    override var isFlipped: Bool { true }
    let separatorView = NSView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        separatorView.wantsLayer = true
        addSubview(separatorView)
    }

    required init?(coder: NSCoder) {
        return nil
    }
}

private final class MarkdownTableView: NSView {
    private struct Layout {
        let tableSize: CGSize
        let contentWidth: CGFloat
        let columnWidths: [CGFloat]
        let rowHeights: [CGFloat]
        let rowSeparatorWidth: CGFloat
        let columnGap: CGFloat
    }

    override var isFlipped: Bool { true }

    private let rows: [MarkdownTableRow]
    private let style: MarkdownTableStyle
    private let columnCount: Int
    private let scrollView = NSScrollView()
    private let contentView = NSView()
    private var rowViews: [MarkdownTableRowView] = []
    private var cellViews: [[NSTextView]] = []
    private var cachedLayout: Layout?
    private var cachedWidth: CGFloat = 0

    init(rows: [MarkdownTableRow], style: MarkdownTableStyle) {
        self.rows = rows
        self.style = style
        self.columnCount = rows.map { $0.cells.count }.max() ?? 0
        super.init(frame: .zero)

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        addSubview(scrollView)

        contentView.wantsLayer = true
        scrollView.documentView = contentView

        buildRows()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func sizeThatFitsWidth(_ width: CGFloat) -> CGSize {
        let targetWidth = max(1, width)
        if abs(targetWidth - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: targetWidth)
            cachedWidth = targetWidth
        }
        needsLayout = true
        return cachedLayout?.tableSize ?? CGSize(width: targetWidth, height: 0)
    }

    override func layout() {
        super.layout()
        let width = bounds.width > 0 ? bounds.width : cachedWidth
        if abs(width - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: max(1, width))
            cachedWidth = max(1, width)
        }
        guard let layout = cachedLayout else { return }

        scrollView.frame = bounds
        contentView.frame = CGRect(x: 0, y: 0, width: layout.contentWidth, height: layout.tableSize.height)
        if let documentView = scrollView.documentView, documentView.frame.size != contentView.frame.size {
            documentView.frame = contentView.frame
        }

        let padding = style.cellPadding
        let rowSeparator = layout.rowSeparatorWidth
        let hasHeader = rows.first?.isHeader == true

        var y: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            guard rowIndex < rowViews.count else { continue }
            let rowHeight = layout.rowHeights[rowIndex]
            let rowView = rowViews[rowIndex]
            let rowViewHeight = rowHeight + rowSeparator
            rowView.frame = CGRect(x: 0, y: y, width: layout.contentWidth, height: rowViewHeight)
            rowView.separatorView.frame = CGRect(x: 0, y: rowHeight, width: layout.contentWidth, height: rowSeparator)
            rowView.separatorView.layer?.backgroundColor = style.borderColor.cgColor

            if row.isHeader {
                rowView.layer?.backgroundColor = style.headerBackground.cgColor
            } else {
                let bodyIndex = rowIndex - (hasHeader ? 1 : 0)
                if bodyIndex % 2 == 1 {
                    rowView.layer?.backgroundColor = style.stripeBackground.cgColor
                } else {
                    rowView.layer?.backgroundColor = nil
                }
            }

            var x: CGFloat = 0
            for column in 0..<layout.columnWidths.count {
                guard rowIndex < cellViews.count, column < cellViews[rowIndex].count else { continue }
                let cellWidth = layout.columnWidths[column]
                let cellView = cellViews[rowIndex][column]
                let textRect = CGRect(
                    x: x + padding.width,
                    y: padding.height,
                    width: max(0, cellWidth - padding.width * 2),
                    height: max(0, rowHeight - padding.height * 2)
                )
                cellView.frame = textRect
                x += cellWidth + layout.columnGap
            }

            y += rowViewHeight
        }
    }

    private func buildRows() {
        guard columnCount > 0 else { return }
        let emptyCell = NSAttributedString(string: "", attributes: [.font: style.baseFont])
        rowViews.reserveCapacity(rows.count)
        cellViews.reserveCapacity(rows.count)
        for row in rows {
            let rowView = MarkdownTableRowView()
            rowView.separatorView.layer?.backgroundColor = style.borderColor.cgColor
            contentView.addSubview(rowView)
            rowViews.append(rowView)

            var rowCells: [NSTextView] = []
            rowCells.reserveCapacity(columnCount)
            for column in 0..<columnCount {
                let cellText = column < row.cells.count ? row.cells[column] : emptyCell
                let cellView = NSTextView()
                cellView.drawsBackground = false
                cellView.isEditable = false
                cellView.isSelectable = true
                cellView.textContainerInset = .zero
                cellView.textContainer?.lineFragmentPadding = 0
                cellView.textContainer?.lineBreakMode = .byWordWrapping
                cellView.textContainer?.widthTracksTextView = true
                cellView.textContainer?.heightTracksTextView = false
                cellView.textContainer?.containerSize = CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
                cellView.isHorizontallyResizable = false
                cellView.isVerticallyResizable = false
                cellView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                cellView.minSize = .zero
                cellView.textStorage?.setAttributedString(cellText)
                rowView.addSubview(cellView)
                rowCells.append(cellView)
            }
            cellViews.append(rowCells)
        }
    }

    private func computeLayout(width: CGFloat) -> Layout {
        let columnCount = self.columnCount
        guard columnCount > 0 else {
            return Layout(
                tableSize: .zero,
                contentWidth: 0,
                columnWidths: [],
                rowHeights: [],
                rowSeparatorWidth: 0,
                columnGap: 0
            )
        }

        let rowSeparator = max(1, style.borderWidth)
        let columnGap: CGFloat = 0
        let paddingX = style.cellPadding.width
        let paddingY = style.cellPadding.height
        let maxCellTextWidth = max(80, min(width * 0.8, 360))

        var contentWidths = Array(repeating: CGFloat(0), count: columnCount)
        for row in rows {
            for column in 0..<columnCount {
                let cell = column < row.cells.count ? row.cells[column] : NSAttributedString(string: "", attributes: [.font: style.baseFont])
                let size = measureAttributedText(cell, width: .greatestFiniteMagnitude)
                contentWidths[column] = max(contentWidths[column], min(size.width, maxCellTextWidth))
            }
        }

        let totalColumnGap = columnGap * CGFloat(max(0, columnCount - 1))
        let columnWidths = contentWidths.map { $0 + paddingX * 2 }
        let minRowHeight = lineHeight(for: style.baseFont)
        var rowHeights: [CGFloat] = []
        rowHeights.reserveCapacity(rows.count)
        for row in rows {
            var rowHeight: CGFloat = 0
            for column in 0..<columnCount {
                let cell = column < row.cells.count ? row.cells[column] : NSAttributedString(string: "", attributes: [.font: style.baseFont])
                let textWidth = max(0, columnWidths[column] - paddingX * 2)
                let size = measureAttributedText(cell, width: textWidth)
                rowHeight = max(rowHeight, max(size.height, minRowHeight))
            }
            rowHeights.append(rowHeight + paddingY * 2)
        }

        let tableWidth = columnWidths.reduce(0, +) + totalColumnGap
        let tableHeight = rowHeights.reduce(0, +) + rowSeparator * CGFloat(rows.count)
        let viewportWidth = min(width, tableWidth)
        return Layout(
            tableSize: CGSize(width: viewportWidth, height: tableHeight),
            contentWidth: tableWidth,
            columnWidths: columnWidths,
            rowHeights: rowHeights,
            rowSeparatorWidth: rowSeparator,
            columnGap: columnGap
        )
    }

    private func lineHeight(for font: MarkdownPlatformFont) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: font)
    }
}

private final class MarkdownQuoteView: NSView {
    private struct Layout {
        let size: CGSize
        let borderFrame: CGRect
        let textFrame: CGRect
    }

    override var isFlipped: Bool { true }

    private let content: NSAttributedString
    private let style: MarkdownQuoteStyle
    private let borderView = NSView()
    private let textView = NSTextView()
    private var cachedLayout: Layout?
    private var cachedWidth: CGFloat = 0

    init(content: NSAttributedString, style: MarkdownQuoteStyle) {
        self.content = content
        self.style = style
        super.init(frame: .zero)

        borderView.wantsLayer = true
        borderView.layer?.backgroundColor = style.borderColor.cgColor
        addSubview(borderView)

        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textStorage?.setAttributedString(content)
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func sizeThatFitsWidth(_ width: CGFloat) -> CGSize {
        let targetWidth = max(1, width)
        if abs(targetWidth - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: targetWidth)
            cachedWidth = targetWidth
        }
        needsLayout = true
        return cachedLayout?.size ?? CGSize(width: targetWidth, height: 0)
    }

    override func layout() {
        super.layout()
        let width = bounds.width > 0 ? bounds.width : cachedWidth
        if abs(width - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: max(1, width))
            cachedWidth = max(1, width)
        }
        guard let layout = cachedLayout else { return }
        borderView.frame = layout.borderFrame
        textView.frame = layout.textFrame
    }

    private func computeLayout(width: CGFloat) -> Layout {
        let borderWidth = max(1, style.borderWidth)
        let padding = style.padding
        let textWidth = max(1, width - borderWidth - padding.width * 2)
        let textSize = measureAttributedText(content, width: textWidth)
        let height = textSize.height + padding.height * 2
        let borderFrame = CGRect(x: 0, y: 0, width: borderWidth, height: height)
        let textFrame = CGRect(
            x: borderWidth + padding.width,
            y: padding.height,
            width: textWidth,
            height: textSize.height
        )
        return Layout(size: CGSize(width: width, height: height), borderFrame: borderFrame, textFrame: textFrame)
    }
}

private final class MarkdownRuleView: NSView {
    override var isFlipped: Bool { true }

    private let color: MarkdownPlatformColor
    private let thickness: CGFloat
    private let verticalPadding: CGFloat
    private let lineView = NSView()
    private var cachedWidth: CGFloat = 0
    private var cachedSize: CGSize = .zero

    init(color: MarkdownPlatformColor, thickness: CGFloat, verticalPadding: CGFloat) {
        self.color = color
        self.thickness = max(1, thickness)
        self.verticalPadding = verticalPadding
        super.init(frame: .zero)

        lineView.wantsLayer = true
        lineView.layer?.backgroundColor = color.cgColor
        addSubview(lineView)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func sizeThatFitsWidth(_ width: CGFloat) -> CGSize {
        let targetWidth = max(1, width)
        if abs(targetWidth - cachedWidth) > 0.5 {
            cachedWidth = targetWidth
            cachedSize = CGSize(width: targetWidth, height: verticalPadding * 2 + thickness)
        }
        needsLayout = true
        return cachedSize
    }

    override func layout() {
        super.layout()
        let y = (bounds.height - thickness) / 2
        lineView.frame = CGRect(x: 0, y: y, width: bounds.width, height: thickness)
    }
}

@available(macOS 12.0, *)
final class MarkdownAttachmentViewProvider: NSTextAttachmentViewProvider, @unchecked Sendable {
    private struct UncheckedSendableBox<Value>: @unchecked Sendable {
        let value: Value
    }

    private struct AttachmentLayout: Sendable {
        let view: UncheckedSendableBox<NSView>
        let bounds: CGRect
    }

    private enum Snapshot: Sendable {
        struct CodeBlock: Sendable {
            let code: String
            let languageLabel: String
            let copyLabel: String
            let style: UncheckedSendableBox<MarkdownCodeBlockStyle>
            let codeAttributed: UncheckedSendableBox<NSAttributedString>
            let maxWidth: CGFloat
        }

        struct Table: Sendable {
            let rows: [MarkdownTableRow]
            let style: UncheckedSendableBox<MarkdownTableStyle>
            let maxWidth: CGFloat
        }

        struct Quote: Sendable {
            let content: UncheckedSendableBox<NSAttributedString>
            let style: UncheckedSendableBox<MarkdownQuoteStyle>
            let maxWidth: CGFloat
        }

        struct Rule: Sendable {
            let color: UncheckedSendableBox<MarkdownPlatformColor>
            let thickness: CGFloat
            let verticalPadding: CGFloat
            let maxWidth: CGFloat
        }

        case codeBlock(CodeBlock)
        case table(Table)
        case quote(Quote)
        case rule(Rule)
        case unknown(maxWidth: CGFloat)

        var maxWidth: CGFloat {
            switch self {
            case .codeBlock(let data):
                return data.maxWidth
            case .table(let data):
                return data.maxWidth
            case .quote(let data):
                return data.maxWidth
            case .rule(let data):
                return data.maxWidth
            case .unknown(let maxWidth):
                return maxWidth
            }
        }
    }

    override init(
        textAttachment: NSTextAttachment,
        parentView: NSView?,
        textLayoutManager: NSTextLayoutManager?,
        location: NSTextLocation
    ) {
        super.init(
            textAttachment: textAttachment,
            parentView: parentView,
            textLayoutManager: textLayoutManager,
            location: location
        )
        tracksTextAttachmentViewBounds = true
    }

    override func loadView() {
        let snapshot = snapshotForCurrentTextAttachment()
        let viewBox: UncheckedSendableBox<NSView> = MainActor.assumeIsolated {
            let created = Self.makeView(from: snapshot)
            return UncheckedSendableBox(value: created)
        }
        view = viewBox.value
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        _ = attributes
        _ = location
        _ = textContainer
        _ = position

        let snapshot = snapshotForCurrentTextAttachment()
        let currentViewBox = UncheckedSendableBox(value: view)
        let lineWidth = proposedLineFragment.width

        let layout: AttachmentLayout = MainActor.assumeIsolated {
            let resolvedView: NSView
            if let existing = currentViewBox.value {
                resolvedView = existing
            } else {
                resolvedView = Self.makeView(from: snapshot)
            }

            let available = attachmentAvailableWidth(maxWidth: snapshot.maxWidth, lineFragWidth: lineWidth)
            let bounds: CGRect
            if let view = resolvedView as? MarkdownCodeBlockView {
                bounds = CGRect(origin: .zero, size: view.sizeThatFitsWidth(available))
            } else if let view = resolvedView as? MarkdownTableView {
                bounds = CGRect(origin: .zero, size: view.sizeThatFitsWidth(available))
            } else if let view = resolvedView as? MarkdownQuoteView {
                bounds = CGRect(origin: .zero, size: view.sizeThatFitsWidth(available))
            } else if let view = resolvedView as? MarkdownRuleView {
                bounds = CGRect(origin: .zero, size: view.sizeThatFitsWidth(available))
            } else {
                bounds = CGRect(x: 0, y: 0, width: available, height: 0)
            }
            return AttachmentLayout(view: UncheckedSendableBox(value: resolvedView), bounds: bounds)
        }

        view = layout.view.value
        return layout.bounds
    }

    private func snapshotForCurrentTextAttachment() -> Snapshot {
        guard let attachment = textAttachment as? MarkdownAttachment else {
            return .unknown(maxWidth: 0)
        }
        let maxWidth = attachment.maxWidth
        switch attachment {
        case let attachment as MarkdownCodeBlockAttachment:
            return .codeBlock(
                Snapshot.CodeBlock(
                    code: attachment.code,
                    languageLabel: attachment.languageLabel,
                    copyLabel: attachment.copyLabel,
                    style: UncheckedSendableBox(value: attachment.style),
                    codeAttributed: UncheckedSendableBox(value: attachment.codeAttributed),
                    maxWidth: maxWidth
                )
            )
        case let attachment as MarkdownTableAttachment:
            return .table(
                Snapshot.Table(
                    rows: attachment.rows,
                    style: UncheckedSendableBox(value: attachment.style),
                    maxWidth: maxWidth
                )
            )
        case let attachment as MarkdownQuoteAttachment:
            return .quote(
                Snapshot.Quote(
                    content: UncheckedSendableBox(value: attachment.content),
                    style: UncheckedSendableBox(value: attachment.style),
                    maxWidth: maxWidth
                )
            )
        case let attachment as MarkdownRuleAttachment:
            return .rule(
                Snapshot.Rule(
                    color: UncheckedSendableBox(value: attachment.color),
                    thickness: attachment.thickness,
                    verticalPadding: attachment.verticalPadding,
                    maxWidth: maxWidth
                )
            )
        default:
            return .unknown(maxWidth: maxWidth)
        }
    }

    @MainActor
    private static func makeView(from snapshot: Snapshot) -> NSView {
        switch snapshot {
        case .codeBlock(let data):
            return MarkdownCodeBlockView(
                code: data.code,
                languageLabel: data.languageLabel,
                copyLabel: data.copyLabel,
                style: data.style.value,
                codeAttributed: data.codeAttributed.value
            )
        case .table(let data):
            return MarkdownTableView(rows: data.rows, style: data.style.value)
        case .quote(let data):
            return MarkdownQuoteView(content: data.content.value, style: data.style.value)
        case .rule(let data):
            return MarkdownRuleView(
                color: data.color.value,
                thickness: data.thickness,
                verticalPadding: data.verticalPadding
            )
        case .unknown:
            return NSView()
        }
    }
}


#endif
