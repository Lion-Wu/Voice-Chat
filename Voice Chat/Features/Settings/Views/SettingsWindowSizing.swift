//
//  SettingsWindowSizing.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

#if os(macOS)
import AppKit
import SwiftUI

enum MacSettingsLayout {
    static let minContentSize = NSSize(width: 500, height: 180)
    static let fallbackMaxContentSize = NSSize(width: 860, height: 720)
    static let topLevelContentSize = NSSize(width: 560, height: 540)
    static let screenMargin: CGFloat = 72
    static let resizeThreshold: CGFloat = 1
}

enum SettingsWindowSizer {
    static func updateWindowSizeIfNeeded() {
        Task { @MainActor in
            guard let window = NSApp?.windows.first(where: { $0.isKeyWindow }) else { return }
            let maxContentSize = maxContentSize(for: window)
            let targetSize = clampedContentSize(MacSettingsLayout.topLevelContentSize, maxContentSize: maxContentSize)

            window.contentMinSize = targetSize
            window.contentMaxSize = targetSize

            let currentSize = window.contentView?.bounds.size ?? .zero
            if abs(currentSize.width - targetSize.width) > MacSettingsLayout.resizeThreshold ||
                abs(currentSize.height - targetSize.height) > MacSettingsLayout.resizeThreshold {
                window.setContentSize(targetSize)
                keepWindowVisible(window)
            }
        }
    }

    private static func clampedContentSize(_ preferredSize: NSSize, maxContentSize: NSSize) -> NSSize {
        NSSize(
            width: min(max(preferredSize.width, MacSettingsLayout.minContentSize.width), maxContentSize.width),
            height: min(max(preferredSize.height, MacSettingsLayout.minContentSize.height), maxContentSize.height)
        )
    }

    @MainActor
    private static func maxContentSize(for window: NSWindow) -> NSSize {
        guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else {
            return MacSettingsLayout.fallbackMaxContentSize
        }

        return NSSize(
            width: max(
                MacSettingsLayout.minContentSize.width,
                min(MacSettingsLayout.fallbackMaxContentSize.width, visibleFrame.width - MacSettingsLayout.screenMargin)
            ),
            height: max(
                MacSettingsLayout.minContentSize.height,
                min(MacSettingsLayout.fallbackMaxContentSize.height, visibleFrame.height - MacSettingsLayout.screenMargin)
            )
        )
    }

    @MainActor
    private static func keepWindowVisible(_ window: NSWindow) {
        guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame

        if frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.maxX - frame.width
        }
        if frame.minX < visibleFrame.minX {
            frame.origin.x = visibleFrame.minX
        }
        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.height
        }
        if frame.minY < visibleFrame.minY {
            frame.origin.y = visibleFrame.minY
        }

        if frame.origin != window.frame.origin {
            window.setFrameOrigin(frame.origin)
        }
    }
}
#endif
