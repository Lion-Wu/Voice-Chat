//
//  MarkdownTextCoordinator.swift
//  Voice Chat
//

@preconcurrency import Foundation
import SwiftUI

#if os(iOS) || os(tvOS) || os(watchOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

@MainActor
final class MarkdownTextCoordinator: NSObject, @unchecked Sendable {
    private var lastMarkdown: String = ""
    private var lastStyleKey: String = ""
    private var currentRenderID: UInt64 = 0
    private var attachments: [MarkdownAttachment] = []
    private var lastLayoutWidth: CGFloat = 0
    private weak var currentTextView: MarkdownPlatformTextView?

    private let renderQueue = DispatchQueue(label: "voicechat.markdown.render", qos: .userInitiated)
    private let imageLoader = MarkdownImageLoader.shared

    func updateLayoutWidth(_ width: CGFloat) {
        let resolved = resolveLayoutWidth(width, textView: currentTextView)
        guard resolved > 1 else { return }
        guard abs(resolved - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = resolved
        updateAttachmentWidth()
        if let textView = currentTextView {
            invalidateLayout(for: textView)
        }
    }

    func update(
        textView: MarkdownPlatformTextView,
        markdown: String,
        colorScheme: ColorScheme,
        sizeCategory: ContentSizeCategory,
        force: Bool = false
    ) {
        currentTextView = textView
        let resolvedScheme = resolvedColorScheme(for: textView, fallback: colorScheme)
        let style = MarkdownStyle(colorScheme: resolvedScheme, sizeCategory: sizeCategory)
        let styleKey = style.cacheKey
        configure(textView: textView, style: style)
        if lastLayoutWidth <= 1 {
            let width = resolveLayoutWidth(textView.bounds.width, textView: textView)
            if width > 1 { lastLayoutWidth = width }
        }

        if !force, markdown == lastMarkdown && styleKey == lastStyleKey {
            return
        }

        if styleKey == lastStyleKey,
           attemptIncrementalAppend(to: textView, newMarkdown: markdown, style: style) {
            lastMarkdown = markdown
            return
        }

        renderMarkdown(markdown, style: style, styleKey: styleKey, textView: textView)
    }

    private func configure(textView: MarkdownPlatformTextView, style: MarkdownStyle) {
        #if os(iOS) || os(tvOS) || os(watchOS)
        textView.tintColor = style.linkColor
        #endif
        textView.linkTextAttributes = style.linkAttributes
    }

    private func attemptIncrementalAppend(
        to textView: MarkdownPlatformTextView,
        newMarkdown: String,
        style: MarkdownStyle
    ) -> Bool {
        guard !lastMarkdown.isEmpty, newMarkdown.hasPrefix(lastMarkdown) else { return false }
        let delta = String(newMarkdown.dropFirst(lastMarkdown.count))
        guard !delta.isEmpty else { return true }
        guard isSafePlainAppend(delta) else { return false }
        guard let storage = textStorage(for: textView), storage.length > 0 else { return false }

        let lastIndex = max(0, storage.length - 1)
        let lastAttributes = storage.attributes(at: lastIndex, effectiveRange: nil)
        guard attributesAreBase(lastAttributes, style: style) else { return false }

        var attrs = style.baseAttributes
        attrs[.paragraphStyle] = lastAttributes[.paragraphStyle] ?? style.paragraphStyle()
        let appended = NSAttributedString(string: delta, attributes: attrs)
        storage.append(appended)
        invalidateLayout(for: textView)
        updateAttachmentWidth()
        return true
    }

    private func renderMarkdown(
        _ markdown: String,
        style: MarkdownStyle,
        styleKey: String,
        textView: MarkdownPlatformTextView
    ) {
        currentRenderID &+= 1
        let renderID = currentRenderID
        let resolvedWidth = resolveLayoutWidth(textView.bounds.width, textView: textView)
        if resolvedWidth > 1 { lastLayoutWidth = resolvedWidth }
        let maxWidth = lastLayoutWidth > 1 ? lastLayoutWidth : nil

        if let cached = MarkdownRenderCache.shared.attributedString(
            for: markdown,
            styleKey: styleKey
        ) {
            applyRender(
                MarkdownRenderResult(attributedString: cached, attachments: []),
                to: textView,
                markdown: markdown,
                styleKey: styleKey,
                renderID: renderID
            )
            return
        }

#if os(macOS)
        Task { @MainActor [weak self] in
            guard let self, self.currentRenderID == renderID else { return }
            let renderer = MarkdownAttributedStringRenderer(style: style, maxImageWidth: maxWidth)
            let result = renderer.render(markdown: markdown)
            if result.attachments.isEmpty {
                MarkdownRenderCache.shared.store(
                    result.attributedString,
                    markdown: markdown,
                    styleKey: styleKey
                )
            }
            guard let textView = self.currentTextView else { return }
            self.applyRender(
                result,
                to: textView,
                markdown: markdown,
                styleKey: styleKey,
                renderID: renderID
            )
        }
#else
        renderQueue.async { [weak self] in
            let renderer = MarkdownAttributedStringRenderer(style: style, maxImageWidth: maxWidth)
            let result = renderer.render(markdown: markdown)
            if result.attachments.isEmpty {
                MarkdownRenderCache.shared.store(
                    result.attributedString,
                    markdown: markdown,
                    styleKey: styleKey
                )
            }
            Task { @MainActor [weak self] in
                guard let self, self.currentRenderID == renderID else { return }
                guard let textView = self.currentTextView else { return }
                self.applyRender(
                    result,
                    to: textView,
                    markdown: markdown,
                    styleKey: styleKey,
                    renderID: renderID
                )
            }
        }
#endif
    }

    private func applyRender(
        _ result: MarkdownRenderResult,
        to textView: MarkdownPlatformTextView,
        markdown: String,
        styleKey: String,
        renderID: UInt64
    ) {
        if let storage = textStorage(for: textView) {
            storage.setAttributedString(result.attributedString)
        }
        attachments = result.attachments
        updateAttachmentWidth()
        queueImageLoads(attachments: result.attachments, renderID: renderID)
        lastMarkdown = markdown
        lastStyleKey = styleKey
        invalidateLayout(for: textView)
    }

    private func queueImageLoads(
        attachments: [MarkdownAttachment],
        renderID: UInt64
    ) {
        guard !attachments.isEmpty else { return }
        for attachment in attachments {
            guard let imageAttachment = attachment as? MarkdownImageAttachment else { continue }
            imageLoader.loadImage(source: imageAttachment.source) { [weak self] image in
                guard let self, self.currentRenderID == renderID else { return }
                guard let textView = self.currentTextView else { return }
                imageAttachment.setImage(image)
                self.updateAttachmentWidth()
                self.invalidateLayout(for: textView)
            }
        }
    }

    private func updateAttachmentWidth() {
        let maxWidth = max(0, lastLayoutWidth - 4)
        guard maxWidth > 0 else { return }
        #if os(macOS)
        let lineFrag = CGRect(x: 0, y: 0, width: maxWidth, height: 0)
        #endif
        for attachment in attachments {
            attachment.maxWidth = maxWidth
            #if os(macOS)
            if !attachment.allowsTextAttachmentView, attachment.image == nil {
                // AppKit layout doesn't consult attachmentBounds for sizing, so prime the image explicitly.
                _ = attachment.attachmentBounds(
                    for: nil,
                    proposedLineFragment: lineFrag,
                    glyphPosition: .zero,
                    characterIndex: 0
                )
            }
            #endif
        }
    }

    private func invalidateLayout(for textView: MarkdownPlatformTextView) {
        #if os(iOS) || os(tvOS) || os(watchOS)
        if #available(iOS 16.0, tvOS 16.0, *) {
            if let textLayoutManager = textView.textLayoutManager,
               let documentRange = textLayoutManager.textContentManager?.documentRange {
                textLayoutManager.invalidateLayout(for: documentRange)
            }
        } else {
            let layoutManager = textView.layoutManager
            let storage = textView.textStorage
            let range = NSRange(location: 0, length: storage.length)
            layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: range)
        }
        textView.setNeedsLayout()
        textView.invalidateIntrinsicContentSize()
        #elseif os(macOS)
        if let layoutManager = textView.layoutManager, let storage = textView.textStorage {
            let range = NSRange(location: 0, length: storage.length)
            layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: range)
        }
        textView.needsLayout = true
        textView.invalidateIntrinsicContentSize()
        #endif
    }

    private func isSafePlainAppend(_ delta: String) -> Bool {
        if delta.contains("\n") { return false }
        let forbidden = CharacterSet(charactersIn: "*_`[]()!#>|~")
        return delta.rangeOfCharacter(from: forbidden) == nil
    }

    private func attributesAreBase(
        _ attributes: [NSAttributedString.Key: Any],
        style: MarkdownStyle
    ) -> Bool {
        guard let font = attributes[.font] as? MarkdownPlatformFont else { return false }
        guard let color = attributes[.foregroundColor] as? MarkdownPlatformColor else { return false }
        if !fontsEqual(font, style.baseFont) { return false }
        if !colorsEqual(color, style.baseColor) { return false }
        if attributes[.link] != nil { return false }
        if attributes[.backgroundColor] != nil { return false }
        if attributes[.attachment] != nil { return false }
        return true
    }

    private func textStorage(for textView: MarkdownPlatformTextView) -> NSTextStorage? {
        #if os(iOS) || os(tvOS) || os(watchOS)
        return textView.textStorage
        #elseif os(macOS)
        return textView.textStorage
        #endif
    }

    private func fontsEqual(_ lhs: MarkdownPlatformFont, _ rhs: MarkdownPlatformFont) -> Bool {
        lhs.fontName == rhs.fontName && abs(lhs.pointSize - rhs.pointSize) < 0.5
    }

    private func colorsEqual(_ lhs: MarkdownPlatformColor, _ rhs: MarkdownPlatformColor) -> Bool {
        lhs.isEqual(rhs)
    }

    private func resolveLayoutWidth(
        _ width: CGFloat,
        textView: MarkdownPlatformTextView?
    ) -> CGFloat {
        if width > 1 { return width }
        guard let textView else { return width }
        #if os(macOS)
        if let containerWidth = textView.textContainer?.containerSize.width, containerWidth > 1 {
            let inset = textView.textContainerInset.width * 2
            return containerWidth + inset
        }
        if let superWidth = textView.superview?.bounds.width, superWidth > 1 {
            return superWidth
        }
        #endif
        return 320
    }

    private func resolvedColorScheme(
        for textView: MarkdownPlatformTextView,
        fallback: ColorScheme
    ) -> ColorScheme {
        #if os(iOS) || os(tvOS) || os(watchOS)
        switch textView.traitCollection.userInterfaceStyle {
        case .dark:
            return .dark
        case .light:
            return .light
        default:
            return fallback
        }
        #else
        return fallback
        #endif
    }
}

