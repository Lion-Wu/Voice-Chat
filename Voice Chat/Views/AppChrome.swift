//
//  AppChrome.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2025/03/09.
//

import SwiftUI

/// Shared app background.
struct AppBackgroundView: View {
    var body: some View {
        PlatformColor.systemBackground
            .ignoresSafeArea()
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

#Preview {
    ZStack {
        AppBackgroundView()
        VStack(alignment: .leading, spacing: 14) {
            Text("Section")
                .appSectionLabelStyle()

            Text("This is a preview of shared app chrome styles.")
                .font(.body)
        }
        .padding(18)
        .appChromedContainer()
        .padding()
    }
}
