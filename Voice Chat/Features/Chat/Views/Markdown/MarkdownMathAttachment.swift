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

    private let prefersViewBackedRendering: Bool
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
        guard prefersViewBackedRendering else {
            allowsTextAttachmentView = false
            fileType = nil
            contents = nil
            return
        }
        if configureViewBackedTextAttachment(fileType: Self.viewProviderFileType) {
            return
        }
    }

    init(segment: MarkdownMathSegment, style: MarkdownMathStyle, displayMode: Bool, maxWidth: CGFloat) {
        self.source = segment.source
        self.latex = segment.latex
        self.displayMode = displayMode
        self.style = style
        self.prefersViewBackedRendering = true
        self.renderOutput = MarkdownMathTypesetter.render(
            latex: segment.latex,
            displayMode: displayMode,
            style: style
        )
        super.init(data: nil, ofType: nil)
        self.maxWidth = maxWidth
        configureTextAttachmentViewIfAvailable()
    }

    private init(
        source: String,
        latex: String,
        displayMode: Bool,
        style: MarkdownMathStyle,
        renderOutput: MarkdownMathRenderOutput,
        maxWidth: CGFloat,
        cachedAvailableWidth: CGFloat,
        cachedBounds: CGRect,
        cachedImage: MarkdownPlatformImage?,
        hasAppliedAttachmentImage: Bool,
        prefersViewBackedRendering: Bool = true
    ) {
        self.source = source
        self.latex = latex
        self.displayMode = displayMode
        self.style = style
        self.renderOutput = renderOutput
        self.prefersViewBackedRendering = prefersViewBackedRendering
        self.cachedAvailableWidth = cachedAvailableWidth
        self.cachedBounds = cachedBounds
        self.cachedImage = cachedImage
        self.hasAppliedAttachmentImage = hasAppliedAttachmentImage
        super.init(data: nil, ofType: nil)
        self.maxWidth = maxWidth
        configureTextAttachmentViewIfAvailable()
        self.image = cachedImage
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
        self.prefersViewBackedRendering = true
        self.renderOutput = MarkdownMathTypesetter.render(
            latex: "",
            displayMode: false,
            style: style
        )
        super.init(coder: coder)
        configureTextAttachmentViewIfAvailable()
    }

    func copiedForStreamingTableCellReuse() -> MarkdownMathAttachment {
        let copy = MarkdownMathAttachment(
            source: source,
            latex: latex,
            displayMode: displayMode,
            style: style,
            renderOutput: renderOutput,
            maxWidth: maxWidth,
            cachedAvailableWidth: cachedAvailableWidth,
            cachedBounds: cachedBounds,
            cachedImage: cachedImage,
            hasAppliedAttachmentImage: hasAppliedAttachmentImage,
            prefersViewBackedRendering: prefersViewBackedRendering
        )
        copy.contentVersion = contentVersion
        return copy
    }

    #if os(macOS)
    var prefersViewBackedTextAttachmentRendering: Bool {
        prefersViewBackedRendering
    }

    func copiedForImageBackedTableCellRendering(availableWidth: CGFloat) -> MarkdownMathAttachment {
        let copy = MarkdownMathAttachment(
            source: source,
            latex: latex,
            displayMode: displayMode,
            style: style,
            renderOutput: renderOutput,
            maxWidth: maxWidth,
            cachedAvailableWidth: 0,
            cachedBounds: .zero,
            cachedImage: nil,
            hasAppliedAttachmentImage: false,
            prefersViewBackedRendering: false
        )
        copy.contentVersion = contentVersion
        copy.prepareImageBackedRendering(availableWidth: availableWidth)
        return copy
    }

    func prepareImageBackedRendering(availableWidth: CGFloat) {
        let available = resolvedAvailableWidth(
            containerWidth: availableWidth,
            proposedLineFragmentWidth: availableWidth
        )
        _ = resolvedBounds(availableWidth: available)
    }
    #endif

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
        guard Self.isSafeImageSize(size) else { return nil }
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        guard Self.isSafeImageSize(size, scale: format.scale) else { return nil }
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

    private static func isSafeImageSize(_ size: CGSize, scale: CGFloat = 1) -> Bool {
        guard size.width.isFinite,
              size.height.isFinite,
              scale.isFinite,
              size.width > 0,
              size.height > 0,
              scale > 0,
              size.width <= MarkdownMathRenderLimits.maxAttachmentDimension,
              size.height <= MarkdownMathRenderLimits.maxAttachmentDimension else {
            return false
        }
        let pixelWidth = ceil(size.width * scale)
        let pixelHeight = ceil(size.height * scale)
        let pixelCount = pixelWidth * pixelHeight
        return pixelWidth.isFinite &&
            pixelHeight.isFinite &&
            pixelCount.isFinite &&
            pixelCount <= 16_777_216
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
    @MainActor
    @objc
    private func applyAttachmentImageOnMainThread(_ image: MarkdownPlatformImage?) {
        setAttachmentImage(image)
    }
    #endif
}
