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
    var maxWidth: CGFloat? = nil

    private var stackSpacing: CGFloat {
        AppChromeMetrics.floatingGap
    }

    private var horizontalPadding: CGFloat {
        #if os(iOS) || os(tvOS)
        return 16
        #else
        return 6
        #endif
    }

    private var defaultMaxStackWidth: CGFloat {
        #if os(iOS) || os(tvOS)
        return .infinity
        #else
        return 540
        #endif
    }

    private let bannerVerticalPadding: CGFloat = 8
    private var dismissTapSize: CGFloat {
        #if os(iOS) || os(tvOS)
        return 36
        #else
        return 28
        #endif
    }
    private let noticeAnimation = Animation.spring(response: 0.35, dampingFraction: 0.9)
    private let noticeTransition = AnyTransition.move(edge: .bottom).combined(with: .opacity)
    private var noticeIDs: [UUID] { notices.map(\.id) }

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
                            .frame(width: dismissTapSize, height: dismissTapSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss error")
                }
                .padding(.vertical, bannerVerticalPadding)
                .padding(.horizontal, 12)
                .appChromedContainer(
                    cornerRadius: 18,
                    tint: notice.tint.opacity(0.08),
                    shadowOpacity: 0.12
                )
                .transition(noticeTransition)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: maxWidth ?? defaultMaxStackWidth)
        .animation(noticeAnimation, value: noticeIDs)
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
            message: "Could not connect to http://localhost:9880",
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
