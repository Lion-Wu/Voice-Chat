//
//  MarkdownStyle.swift
//  Voice Chat
//

@preconcurrency import Foundation
import SwiftUI

#if os(iOS) || os(tvOS) || os(watchOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

extension MarkdownPlatformColor {
    static func markdownHex(_ hex: UInt32, alpha: CGFloat = 1) -> MarkdownPlatformColor {
        let red = CGFloat((hex >> 16) & 0xff) / 255
        let green = CGFloat((hex >> 8) & 0xff) / 255
        let blue = CGFloat(hex & 0xff) / 255
        #if os(iOS) || os(tvOS) || os(watchOS)
        return MarkdownPlatformColor(red: red, green: green, blue: blue, alpha: alpha)
        #elseif os(macOS)
        return MarkdownPlatformColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        #endif
    }

    func markdownWithAlpha(_ alpha: CGFloat) -> MarkdownPlatformColor {
        #if os(iOS) || os(tvOS) || os(watchOS)
        return withAlphaComponent(alpha)
        #elseif os(macOS)
        return withAlphaComponent(alpha)
        #endif
    }

    var markdownAlpha: CGFloat {
        #if os(iOS) || os(tvOS) || os(watchOS)
        return cgColor.alpha
        #elseif os(macOS)
        return usingColorSpace(.sRGB)?.alphaComponent ?? alphaComponent
        #endif
    }
}

struct MarkdownStyle: @unchecked Sendable {
    struct Palette: @unchecked Sendable {
        let text: MarkdownPlatformColor
        let secondaryText: MarkdownPlatformColor
        let link: MarkdownPlatformColor
        let border: MarkdownPlatformColor
        let codeBackground: MarkdownPlatformColor
        let codeBlockBackground: MarkdownPlatformColor
        let tableHeaderBackground: MarkdownPlatformColor
        let tableStripeBackground: MarkdownPlatformColor
        let quoteBorder: MarkdownPlatformColor
        let rule: MarkdownPlatformColor
    }

    let baseFont: MarkdownPlatformFont
    let codeFont: MarkdownPlatformFont
    let baseColor: MarkdownPlatformColor
    let secondaryColor: MarkdownPlatformColor
    let linkColor: MarkdownPlatformColor
    let inlineCodeBackground: MarkdownPlatformColor
    let codeBlockBackground: MarkdownPlatformColor
    let tableHeaderBackground: MarkdownPlatformColor
    let tableStripeBackground: MarkdownPlatformColor
    let tableBorderColor: MarkdownPlatformColor
    let quoteBorderColor: MarkdownPlatformColor
    let ruleColor: MarkdownPlatformColor
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat
    let blockSpacing: CGFloat
    let listIndent: CGFloat
    let listMarkerSpacing: CGFloat
    let tableCellPadding: CGSize
    let tableBorderWidth: CGFloat
    let colorScheme: ColorScheme

    init(colorScheme: ColorScheme, sizeCategory: ContentSizeCategory) {
        _ = sizeCategory
        let palette = Self.palette(for: colorScheme)

        #if os(iOS) || os(tvOS) || os(watchOS)
        let baseFont = MarkdownPlatformFont.preferredFont(forTextStyle: .body)
        let codeFont = MarkdownPlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
        #elseif os(macOS)
        let baseFont = MarkdownPlatformFont.systemFont(ofSize: MarkdownPlatformFont.systemFontSize)
        let codeFont = MarkdownPlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
        #endif

        self.baseFont = baseFont
        self.codeFont = codeFont
        self.baseColor = palette.text
        self.secondaryColor = palette.secondaryText
        self.linkColor = palette.link
        self.inlineCodeBackground = palette.codeBackground
        self.codeBlockBackground = palette.codeBlockBackground
        self.tableHeaderBackground = palette.tableHeaderBackground
        self.tableStripeBackground = palette.tableStripeBackground
        self.tableBorderColor = palette.border
        self.quoteBorderColor = palette.quoteBorder
        self.ruleColor = palette.rule
        self.lineSpacing = 2
        self.paragraphSpacing = 4
        self.blockSpacing = 6
        self.listIndent = baseFont.pointSize * 1.4
        self.listMarkerSpacing = baseFont.pointSize * 0.6
        self.tableCellPadding = CGSize(width: 14, height: 8)
        self.tableBorderWidth = 1
        self.colorScheme = colorScheme
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: baseColor
        ]
    }

    var linkAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: linkColor,
            .underlineStyle: 0
        ]
    }

    var cacheKey: String {
        "md:\(baseFont.pointSize):\(colorScheme)"
    }

    func paragraphStyle(
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat? = nil,
        firstLineHeadIndent: CGFloat? = nil,
        headIndent: CGFloat = 0,
        alignment: NSTextAlignment = .natural
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        #if os(iOS) || os(tvOS) || os(watchOS)
        style.lineBreakMode = .byWordWrapping
        #endif
        style.lineSpacing = lineSpacing
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter ?? paragraphSpacing
        style.firstLineHeadIndent = firstLineHeadIndent ?? headIndent
        style.headIndent = headIndent
        style.alignment = alignment
        return style
    }

    func headingFont(level: Int) -> MarkdownPlatformFont {
        let baseSize = baseFont.pointSize
        let scale: CGFloat
        switch level {
        case 1: scale = 2.0
        case 2: scale = 1.5
        case 3: scale = 1.25
        case 4: scale = 1.1
        case 5: scale = 1.0
        default: scale = 0.9
        }
        return MarkdownPlatformFont.systemFont(ofSize: baseSize * scale, weight: .semibold)
    }

    private static func palette(for scheme: ColorScheme) -> Palette {
        #if os(iOS) || os(tvOS)
        if scheme == .dark {
            return Palette(
                text: MarkdownPlatformColor.markdownHex(0xffffff),
                secondaryText: MarkdownPlatformColor.markdownHex(0xb3b3b3),
                link: MarkdownPlatformColor.markdownHex(0x4da3ff),
                border: MarkdownPlatformColor.markdownHex(0x3a3a3c),
                codeBackground: MarkdownPlatformColor.markdownHex(0x1c1c1e),
                codeBlockBackground: MarkdownPlatformColor.markdownHex(0x1c1c1e),
                tableHeaderBackground: MarkdownPlatformColor.clear,
                tableStripeBackground: MarkdownPlatformColor.clear,
                quoteBorder: MarkdownPlatformColor.markdownHex(0x3a3a3c),
                rule: MarkdownPlatformColor.markdownHex(0x3a3a3c)
            )
        } else {
            return Palette(
                text: MarkdownPlatformColor.markdownHex(0x000000),
                secondaryText: MarkdownPlatformColor.markdownHex(0x555555),
                link: MarkdownPlatformColor.markdownHex(0x007aff),
                border: MarkdownPlatformColor.markdownHex(0xd1d1d6),
                codeBackground: MarkdownPlatformColor.markdownHex(0xf2f2f7),
                codeBlockBackground: MarkdownPlatformColor.markdownHex(0xf2f2f7),
                tableHeaderBackground: MarkdownPlatformColor.clear,
                tableStripeBackground: MarkdownPlatformColor.clear,
                quoteBorder: MarkdownPlatformColor.markdownHex(0xd1d1d6),
                rule: MarkdownPlatformColor.markdownHex(0xd1d1d6)
            )
        }
        #else
        if scheme == .dark {
            return Palette(
                text: MarkdownPlatformColor.markdownHex(0xc9d1d9),
                secondaryText: MarkdownPlatformColor.markdownHex(0x8b949e),
                link: MarkdownPlatformColor.markdownHex(0x58a6ff),
                border: MarkdownPlatformColor.markdownHex(0x30363d),
                codeBackground: MarkdownPlatformColor.markdownHex(0x161b22),
                codeBlockBackground: MarkdownPlatformColor.markdownHex(0x161b22),
                tableHeaderBackground: MarkdownPlatformColor.clear,
                tableStripeBackground: MarkdownPlatformColor.clear,
                quoteBorder: MarkdownPlatformColor.markdownHex(0x30363d),
                rule: MarkdownPlatformColor.markdownHex(0x30363d)
            )
        } else {
            return Palette(
                text: MarkdownPlatformColor.markdownHex(0x24292f),
                secondaryText: MarkdownPlatformColor.markdownHex(0x57606a),
                link: MarkdownPlatformColor.markdownHex(0x0969da),
                border: MarkdownPlatformColor.markdownHex(0xe5e7eb),
                codeBackground: MarkdownPlatformColor.markdownHex(0xf2f4f7),
                codeBlockBackground: MarkdownPlatformColor.markdownHex(0xf7f7f8),
                tableHeaderBackground: MarkdownPlatformColor.clear,
                tableStripeBackground: MarkdownPlatformColor.clear,
                quoteBorder: MarkdownPlatformColor.markdownHex(0xd8dbe0),
                rule: MarkdownPlatformColor.markdownHex(0xe5e7eb)
            )
        }
        #endif
    }
}
