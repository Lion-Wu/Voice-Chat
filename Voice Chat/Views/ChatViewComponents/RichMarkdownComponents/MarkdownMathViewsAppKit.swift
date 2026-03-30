#if os(macOS)
@preconcurrency import Foundation
@preconcurrency import AppKit

final class MarkdownMathView: NSView {
    override var isFlipped: Bool { true }

    private weak var attachment: MarkdownMathAttachment?
    private var cachedWidth: CGFloat = 0
    private var cachedSize: CGSize = .zero

    init(attachment: MarkdownMathAttachment) {
        self.attachment = attachment
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(attachment.accessibilityText)
        setAccessibilityValue(attachment.plainText)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func applyUpdate(from attachment: MarkdownMathAttachment) {
        self.attachment = attachment
        cachedWidth = 0
        cachedSize = .zero
        setAccessibilityLabel(attachment.accessibilityText)
        setAccessibilityValue(attachment.plainText)
        needsDisplay = true
    }

    func sizeThatFitsWidth(_ width: CGFloat) -> CGSize {
        let targetWidth = max(1, width)
        if abs(cachedWidth - targetWidth) > 0.5 || cachedSize == .zero {
            cachedWidth = targetWidth
            cachedSize = attachment?.measuredSize(availableWidth: targetWidth) ?? .zero
            needsDisplay = true
        }
        return cachedSize
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let attachment, let context = NSGraphicsContext.current?.cgContext else { return }
        attachment.draw(in: context, bounds: bounds)
    }
}
#endif
