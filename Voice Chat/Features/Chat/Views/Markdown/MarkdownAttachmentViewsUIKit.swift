#if os(iOS) || os(tvOS) || os(visionOS)
@preconcurrency import Foundation
@preconcurrency import UIKit
@preconcurrency import QuartzCore

@MainActor
private func performWithoutMarkdownImplicitAnimations(_ body: () -> Void) {
    UIView.performWithoutAnimation {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}

private let markdownAttachmentTextContainerHeight: CGFloat = 10_000_000

private final class MarkdownAttachmentSelectionGestureRecognizer: UILongPressGestureRecognizer {}

#if os(iOS)
private final class MarkdownAttachmentLongPressSuppressingGestureRecognizer: UILongPressGestureRecognizer {
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        if preventedGestureRecognizer is MarkdownAttachmentSelectionGestureRecognizer {
            return false
        }
        if preventedGestureRecognizer.view?.isInsideMarkdownSelectableAttachmentTextView == true {
            return false
        }
        return preventedGestureRecognizer is UILongPressGestureRecognizer
    }
}

private final class MarkdownAttachmentLongPressSuppressorDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = MarkdownAttachmentLongPressSuppressorDelegate()

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer is MarkdownAttachmentLongPressSuppressingGestureRecognizer else { return true }
        return touch.view?.isInsideMarkdownSelectableAttachmentTextView != true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer is MarkdownAttachmentLongPressSuppressingGestureRecognizer else { return true }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if otherGestureRecognizer.view?.isInsideMarkdownSelectableAttachmentTextView == true {
            return true
        }
        return false
    }
}

private extension UIView {
    var isInsideMarkdownSelectableAttachmentTextView: Bool {
        var current: UIView? = self
        while let view = current {
            if view is MarkdownSelectableAttachmentTextView {
                return true
            }
            current = view.superview
        }
        return false
    }

    func installMarkdownAttachmentLongPressSuppression() {
        disableMarkdownContextMenuInteractions()
        let alreadyInstalled = gestureRecognizers?.contains {
            $0 is MarkdownAttachmentLongPressSuppressingGestureRecognizer
        } ?? false
        guard !alreadyInstalled else { return }

        for subview in subviews {
            subview.disableMarkdownContextMenuInteractionsRecursively()
        }

        let recognizer = MarkdownAttachmentLongPressSuppressingGestureRecognizer(
            target: self,
            action: #selector(handleMarkdownSuppressedLongPress(_:))
        )
        recognizer.minimumPressDuration = 0.05
        recognizer.allowableMovement = 8
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = MarkdownAttachmentLongPressSuppressorDelegate.shared
        addGestureRecognizer(recognizer)
    }

    func disableMarkdownContextMenuInteractions() {
        for interaction in interactions where interaction is UIContextMenuInteraction {
            removeInteraction(interaction)
        }
    }

    func disableMarkdownContextMenuInteractionsRecursively() {
        if self is MarkdownSelectableAttachmentTextView {
            return
        }
        disableMarkdownContextMenuInteractions()
        for subview in subviews {
            subview.disableMarkdownContextMenuInteractionsRecursively()
        }
    }

    @objc func handleMarkdownSuppressedLongPress(_ recognizer: UILongPressGestureRecognizer) {
        // Intentionally empty. The recognizer claims attachment-background long presses
        // so UIKit's text-item context menu interaction never starts there.
    }
}
#endif

private final class MarkdownHorizontalScrollView: UIScrollView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isDirectionalLockEnabled = true
        delaysContentTouches = false
        canCancelContentTouches = true
        bounces = true
        alwaysBounceHorizontal = true
        alwaysBounceVertical = false
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            let velocity = panGestureRecognizer.velocity(in: self)
            if abs(velocity.y) > abs(velocity.x) {
                return false
            }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    @objc func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === panGestureRecognizer,
           otherGestureRecognizer.view?.isDescendant(of: self) == true {
            return true
        }
        if otherGestureRecognizer === panGestureRecognizer,
           gestureRecognizer.view?.isDescendant(of: self) == true {
            return true
        }
        return false
    }

    override func touchesShouldCancel(in view: UIView) -> Bool {
        if view is MarkdownSelectableAttachmentTextView {
            return true
        }
        return super.touchesShouldCancel(in: view)
    }
}

private final class MarkdownAdjustedSelectionRect: UITextSelectionRect {
    private let base: UITextSelectionRect
    private let adjustedRect: CGRect

    init(base: UITextSelectionRect, rect: CGRect) {
        self.base = base
        self.adjustedRect = rect
        super.init()
    }

    override var rect: CGRect {
        adjustedRect
    }

    override var writingDirection: NSWritingDirection {
        base.writingDirection
    }

    override var containsStart: Bool {
        base.containsStart
    }

    override var containsEnd: Bool {
        base.containsEnd
    }

    override var isVertical: Bool {
        base.isVertical
    }
}

class MarkdownSelectableAttachmentTextView: UITextView {
    var allowsTapSelection = true
    var selectionRectOffset: CGPoint = .zero
    var selectionRectsProvider: ((NSRange) -> [CGRect])?
    private var isForcingStaticContentOffset = false

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    private func configure() {
        isEditable = false
        isSelectable = true
        allowsEditingTextAttributes = false
        isUserInteractionEnabled = true
        isScrollEnabled = false
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        if let textLayoutManager {
            textLayoutManager.usesFontLeading = true
        } else {
            layoutManager.allowsNonContiguousLayout = false
            layoutManager.usesFontLeading = true
        }
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceHorizontal = false
        alwaysBounceVertical = false
        bounces = false
        panGestureRecognizer.isEnabled = false
        contentInset = .zero
        scrollIndicatorInsets = .zero
        #if os(iOS)
        contentInsetAdjustmentBehavior = .never
        disableTextDragAndDrop()
        #endif
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var contentOffset: CGPoint {
        get {
            super.contentOffset
        }
        set {
            applyStaticContentOffset()
        }
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        applyStaticContentOffset()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyStaticContentOffset()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            return false
        }
        if !allowsTapSelection, gestureRecognizer is UITapGestureRecognizer {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    @objc func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if otherGestureRecognizer === enclosingMarkdownHorizontalScrollView()?.panGestureRecognizer {
            return true
        }
        return false
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        .zero
    }

    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        let rects = super.selectionRects(for: range)
        if let selectionRectsProvider {
            let start = offset(from: beginningOfDocument, to: range.start)
            let end = offset(from: beginningOfDocument, to: range.end)
            let location = max(0, min(start, end))
            let length = max(0, max(start, end) - location)
            let adjustedRects = selectionRectsProvider(NSRange(location: location, length: length))
            if !adjustedRects.isEmpty, !rects.isEmpty {
                return adjustedRects.enumerated().map { index, rect in
                    let base = rects[min(index, rects.count - 1)]
                    return MarkdownAdjustedSelectionRect(base: base, rect: rect)
                }
            }
        }
        guard abs(selectionRectOffset.x) > 0.25 || abs(selectionRectOffset.y) > 0.25 else {
            return rects
        }
        return rects.map {
            MarkdownAdjustedSelectionRect(
                base: $0,
                rect: $0.rect.offsetBy(dx: selectionRectOffset.x, dy: selectionRectOffset.y)
            )
        }
    }

    func firstSystemSelectionRectForFirstCharacter() -> CGRect? {
        guard textStorage.length > 0,
              let end = position(from: beginningOfDocument, offset: 1),
              let range = textRange(from: beginningOfDocument, to: end)
        else {
            return nil
        }
        return super.selectionRects(for: range).first?.rect
    }

    private func enclosingMarkdownHorizontalScrollView() -> MarkdownHorizontalScrollView? {
        var current = superview
        while let view = current {
            if let scrollView = view as? MarkdownHorizontalScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }

    private func applyStaticContentOffset() {
        guard !isForcingStaticContentOffset else {
            return
        }
        guard abs(super.contentOffset.x) > 0.5 || abs(super.contentOffset.y) > 0.5 else {
            return
        }
        isForcingStaticContentOffset = true
        super.setContentOffset(.zero, animated: false)
        isForcingStaticContentOffset = false
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
    in textView: UITextView,
    changedRange: NSRange?,
    invalidatesLayout: Bool = true
) {
    let storageLength = textView.textStorage.length
    let range = markdownNormalizedInvalidationRange(changedRange: changedRange, storageLength: storageLength)
    if let textLayoutManager = textView.textLayoutManager,
       let documentRange = textLayoutManager.textContentManager?.documentRange {
        let textRange = markdownTextRange(
            range,
            documentRange: documentRange,
            contentManager: textLayoutManager.textContentManager,
            storageLength: storageLength
        ) ?? documentRange
        if invalidatesLayout {
            textLayoutManager.invalidateLayout(for: textRange)
        }
        textLayoutManager.ensureLayout(for: textRange)
        return
    }

    let layoutManager = textView.layoutManager
    layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
    layoutManager.ensureLayout(forCharacterRange: range)
    layoutManager.invalidateDisplay(forCharacterRange: range)
}

final class MarkdownCodeBlockView: UIView, UIScrollViewDelegate {
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

    private let headerView = UIView()
    private let headerSeparator = UIView()
    private let languageLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let scrollView = MarkdownHorizontalScrollView()
    private let codeTextView = MarkdownSelectableAttachmentTextView(usingTextLayoutManager: true)
    private var cachedLayout: Layout?
    private var cachedWidth: CGFloat = 0
    private var needsImmediateLayout: Bool = true
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
        self.languageLabel.textAlignment = .natural
        self.languageLabel.lineBreakMode = .byTruncatingTail
        self.languageLabel.text = languageText
        headerView.addSubview(self.languageLabel)

        copyButton.titleLabel?.font = style.headerFont
        copyButton.backgroundColor = style.copyBackground
        copyButton.titleLabel?.lineBreakMode = .byTruncatingTail
        copyButton.clipsToBounds = true
        copyButton.addTarget(self, action: #selector(handleCopy), for: .touchUpInside)
        updateCopyButtonAppearance()
        headerView.addSubview(copyButton)

        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.clipsToBounds = true
        scrollView.semanticContentAttribute = .forceLeftToRight
        scrollView.delegate = self
        addSubview(scrollView)

        codeTextView.backgroundColor = .clear
        codeTextView.isEditable = false
        codeTextView.isSelectable = true
        codeTextView.allowsTapSelection = false
        codeTextView.isScrollEnabled = false
        codeTextView.semanticContentAttribute = .forceLeftToRight
        codeTextView.textAlignment = .left
        codeTextView.textContainerInset = .zero
        codeTextView.textContainer.lineFragmentPadding = 0
        codeTextView.textContainer.lineBreakMode = .byClipping
        codeTextView.textContainer.size = CGSize(width: MeasurementSizing.initialContainerWidth, height: 10_000_000)
        if let textLayoutManager = codeTextView.textLayoutManager {
            textLayoutManager.usesFontLeading = true
        } else {
            codeTextView.layoutManager.allowsNonContiguousLayout = false
            codeTextView.layoutManager.usesFontLeading = true
        }
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

    deinit {
        copyFeedbackTask?.cancel()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        #if os(iOS)
        installMarkdownAttachmentLongPressSuppression()
        #endif
    }

    func sizeThatFitsWidth(_ width: CGFloat) -> CGSize {
        let targetWidth = max(1, width)
        if abs(targetWidth - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: targetWidth)
            cachedWidth = targetWidth
            needsImmediateLayout = true
        }
        if needsImmediateLayout {
            setNeedsLayout()
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
        let storage = codeTextView.textStorage
        let oldLen = storage.length
        let newLen = codeAttributed.length
        guard newLen != oldLen || self.code != code else { return false }
        let preservedOffsetX = pendingScrollOffsetX ?? scrollView.contentOffset.x

        let shouldAppend = newLen > oldLen && code.hasPrefix(self.code)
        let redrawStartLine = shouldAppend ? max(0, renderedLineCount - 1) : 0
        var appendedText = ""
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

        let container = codeTextView.textContainer
        var textContainerHeightChanged = false
        if abs(container.size.height - max(container.size.height, estimatedCodeTextSize.height)) > 0.5 {
            container.size = CGSize(width: container.size.width, height: max(container.size.height, estimatedCodeTextSize.height))
            textContainerHeightChanged = true
        }

        let start = max(0, oldLen - 1)
        let range = NSRange(location: start, length: max(0, newLen - start))
        ensureMarkdownTextLayout(in: codeTextView, changedRange: range)

        self.code = code
        self.codeAttributed = codeAttributed
        self.estimatedCodeTextSize = estimatedCodeTextSize
        if shouldAppend {
            renderedLineCount += Self.lineBreakCount(in: appendedText)
            updateMeasuredMaxLineWidth(reset: false, changedCharacterRange: range)
        } else {
            renderedLineCount = Self.lineCount(in: code)
            updateMeasuredMaxLineWidth(reset: true, changedCharacterRange: nil)
        }
        languageText = languageLabel
        copyText = copyLabel
        self.languageLabel.text = languageLabel
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

        let viewLayoutChanged = deferredInlineWidthGrowth
            ? false
            : !layoutsApproximatelyEqual(priorLayout, nextLayout)
        let attachmentBoundsChanged = !attachmentBoundsApproximatelyEqual(priorLayout, nextLayout)
        recordAttachmentHeightDelta(from: priorLayout, to: nextLayout)
        if viewLayoutChanged {
            needsImmediateLayout = true
            pendingScrollOffsetX = preservedOffsetX
            setNeedsLayout()
        } else {
            if deferredInlineWidthGrowth {
                applyDeferredCodeWidthGrowthWithoutRelayout(nextLayout)
            }
            let maxOffsetX = max(0, nextLayout.contentWidth - nextLayout.scrollFrame.width)
            let clampedOffset = min(max(0, preservedOffsetX), maxOffsetX)
            pendingScrollOffsetX = nil
            if abs(scrollView.contentOffset.x - clampedOffset) > 0.5 {
                performWithoutMarkdownImplicitAnimations {
                    scrollView.setContentOffset(CGPoint(x: clampedOffset, y: 0), animated: false)
                }
            }
            attachment?.setHostedHorizontalOffset(clampedOffset)
        }
        invalidateCodeTextDisplay(
            startingAtLine: redrawStartLine,
            fullRedraw: !shouldAppend,
            includesLayoutChange: textContainerHeightChanged || viewLayoutChanged
        )
        return attachmentBoundsChanged
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width > 0 ? bounds.width : cachedWidth
        if abs(width - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: max(1, width))
            cachedWidth = max(1, width)
        }
        guard let layout = cachedLayout else {
            needsImmediateLayout = false
            return
        }
        performWithoutMarkdownImplicitAnimations {
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
        }
        needsImmediateLayout = false
        restoreScrollOffsetIfNeeded()
    }

    func prepareForAttachmentBounds(_ bounds: CGRect) {
        let targetWidth = max(1, bounds.width)
        let didRecomputeLayout: Bool
        if abs(targetWidth - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: targetWidth)
            cachedWidth = targetWidth
            didRecomputeLayout = true
        } else {
            didRecomputeLayout = false
        }
        guard didRecomputeLayout || needsImmediateLayout else { return }
        // TextKit owns the hosted attachment view's bounds. Writing them while
        // NSTextAttachmentViewProvider is measuring feeds bounds tracking back
        // into layout and can visibly detach large views during height changes.
        performWithoutMarkdownImplicitAnimations {
            setNeedsLayout()
        }
    }

    @objc private func handleCopy() {
        #if os(iOS)
        UIPasteboard.general.string = code
        #endif
        showCopyFeedback()
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
            if abs(scrollView.contentSize.width - layout.contentWidth) > 0.5 ||
                abs(scrollView.contentSize.height - layout.codeFrame.height) > 0.5 {
                scrollView.contentSize = CGSize(width: layout.contentWidth, height: layout.codeFrame.height)
            }

            var codeFrame = codeTextView.frame
            if abs(codeFrame.width - layout.codeFrame.width) > 0.5 ||
                abs(codeFrame.height - layout.codeFrame.height) > 0.5 {
                codeFrame.size.width = layout.codeFrame.width
                codeFrame.size.height = layout.codeFrame.height
                codeTextView.frame = codeFrame
            }
        }
    }

    private func computeLayout(width: CGFloat) -> Layout {
        let border = max(1, style.borderWidth)
        let headerPadding = style.headerPadding
        let codePadding = style.codePadding
        let viewportContentWidth = max(1, width - border * 2)
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft

        let headerLineHeight = style.headerFont.lineHeight
        let headerHeight = max(24, headerLineHeight + headerPadding.height * 2)
        let headerFrame = CGRect(x: border, y: border, width: viewportContentWidth, height: headerHeight)
        let separatorFrame = CGRect(x: border, y: headerFrame.maxY, width: viewportContentWidth, height: border)

        let copyTextSize = measureText(copyText, font: style.headerFont)
        let feedbackTextSize = measureText(Self.copyFeedbackText, font: style.headerFont)
        let copyButtonHeight = max(18, headerLineHeight + headerPadding.height)
        let availableCopyWidth = max(0, viewportContentWidth - headerPadding.width)
        let idealCopyWidth = max(copyTextSize.width, feedbackTextSize.width) + headerPadding.width * 2
        let copyButtonWidth = min(idealCopyWidth, availableCopyWidth)
        let copyButtonX = isRightToLeft
            ? headerPadding.width
            : (viewportContentWidth - copyButtonWidth - headerPadding.width)
        let copyButtonY = (headerHeight - copyButtonHeight) / 2
        let copyFrame = CGRect(
            x: max(0, copyButtonX),
            y: copyButtonY,
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
        let sourceOffset = pendingScrollOffsetX ?? attachment?.hostedHorizontalOffset() ?? scrollView.contentOffset.x
        let maxOffsetX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let clamped = min(max(0, sourceOffset), maxOffsetX)
        pendingScrollOffsetX = nil
        if abs(scrollView.contentOffset.x - clamped) > 0.5 || abs(scrollView.contentOffset.y) > 0.5 {
            performWithoutMarkdownImplicitAnimations {
                scrollView.setContentOffset(CGPoint(x: clamped, y: 0), animated: false)
            }
        }
        attachment?.setHostedHorizontalOffset(clamped)
    }

    private func invalidateCodeTextDisplay(
        startingAtLine startLine: Int,
        fullRedraw: Bool,
        includesLayoutChange: Bool
    ) {
        if fullRedraw {
            codeTextView.setNeedsDisplay()
            codeTextView.setNeedsLayout()
            return
        }

        let lineAdvance = max(1, style.codeFont.lineHeight + 2)
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
            codeTextView.setNeedsLayout()
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
        let color = isShowingCopyFeedback ? UIColor.systemGreen : style.copyTextColor
        copyButton.setTitle(title, for: .normal)
        copyButton.setTitleColor(color, for: .normal)
        copyButton.accessibilityLabel = isShowingCopyFeedback ? NSLocalizedString("Copied", comment: "") : copyText
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        let isUserDriven = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
        let storedOffset = attachment?.hostedHorizontalOffset() ?? 0
        if !isUserDriven, scrollView.window == nil, storedOffset > 0.5 {
            return
        }
        if !isUserDriven, scrollView.contentOffset.x <= 0.5, storedOffset > 0.5 {
            return
        }
        let maxOffsetX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let logicalOffset = min(max(0, scrollView.contentOffset.x), maxOffsetX)
        attachment?.setHostedHorizontalOffset(logicalOffset)
    }

    private func measureText(_ text: String, font: MarkdownPlatformFont) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attrs)
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func updateMeasuredMaxLineWidth(reset: Bool, changedCharacterRange: NSRange?) {
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

        let localMaxX = measureMaxLineWidth(
            in: codeTextView.textStorage,
            changedCharacterRange: changedCharacterRange
        )
        guard localMaxX > 0 || codeTextView.textStorage.length == 0 else {
            hasMeasuredMaxLineWidth = true
            return
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

private final class MarkdownStaticAttributedLabel: MarkdownSelectableAttachmentTextView {
    private var appliedLayoutSize: CGSize = .zero
    private var appliedTextContainerSize: CGSize = .zero
    private var needsDynamicAttachmentPreparation = true

    convenience init() {
        self.init(usingTextLayoutManager: true)
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    private func configure() {
        isEditable = false
        isSelectable = true
        allowsEditingTextAttributes = false
        isUserInteractionEnabled = true
        isScrollEnabled = false
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        if let textLayoutManager {
            textLayoutManager.usesFontLeading = true
        } else {
            layoutManager.allowsNonContiguousLayout = false
            layoutManager.usesFontLeading = true
        }
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    @discardableResult
    func setMarkdownAttributedText(_ text: NSAttributedString) -> Bool {
        guard !attributedText.isEqual(to: text) else { return false }
        attributedText = text
        needsDynamicAttachmentPreparation = true
        return true
    }

    func applyLayoutSize(_ size: CGSize, usesUnboundedTextHeight: Bool = false) {
        let normalized = CGSize(
            width: max(1, size.width.rounded(.up)),
            height: max(1, size.height.rounded(.up))
        )
        let containerSize = CGSize(
            width: normalized.width,
            height: usesUnboundedTextHeight ? markdownAttachmentTextContainerHeight : normalized.height
        )
        let sizeChanged = abs(appliedLayoutSize.width - normalized.width) > 0.5 ||
            abs(appliedLayoutSize.height - normalized.height) > 0.5
        let containerChanged = abs(appliedTextContainerSize.width - containerSize.width) > 0.5 ||
            abs(appliedTextContainerSize.height - containerSize.height) > 0.5 ||
            abs(textContainer.size.width - containerSize.width) > 0.5 ||
            abs(textContainer.size.height - containerSize.height) > 0.5
        guard sizeChanged || containerChanged || needsDynamicAttachmentPreparation else { return }

        appliedLayoutSize = normalized
        appliedTextContainerSize = containerSize
        textContainer.size = containerSize
        prepareDynamicMarkdownTextAttachments(in: textStorage, width: normalized.width)
        needsDynamicAttachmentPreparation = false
        ensureMarkdownTextLayout(in: self, changedRange: nil)
        setNeedsDisplay()
    }

    func measuredSizeFittingWidth(_ width: CGFloat) -> CGSize {
        let targetWidth = max(1, width.rounded(.up))
        applyLayoutSize(
            CGSize(width: targetWidth, height: markdownAttachmentTextContainerHeight),
            usesUnboundedTextHeight: true
        )
        let measured = sizeThatFits(CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
        return CGSize(
            width: ceil(max(0, measured.width)),
            height: ceil(max(0, measured.height))
        )
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

private final class MarkdownAttachmentTextLayout {
    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: CGSize(width: 1, height: markdownAttachmentTextContainerHeight))
    private var usedBounds: CGRect = .zero

    init() {
        layoutManager.allowsNonContiguousLayout = false
        layoutManager.usesFontLeading = true
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
    }

    func apply(text: NSAttributedString, size: CGSize) {
        let normalizedWidth = max(1, size.width.rounded(.up))
        var needsLayout = false

        if !textStorage.isEqual(to: text) {
            textStorage.setAttributedString(text)
            needsLayout = true
        }

        let targetSize = CGSize(width: normalizedWidth, height: markdownAttachmentTextContainerHeight)
        if abs(textContainer.size.width - targetSize.width) > 0.5 ||
            abs(textContainer.size.height - targetSize.height) > 0.5 {
            textContainer.size = targetSize
            needsLayout = true
        }

        guard needsLayout else { return }

        let range = NSRange(location: 0, length: textStorage.length)
        prepareDynamicMarkdownTextAttachments(in: textStorage, width: normalizedWidth)
        layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        layoutManager.invalidateDisplay(forCharacterRange: range)
        layoutManager.ensureLayout(for: textContainer)
        usedBounds = Self.measuredBounds(layoutManager: layoutManager, textContainer: textContainer)
    }

    func draw(in frame: CGRect) {
        guard textStorage.length > 0,
              let context = UIGraphicsGetCurrentContext()
        else {
            return
        }
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else { return }

        context.saveGState()
        context.clip(to: frame)
        let origin = textContainerOrigin(in: frame)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
        context.restoreGState()
    }

    var measuredSize: CGSize {
        Self.integralSize(for: usedBounds)
    }

    func selectionFrame(in frame: CGRect) -> CGRect {
        let origin = textContainerOrigin(in: frame)
        return CGRect(origin: origin, size: frame.size)
    }

    func firstSelectionLineRect() -> CGRect? {
        guard textStorage.length > 0 else { return nil }
        let characterRange = NSRange(location: 0, length: 1)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return nil }

        var result: CGRect?
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineFragmentRect, _, _, _, stop in
            result = lineFragmentRect
            stop.pointee = true
        }
        return result ?? layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
    }

    func selectionRects(for characterRange: NSRange) -> [CGRect] {
        guard textStorage.length > 0 else { return [] }
        let clampedLocation = min(max(0, characterRange.location), textStorage.length)
        let clampedEnd = min(
            textStorage.length,
            max(clampedLocation, characterRange.location + characterRange.length)
        )
        guard clampedEnd > clampedLocation else { return [] }

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: clampedLocation, length: clampedEnd - clampedLocation),
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return [] }

        var rects: [CGRect] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [self] lineFragmentRect, _, _, lineGlyphRange, _ in
            let lineSelectionRange = NSIntersectionRange(glyphRange, lineGlyphRange)
            guard lineSelectionRange.length > 0 else { return }

            let glyphRect = layoutManager.boundingRect(forGlyphRange: lineSelectionRange, in: textContainer)
            guard !glyphRect.isNull, !glyphRect.isInfinite else { return }

            let minX = max(lineFragmentRect.minX, glyphRect.minX)
            let maxX = min(lineFragmentRect.maxX, glyphRect.maxX)
            let width = max(2, maxX - minX)
            rects.append(CGRect(
                x: minX,
                y: lineFragmentRect.minY,
                width: width,
                height: lineFragmentRect.height
            ))
        }
        return rects
    }

    private func textContainerOrigin(in frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.minX - min(0, floor(usedBounds.minX)),
            y: frame.minY - min(0, floor(usedBounds.minY))
        )
    }

    private static func measuredBounds(
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> CGRect {
        markdownMeasuredTextContainerBounds(layoutManager: layoutManager, textContainer: textContainer)
    }

    private static func integralSize(for rect: CGRect) -> CGSize {
        guard !rect.isNull, !rect.isInfinite else {
            return .zero
        }
        let minX = min(0, floor(rect.minX))
        let minY = min(0, floor(rect.minY))
        let maxX = max(0, ceil(rect.maxX))
        let maxY = max(0, ceil(rect.maxY))
        return CGSize(
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }
}

private final class MarkdownTableRowView: UIView {
    let separatorView = UIView()
    private let style: MarkdownTableStyle
    private var cells: [NSAttributedString] = []
    private var cellFrames: [CGRect] = []
    private var textLayouts: [Int: MarkdownAttachmentTextLayout] = [:]
    private var hostedCellViews: [Int: MarkdownStaticAttributedLabel] = [:]
    private var selectionCellViews: [Int: MarkdownStaticAttributedLabel] = [:]
    private var rowBackgroundColor: MarkdownPlatformColor = .clear
    private let usesVisibleTextViews: Bool
    private lazy var selectionLongPressRecognizer = MarkdownAttachmentSelectionGestureRecognizer(
        target: self,
        action: #selector(handleSelectionLongPress(_:))
    )

    init(row: MarkdownTableRow, style: MarkdownTableStyle, columnCount: Int, usesVisibleTextViews: Bool) {
        self.style = style
        self.usesVisibleTextViews = usesVisibleTextViews
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false
        isUserInteractionEnabled = true
        separatorView.isUserInteractionEnabled = false
        addSubview(separatorView)
        selectionLongPressRecognizer.minimumPressDuration = 0.45
        selectionLongPressRecognizer.cancelsTouchesInView = false
        addGestureRecognizer(selectionLongPressRecognizer)
        configure(row: row, columnCount: columnCount)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(row: MarkdownTableRow, columnCount: Int) {
        cells = normalizedCells(for: row, columnCount: columnCount)
        cellFrames = Array(repeating: .zero, count: columnCount)
        textLayouts.removeAll(keepingCapacity: false)
        reconcileRequiredHostedCellViews()
        setNeedsDisplay()
    }

    func setRowBackgroundColor(_ color: MarkdownPlatformColor) {
        guard !rowBackgroundColor.isEqual(color) || backgroundColor?.isEqual(color) != true else { return }
        rowBackgroundColor = color
        backgroundColor = color
        setNeedsDisplay()
    }

    func updateCell(at column: Int, text: NSAttributedString) {
        guard cells.indices.contains(column) else { return }
        if cells[column].isEqual(to: text) { return }
        cells[column] = text
        textLayouts[column] = nil
        reconcileRequiredHostedCellView(at: column)
        setNeedsDisplay()
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
                applyTextViewGeometry(to: hosted, column: column)
            }
            if let selectionOverlay = selectionCellViews[column] {
                applyTextViewGeometry(to: selectionOverlay, column: column)
            }
            x += cellWidth + columnGap
        }
        separatorView.frame = CGRect(x: 0, y: rowHeight, width: bounds.width, height: rowSeparator)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        if let context = UIGraphicsGetCurrentContext() {
            context.clear(bounds)
        }
        if rowBackgroundColor.cgColor.alpha > CGFloat.ulpOfOne {
            rowBackgroundColor.setFill()
            UIRectFill(bounds)
        }
        guard !cells.isEmpty else { return }
        for column in 0..<min(cells.count, cellFrames.count) {
            guard hostedCellViews[column] == nil else { continue }
            let frame = cellFrames[column]
            guard frame.intersects(rect), frame.width > 0, frame.height > 0 else { continue }
            let layout = textLayout(for: column)
            layout.apply(text: cells[column], size: frame.size)
            layout.draw(in: frame)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let column = columnIndex(at: point),
              cells.indices.contains(column),
              cellFrames[column].contains(point),
              cells[column].length > 0
        else {
            return super.hitTest(point, with: event)
        }
        if let hosted = hostedCellViews[column] {
            let convertedPoint = hosted.convert(point, from: self)
            return hosted.hitTest(convertedPoint, with: event) ?? hosted
        }
        guard !usesVisibleTextViews else {
            return super.hitTest(point, with: event)
        }
        let selectionOverlay = ensureSelectionCellView(at: column)
        let convertedPoint = selectionOverlay.convert(point, from: self)
        return selectionOverlay.hitTest(convertedPoint, with: event) ?? selectionOverlay
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
        for column in textLayouts.keys where !cells.indices.contains(column) {
            textLayouts[column] = nil
        }
        for column in selectionCellViews.keys where !cells.indices.contains(column) {
            selectionCellViews[column]?.removeFromSuperview()
            selectionCellViews[column] = nil
        }
    }

    private func reconcileRequiredHostedCellView(at column: Int) {
        guard cells.indices.contains(column) else { return }
        let text = cells[column]
        let needsHostedTextView = tableCellRequiresHostedTextView(text) || (usesVisibleTextViews && text.length > 0)
        guard needsHostedTextView else {
            if let hosted = hostedCellViews.removeValue(forKey: column) {
                hosted.removeFromSuperview()
            }
            if let selectionOverlay = selectionCellViews[column] {
                applySelectionOverlay(text: text, to: selectionOverlay)
            }
            return
        }
        if let selectionOverlay = selectionCellViews.removeValue(forKey: column) {
            selectionOverlay.removeFromSuperview()
        }
        textLayouts[column] = nil
        let hosted = hostedCellViews[column] ?? makeHostedCellView()
        hostedCellViews[column] = hosted
        if hosted.superview == nil {
            addSubview(hosted)
        }
        apply(text: text, to: hosted)
        if cellFrames.indices.contains(column) {
            let frame = cellFrames[column]
            hosted.frame = frame
            hosted.applyLayoutSize(frame.size)
        }
    }

    private func columnIndex(at point: CGPoint) -> Int? {
        for column in 0..<cellFrames.count where cellFrames[column].contains(point) {
            return column
        }
        return nil
    }

    private func textLayout(for column: Int) -> MarkdownAttachmentTextLayout {
        if let existing = textLayouts[column] {
            return existing
        }
        let layout = MarkdownAttachmentTextLayout()
        textLayouts[column] = layout
        return layout
    }

    private func ensureSelectionCellView(at column: Int) -> MarkdownStaticAttributedLabel {
        if let existing = selectionCellViews[column] {
            return existing
        }
        let view = makeHostedCellView()
        view.isSelectable = true
        view.isUserInteractionEnabled = true
        view.allowsTapSelection = false
        selectionCellViews[column] = view
        addSubview(view)
        if cells.indices.contains(column) {
            applySelectionOverlay(text: cells[column], to: view)
        }
        applyTextViewGeometry(to: view, column: column)
        return view
    }

    private func makeHostedCellView() -> MarkdownStaticAttributedLabel {
        let view = MarkdownStaticAttributedLabel(usingTextLayoutManager: false)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isUserInteractionEnabled = true
        view.allowsTapSelection = false
        return view
    }

    private func apply(text: NSAttributedString, to view: MarkdownStaticAttributedLabel) {
        guard view.setMarkdownAttributedText(text) else { return }
        if view.bounds.width > 0, view.bounds.height > 0 {
            view.applyLayoutSize(view.bounds.size)
        }
        ensureMarkdownTextLayout(in: view, changedRange: nil)
        view.setNeedsDisplay()
        view.setNeedsLayout()
        setNeedsDisplay()
    }

    private func applySelectionOverlay(text: NSAttributedString, to view: MarkdownStaticAttributedLabel) {
        // Once the user interacts with a cell, one native text view owns both
        // visible text and UIKit selection geometry for that cell. Its frame is
        // derived from the same TextKit layout used by the normal drawn path.
        let selectionText = NSMutableAttributedString(attributedString: text)
        if selectionText.length > 0 {
            let fullRange = NSRange(location: 0, length: selectionText.length)
            for key in Self.selectionOverlayHiddenAttributes {
                selectionText.removeAttribute(key, range: fullRange)
            }
            selectionText.addAttribute(.foregroundColor, value: UIColor.clear, range: fullRange)
        }
        guard view.setMarkdownAttributedText(selectionText) else { return }
        if view.bounds.width > 0, view.bounds.height > 0 {
            view.applyLayoutSize(view.bounds.size)
        }
        ensureMarkdownTextLayout(in: view, changedRange: nil)
        view.setNeedsDisplay()
        view.setNeedsLayout()
        setNeedsDisplay()
    }

    private func applyTextViewGeometry(to view: MarkdownStaticAttributedLabel, column: Int) {
        guard cellFrames.indices.contains(column), cells.indices.contains(column) else { return }
        let textRect = cellFrames[column]
        let isSelectionOverlay = selectionCellViews[column] === view
        if isSelectionOverlay {
            let layout = textLayout(for: column)
            layout.apply(text: cells[column], size: textRect.size)
            view.frame = layout.selectionFrame(in: textRect)
            view.applyLayoutSize(view.bounds.size, usesUnboundedTextHeight: true)
            alignSelectionRects(of: view, to: layout)
        } else {
            view.frame = textRect
            view.applyLayoutSize(textRect.size)
            view.selectionRectOffset = .zero
            view.selectionRectsProvider = nil
        }
        if abs(view.contentOffset.x) > 0.5 || abs(view.contentOffset.y) > 0.5 {
            view.contentOffset = .zero
        }
    }

    private func alignSelectionRects(
        of view: MarkdownStaticAttributedLabel,
        to layout: MarkdownAttachmentTextLayout
    ) {
        guard let expected = layout.firstSelectionLineRect(),
              let actual = view.firstSystemSelectionRectForFirstCharacter()
        else {
            view.selectionRectOffset = .zero
            view.selectionRectsProvider = nil
            return
        }
        view.selectionRectsProvider = { range in
            layout.selectionRects(for: range)
        }
        view.selectionRectOffset = CGPoint(
            x: expected.minX - actual.minX,
            y: expected.minY - actual.minY
        )
    }

    @objc private func handleSelectionLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        let point = recognizer.location(in: self)
        guard let column = columnIndex(at: point),
              cells.indices.contains(column),
              cells[column].length > 0
        else {
            return
        }

        let view: MarkdownStaticAttributedLabel
        if let hosted = hostedCellViews[column] {
            view = hosted
        } else {
            view = ensureSelectionCellView(at: column)
        }
        applyTextViewGeometry(to: view, column: column)
        view.becomeFirstResponder()
        view.selectedRange = NSRange(location: 0, length: view.textStorage.length)
    }

    private static let selectionOverlayHiddenAttributes: [NSAttributedString.Key] = [
        .backgroundColor,
        .underlineStyle,
        .underlineColor,
        .strikethroughStyle,
        .strikethroughColor,
        .strokeColor,
        .strokeWidth,
        .foregroundColor,
        .link
    ]
}

final class MarkdownTableView: UIView, UIScrollViewDelegate {
    private enum IncrementalLayoutTuning {
        // Above this point, relaying out every existing row during streaming is visible as a
        // blank interval. Keep established columns stable and only grow row heights/new rows.
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

    private var rows: [MarkdownTableRow]
    private let style: MarkdownTableStyle
    private var columnCount: Int
    private let scrollView = MarkdownHorizontalScrollView()
    private let contentView = UIView()
    private var rowViews: [MarkdownTableRowView] = []
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
    private var pendingAttachmentBoundsChange = false
    private var usesVisibleCellTextViews: Bool

    init(rows: [MarkdownTableRow], style: MarkdownTableStyle) {
        self.rows = rows
        self.style = style
        self.columnCount = rows.map { $0.cells.count }.max() ?? 0
        self.usesVisibleCellTextViews = Self.shouldUseVisibleCellTextViews(rowCount: rows.count)
        super.init(frame: .zero)

        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = true
        scrollView.backgroundColor = .clear
        scrollView.isOpaque = false
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.clipsToBounds = true
        scrollView.delegate = self
        addSubview(scrollView)
        contentView.isOpaque = false
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = true
        contentView.isUserInteractionEnabled = true
        scrollView.addSubview(contentView)

        buildRows()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        #if os(iOS)
        installMarkdownAttachmentLongPressSuppression()
        #endif
    }

    func sizeThatFitsWidth(_ width: CGFloat) -> CGSize {
        let targetWidth = max(1, width)
        if abs(targetWidth - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: targetWidth)
            cachedWidth = targetWidth
            needsImmediateLayout = true
        }
        if needsImmediateLayout {
            setNeedsLayout()
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
        let preservedOffsetX = pendingScrollOffsetX ?? scrollView.contentOffset.x
        let nextUsesVisibleCellTextViews = Self.shouldUseVisibleCellTextViews(rowCount: nextRows.count)
        if nextUsesVisibleCellTextViews != usesVisibleCellTextViews {
            let nextColumnCount = nextRows.map { $0.cells.count }.max() ?? 0
            guard nextColumnCount > 0 else { return false }
            rebuild(rows: nextRows, columnCount: nextColumnCount)
            needsImmediateLayout = true
            pendingScrollOffsetX = preservedOffsetX
            setNeedsLayout()
            return true
        }

        if nextRows.count < rows.count || columnCount == 0 {
            let nextColumnCount = nextRows.map { $0.cells.count }.max() ?? 0
            guard nextColumnCount > 0 else { return false }
            rebuild(rows: nextRows, columnCount: nextColumnCount)
            needsImmediateLayout = true
            pendingScrollOffsetX = preservedOffsetX
            setNeedsLayout()
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
                needsImmediateLayout = true
                pendingScrollOffsetX = preservedOffsetX
                setNeedsLayout()
                return true
            }

            if !isStreamingAppend, rowsHaveChanged(beforeLastRow: rows, nextRows: nextRows) {
                rebuild(rows: nextRows, columnCount: nextRows.map { $0.cells.count }.max() ?? 0)
                needsImmediateLayout = true
                pendingScrollOffsetX = preservedOffsetX
                setNeedsLayout()
                return true
            }

            let priorLayout = cachedLayout
            let oldLastRowHeight: CGFloat? = {
                guard let priorLayout, priorLayout.rowHeights.indices.contains(lastIndex) else { return nil }
                return priorLayout.rowHeights[lastIndex]
            }()
            var needsViewLayout = false
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
                    columnWidthsChanged
                let rowHeightChanged = abs(heightDelta) > 0.5

                if needsFullRelayout {
                    laidOutRowCount = 0
                    laidOutContentHeight = 0
                    laidOutContentWidth = 0
                    laidOutColumnWidths.removeAll(keepingCapacity: false)
                    needsViewLayout = true
                } else if laidOutRowCount == rows.count {
                    let startY = max(0, priorLayout.tableSize.height - (oldLastRowHeight + priorLayout.rowSeparatorWidth))
                    laidOutRowCount = lastIndex
                    laidOutContentHeight = startY
                    needsViewLayout = rowHeightChanged
                } else if needsImmediateLayout {
                    // A prior streaming update already scheduled a layout pass. Do not
                    // promote content-only deltas into parent TextKit invalidations while
                    // that pass is pending; large attachment views visibly disappear during
                    // repeated bounds negotiation.
                    needsViewLayout = true
                } else {
                    laidOutRowCount = 0
                    laidOutContentHeight = 0
                    laidOutContentWidth = 0
                    laidOutColumnWidths.removeAll(keepingCapacity: false)
                    needsViewLayout = true
                }
            } else {
                cachedLayout = nil
                laidOutRowCount = 0
                laidOutContentHeight = 0
                laidOutContentWidth = 0
                laidOutColumnWidths.removeAll(keepingCapacity: false)
                needsViewLayout = true
            }

            let attachmentBoundsChanged = !tableBoundsApproximatelyEqual(priorLayout, cachedLayout)
            recordAttachmentHeightDelta(from: priorLayout, to: cachedLayout)
            if needsViewLayout {
                needsImmediateLayout = true
                pendingScrollOffsetX = preservedOffsetX
                applyCurrentLayoutBoundsIfNeeded()
                setNeedsLayout()
            } else {
                pendingScrollOffsetX = preservedOffsetX
                restoreScrollOffsetIfNeeded()
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
            needsImmediateLayout = true
            pendingScrollOffsetX = preservedOffsetX
            setNeedsLayout()
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

        needsImmediateLayout = true
        pendingScrollOffsetX = preservedOffsetX
        applyCurrentLayoutBoundsIfNeeded()
        setNeedsLayout()
        return attachmentBoundsChanged
    }

    private func applyCurrentLayoutBoundsIfNeeded() {
        guard let layout = cachedLayout,
              layout.tableSize.width > 0,
              layout.tableSize.height > 0
        else {
            return
        }
        guard bounds.width > 0,
              abs(bounds.width - layout.tableSize.width) <= 0.5
        else {
            setNeedsLayout()
            return
        }
        performWithoutMarkdownImplicitAnimations {
            setNeedsLayout()
            layoutIfNeeded()
        }
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
        let minRowHeight = style.baseFont.lineHeight
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
        let minRowHeight = style.baseFont.lineHeight
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
        guard let layout = cachedLayout else {
            needsImmediateLayout = false
            return
        }
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
        performWithoutMarkdownImplicitAnimations {
            scrollView.frame = CGRect(origin: .zero, size: bounds.size)
            scrollView.contentSize = CGSize(width: layout.contentWidth, height: layout.tableSize.height)
            contentView.frame = CGRect(x: 0, y: 0, width: layout.contentWidth, height: layout.tableSize.height)
        }

        guard startIndex < rows.count else {
            needsImmediateLayout = false
            restoreScrollOffsetIfNeeded()
            return
        }

        var y: CGFloat = needsFullRelayout ? 0 : laidOutContentHeight
        performWithoutMarkdownImplicitAnimations {
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
        needsImmediateLayout = false
        restoreScrollOffsetIfNeeded()
    }

    func prepareForAttachmentBounds(_ bounds: CGRect) {
        let targetWidth = max(1, bounds.width)
        let didRecomputeLayout: Bool
        if abs(targetWidth - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: targetWidth)
            cachedWidth = targetWidth
            didRecomputeLayout = true
        } else {
            didRecomputeLayout = false
        }
        guard didRecomputeLayout || needsImmediateLayout else { return }
        // Apply the just-measured size before TextKit draws the hosted view.
        // Otherwise a growing streaming row can render one frame with stale
        // cell frames, which makes text appear below the table body.
        performWithoutMarkdownImplicitAnimations {
            let targetBounds = CGRect(origin: self.bounds.origin, size: bounds.size)
            if abs(self.bounds.width - targetBounds.width) > 0.5 ||
                abs(self.bounds.height - targetBounds.height) > 0.5 {
                self.bounds = targetBounds
            }
            setNeedsLayout()
            layoutIfNeeded()
        }
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
        guard abs(delta) > 0.5 else { return }
        attachment?.recordHostedHeightDelta(delta)
    }

    private func buildRows() {
        guard columnCount > 0 else { return }
        rowViews.reserveCapacity(rows.count)
        performWithoutMarkdownImplicitAnimations {
            for row in rows {
                let rowView = MarkdownTableRowView(
                    row: row,
                    style: style,
                    columnCount: columnCount,
                    usesVisibleTextViews: usesVisibleCellTextViews
                )
                rowView.separatorView.backgroundColor = style.borderColor
                contentView.addSubview(rowView)
                rowViews.append(rowView)
            }
        }
    }

    private func rebuild(rows: [MarkdownTableRow], columnCount: Int) {
        self.rows = rows
        self.columnCount = columnCount
        self.usesVisibleCellTextViews = Self.shouldUseVisibleCellTextViews(rowCount: rows.count)
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
                let rowView = MarkdownTableRowView(
                    row: row,
                    style: style,
                    columnCount: columnCount,
                    usesVisibleTextViews: usesVisibleCellTextViews
                )
                rowView.separatorView.backgroundColor = style.borderColor
                contentView.addSubview(rowView)
                rowViews.append(rowView)
            }
        }
    }

    private func restoreScrollOffsetIfNeeded() {
        let sourceOffset = pendingScrollOffsetX ?? attachment?.hostedHorizontalOffset() ?? scrollView.contentOffset.x
        let maxOffsetX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let clamped = min(max(0, sourceOffset), maxOffsetX)
        pendingScrollOffsetX = nil
        if abs(scrollView.contentOffset.x - clamped) > 0.5 || abs(scrollView.contentOffset.y) > 0.5 {
            performWithoutMarkdownImplicitAnimations {
                scrollView.setContentOffset(CGPoint(x: clamped, y: 0), animated: false)
            }
        }
        attachment?.setHostedHorizontalOffset(clamped)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        let isUserDriven = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
        let storedOffset = attachment?.hostedHorizontalOffset() ?? 0
        if !isUserDriven, scrollView.window == nil, storedOffset > 0.5 {
            return
        }
        if !isUserDriven, scrollView.contentOffset.x <= 0.5, storedOffset > 0.5 {
            return
        }
        let maxOffsetX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let logicalOffset = min(max(0, scrollView.contentOffset.x), maxOffsetX)
        attachment?.setHostedHorizontalOffset(logicalOffset)
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
        let minRowHeight = style.baseFont.lineHeight
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

    private func shouldFreezeColumnWidthsForIncrementalUpdate(rowCount: Int) -> Bool {
        rowCount >= IncrementalLayoutTuning.largeTableRowThreshold
    }

    private static func shouldUseVisibleCellTextViews(rowCount _: Int) -> Bool {
        false
    }

    private func measureTableCell(_ cell: NSAttributedString, width: CGFloat) -> CGSize {
        if !width.isFinite || width >= 10_000 {
            return CGSize(
                width: measureUnwrappedAttributedTextWidth(cell, fallbackFont: style.baseFont),
                height: style.baseFont.lineHeight
            )
        }
        return measureHostedAttributedText(cell, width: width)
    }

    private static let tableCellMarkdownSyntaxCharacters = CharacterSet(charactersIn: "*_`[]()!#<>\\$~")

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
        let minRowHeight = style.baseFont.lineHeight
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
    private typealias Layout = MarkdownQuoteLayout

    private let content: NSAttributedString
    private let style: MarkdownQuoteStyle
    private let borderView = UIView()
    private let textLayout = MarkdownAttachmentTextLayout()
    private var hostedTextView: MarkdownStaticAttributedLabel?
    private var selectionOverlay: MarkdownStaticAttributedLabel?
    private var cachedLayout: Layout?
    private var cachedWidth: CGFloat = 0
    private lazy var selectionLongPressRecognizer = MarkdownAttachmentSelectionGestureRecognizer(
        target: self,
        action: #selector(handleSelectionLongPress(_:))
    )

    init(content: NSAttributedString, style: MarkdownQuoteStyle) {
        self.content = content
        self.style = style
        super.init(frame: .zero)

        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = true

        borderView.backgroundColor = style.borderColor
        borderView.isUserInteractionEnabled = false
        addSubview(borderView)

        selectionLongPressRecognizer.minimumPressDuration = 0.45
        selectionLongPressRecognizer.cancelsTouchesInView = false
        addGestureRecognizer(selectionLongPressRecognizer)
        reconcileRequiredHostedTextView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        #if os(iOS)
        installMarkdownAttachmentLongPressSuppression()
        #endif
    }

    func sizeThatFitsWidth(_ width: CGFloat) -> CGSize {
        let targetWidth = max(1, width)
        if abs(targetWidth - cachedWidth) > 0.5 || cachedLayout == nil {
            cachedLayout = computeLayout(width: targetWidth)
            cachedWidth = targetWidth
            setNeedsLayout()
        }
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
        if let hostedTextView {
            applyHostedTextViewGeometry(to: hostedTextView, layout: layout)
        } else {
            textLayout.apply(text: content, size: layout.textFrame.size)
            applySelectionOverlayGeometry()
        }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard hostedTextView == nil,
              let layout = cachedLayout,
              layout.textFrame.intersects(rect),
              content.length > 0
        else {
            return
        }
        textLayout.apply(text: content, size: layout.textFrame.size)
        textLayout.draw(in: layout.textFrame)
    }

    private func computeLayout(width: CGFloat) -> Layout {
        let targetWidth = max(1, width)
        let textWidth = markdownQuoteTextWidth(for: targetWidth, style: style)
        let textSize = measureAttributedText(content, width: textWidth)
        return markdownQuoteLayout(width: targetWidth, style: style, textHeight: textSize.height)
    }

    private func reconcileRequiredHostedTextView() {
        guard tableCellRequiresHostedTextView(content) else {
            return
        }
        _ = ensureHostedTextView()
    }

    private func ensureHostedTextView() -> MarkdownStaticAttributedLabel {
        if let hostedTextView {
            return hostedTextView
        }
        let view = makeHostedTextView()
        hostedTextView = view
        if let selectionOverlay {
            selectionOverlay.removeFromSuperview()
            self.selectionOverlay = nil
        }
        addSubview(view)
        applyHostedText(to: view)
        if let layout = cachedLayout {
            applyHostedTextViewGeometry(to: view, layout: layout)
        }
        setNeedsDisplay()
        return view
    }

    private func makeHostedTextView() -> MarkdownStaticAttributedLabel {
        let view = MarkdownStaticAttributedLabel(usingTextLayoutManager: false)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isUserInteractionEnabled = true
        view.allowsTapSelection = false
        return view
    }

    private func applyHostedText(to view: MarkdownStaticAttributedLabel) {
        guard view.setMarkdownAttributedText(content) else { return }
        if view.bounds.width > 0, view.bounds.height > 0 {
            view.applyLayoutSize(view.bounds.size)
        }
        ensureMarkdownTextLayout(in: view, changedRange: nil)
        view.setNeedsDisplay()
        view.setNeedsLayout()
    }

    private func applyHostedTextViewGeometry(to view: MarkdownStaticAttributedLabel, layout: Layout) {
        view.frame = layout.textFrame
        view.applyLayoutSize(layout.textFrame.size)
        view.selectionRectOffset = .zero
        view.selectionRectsProvider = nil
        if abs(view.contentOffset.x) > 0.5 || abs(view.contentOffset.y) > 0.5 {
            view.contentOffset = .zero
        }
    }

    private func ensureSelectionOverlay() -> MarkdownStaticAttributedLabel {
        if let selectionOverlay {
            return selectionOverlay
        }
        let view = MarkdownStaticAttributedLabel(usingTextLayoutManager: false)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isUserInteractionEnabled = true
        view.allowsTapSelection = false
        selectionOverlay = view
        addSubview(view)
        applySelectionOverlayText(to: view)
        applySelectionOverlayGeometry()
        return view
    }

    private func applySelectionOverlayText(to view: MarkdownStaticAttributedLabel) {
        let selectionText = NSMutableAttributedString(attributedString: content)
        if selectionText.length > 0 {
            let fullRange = NSRange(location: 0, length: selectionText.length)
            for key in Self.selectionOverlayHiddenAttributes {
                selectionText.removeAttribute(key, range: fullRange)
            }
            selectionText.addAttribute(.foregroundColor, value: UIColor.clear, range: fullRange)
        }
        guard view.setMarkdownAttributedText(selectionText) else { return }
        ensureMarkdownTextLayout(in: view, changedRange: nil)
        view.setNeedsDisplay()
        view.setNeedsLayout()
    }

    private func applySelectionOverlayGeometry() {
        guard let overlay = selectionOverlay,
              let layout = cachedLayout
        else {
            return
        }
        textLayout.apply(text: content, size: layout.textFrame.size)
        overlay.frame = textLayout.selectionFrame(in: layout.textFrame)
        overlay.applyLayoutSize(overlay.bounds.size, usesUnboundedTextHeight: true)
        alignSelectionRects(of: overlay)
        if abs(overlay.contentOffset.x) > 0.5 || abs(overlay.contentOffset.y) > 0.5 {
            overlay.contentOffset = .zero
        }
    }

    private func alignSelectionRects(of view: MarkdownStaticAttributedLabel) {
        guard let expected = textLayout.firstSelectionLineRect(),
              let actual = view.firstSystemSelectionRectForFirstCharacter()
        else {
            view.selectionRectOffset = .zero
            view.selectionRectsProvider = nil
            return
        }
        view.selectionRectsProvider = { [textLayout] range in
            textLayout.selectionRects(for: range)
        }
        view.selectionRectOffset = CGPoint(
            x: expected.minX - actual.minX,
            y: expected.minY - actual.minY
        )
    }

    @objc private func handleSelectionLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              let layout = cachedLayout,
              content.length > 0,
              layout.textFrame.contains(recognizer.location(in: self))
        else {
            return
        }
        let view: MarkdownStaticAttributedLabel
        if let hostedTextView {
            view = hostedTextView
        } else {
            view = ensureSelectionOverlay()
            applySelectionOverlayGeometry()
        }
        view.becomeFirstResponder()
        view.selectedRange = NSRange(location: 0, length: view.textStorage.length)
    }

    private static let selectionOverlayHiddenAttributes: [NSAttributedString.Key] = [
        .backgroundColor,
        .underlineStyle,
        .underlineColor,
        .strikethroughStyle,
        .strikethroughColor,
        .strokeColor,
        .strokeWidth,
        .foregroundColor,
        .link
    ]
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        #if os(iOS)
        installMarkdownAttachmentLongPressSuppression()
        #endif
    }

    func sizeThatFitsWidth(_ width: CGFloat) -> CGSize {
        let targetWidth = max(1, width)
        if abs(targetWidth - cachedWidth) > 0.5 {
            cachedWidth = targetWidth
            cachedSize = CGSize(width: targetWidth, height: verticalPadding * 2 + thickness)
            setNeedsLayout()
        }
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
        case math
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
            let attachment = markdownAttachmentBox.value
            let resolved: UIView
            if let attachment = markdownAttachmentBox.value,
               let cached = Self.cachedView(for: attachment) ?? Self.hostedView(for: attachment) {
                resolved = cached
            } else {
                let created = Self.makeView(for: attachment)
                if let attachment {
                    Self.cache(view: created, for: attachment)
                }
                resolved = created
            }
            Self.bind(view: resolved, to: attachment)
            Self.prepareForAttachmentInteraction(resolved)
            return UncheckedSendableBox(value: resolved)
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
        let textContainerWidth = textContainer?.size.width

        let layout: AttachmentLayout = MainActor.assumeIsolated {
            guard let attachment = markdownAttachmentBox.value else {
                let resolvedView = currentViewBox.value ?? UIView()
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
                view resolvedView: UIView,
                attachmentBoundsChanged: Bool
            ) -> AttachmentLayout? {
                guard !attachmentBoundsChanged,
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
                } else if let hosted = codeAttachment.hostedView {
                    resolvedView = hosted
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
                let attachmentBoundsChanged = resolvedView.applyUpdate(from: codeAttachment)
                if let cached = cachedLayoutAfterContentOnlyUpdate(
                    kind: .codeBlock,
                    key: key,
                    view: resolvedView,
                    attachmentBoundsChanged: attachmentBoundsChanged
                ) {
                    return cached
                }
                let bounds = CGRect(origin: .zero, size: resolvedView.sizeThatFitsWidth(available))
                resolvedView.prepareForAttachmentBounds(bounds)
                resolvedView.markAttachmentBoundsObserved()
                return AttachmentLayout(view: UncheckedSendableBox(value: resolvedView), bounds: bounds, cacheKey: key)

            case let tableAttachment as MarkdownTableAttachment:
                if let cached = cachedLayoutIfPossible(kind: .table, contentVersion: tableAttachment.contentVersion) {
                    return cached
                }
                let resolvedView: MarkdownTableView
                if let existing = currentViewBox.value as? MarkdownTableView {
                    resolvedView = existing
                } else if let hosted = tableAttachment.hostedView {
                    resolvedView = hosted
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
                let attachmentBoundsChanged = resolvedView.applyUpdate(from: tableAttachment)
                if let cached = cachedLayoutAfterContentOnlyUpdate(
                    kind: .table,
                    key: key,
                    view: resolvedView,
                    attachmentBoundsChanged: attachmentBoundsChanged
                ) {
                    return cached
                }
                let bounds = CGRect(origin: .zero, size: resolvedView.sizeThatFitsWidth(available))
                resolvedView.prepareForAttachmentBounds(bounds)
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
    private static func makeView(for attachment: MarkdownAttachment?) -> UIView {
        guard let attachment else {
            return UIView()
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
            return UIView()
        }
    }

    @MainActor
    private static func bind(view: UIView, to attachment: MarkdownAttachment?) {
        prepareForAttachmentInteraction(view)
        switch (attachment, view) {
        case let (attachment as MarkdownCodeBlockAttachment, view as MarkdownCodeBlockView):
            attachment.hostedView = view
        case let (attachment as MarkdownTableAttachment, view as MarkdownTableView):
            attachment.hostedView = view
        default:
            break
        }
    }

    @MainActor
    private static func hostedView(for attachment: MarkdownAttachment) -> UIView? {
        switch attachment {
        case let attachment as MarkdownCodeBlockAttachment:
            return attachment.hostedView
        case let attachment as MarkdownTableAttachment:
            return attachment.hostedView
        default:
            return nil
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
        prepareForAttachmentInteraction(view)
        viewCache.setObject(view, forKey: attachment)
    }

    @MainActor
    private static func prepareForAttachmentInteraction(_ view: UIView) {
        #if os(iOS)
        view.installMarkdownAttachmentLongPressSuppression()
        #endif
    }
}


#endif
