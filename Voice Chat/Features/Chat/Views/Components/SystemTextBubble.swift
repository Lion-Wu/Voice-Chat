//
//  SystemTextBubble.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

struct SystemTextBubble: View {
    let message: ChatMessage

    let thinkPreviewLines: Int
    let thinkFontSize: CGFloat
    let developerModeEnabled: Bool
    let maxBubbleWidth: CGFloat?
    let contentFingerprint: ContentFingerprint
    let toolActivityPlacements: [ChatToolActivityPlacement]
    let searchHighlightQuery: String?
    let isStreamingResponse: Bool

    let onAuthorizeTool: (String, Bool) -> Void
    private let renderCache = MessageRenderCache.shared

    var body: some View {
        let assistantSegments = message.assistantSegments

        return VStack(alignment: .center, spacing: 8) {
            if assistantSegments.isEmpty {
                unstructuredContent
            } else {
                structuredContent(assistantSegments)
            }
        }
        .tint(ChatTheme.accent)
        .frame(maxWidth: .infinity, alignment: .center)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func structuredContent(_ segments: [ChatAssistantSegment]) -> some View {
        let blocks = ChatAssistantRenderBlockBuilder.blocks(
            segments: segments,
            placements: toolActivityPlacements
        )

        ForEach(Array(blocks.enumerated()), id: \.element.id) { indexedBlock in
            let block = indexedBlock.element
            switch block.kind {
            case .reasoning:
                ThinkingPreviewBubble(
                    think: block.text,
                    isComplete: !isStreamingResponse || indexedBlock.offset < blocks.count - 1,
                    previewLines: thinkPreviewLines,
                    thinkFontSize: thinkFontSize,
                    toolActivityPlacements: block.toolActivityPlacements,
                    maxBubbleWidth: maxBubbleWidth,
                    developerModeEnabled: developerModeEnabled,
                    onAuthorizeTool: onAuthorizeTool
                )
                .frame(
                    maxWidth: contentMaxWidthForAssistant(availableWidth: maxBubbleWidth),
                    alignment: .leading
                )

            case .text:
                if !block.text.isEmpty || !block.toolActivityPlacements.isEmpty {
                    bodyContent(
                        text: block.text,
                        placements: block.toolActivityPlacements
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var unstructuredContent: some View {
        let parts = renderCache.thinkParts(
            for: message.id,
            content: message.content,
            fingerprint: contentFingerprint
        )
        let thinkingPlacements = toolActivityPlacements.filter { $0.scope == .thinking }
        let bodyPlacements = toolActivityPlacements.filter { $0.scope == .body }

        if parts.think != nil || !thinkingPlacements.isEmpty {
            ThinkingPreviewBubble(
                think: parts.think ?? "",
                isComplete: parts.isClosed && (
                    !isStreamingResponse || thinkingPlacements.isEmpty || !parts.body.isEmpty
                ),
                previewLines: thinkPreviewLines,
                thinkFontSize: thinkFontSize,
                toolActivityPlacements: thinkingPlacements,
                maxBubbleWidth: maxBubbleWidth,
                developerModeEnabled: developerModeEnabled,
                onAuthorizeTool: onAuthorizeTool
            )
            .frame(
                maxWidth: contentMaxWidthForAssistant(availableWidth: maxBubbleWidth),
                alignment: .leading
            )
        }

        if !parts.body.isEmpty || !bodyPlacements.isEmpty {
            bodyContent(text: parts.body, placements: bodyPlacements)
        }
    }

    private func bodyContent(
        text: String,
        placements: [ChatToolActivityPlacement]
    ) -> some View {
        let contentWidth = contentMaxWidthForAssistant(availableWidth: maxBubbleWidth)
        return ChatToolInlineContentView(
            text: text,
            placements: placements,
            maxBubbleWidth: maxBubbleWidth,
            searchHighlightQuery: searchHighlightQuery,
            animateNewText: isStreamingResponse,
            developerModeEnabled: developerModeEnabled,
            onAuthorizeTool: onAuthorizeTool
        )
        .frame(maxWidth: contentWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
