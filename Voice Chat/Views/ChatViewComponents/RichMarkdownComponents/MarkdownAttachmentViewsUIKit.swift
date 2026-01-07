#if os(iOS) || os(tvOS)
@preconcurrency import Foundation
@preconcurrency import UIKit

private final class MarkdownCodeBlockView: UIView {
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

    private let style: MarkdownCodeBlockStyle
    private let code: String
    private let codeAttributed: NSAttributedString
    private let languageText: String
    private let copyText: String

    private let headerView = UIView()
    private let headerSeparator = UIView()
    private let languageLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let codeTextView = UITextView()
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

        backgroundColor = style.backgroundColor
        layer.cornerRadius = style.cornerRadius
        layer.borderWidth = style.borderWidth
        layer.borderColor = style.borderColor.cgColor
        layer.masksToBounds = true

        headerView.backgroundColor = style.headerBackground
        addSubview(headerView)

        headerSeparator.backgroundColor = style.borderColor
        addSubview(headerSeparator)

        self.languageLabel.font = style.headerFont
        self.languageLabel.textColor = style.headerTextColor
        self.languageLabel.lineBreakMode = .byTruncatingTail
        self.languageLabel.text = languageText
        headerView.addSubview(self.languageLabel)

        copyButton.setTitle(copyText, for: .normal)
        copyButton.titleLabel?.font = style.headerFont
        copyButton.setTitleColor(style.copyTextColor, for: .normal)
        copyButton.backgroundColor = style.copyBackground
        copyButton.titleLabel?.lineBreakMode = .byTruncatingTail
        copyButton.clipsToBounds = true
        copyButton.addTarget(self, action: #selector(handleCopy), for: .touchUpInside)
        headerView.addSubview(copyButton)

        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.clipsToBounds = true
        addSubview(scrollView)

        codeTextView.backgroundColor = .clear
        codeTextView.isEditable = false
        codeTextView.isSelectable = true
        codeTextView.isScrollEnabled = false
        codeTextView.textContainerInset = .zero
        codeTextView.textContainer.lineFragmentPadding = 0
        codeTextView.textContainer.lineBreakMode = .byClipping
        #if os(iOS)
        codeTextView.disableTextDragAndDrop()
        #endif
        codeTextView.attributedText = codeAttributed
        scrollView.addSubview(codeTextView)
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
        setNeedsLayout()
        return cachedLayout?.size ?? CGSize(width: targetWidth, height: 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
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
        copyButton.layer.cornerRadius = layout.copyFrame.height / 2
        scrollView.frame = layout.scrollFrame
        scrollView.contentSize = CGSize(width: layout.contentWidth, height: layout.codeFrame.height)
        codeTextView.frame = layout.codeFrame
    }

    @objc private func handleCopy() {
        #if os(iOS)
        UIPasteboard.general.string = code
        #endif
    }

    private func computeLayout(width: CGFloat) -> Layout {
        let border = max(1, style.borderWidth)
        let headerPadding = style.headerPadding
        let codePadding = style.codePadding
        let viewportContentWidth = max(1, width - border * 2)

        let headerLineHeight = style.headerFont.lineHeight
        let headerHeight = max(24, headerLineHeight + headerPadding.height * 2)
        let headerFrame = CGRect(x: border, y: border, width: viewportContentWidth, height: headerHeight)
        let separatorFrame = CGRect(x: border, y: headerFrame.maxY, width: viewportContentWidth, height: border)

        let copyTextSize = measureText(copyText, font: style.headerFont)
        let copyButtonHeight = max(18, headerLineHeight + headerPadding.height)
        let availableCopyWidth = max(0, viewportContentWidth - headerPadding.width)
        let idealCopyWidth = copyTextSize.width + headerPadding.width * 2
        let copyButtonWidth = min(idealCopyWidth, availableCopyWidth)
        let copyButtonX = viewportContentWidth - copyButtonWidth - headerPadding.width
        let copyButtonY = (headerHeight - copyButtonHeight) / 2
        let copyFrame = CGRect(
            x: max(0, copyButtonX),
            y: copyButtonY,
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
        let codeHeight = max(codeTextSize.height, style.codeFont.lineHeight)
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
}

private final class MarkdownTableRowView: UIView {
    let separatorView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(separatorView)
    }

    required init?(coder: NSCoder) {
        return nil
    }
}

private final class MarkdownTableView: UIView {
    private struct Layout {
        let tableSize: CGSize
        let contentWidth: CGFloat
        let columnWidths: [CGFloat]
        let rowHeights: [CGFloat]
        let rowSeparatorWidth: CGFloat
        let columnGap: CGFloat
    }

    private let rows: [MarkdownTableRow]
    private let style: MarkdownTableStyle
    private let columnCount: Int
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private var rowViews: [MarkdownTableRowView] = []
    private var cellViews: [[UITextView]] = []
    private var cachedLayout: Layout?
    private var cachedWidth: CGFloat = 0

    init(rows: [MarkdownTableRow], style: MarkdownTableStyle) {
        self.rows = rows
        self.style = style
        self.columnCount = rows.map { $0.cells.count }.max() ?? 0
        super.init(frame: .zero)

        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.clipsToBounds = true
        addSubview(scrollView)
        scrollView.addSubview(contentView)

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
        setNeedsLayout()
        return cachedLayout?.tableSize ?? CGSize(width: targetWidth, height: 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width > 0 ? bounds.width : cachedWidth
        if abs(width - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: max(1, width))
            cachedWidth = max(1, width)
        }
        guard let layout = cachedLayout else { return }
        scrollView.frame = bounds
        scrollView.contentSize = CGSize(width: layout.contentWidth, height: layout.tableSize.height)
        contentView.frame = CGRect(x: 0, y: 0, width: layout.contentWidth, height: layout.tableSize.height)

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
            rowView.separatorView.backgroundColor = style.borderColor

            if row.isHeader {
                rowView.backgroundColor = style.headerBackground
            } else {
                let bodyIndex = rowIndex - (hasHeader ? 1 : 0)
                if bodyIndex % 2 == 1 {
                    rowView.backgroundColor = style.stripeBackground
                } else {
                    rowView.backgroundColor = .clear
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
            rowView.separatorView.backgroundColor = style.borderColor
            contentView.addSubview(rowView)
            rowViews.append(rowView)

            var rowCells: [UITextView] = []
            rowCells.reserveCapacity(columnCount)
            for column in 0..<columnCount {
                let cellText = column < row.cells.count ? row.cells[column] : emptyCell
                let cellView = UITextView()
                cellView.attributedText = cellText
                cellView.backgroundColor = .clear
                cellView.isEditable = false
                cellView.isSelectable = true
                cellView.isScrollEnabled = false
                cellView.textContainerInset = .zero
                cellView.textContainer.lineFragmentPadding = 0
                cellView.textContainer.lineBreakMode = .byWordWrapping
                #if os(iOS)
                cellView.disableTextDragAndDrop()
                #endif
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
        let minRowHeight = style.baseFont.lineHeight
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
}

private final class MarkdownQuoteView: UIView {
    private struct Layout {
        let size: CGSize
        let borderFrame: CGRect
        let textFrame: CGRect
    }

    private let content: NSAttributedString
    private let style: MarkdownQuoteStyle
    private let borderView = UIView()
    private let textView = UITextView()
    private var cachedLayout: Layout?
    private var cachedWidth: CGFloat = 0

    init(content: NSAttributedString, style: MarkdownQuoteStyle) {
        self.content = content
        self.style = style
        super.init(frame: .zero)

        borderView.backgroundColor = style.borderColor
        addSubview(borderView)

        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        #if os(iOS)
        textView.disableTextDragAndDrop()
        #endif
        textView.attributedText = content
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
        setNeedsLayout()
        return cachedLayout?.size ?? CGSize(width: targetWidth, height: 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
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
        return Layout(
            size: CGSize(width: width, height: height),
            borderFrame: borderFrame,
            textFrame: textFrame
        )
    }
}

private final class MarkdownRuleView: UIView {
    private let color: MarkdownPlatformColor
    private let thickness: CGFloat
    private let verticalPadding: CGFloat
    private let lineView = UIView()
    private var cachedWidth: CGFloat = 0
    private var cachedSize: CGSize = .zero

    init(color: MarkdownPlatformColor, thickness: CGFloat, verticalPadding: CGFloat) {
        self.color = color
        self.thickness = max(1, thickness)
        self.verticalPadding = verticalPadding
        super.init(frame: .zero)

        lineView.backgroundColor = color
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
        setNeedsLayout()
        return cachedSize
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let y = (bounds.height - thickness) / 2
        lineView.frame = CGRect(x: 0, y: y, width: bounds.width, height: thickness)
    }
}

@available(iOS 15.0, tvOS 15.0, *)
final class MarkdownAttachmentViewProvider: NSTextAttachmentViewProvider, @unchecked Sendable {
    private struct UncheckedSendableBox<Value>: @unchecked Sendable {
        let value: Value
    }

    private struct AttachmentLayout: Sendable {
        let view: UncheckedSendableBox<UIView>
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
        parentView: UIView?,
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
        let viewBox: UncheckedSendableBox<UIView> = MainActor.assumeIsolated {
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
            let resolvedView: UIView
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
    private static func makeView(from snapshot: Snapshot) -> UIView {
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
            return UIView()
        }
    }
}


#endif
