//
//  MarkdownTextView.swift
//  Voice Chat
//

@preconcurrency import Foundation
import SwiftUI

#if os(iOS) || os(tvOS) || os(watchOS)
@preconcurrency import UIKit

typealias MarkdownPlatformTextView = UITextView
typealias MarkdownPlatformFont = UIFont
typealias MarkdownPlatformColor = UIColor
typealias MarkdownPlatformImage = UIImage
typealias MarkdownFontTraits = UIFontDescriptor.SymbolicTraits

@MainActor
struct MarkdownTextView: UIViewRepresentable {
    let markdown: String
    let colorScheme: ColorScheme
    let sizeCategory: ContentSizeCategory

    func makeCoordinator() -> MarkdownTextCoordinator {
        MarkdownTextCoordinator()
    }

    func makeUIView(context: Context) -> MarkdownUIKitTextView {
        let textView: MarkdownUIKitTextView
        if #available(iOS 16.0, tvOS 16.0, *) {
            textView = MarkdownUIKitTextView(usingTextLayoutManager: true)
        } else {
            textView = MarkdownUIKitTextView()
        }
        MarkdownAttachmentViewProviderRegistry.registerIfNeeded()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.adjustsFontForContentSizeCategory = true
        #if os(iOS)
        textView.delegate = context.coordinator
        textView.disableTextDragAndDrop()
        #endif
        textView.installTraitObserver()
        textView.onLayout = { [weak coordinator = context.coordinator] width in
            Task { @MainActor in
                coordinator?.updateLayoutWidth(width)
            }
        }
        return textView
    }

    func updateUIView(_ uiView: MarkdownUIKitTextView, context: Context) {
        context.coordinator.update(
            textView: uiView,
            markdown: markdown,
            colorScheme: colorScheme,
            sizeCategory: sizeCategory
        )
        #if os(iOS)
        uiView.disableTextDragAndDrop()
        #endif
        uiView.onTraitChange = { [weak coordinator = context.coordinator, weak uiView] in
            guard let uiView else { return }
            Task { @MainActor in
                coordinator?.update(
                    textView: uiView,
                    markdown: markdown,
                    colorScheme: colorScheme,
                    sizeCategory: sizeCategory,
                    force: true
                )
                #if os(iOS)
                uiView.disableTextDragAndDrop()
                #endif
            }
        }
    }
}

final class MarkdownUIKitTextView: UITextView {
    var onLayout: ((CGFloat) -> Void)?
    var onTraitChange: (() -> Void)?
    private var lastWidth: CGFloat = 0
    private var didInstallTraitObserver = false

    override func layoutSubviews() {
        super.layoutSubviews()
        #if os(iOS)
        disableTextDragAndDrop()
        #endif
        let width = bounds.width
        if abs(width - lastWidth) > 0.5 {
            lastWidth = width
            onLayout?(width)
        }
    }

    override var intrinsicContentSize: CGSize {
        let targetWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        let size = sizeThatFits(CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(size.height))
    }

    deinit {
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        #endif
    }

    override func copy(_ sender: Any?) {
        let range = selectedRange
        guard range.length > 0 else {
            super.copy(sender)
            return
        }
        var hasMarkdownAttachment = false
        textStorage.enumerateAttribute(.attachment, in: range, options: []) { value, _, stop in
            if value is MarkdownAttachment {
                hasMarkdownAttachment = true
                stop.pointee = true
            }
        }
        guard hasMarkdownAttachment else {
            super.copy(sender)
            return
        }
        let attributed = textStorage.attributedSubstring(from: range)
        let plain = extractPlainText(from: attributed)
        guard !plain.isEmpty else {
            super.copy(sender)
            return
        }
        UIPasteboard.general.string = plain
    }

    func installTraitObserver() {
        guard !didInstallTraitObserver else { return }
        didInstallTraitObserver = true
        if #available(iOS 17.0, tvOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self], target: self, action: #selector(handleTraitChange))
        }
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForegroundNotification),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #endif
    }

    @objc private func handleTraitChange() {
        onTraitChange?()
    }

    @objc private func handleForegroundNotification() {
        onTraitChange?()
    }
}

#if os(iOS)
extension UITextView {
    func disableTextDragAndDrop() {
        if #available(iOS 11.0, *) {
            textDragInteraction?.isEnabled = false
            if let dropInteraction = textDropInteraction {
                removeInteraction(dropInteraction)
            }
        }
    }
}
#endif

#elseif os(macOS)
@preconcurrency import AppKit

typealias MarkdownPlatformTextView = NSTextView
typealias MarkdownPlatformFont = NSFont
typealias MarkdownPlatformColor = NSColor
typealias MarkdownPlatformImage = NSImage
typealias MarkdownFontTraits = NSFontDescriptor.SymbolicTraits

@MainActor
struct MarkdownTextView: NSViewRepresentable {
    let markdown: String
    let colorScheme: ColorScheme
    let sizeCategory: ContentSizeCategory

    func makeCoordinator() -> MarkdownTextCoordinator {
        MarkdownTextCoordinator()
    }

    func makeNSView(context: Context) -> MarkdownAppKitTextView {
        let textView: MarkdownAppKitTextView
        if #available(macOS 12.0, *) {
            textView = MarkdownAppKitTextView(usingTextLayoutManager: true)
        } else {
            let textStorage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)
            let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
            layoutManager.addTextContainer(textContainer)
            textView = MarkdownAppKitTextView(frame: .zero, textContainer: textContainer)
        }
        MarkdownAttachmentViewProviderRegistry.registerIfNeeded()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.importsGraphics = true
        textView.layoutManager?.allowsNonContiguousLayout = false
        textView.layoutManager?.usesFontLeading = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isRichText = true
        textView.delegate = context.coordinator
        textView.onLayout = { [weak coordinator = context.coordinator] width in
            Task { @MainActor in
                coordinator?.updateLayoutWidth(width)
            }
        }
        return textView
    }

    func updateNSView(_ nsView: MarkdownAppKitTextView, context: Context) {
        context.coordinator.update(
            textView: nsView,
            markdown: markdown,
            colorScheme: colorScheme,
            sizeCategory: sizeCategory
        )
    }

    @available(macOS 13.0, *)
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: MarkdownAppKitTextView,
        context: Context
    ) -> CGSize? {
        _ = context
        guard let width = proposal.width, width > 1 else { return nil }
        let height = nsView.heightThatFits(width: width)
        return CGSize(width: width, height: height)
    }
}

final class MarkdownAppKitTextView: NSTextView {
    var onLayout: ((CGFloat) -> Void)?
    private var lastWidth: CGFloat = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let width = bounds.width
        updateContainerSize(for: width)
        if abs(width - lastWidth) > 0.5 {
            lastWidth = width
            onLayout?(width)
            invalidateIntrinsicContentSize()
        }
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        updateContainerSize(for: width)
        if abs(width - lastWidth) > 0.5 {
            lastWidth = width
            onLayout?(width)
            invalidateIntrinsicContentSize()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let width = newSize.width
        updateContainerSize(for: width)
        if abs(width - lastWidth) > 0.5 {
            lastWidth = width
            onLayout?(width)
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        let height = heightThatFits(width: bounds.width)
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if handleCopyClick(at: point) {
            return
        }
        super.mouseDown(with: event)
    }

    override func copy(_ sender: Any?) {
        guard let textStorage else {
            super.copy(sender)
            return
        }
        let range = selectedRange()
        guard range.length > 0 else {
            super.copy(sender)
            return
        }
        var hasMarkdownAttachment = false
        textStorage.enumerateAttribute(.attachment, in: range, options: []) { value, _, stop in
            if value is MarkdownAttachment {
                hasMarkdownAttachment = true
                stop.pointee = true
            }
        }
        guard hasMarkdownAttachment else {
            super.copy(sender)
            return
        }
        let plain = plainText(for: range, in: textStorage)
        guard !plain.isEmpty else {
            super.copy(sender)
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(plain, forType: .string)
    }

    override func scrollWheel(with event: NSEvent) {
        if handleAttachmentScroll(with: event) {
            return
        }
        super.scrollWheel(with: event)
    }

    private func updateContainerSize(for width: CGFloat) {
        guard let textContainer else { return }
        let measuredWidth = width > 1 ? width : (lastWidth > 1 ? lastWidth : 320)
        let targetWidth = max(1, measuredWidth - textContainerInset.width * 2)
        if abs(textContainer.containerSize.width - targetWidth) > 0.5 {
            textContainer.containerSize = NSSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    func heightThatFits(width: CGFloat) -> CGFloat {
        guard let layoutManager, let textContainer else { return super.intrinsicContentSize.height }
        updateContainerSize(for: width)
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return ceil(used.height + textContainerInset.height * 2)
    }

    private func handleCopyClick(at point: CGPoint) -> Bool {
        guard let (attachment, rect) = codeAttachment(at: point) else { return false }
        let local = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
        guard attachment.isCopyButtonHit(at: local) else { return false }
        attachment.copyToPasteboard()
        return true
    }

    private func codeAttachment(at point: CGPoint) -> (MarkdownCodeBlockAttachment, CGRect)? {
        guard let (attachment, _, rect) = attachment(at: point),
              let codeAttachment = attachment as? MarkdownCodeBlockAttachment else { return nil }
        guard !attachment.allowsTextAttachmentView else { return nil }
        return (codeAttachment, rect)
    }

    private func attachment(at point: CGPoint) -> (MarkdownAttachment, NSRange, CGRect)? {
        guard let layoutManager, let textContainer else { return nil }
        let origin = textContainerOrigin
        let location = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        var fraction: CGFloat = 0
        let index = layoutManager.characterIndex(
            for: location,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard index < textStorage?.length ?? 0 else { return nil }
        var range = NSRange(location: 0, length: 0)
        guard let attachment = textStorage?.attribute(.attachment, at: index, effectiveRange: &range)
                as? MarkdownAttachment else { return nil }
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: index, length: 1),
            actualCharacterRange: nil
        )
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let adjusted = rect.offsetBy(dx: origin.x, dy: origin.y)
        guard adjusted.contains(point) else { return nil }
        return (attachment, range, adjusted)
    }

    private func handleAttachmentScroll(with event: NSEvent) -> Bool {
        let location = convert(event.locationInWindow, from: nil)
        guard let (attachment, range, _) = attachment(at: location) else { return false }
        guard !attachment.allowsTextAttachmentView else { return false }
        var delta = event.scrollingDeltaX
        if abs(delta) < 0.1, event.modifierFlags.contains(.shift) {
            delta = event.scrollingDeltaY
        }
        if abs(delta) < 0.1 { return false }
        if event.isDirectionInvertedFromDevice {
            delta = -delta
        }
        guard attachment.scrollHorizontally(by: delta) else { return false }
        if let layoutManager {
            layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: range)
        }
        needsDisplay = true
        return true
    }

    private func plainText(for range: NSRange, in storage: NSTextStorage) -> String {
        var output = ""
        storage.enumerateAttributes(in: range, options: []) { attrs, subRange, _ in
            if let attachment = attrs[.attachment] as? MarkdownAttachment {
                output += attachment.plainText
            } else {
                output += storage.attributedSubstring(from: subRange).string
            }
        }
        return output
    }
}

extension MarkdownTextCoordinator: NSTextViewDelegate {
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        false
    }
}
#endif

#if os(iOS)
extension MarkdownTextCoordinator: UITextViewDelegate {
    @available(iOS 17.0, *)
    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        _ = textView
        if case .textAttachment = textItem.content {
            return nil
        }
        return defaultAction
    }

    @available(iOS 17.0, *)
    func textView(
        _ textView: UITextView,
        menuConfigurationFor textItem: UITextItem,
        defaultMenu: UIMenu
    ) -> UITextItem.MenuConfiguration? {
        _ = textView
        if case .textAttachment = textItem.content {
            return nil
        }
        return UITextItem.MenuConfiguration(menu: defaultMenu)
    }

    @available(iOS, introduced: 10.0, deprecated: 17.0)
    func textView(
        _ textView: UITextView,
        shouldInteractWith textAttachment: NSTextAttachment,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        _ = textView
        _ = textAttachment
        _ = characterRange
        _ = interaction
        // Prevent the system from treating attachments as draggable objects during long-press.
        return false
    }
}
#endif

