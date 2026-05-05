//
//  MarkdownAttachmentsCore.swift
//  Voice Chat
//

@preconcurrency import Foundation

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

class MarkdownAttachment: NSTextAttachment, @unchecked Sendable {
    var plainText: String { "" }
    var supportsHorizontalScroll: Bool { false }
    var contentVersion: UInt64 = 0
    var maxWidth: CGFloat = 0 {
        didSet {
            if abs(oldValue - maxWidth) > 0.5 {
                widthDidChange()
            }
        }
    }

    func widthDidChange() {
        // override in subclasses when width affects rendering
    }

    func scrollHorizontally(by delta: CGFloat) -> Bool {
        _ = delta
        return false
    }

    #if os(macOS)
    @MainActor
    #endif
    func setAttachmentImage(_ image: MarkdownPlatformImage?) {
        guard !allowsTextAttachmentView else { return }
        self.image = image
        #if os(macOS)
        if let image {
            if let cell = attachmentCell as? MarkdownAttachmentCell {
                cell.image = image
            } else {
                let cell = MarkdownAttachmentCell()
                cell.image = image
                attachmentCell = cell
            }
        } else {
            attachmentCell = nil
        }
        #endif
    }
}

enum MarkdownAttachmentFileTypes {
    /// Use a system-known UTType to ensure `NSTextAttachmentViewProvider` registration is honored.
    static let viewBacked = "public.data"
}

enum MarkdownAttachmentViewProviderRegistry {
    static func registerIfNeeded() {
        _ = Self.registerOnce
    }

    private static let registerOnce: Void = {
        #if os(iOS) || os(tvOS) || os(visionOS)
        if #available(iOS 15.0, tvOS 15.0, *) {
            NSTextAttachment.registerViewProviderClass(
                MarkdownAttachmentViewProvider.self,
                forFileType: MarkdownAttachmentFileTypes.viewBacked
            )
        }
        #elseif os(macOS)
        if #available(macOS 12.0, *) {
            NSTextAttachment.registerViewProviderClass(
                MarkdownAttachmentViewProvider.self,
                forFileType: MarkdownAttachmentFileTypes.viewBacked
            )
        }
        #endif
    }()
}

#if os(macOS)
final class MarkdownAttachmentCell: NSTextAttachmentCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let image else { return }
        image.draw(
            in: cellFrame,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }
}
#endif

#if os(macOS)
private func markdownImageBackingScale() -> CGFloat {
    let screens = NSScreen.screens.map(\.backingScaleFactor)
    return max(1, screens.max() ?? 2)
}

func renderMarkdownImage(
    size: CGSize,
    draw: (CGContext) -> Void
) -> MarkdownPlatformImage? {
    guard size.width > 0, size.height > 0 else { return nil }
    let scale = markdownImageBackingScale()
    let pixelWidth = max(1, Int(ceil(size.width * scale)))
    let pixelHeight = max(1, Int(ceil(size.height * scale)))
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: pixelWidth,
              height: pixelHeight,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else {
        return nil
    }
    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    draw(context)
    NSGraphicsContext.restoreGraphicsState()
    context.restoreGState()
    guard let cgImage = context.makeImage() else { return nil }
    return MarkdownPlatformImage(cgImage: cgImage, size: size)
}
#endif

struct MarkdownTableRow: @unchecked Sendable {
    let cells: [NSAttributedString]
    let isHeader: Bool
    let sourceMarkdown: String?

    init(cells: [NSAttributedString], isHeader: Bool, sourceMarkdown: String? = nil) {
        self.cells = cells
        self.isHeader = isHeader
        self.sourceMarkdown = sourceMarkdown
    }
}

struct MarkdownTableStyle {
    let baseFont: MarkdownPlatformFont
    let headerBackground: MarkdownPlatformColor
    let stripeBackground: MarkdownPlatformColor
    let borderColor: MarkdownPlatformColor
    let borderWidth: CGFloat
    let cellPadding: CGSize

    static func fallback() -> MarkdownTableStyle {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let baseFont = MarkdownPlatformFont.systemFont(ofSize: MarkdownPlatformFont.systemFontSize)
        #elseif os(macOS)
        let baseFont = MarkdownPlatformFont.systemFont(ofSize: MarkdownPlatformFont.systemFontSize)
        #endif
        return MarkdownTableStyle(
            baseFont: baseFont,
            headerBackground: MarkdownPlatformColor.clear,
            stripeBackground: MarkdownPlatformColor.clear,
            borderColor: MarkdownPlatformColor.markdownHex(0xe5e7eb),
            borderWidth: 1,
            cellPadding: CGSize(width: 14, height: 8)
        )
    }
}

struct MarkdownCodeBlockStyle {
    let codeFont: MarkdownPlatformFont
    let headerFont: MarkdownPlatformFont
    let textColor: MarkdownPlatformColor
    let headerTextColor: MarkdownPlatformColor
    let backgroundColor: MarkdownPlatformColor
    let headerBackground: MarkdownPlatformColor
    let borderColor: MarkdownPlatformColor
    let copyTextColor: MarkdownPlatformColor
    let copyBackground: MarkdownPlatformColor
    let borderWidth: CGFloat
    let cornerRadius: CGFloat
    let codePadding: CGSize
    let headerPadding: CGSize
}

struct MarkdownQuoteStyle {
    let textColor: MarkdownPlatformColor
    let borderColor: MarkdownPlatformColor
    let borderWidth: CGFloat
    let padding: CGSize
}

struct MarkdownQuoteLayout {
    let size: CGSize
    let borderFrame: CGRect
    let textFrame: CGRect
}

func markdownQuoteTextWidth(for width: CGFloat, style: MarkdownQuoteStyle) -> CGFloat {
    let resolvedWidth = max(1, width)
    let borderWidth = max(1, style.borderWidth)
    let horizontalPadding = max(0, style.padding.width)
    return max(1, resolvedWidth - borderWidth - horizontalPadding * 2)
}

func markdownQuoteLayout(
    width: CGFloat,
    style: MarkdownQuoteStyle,
    textHeight: CGFloat
) -> MarkdownQuoteLayout {
    let resolvedWidth = max(1, width)
    let borderWidth = max(1, style.borderWidth)
    let horizontalPadding = max(0, style.padding.width)
    let verticalPadding = max(0, style.padding.height)
    let resolvedTextHeight = ceil(max(0, textHeight))
    let height = ceil(resolvedTextHeight + verticalPadding * 2)
    let textFrame = CGRect(
        x: borderWidth + horizontalPadding,
        y: verticalPadding,
        width: markdownQuoteTextWidth(for: resolvedWidth, style: style),
        height: resolvedTextHeight
    )
    let borderFrame = CGRect(
        x: 0,
        y: 0,
        width: borderWidth,
        height: height
    )
    return MarkdownQuoteLayout(
        size: CGSize(width: resolvedWidth, height: height),
        borderFrame: borderFrame,
        textFrame: textFrame
    )
}
