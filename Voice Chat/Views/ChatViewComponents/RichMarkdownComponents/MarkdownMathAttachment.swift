//
//  MarkdownMathAttachment.swift
//  Voice Chat
//

@preconcurrency import Foundation

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

final class MarkdownMathAttachment: MarkdownAttachment, @unchecked Sendable {
    let source: String
    let latex: String
    let displayMode: Bool
    let style: MarkdownMathStyle
    let renderOutput: MarkdownMathRenderOutput

    private var cachedAvailableWidth: CGFloat = 0
    private var cachedBounds: CGRect = .zero
    private var cachedImage: MarkdownPlatformImage?
    private var hasAppliedAttachmentImage = false

    private static let viewProviderFileType = MarkdownAttachmentFileTypes.viewBacked

    override var plainText: String { source }

    var accessibilityText: String {
        let raw = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return displayMode ? "Displayed math" : "Inline math"
        }
        let kind = displayMode ? "Displayed math" : "Inline math"
        return "\(kind): \(raw)"
    }

    private func configureTextAttachmentViewIfAvailable() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        if #available(iOS 15.0, tvOS 15.0, *) {
            MarkdownAttachmentViewProviderRegistry.registerIfNeeded()
            allowsTextAttachmentView = true
            fileType = Self.viewProviderFileType
            if contents == nil { contents = Data() }
            return
        }
        #elseif os(macOS)
        if #available(macOS 12.0, *) {
            MarkdownAttachmentViewProviderRegistry.registerIfNeeded()
            allowsTextAttachmentView = true
            fileType = Self.viewProviderFileType
            if contents == nil { contents = Data() }
            return
        }
        #endif
        allowsTextAttachmentView = false
        fileType = nil
        if contents != nil { contents = nil }
    }

    init(segment: MarkdownMathSegment, style: MarkdownMathStyle, displayMode: Bool, maxWidth: CGFloat) {
        self.source = segment.source
        self.latex = segment.latex
        self.displayMode = displayMode
        self.style = style
        self.renderOutput = MarkdownMathTypesetter.render(
            latex: segment.latex,
            displayMode: displayMode,
            style: style
        )
        super.init(data: nil, ofType: nil)
        self.maxWidth = maxWidth
        configureTextAttachmentViewIfAvailable()
    }

    required init?(coder: NSCoder) {
        self.source = ""
        self.latex = ""
        self.displayMode = false
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let defaultColor = MarkdownPlatformColor.label
        #elseif os(macOS)
        let defaultColor = MarkdownPlatformColor.labelColor
        #endif
        self.style = MarkdownMathStyle(
            baseFont: MarkdownPlatformFont.systemFont(ofSize: MarkdownPlatformFont.systemFontSize),
            textColor: defaultColor
        )
        self.renderOutput = MarkdownMathTypesetter.render(
            latex: "",
            displayMode: false,
            style: style
        )
        super.init(coder: coder)
        configureTextAttachmentViewIfAvailable()
    }

    override func widthDidChange() {
        cachedAvailableWidth = 0
        cachedBounds = .zero
        cachedImage = nil
        updateAttachmentImage(nil)
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let available = resolvedAvailableWidth(
            containerWidth: effectiveContainerWidth(textContainer),
            proposedLineFragmentWidth: lineFrag.width
        )
        return resolvedBounds(availableWidth: available)
    }

    func measuredSize(availableWidth: CGFloat) -> CGSize {
        resolvedBounds(availableWidth: availableWidth).size
    }

    func layoutBounds(availableWidth: CGFloat) -> CGRect {
        resolvedBounds(availableWidth: availableWidth)
    }

    func resolvedAvailableWidth(
        containerWidth: CGFloat?,
        proposedLineFragmentWidth lineFragWidth: CGFloat
    ) -> CGFloat {
        if displayMode {
            return attachmentAvailableWidth(
                maxWidth: maxWidth,
                lineFragWidth: containerWidth ?? lineFragWidth
            )
        }

        // Inline attachments should size against the container width so they can wrap
        // to the next line instead of shrinking to the current line's residual width.
        if let containerWidth, containerWidth > 1 {
            return attachmentAvailableWidth(maxWidth: maxWidth, lineFragWidth: containerWidth)
        }
        if maxWidth > 1 { return maxWidth }
        if lineFragWidth > 1 { return lineFragWidth }
        return 320
    }

    func draw(in context: CGContext, bounds: CGRect) {
        renderOutput.draw(in: context, bounds: bounds)
    }

    private func resolvedBounds(availableWidth: CGFloat) -> CGRect {
        let needsFallbackImage = !allowsTextAttachmentView
        if abs(cachedAvailableWidth - availableWidth) > 0.5 ||
            cachedBounds == .zero ||
            (needsFallbackImage && cachedImage == nil) {
            let bounds = renderOutput.attachmentBounds(availableWidth: availableWidth)
            cachedAvailableWidth = availableWidth
            cachedBounds = bounds
            if needsFallbackImage {
                cachedImage = renderImage(size: bounds.size)
                updateAttachmentImage(cachedImage)
            } else if cachedImage != nil || hasInstalledAttachmentImage {
                cachedImage = nil
                updateAttachmentImage(nil)
            }
        }
        return cachedBounds
    }

    private func effectiveContainerWidth(_ textContainer: NSTextContainer?) -> CGFloat? {
        guard let textContainer else { return nil }
        let width = textContainer.size.width
        guard width.isFinite, width > 1 else { return nil }
        return width
    }

    private func renderImage(size: CGSize) -> MarkdownPlatformImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            renderOutput.draw(in: context.cgContext, bounds: CGRect(origin: .zero, size: size))
        }
        #elseif os(macOS)
        return renderMarkdownImage(size: size) { context in
            renderOutput.draw(in: context, bounds: CGRect(origin: .zero, size: size))
        }
        #endif
    }

    private func updateAttachmentImage(_ image: MarkdownPlatformImage?) {
        #if os(macOS)
        hasAppliedAttachmentImage = image != nil
        performSelector(onMainThread: #selector(applyAttachmentImageOnMainThread(_:)), with: image, waitUntilDone: true)
        #else
        hasAppliedAttachmentImage = image != nil
        self.image = image
        #endif
    }

    private var hasInstalledAttachmentImage: Bool {
        #if os(macOS)
        hasAppliedAttachmentImage
        #else
        hasAppliedAttachmentImage
        #endif
    }

    #if os(macOS)
    @objc
    private func applyAttachmentImageOnMainThread(_ image: MarkdownPlatformImage?) {
        setValue(image, forKey: "image")
    }
    #endif
}
