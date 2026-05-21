//
//  MarkdownMathCore.swift
//  Voice Chat
//

@preconcurrency import Foundation
@preconcurrency import VoiceChatRaTeX

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

enum MarkdownMathRenderLimits {
    static let maxNodeWidth: CGFloat = VoiceChatRaTeXRenderLimits.maxRenderedWidth
    static let maxNodeHeight: CGFloat = VoiceChatRaTeXRenderLimits.maxRenderedHeight
    static let maxAttachmentDimension: CGFloat = 4_096
}

private func clampedFiniteMathDimension(_ value: CGFloat, limit: CGFloat) -> CGFloat {
    guard value.isFinite, value > 0 else { return 0 }
    return min(ceil(value), limit)
}

struct MarkdownMathStyle: @unchecked Sendable, Equatable {
    let baseFont: MarkdownPlatformFont
    let textColor: MarkdownPlatformColor
    let displayPadding: CGSize
    let inlinePadding: CGSize

    init(baseFont: MarkdownPlatformFont, textColor: MarkdownPlatformColor) {
        self.baseFont = baseFont
        self.textColor = textColor
        self.displayPadding = CGSize(width: max(6, baseFont.pointSize * 0.45), height: max(6, baseFont.pointSize * 0.3))
        self.inlinePadding = CGSize(width: max(1, baseFont.pointSize * 0.08), height: max(1, baseFont.pointSize * 0.02))
    }

    static func == (lhs: MarkdownMathStyle, rhs: MarkdownMathStyle) -> Bool {
        mathFontsEqual(lhs.baseFont, rhs.baseFont) &&
        mathColorsEqual(lhs.textColor, rhs.textColor) &&
        abs(lhs.displayPadding.width - rhs.displayPadding.width) <= 0.01 &&
        abs(lhs.displayPadding.height - rhs.displayPadding.height) <= 0.01 &&
        abs(lhs.inlinePadding.width - rhs.inlinePadding.width) <= 0.01 &&
        abs(lhs.inlinePadding.height - rhs.inlinePadding.height) <= 0.01
    }

    var inlineMathAxisOffset: CGFloat {
        measuredRelationCenterOffset(for: baseFont)
    }
}

final class MarkdownMathRenderNode: @unchecked Sendable {
    let size: CGSize
    let baseline: CGFloat
    let alignmentAxis: CGFloat
    private let drawer: (CGContext, CGPoint) -> Void

    init(
        size: CGSize,
        baseline: CGFloat,
        alignmentAxis: CGFloat? = nil,
        drawer: @escaping (CGContext, CGPoint) -> Void
    ) {
        self.size = CGSize(
            width: clampedFiniteMathDimension(size.width, limit: MarkdownMathRenderLimits.maxNodeWidth),
            height: clampedFiniteMathDimension(size.height, limit: MarkdownMathRenderLimits.maxNodeHeight)
        )
        self.baseline = baseline.isFinite ? min(self.size.height, max(0, baseline)) : 0
        let resolvedAxis = alignmentAxis.flatMap { $0.isFinite ? $0 : nil } ?? self.baseline
        self.alignmentAxis = min(self.size.height, max(0, resolvedAxis))
        self.drawer = drawer
    }

    func draw(at origin: CGPoint, in context: CGContext) {
        drawer(context, origin)
    }

    static func empty(width: CGFloat = 0) -> MarkdownMathRenderNode {
        MarkdownMathRenderNode(size: CGSize(width: width, height: 0), baseline: 0, alignmentAxis: 0) { _, _ in }
    }
}

struct MarkdownMathRenderOutput: @unchecked Sendable {
    let node: MarkdownMathRenderNode
    let displayMode: Bool
    let style: MarkdownMathStyle

    var padding: CGSize {
        displayMode ? style.displayPadding : style.inlinePadding
    }

    var idealSize: CGSize {
        CGSize(
            width: ceil(node.size.width + padding.width * 2),
            height: ceil(node.size.height + padding.height * 2)
        )
    }

    func scaleToFit(availableWidth: CGFloat) -> CGFloat {
        let contentWidth = max(1, node.size.width)
        let usableWidth = max(1, availableWidth - padding.width * 2)
        return min(1, usableWidth / contentWidth)
    }

    func measuredSize(availableWidth: CGFloat) -> CGSize {
        let scale = scaleToFit(availableWidth: availableWidth)
        let width = min(
            max(1, availableWidth),
            ceil(node.size.width * scale + padding.width * 2)
        )
        let height = min(
            MarkdownMathRenderLimits.maxAttachmentDimension,
            ceil(node.size.height * scale + padding.height * 2)
        )
        return CGSize(width: width, height: height)
    }

    func attachmentBounds(availableWidth: CGFloat) -> CGRect {
        let scale = scaleToFit(availableWidth: availableWidth)
        let measured = measuredSize(availableWidth: availableWidth)
        let yOffset: CGFloat
        if displayMode {
            yOffset = 0
        } else {
            let scaledHeight = node.size.height * scale
            let contentY = max(padding.height, (measured.height - scaledHeight) / 2)
            let mathAxis = contentY + node.alignmentAxis * scale
            let surroundingAxis = style.baseFont.ascender - style.inlineMathAxisOffset
            yOffset = surroundingAxis - mathAxis
        }
        return CGRect(x: 0, y: floor(yOffset), width: measured.width, height: measured.height)
    }

    func draw(in context: CGContext, bounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = scaleToFit(availableWidth: bounds.width)
        let scaledWidth = node.size.width * scale
        let scaledHeight = node.size.height * scale
        let contentX: CGFloat
        if displayMode {
            contentX = max(padding.width, (bounds.width - scaledWidth) / 2)
        } else {
            contentX = padding.width
        }
        let contentY = max(padding.height, (bounds.height - scaledHeight) / 2)

        context.saveGState()
        context.translateBy(x: bounds.minX + contentX, y: bounds.minY + contentY)
        context.scaleBy(x: scale, y: scale)
        node.draw(at: .zero, in: context)
        context.restoreGState()
    }
}

enum MarkdownMathTypesetter {
    static func render(
        latex: String,
        displayMode: Bool,
        style: MarkdownMathStyle
    ) -> MarkdownMathRenderOutput {
        let cacheKey = MarkdownMathRenderCacheKey(
            latex: latex,
            displayMode: displayMode,
            style: style
        )
        if let cached = MarkdownMathRenderOutputCache.shared.output(for: cacheKey) {
            return cached
        }

        let output = renderUncached(
            latex: latex,
            displayMode: displayMode,
            style: style
        )
        MarkdownMathRenderOutputCache.shared.insert(output, for: cacheKey)
        return output
    }

    private static func renderUncached(
        latex: String,
        displayMode: Bool,
        style: MarkdownMathStyle
    ) -> MarkdownMathRenderOutput {
        if let output = MarkdownMathRaTeXTypesetter.render(
            latex: latex,
            displayMode: displayMode,
            style: style
        ) {
            return output
        }

        return MarkdownMathUnavailablePlaceholder.makeOutput(
            latex: latex,
            displayMode: displayMode,
            style: style
        )
    }
}

private enum MarkdownMathRaTeXTypesetter {
    static func render(
        latex: String,
        displayMode: Bool,
        style: MarkdownMathStyle
    ) -> MarkdownMathRenderOutput? {
        let fontSize = style.baseFont.pointSize * (displayMode ? 1.16 : 1.0)
        guard let formula = VoiceChatRaTeXEngine.shared.render(
            latex: latex,
            displayMode: displayMode,
            fontSize: fontSize,
            color: ratexColor(from: style.textColor)
        ) else {
            return nil
        }

        let size = CGSize(width: formula.width, height: formula.totalHeight)
        let alignmentAxis = max(0, min(size.height, formula.height - fontSize * 0.25))
        let node = MarkdownMathRenderNode(
            size: size,
            baseline: formula.height,
            alignmentAxis: alignmentAxis
        ) { cgContext, origin in
            cgContext.saveGState()
            cgContext.translateBy(x: origin.x, y: origin.y)
            formula.draw(in: cgContext)
            cgContext.restoreGState()
        }
        return MarkdownMathRenderOutput(node: node, displayMode: displayMode, style: style)
    }

    private static func ratexColor(from color: MarkdownPlatformColor) -> VoiceChatRaTeXColor {
        let components = mathColorKeyComponents(color)
        return VoiceChatRaTeXColor(
            red: Double(components.red) / 255,
            green: Double(components.green) / 255,
            blue: Double(components.blue) / 255,
            alpha: Double(components.alpha) / 255
        )
    }
}

private enum MarkdownMathUnavailablePlaceholder {
    static func makeOutput(
        latex: String,
        displayMode: Bool,
        style: MarkdownMathStyle
    ) -> MarkdownMathRenderOutput {
        let text = latex.isEmpty ? " " : latex
        let font = fallbackFont(for: style)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.textColor
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let measured = attributed.size()
        let lineHeight = max(font.ascender - font.descender + font.leading, measured.height)
        let size = CGSize(width: max(1, measured.width), height: max(1, lineHeight))
        let baseline = max(0, font.ascender)
        let node = MarkdownMathRenderNode(
            size: size,
            baseline: baseline,
            alignmentAxis: baseline
        ) { _, origin in
            attributed.draw(at: origin)
        }
        return MarkdownMathRenderOutput(node: node, displayMode: displayMode, style: style)
    }

    private static func fallbackFont(for style: MarkdownMathStyle) -> MarkdownPlatformFont {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        return MarkdownPlatformFont.monospacedSystemFont(
            ofSize: max(10, style.baseFont.pointSize * 0.92),
            weight: .regular
        )
        #elseif os(macOS)
        return MarkdownPlatformFont.monospacedSystemFont(
            ofSize: max(10, style.baseFont.pointSize * 0.92),
            weight: .regular
        )
        #endif
    }
}

private struct MarkdownMathRenderCacheKey: Hashable {
    let latex: String
    let displayMode: Bool
    let fontName: String
    let fontSize: Int
    let colorRed: Int
    let colorGreen: Int
    let colorBlue: Int
    let colorAlpha: Int

    init(latex: String, displayMode: Bool, style: MarkdownMathStyle) {
        let color = mathColorKeyComponents(style.textColor)
        self.latex = latex
        self.displayMode = displayMode
        self.fontName = style.baseFont.fontName
        self.fontSize = Int((style.baseFont.pointSize * 100).rounded())
        self.colorRed = color.red
        self.colorGreen = color.green
        self.colorBlue = color.blue
        self.colorAlpha = color.alpha
    }
}

private final class MarkdownMathRenderOutputCache: @unchecked Sendable {
    static let shared = MarkdownMathRenderOutputCache()

    private let lock = NSLock()
    private let capacity = 256
    private var values: [MarkdownMathRenderCacheKey: MarkdownMathRenderOutput] = [:]
    private var insertionOrder: [MarkdownMathRenderCacheKey] = []

    private init() {}

    func output(for key: MarkdownMathRenderCacheKey) -> MarkdownMathRenderOutput? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func insert(_ output: MarkdownMathRenderOutput, for key: MarkdownMathRenderCacheKey) {
        lock.lock()
        defer { lock.unlock() }
        if values[key] == nil {
            insertionOrder.append(key)
        }
        values[key] = output
        while insertionOrder.count > capacity, let oldest = insertionOrder.first {
            insertionOrder.removeFirst()
            values.removeValue(forKey: oldest)
        }
    }
}

private func measuredRelationCenterOffset(for font: MarkdownPlatformFont) -> CGFloat {
    let attributed = NSAttributedString(string: "=", attributes: [.font: font])
    let size = measureAttributedText(attributed, width: .greatestFiniteMagnitude)
    return max(1.5, fontAscender(font) - size.height / 2)
}

private func fontAscender(_ font: MarkdownPlatformFont) -> CGFloat {
    ceil(font.ascender)
}

private func mathColorsEqual(_ lhs: MarkdownPlatformColor, _ rhs: MarkdownPlatformColor) -> Bool {
    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    var leftRed: CGFloat = 0
    var leftGreen: CGFloat = 0
    var leftBlue: CGFloat = 0
    var leftAlpha: CGFloat = 0
    var rightRed: CGFloat = 0
    var rightGreen: CGFloat = 0
    var rightBlue: CGFloat = 0
    var rightAlpha: CGFloat = 0
    guard lhs.getRed(&leftRed, green: &leftGreen, blue: &leftBlue, alpha: &leftAlpha),
          rhs.getRed(&rightRed, green: &rightGreen, blue: &rightBlue, alpha: &rightAlpha)
    else {
        return lhs == rhs
    }
    return abs(leftRed - rightRed) <= 0.001 &&
        abs(leftGreen - rightGreen) <= 0.001 &&
        abs(leftBlue - rightBlue) <= 0.001 &&
        abs(leftAlpha - rightAlpha) <= 0.001
    #elseif os(macOS)
    let left = lhs.usingColorSpace(.sRGB) ?? lhs
    let right = rhs.usingColorSpace(.sRGB) ?? rhs
    return abs(left.redComponent - right.redComponent) <= 0.001 &&
        abs(left.greenComponent - right.greenComponent) <= 0.001 &&
        abs(left.blueComponent - right.blueComponent) <= 0.001 &&
        abs(left.alphaComponent - right.alphaComponent) <= 0.001
    #endif
}

private func mathColorKeyComponents(_ color: MarkdownPlatformColor) -> (
    red: Int,
    green: Int,
    blue: Int,
    alpha: Int
) {
    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
        return quantizedColorComponents(red: red, green: green, blue: blue, alpha: alpha)
    }
    let fallbackSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let converted = color.cgColor.converted(
        to: fallbackSpace,
        intent: .defaultIntent,
        options: nil
    ),
          let components = converted.components
    else {
        return (0, 0, 0, 255)
    }
    if components.count >= 4 {
        return quantizedColorComponents(
            red: components[0],
            green: components[1],
            blue: components[2],
            alpha: components[3]
        )
    }
    if components.count >= 2 {
        return quantizedColorComponents(
            red: components[0],
            green: components[0],
            blue: components[0],
            alpha: components[1]
        )
    }
    return (0, 0, 0, 255)
    #elseif os(macOS)
    let resolved = color.usingColorSpace(.sRGB) ?? color
    return quantizedColorComponents(
        red: resolved.redComponent,
        green: resolved.greenComponent,
        blue: resolved.blueComponent,
        alpha: resolved.alphaComponent
    )
    #endif
}

private func quantizedColorComponents(
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat,
    alpha: CGFloat
) -> (red: Int, green: Int, blue: Int, alpha: Int) {
    func quantize(_ component: CGFloat) -> Int {
        Int((min(1, max(0, component)) * 255).rounded())
    }
    return (
        quantize(red),
        quantize(green),
        quantize(blue),
        quantize(alpha)
    )
}

private func mathFontsEqual(_ lhs: MarkdownPlatformFont, _ rhs: MarkdownPlatformFont) -> Bool {
    abs(lhs.pointSize - rhs.pointSize) <= 0.01 && lhs.fontName == rhs.fontName
}
