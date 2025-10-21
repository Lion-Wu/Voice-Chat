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

// MARK: - Platform color mappings

enum PlatformColor {
    static var systemBackground: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }
    static var secondaryBackground: Color {
        #if os(macOS)
        return Color(NSColor.underPageBackgroundColor)
        #else
        return Color(UIColor.secondarySystemBackground)
        #endif
    }
    static var bubbleSystemFill: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(UIColor.secondarySystemBackground)
        #endif
    }
}

// MARK: - Theme definitions and supporting styles

enum ChatTheme {
    static let inputBG: Material = .thin
    static let bubbleRadius: CGFloat = 24
    static let bubbleShadow = Color.black.opacity(0.06)
    static let separator = Color.primary.opacity(0.06)

    static let userBubbleGradient = LinearGradient(
        colors: [Color.blue.opacity(0.85), Color.blue.opacity(0.75)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let systemBubbleFill = PlatformColor.bubbleSystemFill
    static let subtleStroke = Color.primary.opacity(0.08)
    static let accent = Color.blue
}

// MARK: - Input field spacing constants

enum InputMetrics {
    static let outerV: CGFloat = 8
    static let outerH: CGFloat = 12
    static let innerTop: CGFloat = 10
    static let innerBottom: CGFloat = 10
    static let innerLeading: CGFloat = 6
    static let innerTrailing: CGFloat = 6
}
