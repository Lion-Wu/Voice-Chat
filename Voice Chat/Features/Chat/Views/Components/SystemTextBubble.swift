//
//  SystemTextBubble.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

struct SystemTextBubble: View {
    let message: ChatMessage
    @State private var isShowingMessageDetails = false
    @State private var isShowingCopyFeedback = false
    @State private var copyFeedbackToken = 0

    let thinkPreviewLines: Int
    let thinkFontSize: CGFloat
    let showActionButtons: Bool
    let developerModeEnabled: Bool
    let maxBubbleWidth: CGFloat?
    let contentFingerprint: ContentFingerprint
    let toolActivities: [ChatToolActivity]
    let toolActivityPlacements: [ChatToolActivityPlacement]
    let searchHighlightQuery: String?
    let isStreamingResponse: Bool

    let onCopy: () -> Void
    let onRegenerate: () -> Void
    let onReadAloud: () -> Void
    private let renderCache = MessageRenderCache.shared

    var body: some View {
        let parts = renderCache.thinkParts(for: message.id, content: message.content, fingerprint: contentFingerprint)
        let thinkingPlacements = toolActivityPlacements.filter { $0.scope == .thinking }
        let bodyPlacements = toolActivityPlacements.filter { $0.scope == .body }

        let thinkView = Group {
            if let think = parts.think {
                ThinkingPreviewBubble(
                    think: think,
                    isComplete: parts.isClosed && (!isStreamingResponse || thinkingPlacements.isEmpty || !parts.body.isEmpty),
                    previewLines: thinkPreviewLines,
                    thinkFontSize: thinkFontSize,
                    toolActivityPlacements: thinkingPlacements,
                    maxBubbleWidth: maxBubbleWidth
                )
                    .frame(maxWidth: contentMaxWidthForAssistant(availableWidth: maxBubbleWidth), alignment: .leading)
            }
        }

        let bodyView = Group {
            if !parts.body.isEmpty || !bodyPlacements.isEmpty {
                ChatToolInlineContentView(
                    text: parts.body,
                    placements: bodyPlacements,
                    textStyle: .markdown,
                    maxBubbleWidth: maxBubbleWidth,
                    searchHighlightQuery: searchHighlightQuery,
                    animateNewText: isStreamingResponse
                )
                    .frame(maxWidth: contentMaxWidthForAssistant(availableWidth: maxBubbleWidth), alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }

        return VStack(alignment: .center, spacing: 8) {
            thinkView
            bodyView
            if parts.isClosed && !parts.body.isEmpty && showActionButtons {
                HStack(spacing: 6) {
                    Button { handleCopy() } label: {
                        Image(systemName: isShowingCopyFeedback ? "checkmark" : "doc.on.doc")
                            #if os(macOS)
                            .font(.system(size: 12, weight: .semibold))
                            #else
                            .font(.system(size: 16, weight: .semibold))
                            #endif
                            .padding(2)
                            .frame(minWidth: 18, minHeight: 18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isShowingCopyFeedback ? Color.green : .secondary)
                    .accessibilityLabel(isShowingCopyFeedback ? Text("Copied") : Text("Copy"))

                    Button { onRegenerate() } label: {
                        Image(systemName: "arrow.clockwise")
                            #if os(macOS)
                            .font(.system(size: 12, weight: .semibold))
                            #else
                            .font(.system(size: 16, weight: .semibold))
                            #endif
                            .padding(2)
                            .accessibilityLabel("Regenerate")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button { onReadAloud() } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            #if os(macOS)
                            .font(.system(size: 12, weight: .semibold))
                            #else
                            .font(.system(size: 16, weight: .semibold))
                            #endif
                            .padding(2)
                            .accessibilityLabel("Read Aloud")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    if developerModeEnabled {
                        Button { isShowingMessageDetails = true } label: {
                            Image(systemName: "info.circle")
                                #if os(macOS)
                                .font(.system(size: 12, weight: .semibold))
                                #else
                                .font(.system(size: 16, weight: .semibold))
                                #endif
                                .padding(2)
                                .accessibilityLabel("Details")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: contentMaxWidthForAssistant(availableWidth: maxBubbleWidth), alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .tint(ChatTheme.accent)
        .frame(maxWidth: .infinity, alignment: .center)
        .textSelection(.enabled)
        .task(id: copyFeedbackToken) {
            guard copyFeedbackToken > 0 else { return }
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isShowingCopyFeedback = false
                }
            }
        }
        .onDisappear {
            isShowingCopyFeedback = false
            copyFeedbackToken = 0
        }
        .sheet(isPresented: $isShowingMessageDetails) {
            MessageDetailsView(
                message: message,
                toolActivities: toolActivities,
                toolActivityPlacements: toolActivityPlacements
            )
        }
    }

    private func handleCopy() {
        onCopy()
        withAnimation(.easeInOut(duration: 0.18)) {
            isShowingCopyFeedback = true
        }
        copyFeedbackToken += 1
    }
}
