//
//  ErrorNoticeStack.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2025/03/10.
//

import SwiftUI

/// Non-modal stack of floating error banners shared between chat and realtime voice surfaces.
struct ErrorNoticeStack: View {
    let notices: [AppErrorNotice]
    let onDismiss: (AppErrorNotice) -> Void

    private var stackSpacing: CGFloat {
        #if os(iOS) || os(tvOS)
        return 6
        #else
        return 8
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(iOS) || os(tvOS)
        return 16
        #else
        return 6
        #endif
    }

    private var maxStackWidth: CGFloat {
        #if os(iOS) || os(tvOS)
        return .infinity
        #else
        return 540
        #endif
    }

    private let bannerVerticalPadding: CGFloat = 8

    var body: some View {
        VStack(spacing: stackSpacing) {
            ForEach(notices) { notice in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(notice.tint.opacity(0.16))
                            .frame(width: 34, height: 34)
                        Image(systemName: notice.iconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(notice.tint)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(notice.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(notice.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Button {
                        onDismiss(notice)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss error")
                }
                .padding(.vertical, bannerVerticalPadding)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        // Match the composer backdrop with a slightly denser material.
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(PlatformColor.systemBackground.opacity(0.2))
                        )
                        .shadow(color: ChatTheme.bubbleShadow.opacity(0.35), radius: 18, x: 0, y: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(ChatTheme.subtleStroke.opacity(0.6), lineWidth: 0.8)
                        )
                )
            }
        }
        .frame(maxWidth: maxStackWidth)
        .padding(.horizontal, horizontalPadding)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

#Preview {
    let sampleNotices: [AppErrorNotice] = [
        AppErrorNotice(
            id: UUID(),
            title: "Text server unreachable",
            message: "Could not connect to http://localhost:1234",
            category: .textModel,
            timestamp: Date(),
            severity: .critical
        ),
        AppErrorNotice(
            id: UUID(),
            title: "TTS server unreachable",
            message: "Could not connect to http://127.0.0.1:9880",
            category: .tts,
            timestamp: Date(),
            severity: .banner
        )
    ]

    ZStack(alignment: .bottom) {
        AppBackgroundView()
        ErrorNoticeStack(notices: sampleNotices, onDismiss: { _ in })
            .padding(.bottom, 24)
    }
    .frame(height: 320)
}
