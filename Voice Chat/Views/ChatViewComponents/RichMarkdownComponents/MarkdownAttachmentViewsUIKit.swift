#if os(iOS) || os(tvOS)
@preconcurrency import Foundation
@preconcurrency import UIKit

private final class MarkdownCodeBlockView: UIView, UIScrollViewDelegate {
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

    private enum MeasurementSizing {
        static let initialContainerWidth: CGFloat = 10_000
        static let maxContainerWidth: CGFloat = 10_000_000
        static let widthCapThreshold: CGFloat = 1
    }

    private let style: MarkdownCodeBlockStyle
    private var code: String
    private var codeAttributed: NSAttributedString
    private var estimatedCodeTextSize: CGSize
    private var measuredMaxLineWidth: CGFloat = 0
    private var hasMeasuredMaxLineWidth: Bool = false
    private var languageText: String
    private var copyText: String
    private var appliedContentVersion: UInt64 = 0

    private let headerView = UIView()
    private let headerSeparator = UIView()
    private let languageLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let codeTextView = UITextView()
    private var cachedLayout: Layout?
    private var cachedWidth: CGFloat = 0
    private var needsImmediateLayout: Bool = true
    private weak var attachment: MarkdownCodeBlockAttachment?
    private var pendingScrollOffsetX: CGFloat?

    init(
        code: String,
        languageLabel languageText: String,
        copyLabel: String,
        style: MarkdownCodeBlockStyle,
        codeAttributed: NSAttributedString,
        estimatedCodeTextSize: CGSize
    ) {
        self.style = style
        self.code = code
        self.codeAttributed = codeAttributed
        self.estimatedCodeTextSize = estimatedCodeTextSize
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
        scrollView.delegate = self
        addSubview(scrollView)

        codeTextView.backgroundColor = .clear
        codeTextView.isEditable = false
        codeTextView.isSelectable = true
        codeTextView.isScrollEnabled = false
        codeTextView.textContainerInset = .zero
        codeTextView.textContainer.lineFragmentPadding = 0
        codeTextView.textContainer.lineBreakMode = .byClipping
        codeTextView.textContainer.size = CGSize(width: MeasurementSizing.initialContainerWidth, height: 10_000_000)
        codeTextView.layoutManager.allowsNonContiguousLayout = false
        codeTextView.layoutManager.usesFontLeading = true
        #if os(iOS)
        codeTextView.disableTextDragAndDrop()
        #endif
        codeTextView.attributedText = codeAttributed
        scrollView.addSubview(codeTextView)

        updateMeasuredMaxLineWidth(reset: true, changedCharacterRange: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func sizeThatFitsWidth(_ width: CGFloat) -> CGSize {
        let targetWidth = max(1, width)
        if abs(targetWidth - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: targetWidth)
            cachedWidth = targetWidth
            needsImmediateLayout = true
        }
        if needsImmediateLayout {
            needsImmediateLayout = false
            setNeedsLayout()
        }
        return cachedLayout?.size ?? CGSize(width: targetWidth, height: 0)
    }

    func applyUpdate(from attachment: MarkdownCodeBlockAttachment) {
        self.attachment = attachment
        pendingScrollOffsetX = attachment.hostedHorizontalOffset()
        guard attachment.contentVersion != appliedContentVersion else { return }
        applySnapshot(
            code: attachment.code,
            languageLabel: attachment.languageLabel,
            copyLabel: attachment.copyLabel,
            codeAttributed: attachment.codeAttributed,
            estimatedCodeTextSize: attachment.estimatedCodeTextSize
        )
        appliedContentVersion = attachment.contentVersion
    }

    func applySnapshot(
        code: String,
        languageLabel: String,
        copyLabel: String,
        codeAttributed: NSAttributedString,
        estimatedCodeTextSize: CGSize
    ) {
        let storage = codeTextView.textStorage
        let oldLen = storage.length
        let newLen = codeAttributed.length
        guard newLen != oldLen || self.code != code else { return }
        let preservedOffsetX = pendingScrollOffsetX ?? scrollView.contentOffset.x

        let shouldAppend = newLen > oldLen && code.hasPrefix(self.code)
        storage.beginEditing()
        if shouldAppend {
            let delta = codeAttributed.attributedSubstring(from: NSRange(location: oldLen, length: newLen - oldLen))
            if delta.length > 0 {
                storage.append(delta)
            }
        } else {
            storage.setAttributedString(codeAttributed)
        }
        storage.endEditing()

        let container = codeTextView.textContainer
        if abs(container.size.height - max(container.size.height, estimatedCodeTextSize.height)) > 0.5 {
            container.size = CGSize(width: container.size.width, height: max(container.size.height, estimatedCodeTextSize.height))
        }

        let start = max(0, oldLen - 1)
        let range = NSRange(location: start, length: max(0, newLen - start))
        let layoutManager = codeTextView.layoutManager
        layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        layoutManager.ensureLayout(forCharacterRange: range)
        layoutManager.invalidateDisplay(forCharacterRange: range)
        codeTextView.setNeedsDisplay()
        codeTextView.setNeedsLayout()

        self.code = code
        self.codeAttributed = codeAttributed
        self.estimatedCodeTextSize = estimatedCodeTextSize
        if shouldAppend {
            updateMeasuredMaxLineWidth(reset: false, changedCharacterRange: range)
        } else {
            updateMeasuredMaxLineWidth(reset: true, changedCharacterRange: nil)
        }
        languageText = languageLabel
        copyText = copyLabel
        self.languageLabel.text = languageLabel
        copyButton.setTitle(copyLabel, for: .normal)

        let layoutWidth = max(1, bounds.width > 0 ? bounds.width : max(cachedWidth, MeasurementSizing.initialContainerWidth))
        let priorLayout = cachedLayout
        var nextLayout = computeLayout(width: layoutWidth)
        if let priorLayout {
            let contentWidthGrowth = nextLayout.contentWidth - priorLayout.contentWidth
            let canDeferWidthGrowth =
                contentWidthGrowth > 0.5 &&
                contentWidthGrowth < 8 &&
                abs(nextLayout.size.height - priorLayout.size.height) <= 0.5
            if canDeferWidthGrowth {
                nextLayout = priorLayout
            }
        }
        cachedLayout = nextLayout
        cachedWidth = layoutWidth

        let geometryChanged = !layoutsApproximatelyEqual(priorLayout, nextLayout)
        if geometryChanged {
            needsImmediateLayout = true
            pendingScrollOffsetX = preservedOffsetX
            setNeedsLayout()
        } else {
            let maxOffsetX = max(0, nextLayout.contentWidth - nextLayout.scrollFrame.width)
            let clampedOffset = min(max(0, preservedOffsetX), maxOffsetX)
            pendingScrollOffsetX = nil
            if abs(scrollView.contentOffset.x - clampedOffset) > 0.5 {
                scrollView.setContentOffset(CGPoint(x: clampedOffset, y: 0), animated: false)
            }
            attachment?.setHostedHorizontalOffset(clampedOffset)
        }
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
        let container = codeTextView.textContainer
        let targetHeight = layout.codeFrame.height
        if abs(container.size.height - targetHeight) > 0.5 {
            container.size = CGSize(width: container.size.width, height: targetHeight)
        }
        restoreScrollOffsetIfNeeded()
    }

    @objc private func handleCopy() {
        #if os(iOS)
        UIPasteboard.general.string = code
        #endif
    }

    private func layoutsApproximatelyEqual(_ lhs: Layout?, _ rhs: Layout) -> Bool {
        guard let lhs else { return false }
        return
            abs(lhs.size.width - rhs.size.width) <= 0.5 &&
            abs(lhs.size.height - rhs.size.height) <= 0.5 &&
            abs(lhs.contentWidth - rhs.contentWidth) <= 0.5 &&
            abs(lhs.scrollFrame.width - rhs.scrollFrame.width) <= 0.5 &&
            abs(lhs.scrollFrame.height - rhs.scrollFrame.height) <= 0.5 &&
            abs(lhs.codeFrame.height - rhs.codeFrame.height) <= 0.5 &&
            abs(lhs.copyFrame.width - rhs.copyFrame.width) <= 0.5
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

        let codeTextSize = estimatedCodeTextSize
        let codeHeight = max(codeTextSize.height, style.codeFont.lineHeight)
        let viewportCodeWidth = max(1, viewportContentWidth - codePadding.width * 2)
        let measuredWidth = hasMeasuredMaxLineWidth ? ceil(measuredMaxLineWidth + 1) : 0
        let contentWidth = max(viewportCodeWidth, measuredWidth)
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

    private func restoreScrollOffsetIfNeeded() {
        let sourceOffset = pendingScrollOffsetX ?? scrollView.contentOffset.x
        let maxOffsetX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let clamped = min(max(0, sourceOffset), maxOffsetX)
        pendingScrollOffsetX = nil
        if abs(scrollView.contentOffset.x - clamped) > 0.5 || abs(scrollView.contentOffset.y) > 0.5 {
            scrollView.setContentOffset(CGPoint(x: clamped, y: 0), animated: false)
        }
        attachment?.setHostedHorizontalOffset(clamped)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        attachment?.setHostedHorizontalOffset(scrollView.contentOffset.x)
    }

    private func measureText(_ text: String, font: MarkdownPlatformFont) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attrs)
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func updateMeasuredMaxLineWidth(reset: Bool, changedCharacterRange: NSRange?) {
        let layoutManager = codeTextView.layoutManager
        let textContainer = codeTextView.textContainer
        if reset {
            measuredMaxLineWidth = 0
            hasMeasuredMaxLineWidth = false
            let currentSize = textContainer.size
            let baselineWidth = MeasurementSizing.initialContainerWidth
            if abs(currentSize.width - baselineWidth) > 0.5 {
                textContainer.size = CGSize(width: baselineWidth, height: currentSize.height)
            }
        }

        if let changedCharacterRange {
            layoutManager.ensureLayout(forCharacterRange: changedCharacterRange)
        } else {
            layoutManager.ensureLayout(for: textContainer)
        }

        let glyphRange: NSRange = {
            if let changedCharacterRange {
                return layoutManager.glyphRange(forCharacterRange: changedCharacterRange, actualCharacterRange: nil)
            }
            return NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        }()

        guard glyphRange.length > 0 else {
            hasMeasuredMaxLineWidth = true
            return
        }

        let containerWidth = textContainer.size.width
        var localMaxX: CGFloat = 0
        let glyphEnd = NSMaxRange(glyphRange)
        var glyphIndex = glyphRange.location
        while glyphIndex < glyphEnd {
            var lineGlyphRange = NSRange()
            let usedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphRange)
            let resolvedMaxX: CGFloat
            if usedRect.maxX >= containerWidth - MeasurementSizing.widthCapThreshold {
                let bounds = layoutManager.boundingRect(forGlyphRange: lineGlyphRange, in: textContainer)
                resolvedMaxX = bounds.maxX
            } else {
                resolvedMaxX = usedRect.maxX
            }
            localMaxX = max(localMaxX, resolvedMaxX)
            let nextIndex = NSMaxRange(lineGlyphRange)
            glyphIndex = nextIndex > glyphIndex ? nextIndex : glyphIndex + 1
        }

        measuredMaxLineWidth = max(measuredMaxLineWidth, localMaxX)
        measuredMaxLineWidth = min(measuredMaxLineWidth, MeasurementSizing.maxContainerWidth - 1)

        let requiredWidth = max(MeasurementSizing.initialContainerWidth, ceil(measuredMaxLineWidth + 1))
        let currentWidth = textContainer.size.width
        if requiredWidth > currentWidth + 0.5 {
            let grownWidth = max(requiredWidth, currentWidth * 1.25)
            let clampedWidth = min(grownWidth, MeasurementSizing.maxContainerWidth)
            if clampedWidth > currentWidth + 0.5 {
                textContainer.size = CGSize(width: clampedWidth, height: textContainer.size.height)
            }
        }
        hasMeasuredMaxLineWidth = true
    }
}

private final class MarkdownStaticAttributedLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        numberOfLines = 0
        lineBreakMode = .byWordWrapping
        backgroundColor = .clear
        isUserInteractionEnabled = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        return nil
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

private final class MarkdownTableView: UIView, UIScrollViewDelegate {
    private struct Layout {
        let tableSize: CGSize
        let contentWidth: CGFloat
        let columnWidths: [CGFloat]
        let rowHeights: [CGFloat]
        let rowSeparatorWidth: CGFloat
        let columnGap: CGFloat
    }

    private var rows: [MarkdownTableRow]
    private let style: MarkdownTableStyle
    private var columnCount: Int
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private var rowViews: [MarkdownTableRowView] = []
    private var cellViews: [[MarkdownStaticAttributedLabel]] = []
    private var cachedLayout: Layout?
    private var cachedWidth: CGFloat = 0
    private var appliedContentVersion: UInt64 = 0
    private var laidOutRowCount: Int = 0
    private var laidOutContentWidth: CGFloat = 0
    private var laidOutContentHeight: CGFloat = 0
    private var laidOutColumnWidths: [CGFloat] = []
    private var needsImmediateLayout: Bool = true
    private weak var attachment: MarkdownTableAttachment?
    private var pendingScrollOffsetX: CGFloat?

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
        scrollView.delegate = self
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
            needsImmediateLayout = true
        }
        if needsImmediateLayout {
            needsImmediateLayout = false
            setNeedsLayout()
        }
        return cachedLayout?.tableSize ?? CGSize(width: targetWidth, height: 0)
    }

    func applyUpdate(from attachment: MarkdownTableAttachment) {
        self.attachment = attachment
        pendingScrollOffsetX = attachment.hostedHorizontalOffset()
        guard attachment.contentVersion != appliedContentVersion else { return }
        applySnapshot(rows: attachment.rows)
        appliedContentVersion = attachment.contentVersion
    }

    func applySnapshot(rows nextRows: [MarkdownTableRow]) {
        guard !nextRows.isEmpty else { return }
        let preservedOffsetX = pendingScrollOffsetX ?? scrollView.contentOffset.x

        if nextRows.count < rows.count || columnCount == 0 {
            let nextColumnCount = nextRows.map { $0.cells.count }.max() ?? 0
            guard nextColumnCount > 0 else { return }
            rebuild(rows: nextRows, columnCount: nextColumnCount)
            needsImmediateLayout = true
            pendingScrollOffsetX = preservedOffsetX
            setNeedsLayout()
            return
        }

        let appendedCount = nextRows.count - rows.count
        if appendedCount == 0 {
            let nextMaxColumns = nextRows.map { $0.cells.count }.max() ?? 0
            let nextColumnCount = max(columnCount, nextMaxColumns)
            if nextColumnCount != columnCount {
                rebuild(rows: nextRows, columnCount: nextColumnCount)
                needsImmediateLayout = true
                pendingScrollOffsetX = preservedOffsetX
                setNeedsLayout()
                return
            }
            guard !rows.isEmpty else { return }

            let lastIndex = rows.count - 1
            let priorLayout = cachedLayout
            let oldLastRowHeight: CGFloat? = {
                guard let priorLayout, priorLayout.rowHeights.indices.contains(lastIndex) else { return nil }
                return priorLayout.rowHeights[lastIndex]
            }()
            var shouldRelayout = false

            rows = nextRows
            updateRowContent(at: lastIndex)

            if let priorLayout,
               let oldLastRowHeight,
               priorLayout.columnWidths.count == columnCount,
               priorLayout.rowHeights.count == rows.count {
                let paddingX = style.cellPadding.width
                let maxCellTextWidth = max(80, min(cachedWidth * 0.8, 360))
                let maxColumnWidth = maxCellTextWidth + paddingX * 2
                let columnWidthGrowthStep = max(8, style.baseFont.pointSize * 0.55)
                let emptyCell = NSAttributedString(string: "", attributes: [.font: style.baseFont])
                let lastRow = rows[lastIndex]

                var updatedColumnWidths = priorLayout.columnWidths
                for column in 0..<columnCount {
                    guard updatedColumnWidths[column] < maxColumnWidth - 0.5 else { continue }
                    let cell = column < lastRow.cells.count ? lastRow.cells[column] : emptyCell
                    let size = measureAttributedText(cell, width: .greatestFiniteMagnitude)
                    let desiredTextWidth = min(size.width, maxCellTextWidth)
                    let desiredColumnWidth = desiredTextWidth + paddingX * 2
                    let growth = desiredColumnWidth - updatedColumnWidths[column]
                    if growth > 0.5 {
                        let reachesColumnCap = desiredColumnWidth >= maxColumnWidth - 0.5
                        guard reachesColumnCap || growth >= columnWidthGrowthStep else { continue }
                        updatedColumnWidths[column] = desiredColumnWidth
                    }
                }

                let totalColumnGap = priorLayout.columnGap * CGFloat(max(0, columnCount - 1))
                let updatedContentWidth = updatedColumnWidths.reduce(0, +) + totalColumnGap
                let newLastRowHeight = measureRowHeight(rows[lastIndex], columnWidths: updatedColumnWidths)
                let heightDelta = newLastRowHeight - oldLastRowHeight
                var updatedHeights = priorLayout.rowHeights
                updatedHeights[lastIndex] = newLastRowHeight
                let viewportWidth = min(cachedWidth, updatedContentWidth)
                cachedLayout = Layout(
                    tableSize: CGSize(width: viewportWidth, height: priorLayout.tableSize.height + heightDelta),
                    contentWidth: updatedContentWidth,
                    columnWidths: updatedColumnWidths,
                    rowHeights: updatedHeights,
                    rowSeparatorWidth: priorLayout.rowSeparatorWidth,
                    columnGap: priorLayout.columnGap
                )

                let needsFullRelayout =
                    abs(updatedContentWidth - priorLayout.contentWidth) > 0.5 ||
                    !columnWidthsApproximatelyEqual(updatedColumnWidths, priorLayout.columnWidths)
                let rowHeightChanged = abs(heightDelta) > 0.5

                if needsFullRelayout {
                    laidOutRowCount = 0
                    laidOutContentHeight = 0
                    laidOutContentWidth = 0
                    laidOutColumnWidths.removeAll(keepingCapacity: false)
                    shouldRelayout = true
                } else if laidOutRowCount == rows.count {
                    let startY = max(0, priorLayout.tableSize.height - (oldLastRowHeight + priorLayout.rowSeparatorWidth))
                    laidOutRowCount = lastIndex
                    laidOutContentHeight = startY
                    shouldRelayout = rowHeightChanged
                } else {
                    laidOutRowCount = 0
                    laidOutContentHeight = 0
                    laidOutContentWidth = 0
                    laidOutColumnWidths.removeAll(keepingCapacity: false)
                    shouldRelayout = true
                }
            } else {
                cachedLayout = nil
                laidOutRowCount = 0
                laidOutContentHeight = 0
                laidOutContentWidth = 0
                laidOutColumnWidths.removeAll(keepingCapacity: false)
                shouldRelayout = true
            }

            if shouldRelayout {
                needsImmediateLayout = true
                pendingScrollOffsetX = preservedOffsetX
                setNeedsLayout()
            } else {
                pendingScrollOffsetX = nil
                attachment?.setHostedHorizontalOffset(scrollView.contentOffset.x)
            }
            return
        } else if appendedCount < 0 {
            return
        }

        let appendedRows = Array(nextRows.suffix(appendedCount))
        let appendedMaxColumns = appendedRows.map { $0.cells.count }.max() ?? 0
        let nextColumnCount = max(columnCount, appendedMaxColumns)
        if nextColumnCount != columnCount {
            rebuild(rows: nextRows, columnCount: nextColumnCount)
            needsImmediateLayout = true
            pendingScrollOffsetX = preservedOffsetX
            setNeedsLayout()
            return
        }

        rows = nextRows
        appendRows(appendedRows)
        if let updatedLayout = extendLayout(with: appendedRows) {
            cachedLayout = updatedLayout
        } else {
            cachedLayout = nil
        }

        needsImmediateLayout = true
        pendingScrollOffsetX = preservedOffsetX
        setNeedsLayout()
    }

    private func updateRowContent(at rowIndex: Int) {
        guard rowIndex >= 0, rowIndex < rows.count else { return }
        guard rowIndex < cellViews.count else { return }
        let row = rows[rowIndex]
        let emptyCell = NSAttributedString(string: "", attributes: [.font: style.baseFont])
        for column in 0..<columnCount {
            guard column < cellViews[rowIndex].count else { continue }
            let cellText = column < row.cells.count ? row.cells[column] : emptyCell
            updateCellText(cellViews[rowIndex][column], next: cellText)
        }
    }

    private func updateCellText(_ cellView: MarkdownStaticAttributedLabel, next: NSAttributedString) {
        if let current = cellView.attributedText, current.isEqual(to: next) {
            return
        }
        cellView.attributedText = next
        cellView.setNeedsDisplay()
    }

    private func measureRowHeight(_ row: MarkdownTableRow, columnWidths: [CGFloat]) -> CGFloat {
        let paddingX = style.cellPadding.width
        let paddingY = style.cellPadding.height
        let minRowHeight = style.baseFont.lineHeight
        let emptyCell = NSAttributedString(string: "", attributes: [.font: style.baseFont])

        var rowHeight: CGFloat = 0
        for column in 0..<columnCount {
            let cell = column < row.cells.count ? row.cells[column] : emptyCell
            let textWidth = max(0, columnWidths[column] - paddingX * 2)
            let size = measureAttributedText(cell, width: textWidth)
            rowHeight = max(rowHeight, max(size.height, minRowHeight))
        }
        return rowHeight + paddingY * 2
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width > 0 ? bounds.width : cachedWidth
        let resolvedWidth = max(1, width)
        let didRecomputeLayout: Bool
        if abs(resolvedWidth - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: resolvedWidth)
            cachedWidth = resolvedWidth
            didRecomputeLayout = true
        } else {
            didRecomputeLayout = false
        }
        guard let layout = cachedLayout else { return }
        scrollView.frame = bounds
        scrollView.contentSize = CGSize(width: layout.contentWidth, height: layout.tableSize.height)
        contentView.frame = CGRect(x: 0, y: 0, width: layout.contentWidth, height: layout.tableSize.height)

        let padding = style.cellPadding
        let rowSeparator = layout.rowSeparatorWidth
        let hasHeader = rows.first?.isHeader == true

        let needsFullRelayout: Bool =
            didRecomputeLayout ||
            laidOutRowCount > rows.count ||
            abs(laidOutContentWidth - layout.contentWidth) > 0.5 ||
            !columnWidthsApproximatelyEqual(laidOutColumnWidths, layout.columnWidths)

        if needsFullRelayout {
            laidOutRowCount = 0
            laidOutContentHeight = 0
            laidOutContentWidth = layout.contentWidth
            laidOutColumnWidths = layout.columnWidths
        }

        let startIndex = needsFullRelayout ? 0 : laidOutRowCount
        guard startIndex < rows.count else {
            restoreScrollOffsetIfNeeded()
            return
        }

        var y: CGFloat = needsFullRelayout ? 0 : laidOutContentHeight
        for rowIndex in startIndex..<rows.count {
            guard rowIndex < rowViews.count, rowIndex < layout.rowHeights.count else { continue }
            let row = rows[rowIndex]
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

        laidOutRowCount = rows.count
        laidOutContentHeight = y
        restoreScrollOffsetIfNeeded()
    }

    private func columnWidthsApproximatelyEqual(_ a: [CGFloat], _ b: [CGFloat]) -> Bool {
        guard a.count == b.count else { return false }
        for index in 0..<a.count {
            if abs(a[index] - b[index]) > 0.5 { return false }
        }
        return true
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

            var rowCells: [MarkdownStaticAttributedLabel] = []
            rowCells.reserveCapacity(columnCount)
            for column in 0..<columnCount {
                let cellText = column < row.cells.count ? row.cells[column] : emptyCell
                let cellView = makeCellView(text: cellText)
                rowView.addSubview(cellView)
                rowCells.append(cellView)
            }
            cellViews.append(rowCells)
        }
    }

    private func rebuild(rows: [MarkdownTableRow], columnCount: Int) {
        self.rows = rows
        self.columnCount = columnCount
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll(keepingCapacity: false)
        cellViews.removeAll(keepingCapacity: false)
        buildRows()
        cachedLayout = nil
        cachedWidth = 0
        laidOutRowCount = 0
        laidOutContentWidth = 0
        laidOutContentHeight = 0
        laidOutColumnWidths.removeAll(keepingCapacity: false)
    }

    private func appendRows(_ newRows: [MarkdownTableRow]) {
        guard !newRows.isEmpty, columnCount > 0 else { return }
        let emptyCell = NSAttributedString(string: "", attributes: [.font: style.baseFont])
        for row in newRows {
            let rowView = MarkdownTableRowView()
            rowView.separatorView.backgroundColor = style.borderColor
            contentView.addSubview(rowView)
            rowViews.append(rowView)

            var rowCells: [MarkdownStaticAttributedLabel] = []
            rowCells.reserveCapacity(columnCount)
            for column in 0..<columnCount {
                let cellText = column < row.cells.count ? row.cells[column] : emptyCell
                let cellView = makeCellView(text: cellText)
                rowView.addSubview(cellView)
                rowCells.append(cellView)
            }
            cellViews.append(rowCells)
        }
    }

    private func makeCellView(text: NSAttributedString) -> MarkdownStaticAttributedLabel {
        let view = MarkdownStaticAttributedLabel()
        view.attributedText = text
        return view
    }

    private func restoreScrollOffsetIfNeeded() {
        let sourceOffset = pendingScrollOffsetX ?? scrollView.contentOffset.x
        let maxOffsetX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let clamped = min(max(0, sourceOffset), maxOffsetX)
        pendingScrollOffsetX = nil
        if abs(scrollView.contentOffset.x - clamped) > 0.5 || abs(scrollView.contentOffset.y) > 0.5 {
            scrollView.setContentOffset(CGPoint(x: clamped, y: 0), animated: false)
        }
        attachment?.setHostedHorizontalOffset(clamped)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        attachment?.setHostedHorizontalOffset(scrollView.contentOffset.x)
    }

    private func extendLayout(with appendedRows: [MarkdownTableRow]) -> Layout? {
        guard let existing = cachedLayout else { return nil }
        guard abs(cachedWidth) > 0.5 else { return nil }
        guard columnCount > 0 else { return nil }
        guard existing.columnWidths.count == columnCount else { return nil }

        let rowSeparator = existing.rowSeparatorWidth
        let columnGap = existing.columnGap
        let paddingX = style.cellPadding.width
        let paddingY = style.cellPadding.height
        let maxCellTextWidth = max(80, min(cachedWidth * 0.8, 360))
        let maxColumnWidth = maxCellTextWidth + paddingX * 2

        let emptyCell = NSAttributedString(string: "", attributes: [.font: style.baseFont])
        var columnWidths = existing.columnWidths
        for row in appendedRows {
            for column in 0..<columnCount {
                guard columnWidths[column] < maxColumnWidth - 0.5 else { continue }
                let cell = column < row.cells.count ? row.cells[column] : emptyCell
                let size = measureAttributedText(cell, width: .greatestFiniteMagnitude)
                let desiredTextWidth = min(size.width, maxCellTextWidth)
                let desiredColumnWidth = desiredTextWidth + paddingX * 2
                if desiredColumnWidth > columnWidths[column] + 0.5 {
                    columnWidths[column] = desiredColumnWidth
                }
            }
        }
        let minRowHeight = style.baseFont.lineHeight
        var rowHeights = existing.rowHeights
        rowHeights.reserveCapacity(rows.count)
        var appendedHeightsSum: CGFloat = 0
        for row in appendedRows {
            var rowHeight: CGFloat = 0
            for column in 0..<columnCount {
                let cell = column < row.cells.count ? row.cells[column] : emptyCell
                let textWidth = max(0, columnWidths[column] - paddingX * 2)
                let size = measureAttributedText(cell, width: textWidth)
                rowHeight = max(rowHeight, max(size.height, minRowHeight))
            }
            let finalHeight = rowHeight + paddingY * 2
            rowHeights.append(finalHeight)
            appendedHeightsSum += finalHeight
        }

        let totalColumnGap = columnGap * CGFloat(max(0, columnCount - 1))
        let tableWidth = columnWidths.reduce(0, +) + totalColumnGap
        let tableHeight = existing.tableSize.height + appendedHeightsSum + rowSeparator * CGFloat(appendedRows.count)
        let viewportWidth = min(cachedWidth, tableWidth)
        return Layout(
            tableSize: CGSize(width: viewportWidth, height: tableHeight),
            contentWidth: tableWidth,
            columnWidths: columnWidths,
            rowHeights: rowHeights,
            rowSeparatorWidth: rowSeparator,
            columnGap: columnGap
        )
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
        let emptyCell = NSAttributedString(string: "", attributes: [.font: style.baseFont])

        var contentWidths = Array(repeating: CGFloat(0), count: columnCount)
        for row in rows {
            for column in 0..<columnCount {
                let cell = column < row.cells.count ? row.cells[column] : emptyCell
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
                let cell = column < row.cells.count ? row.cells[column] : emptyCell
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
    private let textLabel = MarkdownStaticAttributedLabel()
    private var cachedLayout: Layout?
    private var cachedWidth: CGFloat = 0

    init(content: NSAttributedString, style: MarkdownQuoteStyle) {
        self.content = content
        self.style = style
        super.init(frame: .zero)

        borderView.backgroundColor = style.borderColor
        addSubview(borderView)

        textLabel.attributedText = content
        addSubview(textLabel)
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
        textLabel.frame = layout.textFrame
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
        let cacheKey: BoundsCacheKey?
    }

    private enum Kind: Sendable {
        case codeBlock
        case table
        case quote
        case rule
        case unknown
    }

    private struct BoundsCacheKey: Sendable, Equatable {
        let kind: Kind
        let contentVersion: UInt64
        let availableWidthKey: Int
    }

    @MainActor
    private static let viewCache = NSMapTable<MarkdownAttachment, UIView>(
        keyOptions: .weakMemory,
        valueOptions: .weakMemory
    )

    private var cachedBoundsKey: BoundsCacheKey?
    private var cachedBounds: CGRect = .zero

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
        let markdownAttachmentBox = UncheckedSendableBox(value: textAttachment as? MarkdownAttachment)
        let viewBox: UncheckedSendableBox<UIView> = MainActor.assumeIsolated {
            if let attachment = markdownAttachmentBox.value,
               let cached = Self.cachedView(for: attachment) {
                return UncheckedSendableBox(value: cached)
            }
            let created = Self.makeView(for: markdownAttachmentBox.value)
            if let attachment = markdownAttachmentBox.value {
                Self.cache(view: created, for: attachment)
            }
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

        let markdownAttachmentBox = UncheckedSendableBox(value: textAttachment as? MarkdownAttachment)
        let currentViewBox = UncheckedSendableBox(value: view)
        let cachedBoundsKeySnapshot = cachedBoundsKey
        let cachedBoundsSnapshot = cachedBounds
        let lineWidth = proposedLineFragment.width

        let layout: AttachmentLayout = MainActor.assumeIsolated {
            guard let attachment = markdownAttachmentBox.value else {
                let resolvedView = currentViewBox.value ?? UIView()
                return AttachmentLayout(view: UncheckedSendableBox(value: resolvedView), bounds: .zero, cacheKey: nil)
            }

            let available = attachmentAvailableWidth(maxWidth: attachment.maxWidth, lineFragWidth: lineWidth)
            let availableWidthKey = Self.widthKey(available)

            func cachedLayoutIfPossible(kind: Kind, contentVersion: UInt64) -> AttachmentLayout? {
                let key = BoundsCacheKey(kind: kind, contentVersion: contentVersion, availableWidthKey: availableWidthKey)
                guard key == cachedBoundsKeySnapshot else { return nil }
                guard let existing = currentViewBox.value else { return nil }
                return AttachmentLayout(view: UncheckedSendableBox(value: existing), bounds: cachedBoundsSnapshot, cacheKey: key)
            }

            switch attachment {
            case let codeAttachment as MarkdownCodeBlockAttachment:
                if let cached = cachedLayoutIfPossible(kind: .codeBlock, contentVersion: codeAttachment.contentVersion) {
                    return cached
                }
                let resolvedView: MarkdownCodeBlockView
                if let existing = currentViewBox.value as? MarkdownCodeBlockView {
                    resolvedView = existing
                } else if let cached = Self.cachedView(for: codeAttachment) as? MarkdownCodeBlockView {
                    resolvedView = cached
                } else {
                    resolvedView = MarkdownCodeBlockView(
                        code: codeAttachment.code,
                        languageLabel: codeAttachment.languageLabel,
                        copyLabel: codeAttachment.copyLabel,
                        style: codeAttachment.style,
                        codeAttributed: codeAttachment.codeAttributed,
                        estimatedCodeTextSize: codeAttachment.estimatedCodeTextSize
                    )
                }
                Self.cache(view: resolvedView, for: codeAttachment)
                resolvedView.applyUpdate(from: codeAttachment)
                let bounds = CGRect(origin: .zero, size: resolvedView.sizeThatFitsWidth(available))
                let key = BoundsCacheKey(
                    kind: .codeBlock,
                    contentVersion: codeAttachment.contentVersion,
                    availableWidthKey: availableWidthKey
                )
                return AttachmentLayout(view: UncheckedSendableBox(value: resolvedView), bounds: bounds, cacheKey: key)

            case let tableAttachment as MarkdownTableAttachment:
                if let cached = cachedLayoutIfPossible(kind: .table, contentVersion: tableAttachment.contentVersion) {
                    return cached
                }
                let resolvedView: MarkdownTableView
                if let existing = currentViewBox.value as? MarkdownTableView {
                    resolvedView = existing
                } else if let cached = Self.cachedView(for: tableAttachment) as? MarkdownTableView {
                    resolvedView = cached
                } else {
                    resolvedView = MarkdownTableView(rows: tableAttachment.rows, style: tableAttachment.style)
                }
                Self.cache(view: resolvedView, for: tableAttachment)
                resolvedView.applyUpdate(from: tableAttachment)
                let bounds = CGRect(origin: .zero, size: resolvedView.sizeThatFitsWidth(available))
                let key = BoundsCacheKey(
                    kind: .table,
                    contentVersion: tableAttachment.contentVersion,
                    availableWidthKey: availableWidthKey
                )
                return AttachmentLayout(view: UncheckedSendableBox(value: resolvedView), bounds: bounds, cacheKey: key)

            case let quoteAttachment as MarkdownQuoteAttachment:
                if let cached = cachedLayoutIfPossible(kind: .quote, contentVersion: quoteAttachment.contentVersion) {
                    return cached
                }
                let resolvedView: MarkdownQuoteView
                if let existing = currentViewBox.value as? MarkdownQuoteView {
                    resolvedView = existing
                } else if let cached = Self.cachedView(for: quoteAttachment) as? MarkdownQuoteView {
                    resolvedView = cached
                } else {
                    resolvedView = MarkdownQuoteView(content: quoteAttachment.content, style: quoteAttachment.style)
                }
                Self.cache(view: resolvedView, for: quoteAttachment)
                let bounds = CGRect(origin: .zero, size: resolvedView.sizeThatFitsWidth(available))
                let key = BoundsCacheKey(
                    kind: .quote,
                    contentVersion: quoteAttachment.contentVersion,
                    availableWidthKey: availableWidthKey
                )
                return AttachmentLayout(view: UncheckedSendableBox(value: resolvedView), bounds: bounds, cacheKey: key)

            case let ruleAttachment as MarkdownRuleAttachment:
                if let cached = cachedLayoutIfPossible(kind: .rule, contentVersion: ruleAttachment.contentVersion) {
                    return cached
                }
                let resolvedView: MarkdownRuleView
                if let existing = currentViewBox.value as? MarkdownRuleView {
                    resolvedView = existing
                } else if let cached = Self.cachedView(for: ruleAttachment) as? MarkdownRuleView {
                    resolvedView = cached
                } else {
                    resolvedView = MarkdownRuleView(
                        color: ruleAttachment.color,
                        thickness: ruleAttachment.thickness,
                        verticalPadding: ruleAttachment.verticalPadding
                    )
                }
                Self.cache(view: resolvedView, for: ruleAttachment)
                let bounds = CGRect(origin: .zero, size: resolvedView.sizeThatFitsWidth(available))
                let key = BoundsCacheKey(
                    kind: .rule,
                    contentVersion: ruleAttachment.contentVersion,
                    availableWidthKey: availableWidthKey
                )
                return AttachmentLayout(view: UncheckedSendableBox(value: resolvedView), bounds: bounds, cacheKey: key)

            default:
                if let cached = cachedLayoutIfPossible(kind: .unknown, contentVersion: attachment.contentVersion) {
                    return cached
                }
                let resolvedView = currentViewBox.value ?? UIView()
                let bounds = CGRect(x: 0, y: 0, width: available, height: 0)
                let key = BoundsCacheKey(
                    kind: .unknown,
                    contentVersion: attachment.contentVersion,
                    availableWidthKey: availableWidthKey
                )
                return AttachmentLayout(view: UncheckedSendableBox(value: resolvedView), bounds: bounds, cacheKey: key)
            }
        }

        view = layout.view.value
        if let key = layout.cacheKey {
            self.cachedBoundsKey = key
            self.cachedBounds = layout.bounds
        }
        return layout.bounds
    }

    @MainActor
    private static func makeView(for attachment: MarkdownAttachment?) -> UIView {
        guard let attachment else {
            return UIView()
        }
        switch attachment {
        case let attachment as MarkdownCodeBlockAttachment:
            return MarkdownCodeBlockView(
                code: attachment.code,
                languageLabel: attachment.languageLabel,
                copyLabel: attachment.copyLabel,
                style: attachment.style,
                codeAttributed: attachment.codeAttributed,
                estimatedCodeTextSize: attachment.estimatedCodeTextSize
            )
        case let attachment as MarkdownTableAttachment:
            return MarkdownTableView(rows: attachment.rows, style: attachment.style)
        case let attachment as MarkdownQuoteAttachment:
            return MarkdownQuoteView(content: attachment.content, style: attachment.style)
        case let attachment as MarkdownRuleAttachment:
            return MarkdownRuleView(
                color: attachment.color,
                thickness: attachment.thickness,
                verticalPadding: attachment.verticalPadding
            )
        default:
            return UIView()
        }
    }

    private static func widthKey(_ width: CGFloat) -> Int {
        Int((max(0, width) * 2).rounded())
    }

    @MainActor
    private static func cachedView(for attachment: MarkdownAttachment) -> UIView? {
        viewCache.object(forKey: attachment)
    }

    @MainActor
    private static func cache(view: UIView, for attachment: MarkdownAttachment) {
        viewCache.setObject(view, forKey: attachment)
    }
}


#endif
