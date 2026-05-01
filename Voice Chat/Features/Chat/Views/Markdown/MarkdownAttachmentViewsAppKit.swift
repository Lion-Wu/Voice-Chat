#if os(macOS)
@preconcurrency import Foundation
@preconcurrency import AppKit
@preconcurrency import QuartzCore

private func performWithoutMarkdownImplicitAnimations(_ body: () -> Void) {
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0
        context.allowsImplicitAnimation = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}

@MainActor
private func makeMarkdownAppKitTextView() -> NSTextView {
    MarkdownNonScrollingTextView(usingTextLayoutManager: true)
}

private class MarkdownNonScrollingTextView: NSTextView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

private final class MarkdownStaticTextView: MarkdownNonScrollingTextView {
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        nextResponder?.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        nextResponder?.rightMouseDown(with: event)
    }
}

private final class MarkdownHorizontalScrollView: NSScrollView {
    private var isHandlingHorizontalScrollSequence = false

    override func scrollWheel(with event: NSEvent) {
        let horizontalDelta = abs(event.scrollingDeltaX)
        let verticalDelta = abs(event.scrollingDeltaY)
        let prefersHorizontal = horizontalDelta > 0.1 && horizontalDelta >= verticalDelta
        let isMomentum = !event.momentumPhase.isEmpty

        if event.phase.contains(.mayBegin) || event.phase.contains(.began) {
            isHandlingHorizontalScrollSequence = prefersHorizontal
        } else if prefersHorizontal {
            isHandlingHorizontalScrollSequence = true
        }

        let shouldHandle = prefersHorizontal || (isMomentum && isHandlingHorizontalScrollSequence)
        if shouldHandle {
            super.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }

        if event.phase.contains(.cancelled) ||
            event.momentumPhase.contains(.ended) ||
            event.momentumPhase.contains(.cancelled) {
            isHandlingHorizontalScrollSequence = false
        }
    }
}

@MainActor
private func markdownClampRange(_ range: NSRange, upperBound: Int) -> NSRange {
    let start = Swift.max(0, Swift.min(range.location, upperBound))
    let end = Swift.max(0, Swift.min(range.location + range.length, upperBound))
    return NSRange(location: start, length: max(0, end - start))
}

@MainActor
private func markdownNormalizedInvalidationRange(
    changedRange: NSRange?,
    storageLength: Int
) -> NSRange {
    guard storageLength > 0 else {
        return NSRange(location: 0, length: 0)
    }
    let fullRange = NSRange(location: 0, length: storageLength)
    let clamped = markdownClampRange(changedRange ?? fullRange, upperBound: storageLength)
    let start = max(0, min(clamped.location, storageLength))
    guard start < storageLength else {
        return NSRange(location: storageLength - 1, length: 1)
    }
    return NSRange(location: start, length: storageLength - start)
}

@MainActor
private func markdownTextRange(
    _ range: NSRange,
    documentRange: NSTextRange,
    contentManager: NSTextContentManager?,
    storageLength: Int
) -> NSTextRange? {
    guard let contentManager else { return nil }
    let clamped = markdownClampRange(range, upperBound: storageLength)
    let startOffset = max(0, clamped.location)
    let length = max(0, clamped.length)
    let endOffset = min(storageLength, startOffset + length)

    if startOffset == 0, endOffset == storageLength {
        return documentRange
    }

    let startDistanceToStart = startOffset
    let startDistanceToEnd = storageLength - startOffset
    let useEndForStart = startDistanceToEnd < startDistanceToStart
    let startAnchor = useEndForStart ? documentRange.endLocation : documentRange.location
    let startAnchorOffset = useEndForStart ? startOffset - storageLength : startOffset
    guard let startLocation = contentManager.location(startAnchor, offsetBy: startAnchorOffset) else {
        return nil
    }

    if length == 0 {
        return NSTextRange(location: startLocation)
    }

    let endLocation: any NSTextLocation
    if endOffset == storageLength {
        endLocation = documentRange.endLocation
    } else {
        let endDistanceToStart = endOffset
        let endDistanceToEnd = storageLength - endOffset
        let useEndForEnd = endDistanceToEnd < endDistanceToStart
        let endAnchor = useEndForEnd ? documentRange.endLocation : documentRange.location
        let endAnchorOffset = useEndForEnd ? endOffset - storageLength : endOffset
        guard let resolvedEndLocation = contentManager.location(endAnchor, offsetBy: endAnchorOffset) else {
            return nil
        }
        endLocation = resolvedEndLocation
    }

    return NSTextRange(location: startLocation, end: endLocation)
}

@MainActor
private func ensureMarkdownTextLayout(
    in textView: NSTextView,
    changedRange: NSRange?,
    invalidatesLayout: Bool = true
) {
    guard let storage = textView.textStorage else { return }
    let range = markdownNormalizedInvalidationRange(changedRange: changedRange, storageLength: storage.length)
    if let textLayoutManager = textView.textLayoutManager,
       let documentRange = textLayoutManager.textContentManager?.documentRange {
        let textRange = markdownTextRange(
            range,
            documentRange: documentRange,
            contentManager: textLayoutManager.textContentManager,
            storageLength: storage.length
        ) ?? documentRange
        if invalidatesLayout {
            textLayoutManager.invalidateLayout(for: textRange)
        }
        textLayoutManager.ensureLayout(for: textRange)
        return
    }

    guard let layoutManager = textView.layoutManager else { return }
    layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
    layoutManager.ensureLayout(forCharacterRange: range)
    layoutManager.invalidateDisplay(forCharacterRange: range)
}

final class MarkdownCodeBlockView: NSView {
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
        // Keep measured code width bounded so long lines cannot grow the hosted text
        // container without a cap during streaming updates.
        static let initialContainerWidth: CGFloat = 4_096
        static let maxContainerWidth: CGFloat = 131_072
        static let widthCapThreshold: CGFloat = 1
    }

    override var isFlipped: Bool { true }

    private let style: MarkdownCodeBlockStyle
    private var code: String
    private var codeAttributed: NSAttributedString
    private var estimatedCodeTextSize: CGSize
    private var measuredMaxLineWidth: CGFloat = 0
    private var hasMeasuredMaxLineWidth: Bool = false
    private var renderedLineCount: Int
    private var languageText: String
    private var copyText: String
    private var appliedContentVersion: UInt64 = 0
    private var pendingAttachmentBoundsChange = false

    private let headerView = NSView()
    private let headerSeparator = NSView()
    private let languageLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private let scrollView = MarkdownHorizontalScrollView()
    private let codeTextView = makeMarkdownAppKitTextView()
    private var cachedLayout: Layout?
    private var cachedWidth: CGFloat = 0
    private weak var attachment: MarkdownCodeBlockAttachment?
    private var pendingScrollOffsetX: CGFloat?
    private var isShowingCopyFeedback = false
    private var copyFeedbackTask: Task<Void, Never>?

    private static let copyFeedbackText = "✓"
    private static let copyFeedbackDuration = Duration.seconds(1.2)

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
        self.renderedLineCount = Self.lineCount(in: code)
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
        languageLabel.alignment = .natural
        languageLabel.lineBreakMode = .byTruncatingTail
        languageLabel.stringValue = languageText
        headerView.addSubview(languageLabel)

        copyButton.target = self
        copyButton.action = #selector(handleCopy)
        copyButton.isBordered = false
        copyButton.bezelStyle = .regularSquare
        updateCopyButtonAppearance()
        headerView.addSubview(copyButton)

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.userInterfaceLayoutDirection = .leftToRight
        addSubview(scrollView)

        codeTextView.drawsBackground = false
        codeTextView.isEditable = false
        codeTextView.isSelectable = true
        codeTextView.userInterfaceLayoutDirection = .leftToRight
        codeTextView.baseWritingDirection = .leftToRight
        codeTextView.alignment = .left
        codeTextView.textContainerInset = .zero
        codeTextView.textContainer?.lineFragmentPadding = 0
        codeTextView.textContainer?.lineBreakMode = .byClipping
        codeTextView.textContainer?.widthTracksTextView = false
        codeTextView.textContainer?.heightTracksTextView = false
        codeTextView.textContainer?.containerSize = CGSize(width: MeasurementSizing.initialContainerWidth, height: 10_000_000)
        codeTextView.isHorizontallyResizable = true
        codeTextView.isVerticallyResizable = false
        codeTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        codeTextView.minSize = .zero
        if let textLayoutManager = codeTextView.textLayoutManager {
            textLayoutManager.usesFontLeading = true
        } else {
            codeTextView.layoutManager?.allowsNonContiguousLayout = false
            codeTextView.layoutManager?.usesFontLeading = true
        }
        codeTextView.textStorage?.setAttributedString(codeAttributed)
        scrollView.documentView = codeTextView

        updateMeasuredMaxLineWidth(reset: true, changedCharacterRange: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        copyFeedbackTask?.cancel()
    }

    func sizeThatFitsWidth(_ width: CGFloat) -> CGSize {
        let targetWidth = max(1, width)
        if abs(targetWidth - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: targetWidth)
            cachedWidth = targetWidth
            needsLayout = true
        }
        return cachedLayout?.size ?? CGSize(width: targetWidth, height: 0)
    }

    @discardableResult
    func applyUpdate(from attachment: MarkdownCodeBlockAttachment) -> Bool {
        self.attachment = attachment
        pendingScrollOffsetX = attachment.hostedHorizontalOffset()
        guard attachment.contentVersion != appliedContentVersion else {
            return pendingAttachmentBoundsChange
        }
        let needsLayoutInvalidation = applySnapshot(
            code: attachment.code,
            languageLabel: attachment.languageLabel,
            copyLabel: attachment.copyLabel,
            codeAttributed: attachment.codeAttributed,
            estimatedCodeTextSize: attachment.estimatedCodeTextSize
        )
        appliedContentVersion = attachment.contentVersion
        if needsLayoutInvalidation {
            pendingAttachmentBoundsChange = true
        }
        return pendingAttachmentBoundsChange
    }

    func markAttachmentBoundsObserved() {
        pendingAttachmentBoundsChange = false
    }

    @discardableResult
    func applySnapshot(
        code: String,
        languageLabel: String,
        copyLabel: String,
        codeAttributed: NSAttributedString,
        estimatedCodeTextSize: CGSize
    ) -> Bool {
        let oldLen = codeTextView.textStorage?.length ?? 0
        let newLen = codeAttributed.length
        guard newLen != oldLen || self.code != code else { return false }
        let preservedOffsetX = pendingScrollOffsetX ?? scrollView.contentView.bounds.origin.x

        let shouldAppend = newLen > oldLen && code.hasPrefix(self.code)
        let redrawStartLine = shouldAppend ? max(0, renderedLineCount - 1) : 0
        var appendedText = ""
        if let storage = codeTextView.textStorage {
            storage.beginEditing()
            if shouldAppend {
                let delta = codeAttributed.attributedSubstring(from: NSRange(location: oldLen, length: newLen - oldLen))
                if delta.length > 0 {
                    appendedText = delta.string
                    storage.append(delta)
                }
            } else {
                storage.setAttributedString(codeAttributed)
            }
            storage.endEditing()
        } else {
            codeTextView.textStorage?.setAttributedString(codeAttributed)
        }

        var textContainerHeightChanged = false
        if let textContainer = codeTextView.textContainer {
            let current = textContainer.containerSize
            let targetHeight = max(current.height, estimatedCodeTextSize.height)
            if abs(current.height - targetHeight) > 0.5 {
                textContainer.containerSize = CGSize(width: current.width, height: targetHeight)
                textContainerHeightChanged = true
            }
        }

        let start = max(0, oldLen - 1)
        let range = NSRange(location: start, length: max(0, newLen - start))
        ensureMarkdownTextLayout(in: codeTextView, changedRange: range)
        if shouldAppend {
            renderedLineCount += Self.lineBreakCount(in: appendedText)
            updateMeasuredMaxLineWidth(reset: false, changedCharacterRange: range)
        } else {
            renderedLineCount = Self.lineCount(in: code)
            updateMeasuredMaxLineWidth(reset: true, changedCharacterRange: nil)
        }

        self.code = code
        self.codeAttributed = codeAttributed
        self.estimatedCodeTextSize = estimatedCodeTextSize
        languageText = languageLabel
        copyText = copyLabel
        self.languageLabel.stringValue = languageLabel
        updateCopyButtonAppearance()

        let layoutWidth = max(1, bounds.width > 0 ? bounds.width : max(cachedWidth, MeasurementSizing.initialContainerWidth))
        let priorLayout = cachedLayout
        let measuredLayout = computeLayout(width: layoutWidth)
        var nextLayout = measuredLayout
        var deferredInlineWidthGrowth = false
        if let priorLayout {
            let contentWidthGrowth = measuredLayout.contentWidth - priorLayout.contentWidth
            let canDeferWidthGrowth =
                contentWidthGrowth > 0.5 &&
                contentWidthGrowth < 8 &&
                abs(measuredLayout.size.height - priorLayout.size.height) <= 0.5
            if canDeferWidthGrowth {
                nextLayout = layoutByDeferringSmallCodeWidthGrowth(
                    priorLayout: priorLayout,
                    measuredLayout: measuredLayout
                )
                deferredInlineWidthGrowth = abs(nextLayout.contentWidth - priorLayout.contentWidth) > 0.5
            }
        }
        cachedLayout = nextLayout
        cachedWidth = layoutWidth

        let geometryChanged = deferredInlineWidthGrowth
            ? false
            : !layoutsApproximatelyEqual(priorLayout, nextLayout)
        let attachmentBoundsChanged = !attachmentBoundsApproximatelyEqual(priorLayout, nextLayout)
        recordAttachmentHeightDelta(from: priorLayout, to: nextLayout)
        if geometryChanged {
            pendingScrollOffsetX = preservedOffsetX
            needsLayout = true
        } else {
            if deferredInlineWidthGrowth {
                applyDeferredCodeWidthGrowthWithoutRelayout(nextLayout)
            }
            restoreScrollOffset(preservedOffsetX, layout: nextLayout)
        }
        invalidateCodeTextDisplay(
            startingAtLine: redrawStartLine,
            fullRedraw: !shouldAppend,
            includesLayoutChange: textContainerHeightChanged || geometryChanged
        )
        return attachmentBoundsChanged
    }

    override func layout() {
        super.layout()
        let width = bounds.width > 0 ? bounds.width : cachedWidth
        if abs(width - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: max(1, width))
            cachedWidth = max(1, width)
        }
        guard let layout = cachedLayout else { return }

        performWithoutMarkdownImplicitAnimations {
            headerView.frame = layout.headerFrame
            headerSeparator.frame = layout.separatorFrame
            languageLabel.frame = layout.languageFrame
            copyButton.frame = layout.copyFrame
            scrollView.frame = layout.scrollFrame
            if let textContainer = codeTextView.textContainer {
                let current = textContainer.containerSize
                let minWidth = max(10_000, layout.contentWidth)
                let targetWidth = max(current.width, minWidth)
                let targetHeight = layout.codeFrame.height
                if abs(current.width - targetWidth) > 0.5 || abs(current.height - targetHeight) > 0.5 {
                    textContainer.containerSize = CGSize(width: targetWidth, height: targetHeight)
                }
            }
            codeTextView.frame = layout.codeFrame
            if let documentView = scrollView.documentView, documentView.frame.size != layout.codeFrame.size {
                documentView.frame = layout.codeFrame
            }
        }
        restoreScrollOffsetIfNeeded(layout: layout)
    }

    @objc private func handleCopy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        showCopyFeedback()
    }

    private func computeLayout(width: CGFloat) -> Layout {
        let border = max(1, style.borderWidth)
        let headerPadding = style.headerPadding
        let codePadding = style.codePadding
        let viewportContentWidth = max(1, width - border * 2)
        let isRightToLeft = userInterfaceLayoutDirection == .rightToLeft

        let headerLineHeight = lineHeight(for: style.headerFont)
        let headerHeight = max(24, headerLineHeight + headerPadding.height * 2)
        let headerFrame = CGRect(x: border, y: border, width: viewportContentWidth, height: headerHeight)
        let separatorFrame = CGRect(x: border, y: headerFrame.maxY - border, width: viewportContentWidth, height: border)

        let copyTextSize = measureText(copyText, font: style.headerFont)
        let feedbackTextSize = measureText(Self.copyFeedbackText, font: style.headerFont)
        let copyButtonHeight = max(18, headerLineHeight + headerPadding.height)
        let idealCopyWidth = max(copyTextSize.width, feedbackTextSize.width) + headerPadding.width * 2
        let availableCopyWidth = max(0, viewportContentWidth - headerPadding.width)
        let copyButtonWidth = min(idealCopyWidth, availableCopyWidth)
        let copyButtonX = isRightToLeft
            ? headerPadding.width
            : max(0, viewportContentWidth - copyButtonWidth - headerPadding.width)
        let copyFrame = CGRect(
            x: copyButtonX,
            y: (headerHeight - copyButtonHeight) / 2,
            width: min(copyButtonWidth, viewportContentWidth),
            height: copyButtonHeight
        )

        let languageX = isRightToLeft
            ? min(viewportContentWidth, copyFrame.maxX + headerPadding.width)
            : headerPadding.width
        let languageWidth = isRightToLeft
            ? max(0, viewportContentWidth - languageX - headerPadding.width)
            : max(0, copyFrame.minX - languageX - headerPadding.width)
        let languageFrame = CGRect(
            x: languageX,
            y: (headerHeight - headerLineHeight) / 2,
            width: languageWidth,
            height: headerLineHeight
        )

        let codeTextSize = estimatedCodeTextSize
        let codeHeight = max(codeTextSize.height, lineHeight(for: style.codeFont))
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

    private func attachmentBoundsApproximatelyEqual(_ lhs: Layout?, _ rhs: Layout) -> Bool {
        guard let lhs else { return false }
        return
            abs(lhs.size.width - rhs.size.width) <= 0.5 &&
            abs(lhs.size.height - rhs.size.height) <= 0.5
    }

    private func recordAttachmentHeightDelta(from prior: Layout?, to next: Layout?) {
        guard let prior, let next else { return }
        attachment?.recordHostedHeightDelta(next.size.height - prior.size.height)
    }

    private func layoutByDeferringSmallCodeWidthGrowth(
        priorLayout: Layout,
        measuredLayout: Layout
    ) -> Layout {
        let grownContentWidth = max(priorLayout.contentWidth, measuredLayout.contentWidth)
        guard grownContentWidth > priorLayout.contentWidth + 0.5 else {
            return priorLayout
        }

        let grownCodeFrame = CGRect(
            x: priorLayout.codeFrame.origin.x,
            y: priorLayout.codeFrame.origin.y,
            width: grownContentWidth,
            height: priorLayout.codeFrame.height
        )
        return Layout(
            size: priorLayout.size,
            headerFrame: priorLayout.headerFrame,
            separatorFrame: priorLayout.separatorFrame,
            languageFrame: priorLayout.languageFrame,
            copyFrame: priorLayout.copyFrame,
            scrollFrame: priorLayout.scrollFrame,
            codeFrame: grownCodeFrame,
            contentWidth: grownContentWidth
        )
    }

    private func applyDeferredCodeWidthGrowthWithoutRelayout(_ layout: Layout) {
        performWithoutMarkdownImplicitAnimations {
            var codeFrame = codeTextView.frame
            if abs(codeFrame.width - layout.codeFrame.width) > 0.5 ||
                abs(codeFrame.height - layout.codeFrame.height) > 0.5 {
                codeFrame.size.width = layout.codeFrame.width
                codeFrame.size.height = layout.codeFrame.height
                codeTextView.frame = codeFrame
            }

            if let textContainer = codeTextView.textContainer {
                let current = textContainer.containerSize
                let minWidth = max(10_000, layout.contentWidth)
                let targetWidth = max(current.width, minWidth)
                if abs(current.width - targetWidth) > 0.5 ||
                    abs(current.height - layout.codeFrame.height) > 0.5 {
                    textContainer.containerSize = CGSize(width: targetWidth, height: layout.codeFrame.height)
                }
            }

            if let documentView = scrollView.documentView, documentView.frame.size != layout.codeFrame.size {
                documentView.frame = layout.codeFrame
            }
        }
    }

    private func restoreScrollOffsetIfNeeded(layout: Layout) {
        let sourceOffset = pendingScrollOffsetX ?? scrollView.contentView.bounds.origin.x
        pendingScrollOffsetX = nil
        restoreScrollOffset(sourceOffset, layout: layout)
    }

    private func restoreScrollOffset(_ offset: CGFloat, layout: Layout) {
        let maxOffsetX = max(0, layout.contentWidth - layout.scrollFrame.width)
        let clampedOffset = min(max(0, offset), maxOffsetX)
        let clipView = scrollView.contentView
        if abs(clipView.bounds.origin.x - clampedOffset) > 0.5 || abs(clipView.bounds.origin.y) > 0.5 {
            clipView.scroll(to: NSPoint(x: clampedOffset, y: 0))
            scrollView.reflectScrolledClipView(clipView)
        }
        pendingScrollOffsetX = nil
        attachment?.setHostedHorizontalOffset(clampedOffset)
    }

    private func measureText(_ text: String, font: MarkdownPlatformFont) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attrs)
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func lineHeight(for font: MarkdownPlatformFont) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: font)
    }

    private func invalidateCodeTextDisplay(
        startingAtLine startLine: Int,
        fullRedraw: Bool,
        includesLayoutChange: Bool
    ) {
        if fullRedraw {
            codeTextView.needsDisplay = true
            codeTextView.needsLayout = true
            scrollView.needsDisplay = true
            return
        }

        let lineAdvance = max(1, lineHeight(for: style.codeFont) + 2)
        let dirtyY = max(0, CGFloat(max(0, startLine)) * lineAdvance - lineAdvance)
        let visibleHeight = max(codeTextView.bounds.height, codeTextView.frame.height)
        let lineCount = max(1, renderedLineCount - max(0, startLine))
        let wantedHeight = lineAdvance * CGFloat(lineCount + 2)
        let dirtyHeight = visibleHeight > dirtyY ? min(visibleHeight - dirtyY, wantedHeight) : wantedHeight
        let dirtyRect = CGRect(
            x: 0,
            y: dirtyY,
            width: max(codeTextView.bounds.width, codeTextView.frame.width),
            height: max(lineAdvance, dirtyHeight)
        )
        codeTextView.setNeedsDisplay(dirtyRect)
        if includesLayoutChange {
            codeTextView.needsLayout = true
        }
    }

    private static func lineCount(in text: String) -> Int {
        max(1, lineBreakCount(in: text) + 1)
    }

    private static func lineBreakCount(in text: String) -> Int {
        var count = 0
        var previousWasCarriageReturn = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 10:
                if !previousWasCarriageReturn {
                    count += 1
                }
                previousWasCarriageReturn = false
            case 13:
                count += 1
                previousWasCarriageReturn = true
            default:
                previousWasCarriageReturn = false
            }
        }
        return count
    }

    private func showCopyFeedback() {
        copyFeedbackTask?.cancel()
        isShowingCopyFeedback = true
        updateCopyButtonAppearance()
        copyFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: Self.copyFeedbackDuration)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.isShowingCopyFeedback = false
                self.updateCopyButtonAppearance()
                self.copyFeedbackTask = nil
            }
        }
    }

    private func updateCopyButtonAppearance() {
        let title = isShowingCopyFeedback ? Self.copyFeedbackText : copyText
        let color = isShowingCopyFeedback ? NSColor.systemGreen : style.copyTextColor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: style.headerFont,
            .foregroundColor: color
        ]
        copyButton.title = title
        copyButton.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        copyButton.toolTip = isShowingCopyFeedback ? NSLocalizedString("Copied", comment: "") : copyText
    }

    private func updateMeasuredMaxLineWidth(reset: Bool, changedCharacterRange: NSRange?) {
        guard let textContainer = codeTextView.textContainer else { return }
        guard let textStorage = codeTextView.textStorage else { return }

        if reset {
            measuredMaxLineWidth = 0
            hasMeasuredMaxLineWidth = false
            let currentSize = textContainer.containerSize
            let baselineWidth = MeasurementSizing.initialContainerWidth
            if abs(currentSize.width - baselineWidth) > 0.5 {
                textContainer.containerSize = CGSize(width: baselineWidth, height: currentSize.height)
            }
        }

        let localMaxX = measureMaxLineWidth(
            in: textStorage,
            changedCharacterRange: changedCharacterRange
        )
        guard localMaxX > 0 || textStorage.length == 0 else {
            hasMeasuredMaxLineWidth = true
            return
        }

        measuredMaxLineWidth = max(measuredMaxLineWidth, localMaxX)
        measuredMaxLineWidth = min(measuredMaxLineWidth, MeasurementSizing.maxContainerWidth - 1)

        let requiredWidth = max(MeasurementSizing.initialContainerWidth, ceil(measuredMaxLineWidth + 1))
        let currentWidth = textContainer.containerSize.width
        if requiredWidth > currentWidth + 0.5 {
            let grownWidth = max(requiredWidth, currentWidth * 1.25)
            let clampedWidth = min(grownWidth, MeasurementSizing.maxContainerWidth)
            if clampedWidth > currentWidth + 0.5 {
                textContainer.containerSize = CGSize(width: clampedWidth, height: textContainer.containerSize.height)
            }
        }
        hasMeasuredMaxLineWidth = true
    }

    private func measureMaxLineWidth(
        in attributedText: NSAttributedString,
        changedCharacterRange: NSRange?
    ) -> CGFloat {
        let string = attributedText.string as NSString
        guard let measurementRange = lineMeasurementRange(
            in: string,
            changedCharacterRange: changedCharacterRange
        ) else {
            return 0
        }

        var maxWidth: CGFloat = 0
        var cursor = measurementRange.location
        let end = NSMaxRange(measurementRange)
        while cursor < end {
            let rawLineRange = string.lineRange(for: NSRange(location: cursor, length: 0))
            let lineRange = NSIntersectionRange(rawLineRange, measurementRange)
            let drawableRange = drawableLineRange(lineRange, in: string)
            if drawableRange.length > 0 {
                let line = attributedText.attributedSubstring(from: drawableRange)
                let bounds = line.boundingRect(
                    with: CGSize(
                        width: MeasurementSizing.maxContainerWidth,
                        height: CGFloat.greatestFiniteMagnitude
                    ),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                maxWidth = max(maxWidth, ceil(max(0, bounds.width)))
            }
            let nextCursor = NSMaxRange(rawLineRange)
            cursor = nextCursor > cursor ? nextCursor : cursor + 1
        }
        return maxWidth
    }

    private func lineMeasurementRange(
        in string: NSString,
        changedCharacterRange: NSRange?
    ) -> NSRange? {
        guard string.length > 0 else { return nil }
        guard let changedCharacterRange else {
            return NSRange(location: 0, length: string.length)
        }

        let clamped = markdownClampRange(changedCharacterRange, upperBound: string.length)
        let location = min(max(0, clamped.location), string.length - 1)
        let length = max(1, min(string.length - location, max(1, clamped.length)))
        return string.lineRange(for: NSRange(location: location, length: length))
    }

    private func drawableLineRange(_ lineRange: NSRange, in string: NSString) -> NSRange {
        var end = min(NSMaxRange(lineRange), string.length)
        while end > lineRange.location {
            let character = string.character(at: end - 1)
            if character == 10 || character == 13 {
                end -= 1
            } else {
                break
            }
        }
        return NSRange(location: lineRange.location, length: max(0, end - lineRange.location))
    }
}

private final class MarkdownTableRowView: NSView {
    override var isFlipped: Bool { true }
    let separatorView = NSView()
    private let style: MarkdownTableStyle
    private var cells: [NSAttributedString] = []
    private var cellFrames: [CGRect] = []
    private var hostedCellViews: [Int: NSTextView] = [:]
    private var rowBackgroundColor: MarkdownPlatformColor = .clear

    init(row: MarkdownTableRow, style: MarkdownTableStyle, columnCount: Int) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = nil
        separatorView.wantsLayer = true
        addSubview(separatorView)
        configure(row: row, columnCount: columnCount)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(row: MarkdownTableRow, columnCount: Int) {
        cells = normalizedCells(for: row, columnCount: columnCount)
        cellFrames = Array(repeating: .zero, count: columnCount)
        reconcileRequiredHostedCellViews()
        needsDisplay = true
    }

    func setRowBackgroundColor(_ color: MarkdownPlatformColor) {
        guard !rowBackgroundColor.isEqual(color) else { return }
        rowBackgroundColor = color
        layer?.backgroundColor = color.cgColor
        needsDisplay = true
    }

    func updateCell(at column: Int, text: NSAttributedString) {
        guard cells.indices.contains(column) else { return }
        if cells[column].isEqual(to: text) { return }
        cells[column] = text
        reconcileRequiredHostedCellView(at: column)
        needsDisplay = true
    }

    func layoutCells(
        columnWidths: [CGFloat],
        rowHeight: CGFloat,
        rowSeparator: CGFloat,
        padding: CGSize,
        columnGap: CGFloat
    ) {
        if cellFrames.count != columnWidths.count {
            cellFrames = Array(repeating: .zero, count: columnWidths.count)
        }
        var x: CGFloat = 0
        for column in 0..<columnWidths.count {
            let cellWidth = columnWidths[column]
            let textRect = CGRect(
                x: x + padding.width,
                y: padding.height,
                width: max(0, cellWidth - padding.width * 2),
                height: max(0, rowHeight - padding.height * 2)
            )
            cellFrames[column] = textRect
            if let hosted = hostedCellViews[column] {
                hosted.frame = textRect
                hosted.textContainer?.containerSize = CGSize(
                    width: textRect.width,
                    height: max(textRect.height, 1)
                )
                if let storage = hosted.textStorage {
                    prepareDynamicMarkdownTextAttachments(in: storage, width: textRect.width)
                }
                ensureMarkdownTextLayout(in: hosted, changedRange: nil, invalidatesLayout: false)
            }
            x += cellWidth + columnGap
        }
        separatorView.frame = CGRect(x: 0, y: rowHeight, width: bounds.width, height: rowSeparator)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let context = NSGraphicsContext.current?.cgContext {
            context.clear(bounds)
        }
        if rowBackgroundColor.alphaComponent > CGFloat.ulpOfOne {
            rowBackgroundColor.setFill()
            bounds.fill()
        }
        guard !cells.isEmpty else { return }
        for column in 0..<min(cells.count, cellFrames.count) {
            guard hostedCellViews[column] == nil else { continue }
            let frame = cellFrames[column]
            guard frame.intersects(dirtyRect), frame.width > 0, frame.height > 0 else { continue }
            cells[column].draw(
                with: frame,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let column = columnIndex(at: point),
              cells.indices.contains(column),
              cells[column].length > 0
        else {
            super.mouseDown(with: event)
            return
        }
        let hosted = ensureHostedCellView(at: column)
        window?.makeFirstResponder(hosted)
        hosted.mouseDown(with: event)
    }

    private func normalizedCells(for row: MarkdownTableRow, columnCount: Int) -> [NSAttributedString] {
        let emptyCell = NSAttributedString(string: "", attributes: [.font: style.baseFont])
        return (0..<columnCount).map { column in
            column < row.cells.count ? row.cells[column] : emptyCell
        }
    }

    private func reconcileRequiredHostedCellViews() {
        for column in 0..<cells.count {
            reconcileRequiredHostedCellView(at: column)
        }
        for column in hostedCellViews.keys where !cells.indices.contains(column) {
            hostedCellViews[column]?.removeFromSuperview()
            hostedCellViews[column] = nil
        }
    }

    private func reconcileRequiredHostedCellView(at column: Int) {
        guard cells.indices.contains(column) else { return }
        let text = cells[column]
        guard tableCellRequiresHostedTextView(text) || hostedCellViews[column] != nil else {
            if let hosted = hostedCellViews.removeValue(forKey: column) {
                hosted.removeFromSuperview()
            }
            return
        }
        let hosted = hostedCellViews[column] ?? makeHostedCellView()
        hostedCellViews[column] = hosted
        if hosted.superview == nil {
            addSubview(hosted)
        }
        apply(text: text, to: hosted)
        if cellFrames.indices.contains(column) {
            hosted.frame = cellFrames[column]
        }
    }

    private func ensureHostedCellView(at column: Int) -> NSTextView {
        let hosted = hostedCellViews[column] ?? makeHostedCellView()
        hostedCellViews[column] = hosted
        if hosted.superview == nil {
            addSubview(hosted)
        }
        apply(text: cells[column], to: hosted)
        if cellFrames.indices.contains(column) {
            let frame = cellFrames[column]
            hosted.frame = frame
            hosted.textContainer?.containerSize = CGSize(width: frame.width, height: max(frame.height, 1))
            if let storage = hosted.textStorage {
                prepareDynamicMarkdownTextAttachments(in: storage, width: frame.width)
            }
        }
        needsDisplay = true
        return hosted
    }

    private func columnIndex(at point: CGPoint) -> Int? {
        for column in 0..<cellFrames.count where cellFrames[column].contains(point) {
            return column
        }
        return nil
    }

    private func makeHostedCellView() -> NSTextView {
        let cellView = MarkdownNonScrollingTextView()
        cellView.drawsBackground = false
        cellView.backgroundColor = .clear
        cellView.isEditable = false
        cellView.isSelectable = true
        cellView.isRichText = true
        cellView.importsGraphics = false
        cellView.allowsUndo = false
        cellView.focusRingType = .none
        cellView.wantsLayer = true
        cellView.layer?.backgroundColor = NSColor.clear.cgColor
        cellView.layer?.borderWidth = 0
        cellView.layer?.cornerRadius = 0
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
        if let textLayoutManager = cellView.textLayoutManager {
            textLayoutManager.usesFontLeading = true
        } else {
            cellView.layoutManager?.allowsNonContiguousLayout = false
            cellView.layoutManager?.usesFontLeading = true
        }
        return cellView
    }

    private func apply(text: NSAttributedString, to view: NSTextView) {
        guard let storage = view.textStorage else { return }
        guard !storage.isEqual(to: text) else { return }
        storage.setAttributedString(text)
        ensureMarkdownTextLayout(in: view, changedRange: nil)
        view.needsDisplay = true
        view.needsLayout = true
    }

}

private func tableCellRequiresHostedTextView(_ text: NSAttributedString) -> Bool {
    guard text.length > 0 else { return false }
    var requiresHostedView = false
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length), options: []) { value, _, stop in
        if value is NSTextAttachment {
            requiresHostedView = true
            stop.pointee = true
        }
    }
    return requiresHostedView
}

final class MarkdownTableView: NSView {
    private enum IncrementalLayoutTuning {
        static let largeTableRowThreshold = 32
    }

    private struct Layout {
        let tableSize: CGSize
        let contentWidth: CGFloat
        let columnWidths: [CGFloat]
        let rowHeights: [CGFloat]
        let rowSeparatorWidth: CGFloat
        let columnGap: CGFloat
    }

    override var isFlipped: Bool { true }

    private var rows: [MarkdownTableRow]
    private let style: MarkdownTableStyle
    private var columnCount: Int
    private final class FlippedContentView: NSView {
        override var isFlipped: Bool { true }
    }

    private let scrollView = MarkdownHorizontalScrollView()
    private let contentView = FlippedContentView()
    private var rowViews: [MarkdownTableRowView] = []
    private var cachedLayout: Layout?
    private var cachedWidth: CGFloat = 0
    private var appliedContentVersion: UInt64 = 0
    private var laidOutRowCount: Int = 0
    private var laidOutContentWidth: CGFloat = 0
    private var laidOutContentHeight: CGFloat = 0
    private var laidOutColumnWidths: [CGFloat] = []
    private weak var attachment: MarkdownTableAttachment?
    private var pendingScrollOffsetX: CGFloat?
    private var pendingAttachmentBoundsChange = false

    private static func resolvedViewportAndContentWidth(
        contentWidth rawContentWidth: CGFloat,
        availableWidth: CGFloat
    ) -> (viewportWidth: CGFloat, contentWidth: CGFloat) {
        let viewportWidth = max(1, availableWidth)
        return (viewportWidth, max(rawContentWidth, viewportWidth))
    }

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
            needsLayout = true
        }
        return cachedLayout?.tableSize ?? CGSize(width: targetWidth, height: 0)
    }

    @discardableResult
    func applyUpdate(from attachment: MarkdownTableAttachment) -> Bool {
        self.attachment = attachment
        pendingScrollOffsetX = attachment.hostedHorizontalOffset()
        guard attachment.contentVersion != appliedContentVersion else {
            return pendingAttachmentBoundsChange
        }
        let needsLayoutInvalidation = applySnapshot(rows: attachment.rows)
        appliedContentVersion = attachment.contentVersion
        if needsLayoutInvalidation {
            pendingAttachmentBoundsChange = true
        }
        return pendingAttachmentBoundsChange
    }

    func markAttachmentBoundsObserved() {
        pendingAttachmentBoundsChange = false
    }

    @discardableResult
    func applySnapshot(rows nextRows: [MarkdownTableRow]) -> Bool {
        guard !nextRows.isEmpty else { return false }
        let preservedOffsetX = pendingScrollOffsetX ?? scrollView.contentView.bounds.origin.x

        if nextRows.count < rows.count || columnCount == 0 {
            let nextColumnCount = nextRows.map { $0.cells.count }.max() ?? 0
            guard nextColumnCount > 0 else { return false }
            rebuild(rows: nextRows, columnCount: nextColumnCount)
            pendingScrollOffsetX = preservedOffsetX
            needsLayout = true
            return true
        }

        let appendedCount = nextRows.count - rows.count
        if appendedCount == 0 {
            guard !rows.isEmpty else { return false }
            let lastIndex = rows.count - 1
            let previousLastRow = rows[lastIndex]
            let nextLastRow = nextRows[lastIndex]
            let isStreamingAppend: Bool = {
                guard let previousSource = previousLastRow.sourceMarkdown,
                      let nextSource = nextLastRow.sourceMarkdown
                else { return false }
                return nextSource.hasPrefix(previousSource)
            }()
            let nextMaxColumns = isStreamingAppend
                ? max(columnCount, nextLastRow.cells.count)
                : (nextRows.map { $0.cells.count }.max() ?? 0)
            let nextColumnCount = isStreamingAppend ? max(columnCount, nextMaxColumns) : nextMaxColumns
            if nextColumnCount != columnCount {
                rebuild(rows: nextRows, columnCount: nextColumnCount)
                pendingScrollOffsetX = preservedOffsetX
                needsLayout = true
                return true
            }

            if !isStreamingAppend, rowsHaveChanged(beforeLastRow: rows, nextRows: nextRows) {
                rebuild(rows: nextRows, columnCount: nextRows.map { $0.cells.count }.max() ?? 0)
                pendingScrollOffsetX = preservedOffsetX
                needsLayout = true
                return true
            }

            let priorLayout = cachedLayout
            let oldLastRowHeight: CGFloat? = {
                guard let priorLayout, priorLayout.rowHeights.indices.contains(lastIndex) else { return nil }
                return priorLayout.rowHeights[lastIndex]
            }()
            var shouldRelayout = false
            let changedColumns = changedColumnIndices(previous: previousLastRow, next: nextLastRow, columnCount: columnCount)

            rows = nextRows
            updateRowContent(at: lastIndex, columns: changedColumns)

            if let priorLayout,
               let oldLastRowHeight,
               priorLayout.columnWidths.count == columnCount,
               priorLayout.rowHeights.count == rows.count {
                let paddingX = style.cellPadding.width
                let maxCellTextWidth = markdownTableMaximumTextWidth(
                    availableWidth: cachedWidth,
                    columnCount: columnCount,
                    baseFont: style.baseFont
                )
                let maxColumnWidth = maxCellTextWidth + paddingX * 2
                let columnWidthGrowthStep = markdownStreamingTableColumnWidthGrowthStep(baseFont: style.baseFont)
                let emptyCell = NSAttributedString(string: "", attributes: [.font: style.baseFont])
                let lastRow = rows[lastIndex]

                var updatedColumnWidths = priorLayout.columnWidths
                let freezesColumnWidths = shouldFreezeColumnWidthsForIncrementalUpdate(rowCount: rows.count)
                var didGrowColumnWidth = false
                if !freezesColumnWidths {
                    for column in changedColumns {
                        guard updatedColumnWidths[column] < maxColumnWidth - 0.5 else { continue }
                        let cell = column < lastRow.cells.count ? lastRow.cells[column] : emptyCell
                        let size = measureTableCell(cell, width: .greatestFiniteMagnitude)
                        let desiredTextWidth = min(size.width, maxCellTextWidth)
                        let desiredColumnWidth = desiredTextWidth + paddingX * 2
                        let growth = desiredColumnWidth - updatedColumnWidths[column]
                        if growth > 0.5 {
                            let reachesColumnCap = desiredColumnWidth >= maxColumnWidth - 0.5
                            guard reachesColumnCap || growth >= columnWidthGrowthStep else { continue }
                            updatedColumnWidths[column] = desiredColumnWidth
                            didGrowColumnWidth = true
                        }
                    }
                    if didGrowColumnWidth {
                        let desiredContentWidths = updatedColumnWidths.map { max(0, $0 - paddingX * 2) }
                        let fittedContentWidths = markdownFittedTableContentWidths(
                            desiredContentWidths,
                            availableWidth: cachedWidth,
                            paddingX: paddingX,
                            columnGap: priorLayout.columnGap,
                            baseFont: style.baseFont
                        )
                        updatedColumnWidths = fittedContentWidths.map { $0 + paddingX * 2 }
                    }
                }

                let totalColumnGap = priorLayout.columnGap * CGFloat(max(0, columnCount - 1))
                let updatedContentWidth = updatedColumnWidths.reduce(0, +) + totalColumnGap
                let resolvedWidths = Self.resolvedViewportAndContentWidth(
                    contentWidth: updatedContentWidth,
                    availableWidth: cachedWidth
                )
                let columnWidthsChanged = !columnWidthsApproximatelyEqual(updatedColumnWidths, priorLayout.columnWidths)
                let canReusePriorMaxHeight = isPlainStreamingAppend(previous: previousLastRow, next: nextLastRow) &&
                    !columnWidthsChanged
                let newLastRowHeight = canReusePriorMaxHeight
                    ? measureChangedColumnsRowHeight(
                        rows[lastIndex],
                        columnWidths: updatedColumnWidths,
                        changedColumns: changedColumns,
                        previousRowHeight: oldLastRowHeight
                    )
                    : measureRowHeight(rows[lastIndex], columnWidths: updatedColumnWidths)
                let heightDelta = newLastRowHeight - oldLastRowHeight
                var updatedHeights = priorLayout.rowHeights
                updatedHeights[lastIndex] = newLastRowHeight
                cachedLayout = Layout(
                    tableSize: CGSize(width: resolvedWidths.viewportWidth, height: priorLayout.tableSize.height + heightDelta),
                    contentWidth: resolvedWidths.contentWidth,
                    columnWidths: updatedColumnWidths,
                    rowHeights: updatedHeights,
                    rowSeparatorWidth: priorLayout.rowSeparatorWidth,
                    columnGap: priorLayout.columnGap
                )

                let needsFullRelayout =
                    abs(updatedContentWidth - priorLayout.contentWidth) > 0.5 ||
                    columnWidthsChanged
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
                } else if needsLayout {
                    shouldRelayout = true
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

            let attachmentBoundsChanged = !tableBoundsApproximatelyEqual(priorLayout, cachedLayout)
            recordAttachmentHeightDelta(from: priorLayout, to: cachedLayout)
            if shouldRelayout {
                pendingScrollOffsetX = preservedOffsetX
                needsLayout = true
            } else {
                restoreScrollOffset(preservedOffsetX)
            }
            return attachmentBoundsChanged
        } else if appendedCount < 0 {
            return false
        }

        let appendedRows = Array(nextRows.suffix(appendedCount))
        let appendedMaxColumns = appendedRows.map { $0.cells.count }.max() ?? 0
        let nextColumnCount = max(columnCount, appendedMaxColumns)
        if nextColumnCount != columnCount {
            rebuild(rows: nextRows, columnCount: nextColumnCount)
            pendingScrollOffsetX = preservedOffsetX
            needsLayout = true
            return true
        }

        rows = nextRows
        appendRows(appendedRows)
        let priorLayout = cachedLayout
        if let updatedLayout = extendLayout(with: appendedRows) {
            cachedLayout = updatedLayout
        } else {
            cachedLayout = nil
        }
        let attachmentBoundsChanged = !tableBoundsApproximatelyEqual(priorLayout, cachedLayout)
        recordAttachmentHeightDelta(from: priorLayout, to: cachedLayout)

        pendingScrollOffsetX = preservedOffsetX
        needsLayout = true
        return attachmentBoundsChanged
    }

    private func updateRowContent(at rowIndex: Int, columns: [Int]? = nil) {
        guard rowIndex >= 0, rowIndex < rows.count else { return }
        guard rowIndex < rowViews.count else { return }
        let row = rows[rowIndex]
        let emptyCell = NSAttributedString(string: "", attributes: [.font: style.baseFont])
        let targetColumns = columns ?? Array(0..<columnCount)
        for column in targetColumns {
            guard column < columnCount else { continue }
            let cellText = column < row.cells.count ? row.cells[column] : emptyCell
            rowViews[rowIndex].updateCell(at: column, text: cellText)
        }
    }

    private func measureRowHeight(_ row: MarkdownTableRow, columnWidths: [CGFloat]) -> CGFloat {
        let paddingX = style.cellPadding.width
        let paddingY = style.cellPadding.height
        let minRowHeight = lineHeight(for: style.baseFont)
        let emptyCell = NSAttributedString(string: "", attributes: [.font: style.baseFont])

        var rowHeight: CGFloat = 0
        for column in 0..<columnCount {
            let cell = column < row.cells.count ? row.cells[column] : emptyCell
            let textWidth = max(0, columnWidths[column] - paddingX * 2)
            let size = measureTableCell(cell, width: textWidth)
            rowHeight = max(rowHeight, max(size.height, minRowHeight))
        }
        return ceil(rowHeight + paddingY * 2)
    }

    private func measureChangedColumnsRowHeight(
        _ row: MarkdownTableRow,
        columnWidths: [CGFloat],
        changedColumns: [Int],
        previousRowHeight: CGFloat
    ) -> CGFloat {
        guard !changedColumns.isEmpty else { return previousRowHeight }
        let paddingX = style.cellPadding.width
        let paddingY = style.cellPadding.height
        let minRowHeight = lineHeight(for: style.baseFont)
        let emptyCell = NSAttributedString(string: "", attributes: [.font: style.baseFont])
        var rowHeight = max(minRowHeight, previousRowHeight - paddingY * 2)

        for column in changedColumns {
            guard column >= 0, column < columnCount, column < columnWidths.count else { continue }
            let cell = column < row.cells.count ? row.cells[column] : emptyCell
            let textWidth = max(0, columnWidths[column] - paddingX * 2)
            let size = measureTableCell(cell, width: textWidth)
            rowHeight = max(rowHeight, max(size.height, minRowHeight))
        }
        return ceil(rowHeight + paddingY * 2)
    }

    private func changedColumnIndices(
        previous: MarkdownTableRow,
        next: MarkdownTableRow,
        columnCount: Int
    ) -> [Int] {
        guard columnCount > 0 else { return [] }
        var columns: [Int] = []
        columns.reserveCapacity(min(columnCount, 4))
        for column in 0..<columnCount {
            let previousCell = column < previous.cells.count ? previous.cells[column] : nil
            let nextCell = column < next.cells.count ? next.cells[column] : nil
            switch (previousCell, nextCell) {
            case let (left?, right?):
                if !left.isEqual(to: right) {
                    columns.append(column)
                }
            case (nil, nil):
                continue
            default:
                columns.append(column)
            }
        }
        return columns
    }

    private func rowsHaveChanged(beforeLastRow previousRows: [MarkdownTableRow], nextRows: [MarkdownTableRow]) -> Bool {
        guard previousRows.count == nextRows.count, previousRows.count > 1 else { return false }
        let lastIndex = previousRows.count - 1
        for rowIndex in 0..<lastIndex {
            if !tableRowStableContentEqual(previousRows[rowIndex], nextRows[rowIndex]) {
                return true
            }
        }
        return false
    }

    private func tableRowStableContentEqual(_ lhs: MarkdownTableRow, _ rhs: MarkdownTableRow) -> Bool {
        if tableRowContentEqual(lhs, rhs) { return true }
        guard let lhsSource = lhs.sourceMarkdown,
              let rhsSource = rhs.sourceMarkdown,
              lhsSource == rhsSource
        else {
            return false
        }
        guard lhs.isHeader == rhs.isHeader else { return false }
        guard lhs.cells.count == rhs.cells.count else { return false }
        for index in 0..<lhs.cells.count {
            if extractPlainText(from: lhs.cells[index]) != extractPlainText(from: rhs.cells[index]) {
                return false
            }
            if !paragraphStylesCompatible(
                firstParagraphStyle(in: lhs.cells[index]),
                firstParagraphStyle(in: rhs.cells[index])
            ) {
                return false
            }
        }
        return true
    }

    private func tableRowContentEqual(_ lhs: MarkdownTableRow, _ rhs: MarkdownTableRow) -> Bool {
        guard lhs.isHeader == rhs.isHeader else { return false }
        guard lhs.cells.count == rhs.cells.count else { return false }
        for index in 0..<lhs.cells.count {
            if !lhs.cells[index].isEqual(to: rhs.cells[index]) {
                return false
            }
        }
        return true
    }

    private func firstParagraphStyle(in cell: NSAttributedString) -> NSParagraphStyle? {
        guard cell.length > 0 else { return nil }
        var result: NSParagraphStyle?
        cell.enumerateAttribute(
            .paragraphStyle,
            in: NSRange(location: 0, length: cell.length),
            options: []
        ) { value, _, stop in
            guard let style = value as? NSParagraphStyle else { return }
            result = style
            stop.pointee = true
        }
        return result
    }

    private func paragraphStylesCompatible(_ lhs: NSParagraphStyle?, _ rhs: NSParagraphStyle?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.alignment == rhs.alignment &&
                lhs.lineBreakMode == rhs.lineBreakMode &&
                abs(lhs.lineSpacing - rhs.lineSpacing) <= 0.5
        default:
            return false
        }
    }

    override func layout() {
        super.layout()
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
        performWithoutMarkdownImplicitAnimations {
            scrollView.frame = bounds
            contentView.frame = CGRect(x: 0, y: 0, width: layout.contentWidth, height: layout.tableSize.height)
            if let documentView = scrollView.documentView, documentView.frame.size != contentView.frame.size {
                documentView.frame = contentView.frame
            }

            for rowIndex in startIndex..<rows.count {
                guard rowIndex < rowViews.count, rowIndex < layout.rowHeights.count else { continue }
                let row = rows[rowIndex]
                let rowHeight = layout.rowHeights[rowIndex]
                let rowView = rowViews[rowIndex]
                let rowViewHeight = rowHeight + rowSeparator
                rowView.frame = CGRect(x: 0, y: y, width: layout.contentWidth, height: rowViewHeight)
                rowView.separatorView.frame = CGRect(x: 0, y: rowHeight, width: layout.contentWidth, height: rowSeparator)
                rowView.separatorView.layer?.backgroundColor = style.borderColor.cgColor

                if row.isHeader {
                    rowView.setRowBackgroundColor(style.headerBackground)
                } else {
                    let bodyIndex = rowIndex - (hasHeader ? 1 : 0)
                    if bodyIndex % 2 == 1 {
                        rowView.setRowBackgroundColor(style.stripeBackground)
                    } else {
                        rowView.setRowBackgroundColor(.clear)
                    }
                }

                rowView.layoutCells(
                    columnWidths: layout.columnWidths,
                    rowHeight: rowHeight,
                    rowSeparator: rowSeparator,
                    padding: padding,
                    columnGap: layout.columnGap
                )

                y += rowViewHeight
            }
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

    private func tableBoundsApproximatelyEqual(_ lhs: Layout?, _ rhs: Layout?) -> Bool {
        guard let lhs, let rhs else { return false }
        return
            abs(lhs.tableSize.width - rhs.tableSize.width) <= 0.5 &&
            abs(lhs.tableSize.height - rhs.tableSize.height) <= 0.5
    }

    private func recordAttachmentHeightDelta(from prior: Layout?, to next: Layout?) {
        guard let prior, let next else { return }
        let delta = next.tableSize.height - prior.tableSize.height
        attachment?.recordHostedHeightDelta(delta)
    }

    private func restoreScrollOffsetIfNeeded() {
        let sourceOffset = pendingScrollOffsetX ?? scrollView.contentView.bounds.origin.x
        pendingScrollOffsetX = nil
        restoreScrollOffset(sourceOffset)
    }

    private func restoreScrollOffset(_ offset: CGFloat) {
        let documentWidth = scrollView.documentView?.frame.width ?? contentView.frame.width
        let maxOffsetX = max(0, documentWidth - scrollView.contentView.bounds.width)
        let clampedOffset = min(max(0, offset), maxOffsetX)
        let clipView = scrollView.contentView
        if abs(clipView.bounds.origin.x - clampedOffset) > 0.5 || abs(clipView.bounds.origin.y) > 0.5 {
            clipView.scroll(to: NSPoint(x: clampedOffset, y: 0))
            scrollView.reflectScrolledClipView(clipView)
        }
        pendingScrollOffsetX = nil
        attachment?.setHostedHorizontalOffset(clampedOffset)
    }

    private func rebuild(rows: [MarkdownTableRow], columnCount: Int) {
        self.rows = rows
        self.columnCount = columnCount
        performWithoutMarkdownImplicitAnimations {
            rowViews.forEach { $0.removeFromSuperview() }
            rowViews.removeAll(keepingCapacity: false)
            buildRows()
        }
        cachedLayout = nil
        cachedWidth = 0
        laidOutRowCount = 0
        laidOutContentWidth = 0
        laidOutContentHeight = 0
        laidOutColumnWidths.removeAll(keepingCapacity: false)
    }

    private func appendRows(_ newRows: [MarkdownTableRow]) {
        guard !newRows.isEmpty, columnCount > 0 else { return }
        performWithoutMarkdownImplicitAnimations {
            for row in newRows {
                let rowView = MarkdownTableRowView(row: row, style: style, columnCount: columnCount)
                rowView.separatorView.layer?.backgroundColor = style.borderColor.cgColor
                contentView.addSubview(rowView)
                rowViews.append(rowView)
            }
        }
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
        let maxCellTextWidth = markdownTableMaximumTextWidth(
            availableWidth: cachedWidth,
            columnCount: columnCount,
            baseFont: style.baseFont
        )
        let maxColumnWidth = maxCellTextWidth + paddingX * 2

        let emptyCell = NSAttributedString(string: "", attributes: [.font: style.baseFont])
        var columnWidths = existing.columnWidths
        if !shouldFreezeColumnWidthsForIncrementalUpdate(rowCount: existing.rowHeights.count) {
            for row in appendedRows {
                for column in 0..<columnCount {
                    guard columnWidths[column] < maxColumnWidth - 0.5 else { continue }
                    let cell = column < row.cells.count ? row.cells[column] : emptyCell
                    let size = measureTableCell(cell, width: .greatestFiniteMagnitude)
                    let desiredTextWidth = min(size.width, maxCellTextWidth)
                    let desiredColumnWidth = desiredTextWidth + paddingX * 2
                    if desiredColumnWidth > columnWidths[column] + 0.5 {
                        columnWidths[column] = desiredColumnWidth
                    }
                }
            }
            let desiredContentWidths = columnWidths.map { max(0, $0 - paddingX * 2) }
            let fittedContentWidths = markdownFittedTableContentWidths(
                desiredContentWidths,
                availableWidth: cachedWidth,
                paddingX: paddingX,
                columnGap: columnGap,
                baseFont: style.baseFont
            )
            columnWidths = fittedContentWidths.map { $0 + paddingX * 2 }
        }
        let minRowHeight = lineHeight(for: style.baseFont)
        var rowHeights = existing.rowHeights
        rowHeights.reserveCapacity(rows.count)
        var appendedHeightsSum: CGFloat = 0
        for row in appendedRows {
            var rowHeight: CGFloat = 0
            for column in 0..<columnCount {
                let cell = column < row.cells.count ? row.cells[column] : emptyCell
                let textWidth = max(0, columnWidths[column] - paddingX * 2)
                let size = measureTableCell(cell, width: textWidth)
                rowHeight = max(rowHeight, max(size.height, minRowHeight))
            }
            let finalHeight = ceil(rowHeight + paddingY * 2)
            rowHeights.append(finalHeight)
            appendedHeightsSum += finalHeight
        }

        let totalColumnGap = columnGap * CGFloat(max(0, columnCount - 1))
        let tableWidth = columnWidths.reduce(0, +) + totalColumnGap
        let tableHeight = existing.tableSize.height + appendedHeightsSum + rowSeparator * CGFloat(appendedRows.count)
        let resolvedWidths = Self.resolvedViewportAndContentWidth(
            contentWidth: tableWidth,
            availableWidth: cachedWidth
        )
        return Layout(
            tableSize: CGSize(width: resolvedWidths.viewportWidth, height: tableHeight),
            contentWidth: resolvedWidths.contentWidth,
            columnWidths: columnWidths,
            rowHeights: rowHeights,
            rowSeparatorWidth: rowSeparator,
            columnGap: columnGap
        )
    }

    private func shouldFreezeColumnWidthsForIncrementalUpdate(rowCount: Int) -> Bool {
        rowCount >= IncrementalLayoutTuning.largeTableRowThreshold
    }

    private func measureTableCell(_ cell: NSAttributedString, width: CGFloat) -> CGSize {
        if !width.isFinite || width >= 10_000 {
            return CGSize(
                width: measureUnwrappedAttributedTextWidth(cell, fallbackFont: style.baseFont),
                height: lineHeight(for: style.baseFont)
            )
        }
        return measureAttributedText(cell, width: width)
    }

    private func isPlainStreamingAppend(previous: MarkdownTableRow, next: MarkdownTableRow) -> Bool {
        guard let previousSource = previous.sourceMarkdown,
              let nextSource = next.sourceMarkdown,
              nextSource.hasPrefix(previousSource)
        else {
            return false
        }
        let delta = String(nextSource.dropFirst(previousSource.count))
        guard !delta.isEmpty else { return true }
        guard !delta.contains("\n"), !delta.contains("\r"), !delta.contains("|") else {
            return false
        }
        return delta.rangeOfCharacter(from: Self.tableCellMarkdownSyntaxCharacters) == nil
    }

    private static let tableCellMarkdownSyntaxCharacters = CharacterSet(charactersIn: "*_`[]()!#<>\\$~")

    private func buildRows() {
        guard columnCount > 0 else { return }
        rowViews.reserveCapacity(rows.count)
        for row in rows {
            let rowView = MarkdownTableRowView(row: row, style: style, columnCount: columnCount)
            rowView.separatorView.layer?.backgroundColor = style.borderColor.cgColor
            contentView.addSubview(rowView)
            rowViews.append(rowView)
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
        let emptyCell = NSAttributedString(string: "", attributes: [.font: style.baseFont])
        let contentWidths = markdownMeasuredTableContentWidths(
            rows: rows,
            columnCount: columnCount,
            availableWidth: width,
            paddingX: paddingX,
            columnGap: columnGap,
            baseFont: style.baseFont,
            emptyCell: emptyCell
        ) { cell, textWidth in
            measureTableCell(cell, width: textWidth)
        }

        let totalColumnGap = columnGap * CGFloat(max(0, columnCount - 1))
        let columnWidths = contentWidths.map { $0 + paddingX * 2 }
        let minRowHeight = lineHeight(for: style.baseFont)
        var rowHeights: [CGFloat] = []
        rowHeights.reserveCapacity(rows.count)
        for row in rows {
            var rowHeight: CGFloat = 0
            for column in 0..<columnCount {
                let cell = column < row.cells.count ? row.cells[column] : emptyCell
                let textWidth = max(0, columnWidths[column] - paddingX * 2)
                let size = measureTableCell(cell, width: textWidth)
                rowHeight = max(rowHeight, max(size.height, minRowHeight))
            }
            rowHeights.append(ceil(rowHeight + paddingY * 2))
        }

        let tableWidth = columnWidths.reduce(0, +) + totalColumnGap
        let tableHeight = rowHeights.reduce(0, +) + rowSeparator * CGFloat(rows.count)
        let resolvedWidths = Self.resolvedViewportAndContentWidth(
            contentWidth: tableWidth,
            availableWidth: width
        )
        return Layout(
            tableSize: CGSize(width: resolvedWidths.viewportWidth, height: tableHeight),
            contentWidth: resolvedWidths.contentWidth,
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
    private let textView: NSTextView
    private var cachedLayout: Layout?
    private var cachedWidth: CGFloat = 0

    init(content: NSAttributedString, style: MarkdownQuoteStyle) {
        self.content = content
        self.style = style
        self.textView = MarkdownNonScrollingTextView()
        super.init(frame: .zero)
        MarkdownAttachmentViewProviderRegistry.registerIfNeeded()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        borderView.wantsLayer = true
        borderView.layer?.backgroundColor = style.borderColor.cgColor
        addSubview(borderView)

        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.focusRingType = .none
        textView.wantsLayer = true
        textView.layer?.backgroundColor = NSColor.clear.cgColor
        textView.layer?.borderWidth = 0
        textView.layer?.cornerRadius = 0
        textView.isEditable = false
        textView.isSelectable = true
        textView.importsGraphics = true
        textView.allowsUndo = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isRichText = true
        if let textLayoutManager = textView.textLayoutManager {
            textLayoutManager.usesFontLeading = true
        } else {
            textView.layoutManager?.allowsNonContiguousLayout = false
            textView.layoutManager?.usesFontLeading = true
        }
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
            needsLayout = true
        }
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
        textView.textContainer?.containerSize = CGSize(
            width: layout.textFrame.width,
            height: max(layout.textFrame.height, 1)
        )
        if let storage = textView.textStorage {
            prepareDynamicMarkdownTextAttachments(in: storage, width: layout.textFrame.width)
        }
    }

    private func computeLayout(width: CGFloat) -> Layout {
        let borderWidth = max(1, style.borderWidth)
        let padding = style.padding
        let textWidth = max(1, width - borderWidth - padding.width * 2)
        let textSize = measureHostedAttributedText(content, width: textWidth)
        let height = ceil(textSize.height + padding.height * 2)
        let borderFrame = CGRect(x: 0, y: 0, width: borderWidth, height: height)
        let textFrame = CGRect(
            x: borderWidth + padding.width,
            y: padding.height,
            width: textWidth,
            height: ceil(textSize.height)
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
            needsLayout = true
        }
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
        let cacheKey: BoundsCacheKey?
    }

    private enum Kind: Sendable {
        case codeBlock
        case table
        case quote
        case rule
        case math
        case unknown
    }

    private struct BoundsCacheKey: Sendable, Equatable {
        let kind: Kind
        let contentVersion: UInt64
        let availableWidthKey: Int
    }

    private var cachedBoundsKey: BoundsCacheKey?
    private var cachedBounds: CGRect = .zero

    @MainActor
    private static let viewCache = NSMapTable<MarkdownAttachment, NSView>(
        keyOptions: .weakMemory,
        valueOptions: .weakMemory
    )

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

    private static func resolvedLineFragmentWidth(
        proposedWidth: CGFloat,
        textContainerWidth: CGFloat?
    ) -> CGFloat {
        let proposed = proposedWidth.isFinite && proposedWidth > 1 ? proposedWidth : 0
        let container: CGFloat
        if let textContainerWidth,
           textContainerWidth.isFinite,
           textContainerWidth > 1 {
            container = textContainerWidth
        } else {
            container = 0
        }
        let resolved = max(proposed, container)
        return resolved > 1 ? resolved : proposedWidth
    }

    override func loadView() {
        let markdownAttachmentBox = UncheckedSendableBox(value: textAttachment as? MarkdownAttachment)
        let viewBox: UncheckedSendableBox<NSView> = MainActor.assumeIsolated {
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
        _ = position

        let markdownAttachmentBox = UncheckedSendableBox(value: textAttachment as? MarkdownAttachment)
        let currentViewBox = UncheckedSendableBox(value: view)
        let cachedBoundsKeySnapshot = cachedBoundsKey
        let cachedBoundsSnapshot = cachedBounds
        let textContainerWidth = textContainer?.size.width
        let lineWidth = Self.resolvedLineFragmentWidth(
            proposedWidth: proposedLineFragment.width,
            textContainerWidth: textContainerWidth
        )

        let layout: AttachmentLayout = MainActor.assumeIsolated {
            guard let attachment = markdownAttachmentBox.value else {
                let resolvedView = currentViewBox.value ?? NSView()
                return AttachmentLayout(view: UncheckedSendableBox(value: resolvedView), bounds: .zero, cacheKey: nil)
            }

            let available = attachmentAvailableWidth(maxWidth: attachment.maxWidth, lineFragWidth: lineWidth)
            let availableWidthKey = Self.widthKey(available)

            func cachedLayoutIfPossible(
                kind: Kind,
                contentVersion: UInt64,
                availableWidthKey: Int = availableWidthKey
            ) -> AttachmentLayout? {
                let key = BoundsCacheKey(kind: kind, contentVersion: contentVersion, availableWidthKey: availableWidthKey)
                guard key == cachedBoundsKeySnapshot else { return nil }
                guard let existing = currentViewBox.value else { return nil }
                return AttachmentLayout(view: UncheckedSendableBox(value: existing), bounds: cachedBoundsSnapshot, cacheKey: key)
            }

            func cachedLayoutAfterContentOnlyUpdate(
                kind: Kind,
                key: BoundsCacheKey,
                view resolvedView: NSView,
                needsLayoutInvalidation: Bool
            ) -> AttachmentLayout? {
                guard !needsLayoutInvalidation,
                      let cachedKey = cachedBoundsKeySnapshot,
                      cachedKey.kind == kind,
                      cachedKey.availableWidthKey == key.availableWidthKey
                else {
                    return nil
                }
                return AttachmentLayout(
                    view: UncheckedSendableBox(value: resolvedView),
                    bounds: cachedBoundsSnapshot,
                    cacheKey: key
                )
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
                codeAttachment.hostedView = resolvedView
                Self.cache(view: resolvedView, for: codeAttachment)
                let key = BoundsCacheKey(
                    kind: .codeBlock,
                    contentVersion: codeAttachment.contentVersion,
                    availableWidthKey: availableWidthKey
                )
                let needsLayoutInvalidation = resolvedView.applyUpdate(from: codeAttachment)
                if let cached = cachedLayoutAfterContentOnlyUpdate(
                    kind: .codeBlock,
                    key: key,
                    view: resolvedView,
                    needsLayoutInvalidation: needsLayoutInvalidation
                ) {
                    return cached
                }
                let bounds = CGRect(origin: .zero, size: resolvedView.sizeThatFitsWidth(available))
                resolvedView.markAttachmentBoundsObserved()
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
                tableAttachment.hostedView = resolvedView
                Self.cache(view: resolvedView, for: tableAttachment)
                let key = BoundsCacheKey(
                    kind: .table,
                    contentVersion: tableAttachment.contentVersion,
                    availableWidthKey: availableWidthKey
                )
                let needsLayoutInvalidation = resolvedView.applyUpdate(from: tableAttachment)
                if let cached = cachedLayoutAfterContentOnlyUpdate(
                    kind: .table,
                    key: key,
                    view: resolvedView,
                    needsLayoutInvalidation: needsLayoutInvalidation
                ) {
                    return cached
                }
                let bounds = CGRect(origin: .zero, size: resolvedView.sizeThatFitsWidth(available))
                resolvedView.markAttachmentBoundsObserved()
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

            case let mathAttachment as MarkdownMathAttachment:
                let mathAvailable = mathAttachment.resolvedAvailableWidth(
                    containerWidth: textContainerWidth,
                    proposedLineFragmentWidth: lineWidth
                )
                let mathAvailableWidthKey = Self.widthKey(mathAvailable)
                if let cached = cachedLayoutIfPossible(
                    kind: .math,
                    contentVersion: mathAttachment.contentVersion,
                    availableWidthKey: mathAvailableWidthKey
                ) {
                    return cached
                }
                let resolvedView: MarkdownMathView
                if let existing = currentViewBox.value as? MarkdownMathView {
                    resolvedView = existing
                } else if let cached = Self.cachedView(for: mathAttachment) as? MarkdownMathView {
                    resolvedView = cached
                } else {
                    resolvedView = MarkdownMathView(attachment: mathAttachment)
                }
                Self.cache(view: resolvedView, for: mathAttachment)
                resolvedView.applyUpdate(from: mathAttachment)
                _ = resolvedView.sizeThatFitsWidth(mathAvailable)
                let bounds = mathAttachment.layoutBounds(availableWidth: mathAvailable)
                let key = BoundsCacheKey(
                    kind: .math,
                    contentVersion: mathAttachment.contentVersion,
                    availableWidthKey: mathAvailableWidthKey
                )
                return AttachmentLayout(view: UncheckedSendableBox(value: resolvedView), bounds: bounds, cacheKey: key)

            default:
                if let cached = cachedLayoutIfPossible(kind: .unknown, contentVersion: attachment.contentVersion) {
                    return cached
                }
                let resolvedView = currentViewBox.value ?? NSView()
                let bounds = CGRect(x: 0, y: 0, width: available, height: 0)
                let key = BoundsCacheKey(
                    kind: .unknown,
                    contentVersion: attachment.contentVersion,
                    availableWidthKey: availableWidthKey
                )
                return AttachmentLayout(view: UncheckedSendableBox(value: resolvedView), bounds: bounds, cacheKey: key)
            }
        }

        if view !== layout.view.value {
            view = layout.view.value
        }
        if let key = layout.cacheKey {
            self.cachedBoundsKey = key
            self.cachedBounds = layout.bounds
        }
        return layout.bounds
    }

    @MainActor
    private static func makeView(for attachment: MarkdownAttachment?) -> NSView {
        guard let attachment else {
            return NSView()
        }
        switch attachment {
        case let attachment as MarkdownCodeBlockAttachment:
            let view = MarkdownCodeBlockView(
                code: attachment.code,
                languageLabel: attachment.languageLabel,
                copyLabel: attachment.copyLabel,
                style: attachment.style,
                codeAttributed: attachment.codeAttributed,
                estimatedCodeTextSize: attachment.estimatedCodeTextSize
            )
            attachment.hostedView = view
            return view
        case let attachment as MarkdownTableAttachment:
            let view = MarkdownTableView(rows: attachment.rows, style: attachment.style)
            attachment.hostedView = view
            return view
        case let attachment as MarkdownQuoteAttachment:
            return MarkdownQuoteView(content: attachment.content, style: attachment.style)
        case let attachment as MarkdownRuleAttachment:
            return MarkdownRuleView(
                color: attachment.color,
                thickness: attachment.thickness,
                verticalPadding: attachment.verticalPadding
            )
        case let attachment as MarkdownMathAttachment:
            return MarkdownMathView(attachment: attachment)
        default:
            return NSView()
        }
    }

    private static func widthKey(_ width: CGFloat) -> Int {
        Int((max(0, width) * 2).rounded())
    }

    @MainActor
    private static func cachedView(for attachment: MarkdownAttachment) -> NSView? {
        viewCache.object(forKey: attachment)
    }

    @MainActor
    private static func cache(view: NSView, for attachment: MarkdownAttachment) {
        viewCache.setObject(view, forKey: attachment)
    }
}


#endif
