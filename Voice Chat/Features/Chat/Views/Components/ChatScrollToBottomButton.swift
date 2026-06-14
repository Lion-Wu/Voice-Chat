//
//  ChatScrollToBottomButton.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import SwiftUI

struct ChatScrollToBottomButton: View {
    let size: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            #if os(visionOS)
            fallbackLabel
            #else
            if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: size, height: size)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(Circle())
            } else {
                fallbackLabel
            }
            #endif
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel("Scroll to bottom")
    }

    private var fallbackLabel: some View {
        Image(systemName: "arrow.down")
            .font(.system(size: 18, weight: .semibold))
            .frame(width: size, height: size)
            .contentShape(Circle())
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Circle()
                    .stroke(ChatTheme.subtleStroke.opacity(0.5), lineWidth: 0.6)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
    }
}
