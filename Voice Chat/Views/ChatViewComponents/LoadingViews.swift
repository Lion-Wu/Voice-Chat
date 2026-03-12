//
//  LoadingViews.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI

struct LoadingIndicatorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var tint: Color = .secondary
    var dotSize: CGFloat = 8
    var spacing: CGFloat = 6

    private let cycleDuration: TimeInterval = 1.1
    private let phaseOffset: Double = 0.16

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.6 : (1.0 / 30.0))) { context in
            let progress = animationProgress(at: context.date)

            HStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { index in
                    let emphasis = dotEmphasis(index: index, progress: progress)
                    Circle()
                        .fill(tint)
                        .frame(width: dotSize, height: dotSize)
                        .scaleEffect(reduceMotion ? 1 : 0.78 + (0.38 * emphasis))
                        .offset(y: reduceMotion ? 0 : -(dotSize * 0.22 * emphasis))
                        .opacity(0.34 + (0.66 * emphasis))
                        .shadow(
                            color: tint.opacity(reduceMotion ? 0 : 0.08 + (0.12 * emphasis)),
                            radius: reduceMotion ? 0 : (dotSize * 0.45),
                            y: reduceMotion ? 0 : (dotSize * 0.08)
                        )
                }
            }
            .frame(height: dotSize * 1.5)
            .accessibilityHidden(true)
        }
    }

    private func animationProgress(at date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycleDuration)
        return elapsed / cycleDuration
    }

    private func dotEmphasis(index: Int, progress: Double) -> Double {
        let shifted = progress - (Double(index) * phaseOffset)
        let wrapped = shifted >= 0 ? shifted : (shifted + 1)
        let wave = sin(wrapped * (.pi * 2))
        let normalized = max(0, wave)
        if reduceMotion {
            return 0.45 + (0.55 * normalized)
        }
        return normalized
    }
}

struct AssistantAlignedLoadingBubble: View {
    var maxBubbleWidth: CGFloat? = nil

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack {
                    LoadingIndicatorView()
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous)
                                .fill(PlatformColor.secondaryBackground.opacity(0.72))
                                .overlay {
                                    RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous)
                                        .strokeBorder(.white.opacity(0.06))
                                }
                        )
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: contentMaxWidthForAssistant(availableWidth: maxBubbleWidth), alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 6)
        #if os(macOS)
        .padding(.horizontal)
        #else
        .padding(.horizontal, 2)
        #endif
    }
}

struct AssistantAlignedRetryingBubble: View {
    let attempt: Int
    let lastError: String?
    var maxBubbleWidth: CGFloat? = nil

    private var title: String {
        String(format: NSLocalizedString("Retrying (attempt %d)...", comment: "Shown while auto retry is waiting to reconnect"), max(1, attempt))
    }

    private var detail: String? {
        let trimmed = (lastError ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            LoadingIndicatorView()
                            Text(title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(PlatformColor.secondaryBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous))

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: contentMaxWidthForAssistant(availableWidth: maxBubbleWidth), alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 6)
        #if os(macOS)
        .padding(.horizontal)
        #else
        .padding(.horizontal, 2)
        #endif
    }
}

#Preview {
    ZStack {
        AppBackgroundView()
        VStack(spacing: 18) {
            AssistantAlignedLoadingBubble()
            AssistantAlignedRetryingBubble(attempt: 2, lastError: "Connection timed out")
        }
        .padding()
    }
}
