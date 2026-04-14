#if os(iOS) || os(tvOS) || os(visionOS)
@preconcurrency import Foundation
@preconcurrency import UIKit

final class MarkdownMathView: UIView {
    private weak var attachment: MarkdownMathAttachment?
    private var cachedWidth: CGFloat = 0
    private var cachedSize: CGSize = .zero

    init(attachment: MarkdownMathAttachment) {
        self.attachment = attachment
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = attachment.accessibilityText
        accessibilityValue = attachment.plainText
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func applyUpdate(from attachment: MarkdownMathAttachment) {
        self.attachment = attachment
        cachedWidth = 0
        cachedSize = .zero
        accessibilityLabel = attachment.accessibilityText
        accessibilityValue = attachment.plainText
        setNeedsDisplay()
    }

    func sizeThatFitsWidth(_ width: CGFloat) -> CGSize {
        let targetWidth = max(1, width)
        if abs(cachedWidth - targetWidth) > 0.5 || cachedSize == .zero {
            cachedWidth = targetWidth
            cachedSize = attachment?.measuredSize(availableWidth: targetWidth) ?? .zero
            setNeedsDisplay()
        }
        return cachedSize
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let attachment, let context = UIGraphicsGetCurrentContext() else { return }
        attachment.draw(in: context, bounds: bounds)
    }
}

#endif
