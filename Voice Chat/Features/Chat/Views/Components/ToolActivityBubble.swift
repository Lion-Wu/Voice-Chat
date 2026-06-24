//
//  ToolActivityBubble.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import SwiftUI

struct ToolActivityBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let activities: [ChatToolActivity]
    var maxBubbleWidth: CGFloat? = nil
    var isEmbeddedInMessage = false

    var body: some View {
        let barMaxWidth = contentMaxWidthForAssistant(availableWidth: maxBubbleWidth)
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(activities) { activity in
                    row(activity)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ChatTheme.systemBubbleFill.opacity(0.9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(ChatTheme.subtleStroke.opacity(0.8))
                    }
            )
            .shadow(color: Color.black.opacity(0.035), radius: 5, x: 0, y: 2)
            .frame(maxWidth: barMaxWidth, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.vertical, isEmbeddedInMessage ? 1 : 4)
        #if os(macOS)
        .padding(.horizontal, isEmbeddedInMessage ? 0 : 16)
        #else
        .padding(.horizontal, isEmbeddedInMessage ? 0 : 2)
        #endif
    }

    private func row(_ activity: ChatToolActivity) -> some View {
        HStack(spacing: 9) {
            icon(for: activity)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(phaseTint(for: activity).opacity(0.12))
                )

            Text(activity.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            if let summary = activity.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty {
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    }

    @ViewBuilder
    private func icon(for activity: ChatToolActivity) -> some View {
        switch activity.phase {
        case .requested, .authorizing, .running, .processing:
            if reduceMotion {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(phaseTint(for: activity))
            } else {
                LoadingIndicatorView(tint: phaseTint(for: activity), dotSize: 4.5, spacing: 2.5)
            }
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(phaseTint(for: activity))
        case .denied:
            Image(systemName: "hand.raised.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(phaseTint(for: activity))
        case .unsupported:
            Image(systemName: "slash.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(phaseTint(for: activity))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(phaseTint(for: activity))
        }
    }

    private func phaseTint(for activity: ChatToolActivity) -> Color {
        switch activity.phase {
        case .requested, .authorizing, .running, .processing:
            return ChatTheme.accent.opacity(0.9)
        case .succeeded:
            return .green
        case .denied, .failed:
            return .orange
        case .unsupported:
            return .secondary
        }
    }
}
