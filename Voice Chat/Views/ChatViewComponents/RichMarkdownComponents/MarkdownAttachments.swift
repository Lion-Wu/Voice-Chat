//
//  MarkdownAttachments.swift
//  Voice Chat
//

@preconcurrency import Foundation

#if os(iOS) || os(tvOS) || os(watchOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

final class MarkdownImageAttachment: MarkdownAttachment, @unchecked Sendable {
    let source: String
    let altText: String
    private let placeholderSize = CGSize(width: 160, height: 120)
    private var cachedImage: MarkdownPlatformImage?

    override var plainText: String {
        let trimmed = altText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? source : trimmed
    }

    init(source: String, altText: String, maxWidth: CGFloat) {
        self.source = source
        self.altText = altText
        super.init(data: nil, ofType: nil)
        self.maxWidth = maxWidth
    }

    required init?(coder: NSCoder) {
        self.source = ""
        self.altText = ""
        super.init(coder: coder)
        self.maxWidth = 240
    }

    #if os(macOS)
    @MainActor
    #endif
    func setImage(_ image: MarkdownPlatformImage?) {
        cachedImage = image
        setAttachmentImage(image)
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let available = attachmentAvailableWidth(maxWidth: maxWidth, lineFragWidth: lineFrag.width)
        let size = cachedImage?.size ?? placeholderSize
        guard size.width > 0, size.height > 0 else {
            return CGRect(x: 0, y: 0, width: available, height: placeholderSize.height)
        }
        let scale = min(1, available / size.width)
        return CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
    }
}

final class MarkdownQuoteAttachment: MarkdownAttachment, @unchecked Sendable {
    let content: NSAttributedString
    let style: MarkdownQuoteStyle
    private var cachedImage: MarkdownPlatformImage?
    private var cachedSize: CGSize = .zero
    private var cachedWidth: CGFloat = 0
    private var lastLayout: QuoteLayout?

    override var plainText: String { extractPlainText(from: content) }

    private static let viewProviderFileType = MarkdownAttachmentFileTypes.viewBacked

    private func configureTextAttachmentViewIfAvailable() {
        #if os(iOS) || os(tvOS)
        if #available(iOS 15.0, tvOS 15.0, *) {
            MarkdownAttachmentViewProviderRegistry.registerIfNeeded()
            allowsTextAttachmentView = true
            fileType = Self.viewProviderFileType
            if contents == nil { contents = Data() }
        }
        #elseif os(macOS)
        if #available(macOS 12.0, *) {
            MarkdownAttachmentViewProviderRegistry.registerIfNeeded()
            allowsTextAttachmentView = true
            fileType = Self.viewProviderFileType
            if contents == nil { contents = Data() }
        }
        #endif
    }

    #if os(macOS)
    @MainActor
    #endif
    init(content: NSAttributedString, style: MarkdownQuoteStyle, maxWidth: CGFloat) {
        self.content = content
        self.style = style
        super.init(data: nil, ofType: nil)
        self.maxWidth = maxWidth
        #if os(iOS) || os(tvOS) || os(macOS)
        configureTextAttachmentViewIfAvailable()
        #endif
    }

    required init?(coder: NSCoder) {
        self.content = NSAttributedString(string: "")
        self.style = MarkdownQuoteStyle(
            textColor: MarkdownPlatformColor.markdownHex(0x24292f),
            borderColor: MarkdownPlatformColor.markdownHex(0xd8dbe0),
            borderWidth: 3,
            padding: CGSize(width: 12, height: 6)
        )
        super.init(coder: coder)
        #if os(iOS) || os(tvOS) || os(macOS)
        configureTextAttachmentViewIfAvailable()
        #endif
    }

    override func widthDidChange() {
        cachedImage = nil
        cachedSize = .zero
        cachedWidth = 0
        lastLayout = nil
        #if !os(macOS)
        setAttachmentImage(nil)
        #endif
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let available = attachmentAvailableWidth(maxWidth: maxWidth, lineFragWidth: lineFrag.width)
        let size = renderIfNeeded(maxWidth: available)
        return CGRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    private func renderIfNeeded(maxWidth: CGFloat) -> CGSize {
        if abs(cachedWidth - maxWidth) > 0.5 || lastLayout == nil || (!allowsTextAttachmentView && cachedImage == nil) {
            let layout = layoutQuote(maxWidth: maxWidth)
            cachedSize = layout.size
            cachedWidth = maxWidth
            lastLayout = layout
            if !allowsTextAttachmentView {
                cachedImage = drawQuote(layout: layout)
                #if !os(macOS)
                setAttachmentImage(cachedImage)
                #endif
            }
        }
        return cachedSize
    }

    private struct QuoteLayout {
        let size: CGSize
        let textRect: CGRect
    }

    private func layoutQuote(maxWidth: CGFloat) -> QuoteLayout {
        let borderWidth = max(1, style.borderWidth)
        let padding = style.padding
        let textInsetX = borderWidth + padding.width
        let textWidth = max(1, maxWidth - textInsetX - padding.width)
        let textSize = measureAttributed(content, width: textWidth)
        let height = textSize.height + padding.height * 2
        let textRect = CGRect(
            x: textInsetX,
            y: padding.height,
            width: textWidth,
            height: textSize.height
        )
        return QuoteLayout(size: CGSize(width: maxWidth, height: height), textRect: textRect)
    }

    private func drawQuote(layout: QuoteLayout) -> MarkdownPlatformImage? {
        let size = layout.size
        guard size.width > 0, size.height > 0 else { return nil }
        #if os(iOS) || os(tvOS) || os(watchOS)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            drawQuote(in: context.cgContext, layout: layout)
        }
        #elseif os(macOS)
        return renderMarkdownImage(size: size) { context in
            drawQuote(in: context, layout: layout)
        }
        #endif
    }

    private func drawQuote(in context: CGContext, layout: QuoteLayout) {
        let borderWidth = max(1, style.borderWidth)
        let lineRect = CGRect(x: 0, y: 0, width: borderWidth, height: layout.size.height)
        context.setFillColor(style.borderColor.cgColor)
        context.fill(lineRect)

        content.draw(
            with: layout.textRect.integral,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
    }

    private func measureAttributed(_ text: NSAttributedString, width: CGFloat) -> CGSize {
        measureAttributedText(text, width: width)
    }
}

final class MarkdownCodeBlockAttachment: MarkdownAttachment, @unchecked Sendable {
    private struct Layout {
        let size: CGSize
        let contentWidth: CGFloat
        let headerRect: CGRect
        let codeRect: CGRect
        let languageRect: CGRect
        let copyButtonRect: CGRect
        let copyIconRect: CGRect
        let copyTextRect: CGRect
    }

    private(set) var code: String
    override var plainText: String { code }
    override var supportsHorizontalScroll: Bool { true }
    let languageLabel: String
    let copyLabel: String
    let style: MarkdownCodeBlockStyle

    private struct EstimatedCodeMetrics {
        var lineCount: Int
        var currentLineUnits: Int
        var maxLineUnits: Int
    }

    private enum EstimatedSizing {
        static let tabWidthUnits: Int = 4
        static let nonASCIIWidthUnits: Int = 2
    }

    private let estimatedCharWidth: CGFloat
    private let estimatedLineHeight: CGFloat
    private let estimatedLineSpacing: CGFloat
    private var estimatedMetrics: EstimatedCodeMetrics

    private let codeAttributes: [NSAttributedString.Key: Any]
    private let codeAttributedStorage: NSMutableAttributedString
    var codeAttributed: NSAttributedString { codeAttributedStorage }
    var estimatedCodeTextSize: CGSize {
        let width = CGFloat(estimatedMetrics.maxLineUnits) * estimatedCharWidth
        let lines = max(1, estimatedMetrics.lineCount)
        let height = CGFloat(lines) * estimatedLineHeight + CGFloat(max(0, lines - 1)) * estimatedLineSpacing
        return CGSize(width: ceil(width), height: ceil(height))
    }
    private var horizontalScrollOffset: CGFloat = 0
    private var horizontalScrollRange: CGFloat = 0
    private var cachedImage: MarkdownPlatformImage?
    private var cachedSize: CGSize = .zero
    private var cachedWidth: CGFloat = 0
    private var lastLayout: Layout?

    #if os(macOS)
    weak var hostedView: MarkdownCodeBlockView?
    #endif

    private static let viewProviderFileType = MarkdownAttachmentFileTypes.viewBacked

    private func configureTextAttachmentViewIfAvailable() {
        #if os(iOS) || os(tvOS)
        if #available(iOS 15.0, tvOS 15.0, *) {
            MarkdownAttachmentViewProviderRegistry.registerIfNeeded()
            allowsTextAttachmentView = true
            fileType = Self.viewProviderFileType
            if contents == nil { contents = Data() }
        }
        #elseif os(macOS)
        if #available(macOS 12.0, *) {
            MarkdownAttachmentViewProviderRegistry.registerIfNeeded()
            allowsTextAttachmentView = true
            fileType = Self.viewProviderFileType
            if contents == nil { contents = Data() }
        }
        #endif
    }

    #if os(macOS)
    @MainActor
    #endif
    init(
        code: String,
        languageLabel: String,
        copyLabel: String,
        style: MarkdownCodeBlockStyle,
        maxWidth: CGFloat
    ) {
        self.code = code
        self.languageLabel = languageLabel
        self.copyLabel = copyLabel
        self.style = style
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        paragraph.lineSpacing = 2
        let fontMeasurementAttributes: [NSAttributedString.Key: Any] = [.font: style.codeFont]
        let measuredCharWidth = ("0" as NSString).size(withAttributes: fontMeasurementAttributes).width
        self.estimatedCharWidth = max(1, measuredCharWidth)
        #if os(iOS) || os(tvOS) || os(watchOS)
        self.estimatedLineHeight = style.codeFont.lineHeight
        #elseif os(macOS)
        self.estimatedLineHeight = NSLayoutManager().defaultLineHeight(for: style.codeFont)
        #endif
        self.estimatedLineSpacing = paragraph.lineSpacing
        self.estimatedMetrics = Self.estimateMetrics(for: code)
        self.codeAttributes = [
            .font: style.codeFont,
            .foregroundColor: style.textColor,
            .paragraphStyle: paragraph
        ]
        self.codeAttributedStorage = NSMutableAttributedString(string: code, attributes: self.codeAttributes)
        super.init(data: nil, ofType: nil)
        self.maxWidth = maxWidth
        #if os(iOS) || os(tvOS) || os(macOS)
        configureTextAttachmentViewIfAvailable()
        #endif
    }

    required init?(coder: NSCoder) {
        self.code = ""
        self.languageLabel = "CODE"
        self.copyLabel = "Copy"
        self.style = MarkdownCodeBlockStyle(
            codeFont: MarkdownPlatformFont.monospacedSystemFont(ofSize: MarkdownPlatformFont.systemFontSize, weight: .regular),
            headerFont: MarkdownPlatformFont.systemFont(ofSize: MarkdownPlatformFont.systemFontSize, weight: .semibold),
            textColor: MarkdownPlatformColor.markdownHex(0x24292f),
            headerTextColor: MarkdownPlatformColor.markdownHex(0x57606a),
            backgroundColor: MarkdownPlatformColor.markdownHex(0xf6f8fa),
            headerBackground: MarkdownPlatformColor.markdownHex(0xf6f8fa),
            borderColor: MarkdownPlatformColor.markdownHex(0xd0d7de),
            copyTextColor: MarkdownPlatformColor.markdownHex(0x8c959f),
            copyBackground: MarkdownPlatformColor.clear,
            borderWidth: 1,
            cornerRadius: 10,
            codePadding: CGSize(width: 14, height: 12),
            headerPadding: CGSize(width: 12, height: 6)
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        paragraph.lineSpacing = 2
        let fontMeasurementAttributes: [NSAttributedString.Key: Any] = [.font: style.codeFont]
        let measuredCharWidth = ("0" as NSString).size(withAttributes: fontMeasurementAttributes).width
        self.estimatedCharWidth = max(1, measuredCharWidth)
        #if os(iOS) || os(tvOS) || os(watchOS)
        self.estimatedLineHeight = style.codeFont.lineHeight
        #elseif os(macOS)
        self.estimatedLineHeight = NSLayoutManager().defaultLineHeight(for: style.codeFont)
        #endif
        self.estimatedLineSpacing = paragraph.lineSpacing
        self.estimatedMetrics = EstimatedCodeMetrics(lineCount: 1, currentLineUnits: 0, maxLineUnits: 0)
        self.codeAttributes = [
            .font: style.codeFont,
            .foregroundColor: style.textColor,
            .paragraphStyle: paragraph
        ]
        self.codeAttributedStorage = NSMutableAttributedString(string: "", attributes: self.codeAttributes)
        super.init(coder: coder)
        #if os(iOS) || os(tvOS) || os(macOS)
        configureTextAttachmentViewIfAvailable()
        #endif
    }

    #if os(macOS)
    @MainActor
    #endif
    func appendCode(_ delta: String) {
        guard !delta.isEmpty else { return }
        code.append(contentsOf: delta)
        codeAttributedStorage.append(NSAttributedString(string: delta, attributes: codeAttributes))
        Self.ingest(delta: delta, into: &estimatedMetrics)
        contentVersion &+= 1
        invalidateForContentChange()
        #if os(macOS)
        hostedView?.applyUpdate(from: self)
        #endif
    }

    #if os(macOS)
    @MainActor
    #endif
    func replaceCode(_ nextCode: String) {
        guard nextCode != code else { return }
        code = nextCode
        codeAttributedStorage.setAttributedString(NSAttributedString(string: nextCode, attributes: codeAttributes))
        estimatedMetrics = Self.estimateMetrics(for: nextCode)
        contentVersion &+= 1
        invalidateForContentChange()
        #if os(macOS)
        hostedView?.applyUpdate(from: self)
        #endif
    }

    func hostedHorizontalOffset() -> CGFloat {
        horizontalScrollOffset
    }

    func setHostedHorizontalOffset(_ offset: CGFloat) {
        horizontalScrollOffset = max(0, offset)
    }

    override func widthDidChange() {
        cachedImage = nil
        cachedSize = .zero
        cachedWidth = 0
        lastLayout = nil
        horizontalScrollRange = 0
        #if !os(macOS)
        setAttachmentImage(nil)
        #endif
    }

    private func invalidateForContentChange() {
        cachedImage = nil
        cachedSize = .zero
        cachedWidth = 0
        lastLayout = nil
        horizontalScrollRange = 0
        #if !os(macOS)
        setAttachmentImage(nil)
        #endif
    }

    override func scrollHorizontally(by delta: CGFloat) -> Bool {
        guard !allowsTextAttachmentView else { return false }
        guard horizontalScrollRange > 0 else { return false }
        let nextOffset = min(max(0, horizontalScrollOffset + delta), horizontalScrollRange)
        if abs(nextOffset - horizontalScrollOffset) < 0.5 { return false }
        horizontalScrollOffset = nextOffset
        if lastLayout == nil {
            let fallbackWidth = max(maxWidth, cachedWidth)
            if fallbackWidth > 1 {
                _ = renderIfNeeded(maxWidth: fallbackWidth)
            }
        }
        guard let layout = lastLayout else { return false }
        cachedImage = drawBlock(layout: layout)
        #if !os(macOS)
        setAttachmentImage(cachedImage)
        #endif
        return true
    }

    func isCopyButtonHit(at point: CGPoint) -> Bool {
        guard !allowsTextAttachmentView else { return false }
        guard let layout = lastLayout else { return false }
        return layout.copyButtonRect.contains(point)
    }

    func copyToPasteboard() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        UIPasteboard.general.string = code
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        #endif
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let available = attachmentAvailableWidth(maxWidth: maxWidth, lineFragWidth: lineFrag.width)
        let size = renderIfNeeded(maxWidth: available)
        return CGRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    private func renderIfNeeded(maxWidth: CGFloat) -> CGSize {
        if abs(cachedWidth - maxWidth) > 0.5 || lastLayout == nil || (!allowsTextAttachmentView && cachedImage == nil) {
            let layout = layoutBlock(maxWidth: maxWidth)
            cachedSize = layout.size
            cachedWidth = maxWidth
            lastLayout = layout
            if !allowsTextAttachmentView {
                let viewportWidth = layout.codeRect.width + style.codePadding.width * 2
                let scrollRange = max(0, layout.contentWidth - viewportWidth)
                horizontalScrollRange = scrollRange
                if horizontalScrollOffset > scrollRange {
                    horizontalScrollOffset = scrollRange
                }
                cachedImage = drawBlock(layout: layout)
                #if !os(macOS)
                setAttachmentImage(cachedImage)
                #endif
            } else {
                horizontalScrollOffset = 0
                horizontalScrollRange = 0
            }
        }
        return cachedSize
    }

    private func layoutBlock(maxWidth: CGFloat) -> Layout {
        let border = max(1, style.borderWidth)
        let headerPadding = style.headerPadding
        let codePadding = style.codePadding
        let viewportContentWidth = max(1, maxWidth - border * 2)

        let headerLineHeight = lineHeight(for: style.headerFont)
        let headerHeight = max(24, headerLineHeight + headerPadding.height * 2)
        let headerRect = CGRect(x: border, y: border, width: viewportContentWidth, height: headerHeight)

        let copyTextSize = measureText(copyLabel, font: style.headerFont)
        let copyButtonHeight = max(18, headerLineHeight + headerPadding.height)
        let iconSize = max(10, min(14, copyButtonHeight - 6))
        let iconSpacing: CGFloat = 6
        let idealCopyWidth = copyTextSize.width + headerPadding.width * 2
        let availableCopyWidth = max(0, viewportContentWidth - headerPadding.width)
        let copyButtonWidth = min(idealCopyWidth, availableCopyWidth)
        let copyButtonY = border + (headerHeight - copyButtonHeight) / 2
        let copyButtonX = border + viewportContentWidth - copyButtonWidth - headerPadding.width
        let copyButtonRect = CGRect(
            x: max(border, copyButtonX),
            y: copyButtonY,
            width: min(copyButtonWidth, availableCopyWidth),
            height: copyButtonHeight
        )
        let iconFits = copyButtonRect.width >= copyTextSize.width + iconSize + iconSpacing
        let copyIconRect: CGRect
        let copyTextRect: CGRect
        if iconFits {
            let iconX = copyButtonRect.minX + headerPadding.width * 0.6
            let iconY = copyButtonRect.minY + (copyButtonRect.height - iconSize) / 2
            copyIconRect = CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
            let textX = copyIconRect.maxX + iconSpacing
            copyTextRect = CGRect(
                x: textX,
                y: copyButtonRect.minY + max(0, (copyButtonRect.height - copyTextSize.height) / 2),
                width: min(copyTextSize.width, copyButtonRect.maxX - textX - headerPadding.width * 0.4),
                height: min(copyTextSize.height, copyButtonRect.height)
            )
        } else {
            copyIconRect = .zero
            copyTextRect = CGRect(
                x: copyButtonRect.minX + max(0, (copyButtonRect.width - copyTextSize.width) / 2),
                y: copyButtonRect.minY + max(0, (copyButtonRect.height - copyTextSize.height) / 2),
                width: min(copyTextSize.width, copyButtonRect.width),
                height: min(copyTextSize.height, copyButtonRect.height)
            )
        }

        let languageStartX = border + headerPadding.width
        let languageWidth = max(0, copyButtonRect.minX - languageStartX - headerPadding.width)
        let languageRect = CGRect(
            x: languageStartX,
            y: border + (headerHeight - headerLineHeight) / 2,
            width: languageWidth,
            height: headerLineHeight
        )

        let codeTextWidth = max(1, viewportContentWidth - codePadding.width * 2)
        let codeTextSize = estimatedCodeTextSize
        let contentWidth = max(viewportContentWidth, codeTextSize.width + codePadding.width * 2)
        let codeHeight = max(codeTextSize.height, lineHeight(for: style.codeFont))
        let codeRect = CGRect(
            x: border + codePadding.width,
            y: border + headerHeight + codePadding.height,
            width: codeTextWidth,
            height: codeHeight
        )

        let totalHeight = border * 2 + headerHeight + codePadding.height * 2 + codeHeight
        return Layout(
            size: CGSize(width: maxWidth, height: totalHeight),
            contentWidth: contentWidth,
            headerRect: headerRect,
            codeRect: codeRect,
            languageRect: languageRect,
            copyButtonRect: copyButtonRect,
            copyIconRect: copyIconRect,
            copyTextRect: copyTextRect
        )
    }

    private func drawBlock(layout: Layout) -> MarkdownPlatformImage? {
        let size = layout.size
        guard size.width > 0, size.height > 0 else { return nil }
        #if os(iOS) || os(tvOS) || os(watchOS)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            drawBlock(in: context.cgContext, layout: layout)
        }
        #elseif os(macOS)
        return renderMarkdownImage(size: size) { context in
            drawBlock(in: context, layout: layout)
        }
        #endif
    }

    private func drawBlock(in context: CGContext, layout: Layout) {
        let rect = CGRect(origin: .zero, size: layout.size)
        let borderInset = max(0, style.borderWidth / 2)
        let strokeRect = rect.insetBy(dx: borderInset, dy: borderInset)
        let strokeCorner = max(0, style.cornerRadius - borderInset)
        let backgroundPath = CGPath(
            roundedRect: rect,
            cornerWidth: style.cornerRadius,
            cornerHeight: style.cornerRadius,
            transform: nil
        )
        context.addPath(backgroundPath)
        context.setFillColor(style.backgroundColor.cgColor)
        context.fillPath()

        let strokePath = CGPath(
            roundedRect: strokeRect,
            cornerWidth: strokeCorner,
            cornerHeight: strokeCorner,
            transform: nil
        )
        context.addPath(strokePath)
        context.setStrokeColor(style.borderColor.cgColor)
        context.setLineWidth(style.borderWidth)
        context.strokePath()

        context.setFillColor(style.headerBackground.cgColor)
        context.fill(layout.headerRect)

        context.setStrokeColor(style.borderColor.cgColor)
        context.setLineWidth(style.borderWidth)
        context.move(to: CGPoint(x: style.borderWidth / 2, y: layout.headerRect.maxY))
        context.addLine(to: CGPoint(x: layout.size.width - style.borderWidth / 2, y: layout.headerRect.maxY))
        context.strokePath()

        if style.copyBackground.markdownAlpha > 0.01 {
            let copyPath = CGPath(
                roundedRect: layout.copyButtonRect,
                cornerWidth: layout.copyButtonRect.height / 2,
                cornerHeight: layout.copyButtonRect.height / 2,
                transform: nil
            )
            context.addPath(copyPath)
            context.setFillColor(style.copyBackground.cgColor)
            context.fillPath()
        }

        let languageAttributes: [NSAttributedString.Key: Any] = [
            .font: style.headerFont,
            .foregroundColor: style.headerTextColor,
            .paragraphStyle: {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
                return paragraph
            }()
        ]
        let languageString = NSAttributedString(string: languageLabel, attributes: languageAttributes)
        languageString.draw(
            with: layout.languageRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        let copyAttributes: [NSAttributedString.Key: Any] = [
            .font: style.headerFont,
            .foregroundColor: style.copyTextColor
        ]
        let copyString = NSAttributedString(string: copyLabel, attributes: copyAttributes)
        if layout.copyIconRect != .zero {
            drawCopyIcon(in: context, rect: layout.copyIconRect, color: style.copyTextColor)
        }
        copyString.draw(
            with: layout.copyTextRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        let codeDrawWidth = max(1, layout.contentWidth - style.codePadding.width * 2)
        let codeDrawRect = CGRect(
            x: layout.codeRect.minX - horizontalScrollOffset,
            y: layout.codeRect.minY,
            width: codeDrawWidth,
            height: layout.codeRect.height
        )
        context.saveGState()
        context.clip(to: layout.codeRect)
        codeAttributed.draw(
            with: codeDrawRect.integral,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        context.restoreGState()
    }

    private func measureText(_ text: String, font: MarkdownPlatformFont) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attrs)
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func measureAttributed(_ text: NSAttributedString, width: CGFloat) -> CGSize {
        measureAttributedText(text, width: width)
    }

    private static func estimateMetrics(for code: String) -> EstimatedCodeMetrics {
        var metrics = EstimatedCodeMetrics(lineCount: 1, currentLineUnits: 0, maxLineUnits: 0)
        ingest(delta: code, into: &metrics)
        return metrics
    }

    private static func ingest(delta: String, into metrics: inout EstimatedCodeMetrics) {
        guard !delta.isEmpty else { return }
        for scalar in delta.unicodeScalars {
            switch scalar.value {
            case 10: // \n
                metrics.maxLineUnits = max(metrics.maxLineUnits, metrics.currentLineUnits)
                metrics.lineCount += 1
                metrics.currentLineUnits = 0
            case 13: // \r
                continue
            case 9: // \t
                metrics.currentLineUnits += EstimatedSizing.tabWidthUnits
                metrics.maxLineUnits = max(metrics.maxLineUnits, metrics.currentLineUnits)
            default:
                metrics.currentLineUnits += scalar.isASCII ? 1 : EstimatedSizing.nonASCIIWidthUnits
                metrics.maxLineUnits = max(metrics.maxLineUnits, metrics.currentLineUnits)
            }
        }
    }

    private func lineHeight(for font: MarkdownPlatformFont) -> CGFloat {
        #if os(iOS) || os(tvOS) || os(watchOS)
        return font.lineHeight
        #elseif os(macOS)
        return NSLayoutManager().defaultLineHeight(for: font)
        #endif
    }

    private func drawCopyIcon(in context: CGContext, rect: CGRect, color: MarkdownPlatformColor) {
        let lineWidth: CGFloat = 1.3
        let offset = rect.width * 0.22
        let backRect = CGRect(
            x: rect.minX + offset,
            y: rect.minY,
            width: rect.width - offset,
            height: rect.height - offset
        )
        let frontRect = CGRect(
            x: rect.minX,
            y: rect.minY + offset,
            width: rect.width - offset,
            height: rect.height - offset
        )

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.stroke(backRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        context.stroke(frontRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
    }
}

final class MarkdownTableAttachment: MarkdownAttachment, @unchecked Sendable {
    private struct TableLayout {
        let tableSize: CGSize
        let contentWidth: CGFloat
        let columnWidths: [CGFloat]
        let rowHeights: [CGFloat]
        let rowSeparatorWidth: CGFloat
        let columnGap: CGFloat
    }

    private(set) var rows: [MarkdownTableRow]
    override var plainText: String {
        rows.map { row in
            row.cells.map { extractPlainText(from: $0) }.joined(separator: "\t")
        }.joined(separator: "\n")
    }
    override var supportsHorizontalScroll: Bool { true }
    let style: MarkdownTableStyle
    private var horizontalScrollOffset: CGFloat = 0
    private var horizontalScrollRange: CGFloat = 0
    private var cachedImage: MarkdownPlatformImage?
    private var cachedSize: CGSize = .zero
    private var cachedWidth: CGFloat = 0
    private var lastLayout: TableLayout?

    #if os(macOS)
    weak var hostedView: MarkdownTableView?
    #endif

    private static let viewProviderFileType = MarkdownAttachmentFileTypes.viewBacked

    private func configureTextAttachmentViewIfAvailable() {
        #if os(iOS) || os(tvOS)
        if #available(iOS 15.0, tvOS 15.0, *) {
            MarkdownAttachmentViewProviderRegistry.registerIfNeeded()
            allowsTextAttachmentView = true
            fileType = Self.viewProviderFileType
            if contents == nil { contents = Data() }
        }
        #elseif os(macOS)
        if #available(macOS 12.0, *) {
            MarkdownAttachmentViewProviderRegistry.registerIfNeeded()
            allowsTextAttachmentView = true
            fileType = Self.viewProviderFileType
            if contents == nil { contents = Data() }
        }
        #endif
    }

    #if os(macOS)
    @MainActor
    #endif
    init(rows: [MarkdownTableRow], style: MarkdownTableStyle, maxWidth: CGFloat) {
        self.rows = rows
        self.style = style
        super.init(data: nil, ofType: nil)
        self.maxWidth = maxWidth
        #if os(iOS) || os(tvOS) || os(macOS)
        configureTextAttachmentViewIfAvailable()
        #endif
    }

    required init?(coder: NSCoder) {
        self.rows = []
        self.style = MarkdownTableStyle.fallback()
        super.init(coder: coder)
        #if os(iOS) || os(tvOS) || os(macOS)
        configureTextAttachmentViewIfAvailable()
        #endif
    }

    #if os(macOS)
    @MainActor
    #endif
    func appendRows(_ newRows: [MarkdownTableRow]) {
        guard !newRows.isEmpty else { return }
        rows.append(contentsOf: newRows)
        contentVersion &+= 1
        invalidateForContentChange()
        #if os(macOS)
        hostedView?.applyUpdate(from: self)
        #endif
    }

    #if os(macOS)
    @MainActor
    #endif
    func replaceLastRow(_ row: MarkdownTableRow) {
        if rows.isEmpty {
            rows = [row]
        } else {
            rows[rows.count - 1] = row
        }
        contentVersion &+= 1
        invalidateForContentChange()
        #if os(macOS)
        hostedView?.applyUpdate(from: self)
        #endif
    }

    #if os(macOS)
    @MainActor
    #endif
    func synchronizeRows(to nextRows: [MarkdownTableRow]) {
        guard !Self.rowsEqual(rows, nextRows) else { return }
        rows = nextRows
        contentVersion &+= 1
        invalidateForContentChange()
        #if os(macOS)
        hostedView?.applyUpdate(from: self)
        #endif
    }

    func hostedHorizontalOffset() -> CGFloat {
        horizontalScrollOffset
    }

    func setHostedHorizontalOffset(_ offset: CGFloat) {
        horizontalScrollOffset = max(0, offset)
    }

    override func widthDidChange() {
        cachedImage = nil
        cachedSize = .zero
        cachedWidth = 0
        lastLayout = nil
        horizontalScrollRange = 0
        #if !os(macOS)
        setAttachmentImage(nil)
        #endif
    }

    private func invalidateForContentChange() {
        cachedImage = nil
        cachedSize = .zero
        cachedWidth = 0
        lastLayout = nil
        horizontalScrollRange = 0
        #if !os(macOS)
        setAttachmentImage(nil)
        #endif
    }

    override func scrollHorizontally(by delta: CGFloat) -> Bool {
        guard !allowsTextAttachmentView else { return false }
        guard horizontalScrollRange > 0 else { return false }
        let nextOffset = min(max(0, horizontalScrollOffset + delta), horizontalScrollRange)
        if abs(nextOffset - horizontalScrollOffset) < 0.5 { return false }
        horizontalScrollOffset = nextOffset
        if lastLayout == nil {
            let fallbackWidth = max(maxWidth, cachedWidth)
            if fallbackWidth > 1 {
                _ = renderIfNeeded(maxWidth: fallbackWidth)
            }
        }
        guard let layout = lastLayout else { return false }
        cachedImage = drawTable(layout: layout)
        #if !os(macOS)
        setAttachmentImage(cachedImage)
        #endif
        return true
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let targetWidth = attachmentAvailableWidth(maxWidth: maxWidth, lineFragWidth: lineFrag.width)
        let size = renderIfNeeded(maxWidth: targetWidth)
        return CGRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    private func renderIfNeeded(maxWidth: CGFloat) -> CGSize {
        if abs(cachedWidth - maxWidth) > 0.5 || lastLayout == nil || (!allowsTextAttachmentView && cachedImage == nil) {
            let layout = layoutTable(maxWidth: maxWidth)
            cachedSize = layout.tableSize
            cachedWidth = maxWidth
            lastLayout = layout
            if !allowsTextAttachmentView {
                let scrollRange = max(0, layout.contentWidth - layout.tableSize.width)
                horizontalScrollRange = scrollRange
                if horizontalScrollOffset > scrollRange {
                    horizontalScrollOffset = scrollRange
                }
                cachedImage = drawTable(layout: layout)
                #if !os(macOS)
                setAttachmentImage(cachedImage)
                #endif
            } else {
                horizontalScrollOffset = 0
                horizontalScrollRange = 0
            }
        }
        return cachedSize
    }

    private func layoutTable(maxWidth: CGFloat) -> TableLayout {
        let columnCount = rows.map { $0.cells.count }.max() ?? 0
        guard columnCount > 0 else {
            return TableLayout(
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
        let maxCellTextWidth = max(80, min(maxWidth * 0.8, 360))
        let emptyCell = NSAttributedString(string: "", attributes: [.font: style.baseFont])

        var contentWidths = Array(repeating: CGFloat(0), count: columnCount)
        for row in rows {
            for column in 0..<columnCount {
                let cell = column < row.cells.count ? row.cells[column] : emptyCell
                let size = measureCell(cell, width: .greatestFiniteMagnitude)
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
                let cell = column < row.cells.count ? row.cells[column] : emptyCell
                let textWidth = max(0, columnWidths[column] - paddingX * 2)
                let size = measureCell(cell, width: textWidth)
                rowHeight = max(rowHeight, max(size.height, minRowHeight))
            }
            rowHeights.append(rowHeight + paddingY * 2)
        }

        let tableWidth = columnWidths.reduce(0, +) + totalColumnGap
        let tableHeight = rowHeights.reduce(0, +) + rowSeparator * CGFloat(rows.count)
        let viewportWidth = min(maxWidth, tableWidth)
        return TableLayout(
            tableSize: CGSize(width: viewportWidth, height: tableHeight),
            contentWidth: tableWidth,
            columnWidths: columnWidths,
            rowHeights: rowHeights,
            rowSeparatorWidth: rowSeparator,
            columnGap: columnGap
        )
    }

    private func drawTable(layout: TableLayout) -> MarkdownPlatformImage? {
        let size = layout.tableSize
        guard size.width > 0, size.height > 0 else { return nil }
        #if os(iOS) || os(tvOS) || os(watchOS)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            drawTable(in: context.cgContext, layout: layout)
        }
        #elseif os(macOS)
        return renderMarkdownImage(size: size) { context in
            drawTable(in: context, layout: layout)
        }
        #endif
    }

    private func drawTable(in context: CGContext, layout: TableLayout) {
        let rowSeparator = layout.rowSeparatorWidth
        let halfSeparator = rowSeparator / 2
        let columnGap = layout.columnGap
        let padding = style.cellPadding
        let tableWidth = layout.contentWidth
        let hasHeader = rows.first?.isHeader == true
        let emptyCell = NSAttributedString(string: "")

        context.setStrokeColor(style.borderColor.cgColor)
        context.setLineWidth(rowSeparator)

        let viewportRect = CGRect(origin: .zero, size: layout.tableSize)
        context.saveGState()
        context.clip(to: viewportRect)
        context.translateBy(x: -horizontalScrollOffset, y: 0)

        var y: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            let rowHeight = layout.rowHeights[rowIndex]
            let rowRect = CGRect(x: 0, y: y, width: tableWidth, height: rowHeight)
            if row.isHeader {
                if style.headerBackground.markdownAlpha > 0.01 {
                    context.setFillColor(style.headerBackground.cgColor)
                    context.fill(rowRect)
                }
            } else {
                let bodyIndex = rowIndex - (hasHeader ? 1 : 0)
                if bodyIndex % 2 == 1 {
                    if style.stripeBackground.markdownAlpha > 0.01 {
                        context.setFillColor(style.stripeBackground.cgColor)
                        context.fill(rowRect)
                    }
                }
            }

            var x: CGFloat = 0
            for column in 0..<layout.columnWidths.count {
                let cellWidth = layout.columnWidths[column]
                let cellRect = CGRect(x: x, y: y, width: cellWidth, height: rowHeight)
                let textRect = cellRect.insetBy(dx: padding.width, dy: padding.height)
                let cell = column < row.cells.count ? row.cells[column] : emptyCell
                if textRect.width > 0 && textRect.height > 0 {
                    cell.draw(
                        with: textRect.integral,
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                }
                x += cellWidth + columnGap
            }

            y += rowHeight
            let lineY = y + halfSeparator
            context.move(to: CGPoint(x: halfSeparator, y: lineY))
            context.addLine(to: CGPoint(x: tableWidth - halfSeparator, y: lineY))
            y += rowSeparator
        }
        context.setStrokeColor(style.borderColor.cgColor)
        context.setLineWidth(rowSeparator)
        context.strokePath()
        context.restoreGState()
    }

    private func measureCell(_ cell: NSAttributedString, width: CGFloat) -> CGSize {
        measureAttributedText(cell, width: width)
    }

    private func lineHeight(for font: MarkdownPlatformFont) -> CGFloat {
        #if os(iOS) || os(tvOS) || os(watchOS)
        return font.lineHeight
        #elseif os(macOS)
        return NSLayoutManager().defaultLineHeight(for: font)
        #endif
    }

    private static func rowsEqual(_ lhs: [MarkdownTableRow], _ rhs: [MarkdownTableRow]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for index in 0..<lhs.count {
            let left = lhs[index]
            let right = rhs[index]
            if left.isHeader != right.isHeader { return false }
            if left.cells.count != right.cells.count { return false }
            for column in 0..<left.cells.count {
                if !left.cells[column].isEqual(to: right.cells[column]) { return false }
            }
        }
        return true
    }
}

final class MarkdownRuleAttachment: MarkdownAttachment, @unchecked Sendable {
    let color: MarkdownPlatformColor
    let thickness: CGFloat
    let verticalPadding: CGFloat
    private var cachedImage: MarkdownPlatformImage?
    private var cachedWidth: CGFloat = 0
    private var cachedSize: CGSize = .zero

    private static let viewProviderFileType = MarkdownAttachmentFileTypes.viewBacked

    private func configureTextAttachmentViewIfAvailable() {
        #if os(iOS) || os(tvOS)
        if #available(iOS 15.0, tvOS 15.0, *) {
            MarkdownAttachmentViewProviderRegistry.registerIfNeeded()
            allowsTextAttachmentView = true
            fileType = Self.viewProviderFileType
            if contents == nil { contents = Data() }
        }
        #elseif os(macOS)
        if #available(macOS 12.0, *) {
            MarkdownAttachmentViewProviderRegistry.registerIfNeeded()
            allowsTextAttachmentView = true
            fileType = Self.viewProviderFileType
            if contents == nil { contents = Data() }
        }
        #endif
    }

    #if os(macOS)
    @MainActor
    #endif
    init(color: MarkdownPlatformColor, thickness: CGFloat, verticalPadding: CGFloat, maxWidth: CGFloat) {
        self.color = color
        self.thickness = max(1, thickness)
        self.verticalPadding = verticalPadding
        super.init(data: nil, ofType: nil)
        self.maxWidth = maxWidth
        #if os(iOS) || os(tvOS) || os(macOS)
        configureTextAttachmentViewIfAvailable()
        #endif
    }

    required init?(coder: NSCoder) {
        self.color = MarkdownPlatformColor.markdownHex(0xd0d7de)
        self.thickness = 1
        self.verticalPadding = 6
        super.init(coder: coder)
        #if os(iOS) || os(tvOS) || os(macOS)
        configureTextAttachmentViewIfAvailable()
        #endif
    }

    override func widthDidChange() {
        cachedImage = nil
        cachedSize = .zero
        cachedWidth = 0
        #if !os(macOS)
        setAttachmentImage(nil)
        #endif
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let targetWidth = attachmentAvailableWidth(maxWidth: maxWidth, lineFragWidth: lineFrag.width)
        let size = renderIfNeeded(width: targetWidth)
        return CGRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    private func renderIfNeeded(width: CGFloat) -> CGSize {
        if abs(cachedWidth - width) > 0.5 || (!allowsTextAttachmentView && cachedImage == nil) {
            let height = verticalPadding * 2 + thickness
            let size = CGSize(width: width, height: height)
            cachedSize = size
            cachedWidth = width
            if !allowsTextAttachmentView {
                cachedImage = drawRule(size: size)
                #if !os(macOS)
                setAttachmentImage(cachedImage)
                #endif
            }
        }
        return cachedSize
    }

    private func drawRule(size: CGSize) -> MarkdownPlatformImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        #if os(iOS) || os(tvOS) || os(watchOS)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            drawRule(in: context.cgContext, size: size)
        }
        #elseif os(macOS)
        return renderMarkdownImage(size: size) { context in
            drawRule(in: context, size: size)
        }
        #endif
    }

    private func drawRule(in context: CGContext, size: CGSize) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(thickness)
        let halfThickness = thickness / 2
        let y = size.height / 2
        context.move(to: CGPoint(x: halfThickness, y: y))
        context.addLine(to: CGPoint(x: max(halfThickness, size.width - halfThickness), y: y))
        context.strokePath()
    }
}
