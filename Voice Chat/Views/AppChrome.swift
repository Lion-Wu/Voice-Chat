//
//  AppChrome.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2025/03/09.
//

import SwiftUI

enum AppChromeMetrics {
    #if os(iOS) || os(tvOS)
    static let floatingGap: CGFloat = 10
    static let floatingGlassGroupingSpacing: CGFloat = 24
    static let floatingComposerCornerRadius: CGFloat = 32
    static let composerControlButtonSize: CGFloat = 28
    static let floatingScrollButtonSize: CGFloat = 32
    static let floatingCloseButtonSize: CGFloat = 40
    static let composerAttachmentTapSize: CGFloat = 40
    #else
    static let floatingGap: CGFloat = 10
    static let floatingGlassGroupingSpacing: CGFloat = 18
    static let floatingComposerCornerRadius: CGFloat = 30
    static let composerControlButtonSize: CGFloat = 26
    static let floatingScrollButtonSize: CGFloat = 36
    static let floatingCloseButtonSize: CGFloat = 36
    static let composerAttachmentTapSize: CGFloat = 38
    #endif
}

/// Shared app background.
struct AppBackgroundView: View {
    var body: some View {
        PlatformColor.systemBackground
            .ignoresSafeArea()
    }
}

struct AppLiquidGlassContainer<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
#if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
#else
        content
#endif
    }
}

private struct AppGlassBackground: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?
    var interactive: Bool
    var shadowOpacity: Double

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            if let tint {
                if interactive {
                    content
                        .glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
                } else {
                    content
                        .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
                }
            } else if interactive {
                content
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content
                    .glassEffect(in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            fallback(content: content)
        }
#else
        fallback(content: content)
#endif
    }

    private func fallback(content: Content) -> some View {
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

private struct AppGlassButtonStyleModifier: ViewModifier {
    var prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            content
        }
#else
        content
#endif
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
    func appChromedContainer(
        cornerRadius: CGFloat = 22,
        tint: Color? = nil,
        interactive: Bool = false,
        shadowOpacity: Double = 0.9
    ) -> some View {
        modifier(
            AppGlassBackground(
                cornerRadius: cornerRadius,
                tint: tint,
                interactive: interactive,
                shadowOpacity: shadowOpacity
            )
        )
    }

    func appSectionLabelStyle() -> some View {
        modifier(SectionLabelStyle())
    }

    func appGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(AppGlassButtonStyleModifier(prominent: prominent))
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
