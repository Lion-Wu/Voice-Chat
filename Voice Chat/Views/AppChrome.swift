//
//  AppChrome.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2025/03/09.
//

import SwiftUI

/// Shared gradient background that keeps the app visually consistent with Apple HIG guidance.
struct AppBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        #if os(iOS) || os(tvOS)
        let highlightOpacity: Double = colorScheme == .dark ? 0.08 : 0.32
        LinearGradient(
            colors: [
                PlatformColor.systemBackground,
                PlatformColor.secondaryBackground
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [
                    Color.white.opacity(highlightOpacity),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 420
            )
        )
        .ignoresSafeArea()
        #else
        PlatformColor.systemBackground
            .ignoresSafeArea()
        #endif
    }
}

private struct AppGlassBackground: ViewModifier {
    var cornerRadius: CGFloat
    var shadowOpacity: Double

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ChatTheme.chromeBorder, lineWidth: 1)
            )
            .shadow(color: ChatTheme.bubbleShadow.opacity(shadowOpacity), radius: 12, x: 0, y: 6)
    }
}

private struct SectionLabelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

extension View {
    func appChromedContainer(cornerRadius: CGFloat = 22, shadowOpacity: Double = 0.9) -> some View {
        modifier(AppGlassBackground(cornerRadius: cornerRadius, shadowOpacity: shadowOpacity))
    }

    func appSectionLabelStyle() -> some View {
        modifier(SectionLabelStyle())
    }
}
