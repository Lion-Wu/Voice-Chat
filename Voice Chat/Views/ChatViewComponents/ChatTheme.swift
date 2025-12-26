//
//  ChatTheme.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Platform Color Mapping

enum PlatformColor {
    static var systemBackground: Color {
        groupedBackground
    }

    static var secondaryBackground: Color {
        secondaryGroupedBackground
    }

    static var bubbleSystemFill: Color {
        tertiaryGroupedBackground
    }

    static var groupedBackground: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemGroupedBackground)
        #endif
    }

    static var secondaryGroupedBackground: Color {
        #if os(macOS)
        return Color(NSColor.underPageBackgroundColor)
        #else
        return Color(UIColor.secondarySystemGroupedBackground)
        #endif
    }

    static var tertiaryGroupedBackground: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(UIColor.tertiarySystemGroupedBackground)
        #endif
    }

    static var elevatedFill: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor.withAlphaComponent(0.8))
        #else
        return Color(UIColor.secondarySystemBackground.withAlphaComponent(0.9))
        #endif
    }
}

// MARK: - Theme Helpers

enum ChatTheme {
    static let inputBG: Material = .thin
    static let bubbleRadius: CGFloat = 24
    static let bubbleShadow = Color.black.opacity(0.06)
    static let separator = Color.primary.opacity(0.06)

    static let userBubbleGradient = LinearGradient(
        colors: [
            accent.opacity(0.95),
            accent.opacity(0.78)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let systemBubbleFill = PlatformColor.bubbleSystemFill
    static let subtleStroke = Color.primary.opacity(0.08)
    static let accent = Color.accentColor
    static let chromeBackground = PlatformColor.secondaryGroupedBackground
    static let chromeBorder = Color.primary.opacity(0.05)
}

// MARK: - Input Layout Constants

enum InputMetrics {
    #if os(iOS) || os(tvOS)
    static let outerV: CGFloat = 5
    static let outerH: CGFloat = 8
    static let innerTop: CGFloat = 6
    static let innerBottom: CGFloat = 6
#else
    static let outerV: CGFloat = 6
    static let outerH: CGFloat = 12
    static let innerTop: CGFloat = 7
    static let innerBottom: CGFloat = 7
#endif
    static let innerLeading: CGFloat = 4
    static let innerTrailing: CGFloat = 4
    static let baseLineHeight: CGFloat = 21
    static let defaultHeight: CGFloat = innerTop + innerBottom + baseLineHeight
}
