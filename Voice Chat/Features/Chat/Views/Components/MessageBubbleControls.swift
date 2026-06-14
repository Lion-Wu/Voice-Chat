//
//  MessageBubbleControls.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

struct UserContextMenuModifier: ViewModifier {
    let isUser: Bool
    let message: ChatMessage
    let onSelectText: (String) -> Void
    let onEditUserMessage: (ChatMessage) -> Void
    let copyToClipboard: (String) -> Void

    func body(content: Content) -> some View {
        if isUser {
            content.contextMenu(menuItems: {
                let parts = message.content.extractThinkParts()
                let bodyText = parts.body
                Button { copyToClipboard(bodyText) } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button { onSelectText(bodyText) } label: { Label("Select Text", systemImage: "text.cursor") }
                Button { onEditUserMessage(message) } label: { Label("Edit Message", systemImage: "pencil") }
            })
        } else {
            content
        }
    }
}

struct MessageBranchControls: View {
    let currentIndex: Int
    let totalCount: Int
    let isEnabled: Bool
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onPrevious()
            } label: {
                Text("←")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled || !canGoPrevious)

            Text("\(currentIndex)/\(totalCount)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()

            Button {
                onNext()
            } label: {
                Text("→")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled || !canGoNext)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(
                String.localizedStringWithFormat(
                    NSLocalizedString(
                        "Version %1$d of %2$d",
                        comment: "Accessibility label describing the current message branch version"
                    ),
                    currentIndex,
                    totalCount
                )
            )
        )
    }
}

struct ErrorBubbleView: View {
    let text: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                Text("An error occurred")
                    .foregroundStyle(.white)
                    .font(.headline)
            }
            .padding(.bottom, 2)

            Text(text.isEmpty ? "Unknown error" : text)
                .foregroundStyle(.white.opacity(0.95))
                .font(.subheadline)

            HStack {
                Spacer()
                Button {
                    onRetry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.white.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.95), in: RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous))
        .shadow(color: ChatTheme.bubbleShadow, radius: 8, x: 0, y: 4)
    }
}
