//
//  ChatToolInlineContentView.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.23.
//

import SwiftUI

enum ChatToolInlineTextStyle: Equatable {
    case markdown
    case thinking(fontSize: CGFloat)
}

struct ChatToolInlineContentView: View {
    let text: String
    let placements: [ChatToolActivityPlacement]
    let textStyle: ChatToolInlineTextStyle
    let maxBubbleWidth: CGFloat?
    var searchHighlightQuery: String? = nil
    var animateNewText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments) { segment in
                switch segment.kind {
                case let .text(value):
                    textView(value)
                case let .tool(placement):
                    ToolActivityBubble(
                        activities: [placement.activity],
                        maxBubbleWidth: maxBubbleWidth,
                        isEmbeddedInMessage: true
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func textView(_ value: String) -> some View {
        switch textStyle {
        case .markdown:
            RichMarkdownView(
                markdown: value,
                searchHighlightQuery: searchHighlightQuery,
                animateNewText: animateNewText
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .thinking(fontSize):
            Text(value)
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var segments: [ChatToolInlineSegment] {
        ChatToolInlineSegmentBuilder.segments(text: text, placements: placements)
    }
}

struct ChatToolInlineSegment: Identifiable, Equatable {
    enum Kind: Equatable {
        case text(String)
        case tool(ChatToolActivityPlacement)
    }

    let id: String
    let kind: Kind
}

enum ChatToolInlineSegmentBuilder {
    static func segments(
        text: String,
        placements: [ChatToolActivityPlacement]
    ) -> [ChatToolInlineSegment] {
        let sorted = placements.sorted {
            if $0.offset == $1.offset {
                return $0.id < $1.id
            }
            return $0.offset < $1.offset
        }
        var output: [ChatToolInlineSegment] = []
        var cursor = 0
        var previousBoundaryID = "start"
        let length = text.count

        for placement in sorted {
            let offset = min(max(placement.offset, 0), length)
            if cursor < offset {
                appendTextSegment(
                    textSlice(text, from: cursor, to: offset),
                    startOffset: cursor,
                    previousBoundaryID: previousBoundaryID,
                    nextBoundaryID: placement.id,
                    to: &output
                )
            }
            output.append(ChatToolInlineSegment(
                id: "tool-\(placement.id)",
                kind: .tool(placement)
            ))
            cursor = offset
            previousBoundaryID = placement.id
        }

        if cursor < length {
            appendTextSegment(
                textSlice(text, from: cursor, to: length),
                startOffset: cursor,
                previousBoundaryID: previousBoundaryID,
                nextBoundaryID: "end",
                to: &output
            )
        }
        return output
    }

    private static func appendTextSegment(
        _ value: String,
        startOffset: Int,
        previousBoundaryID: String,
        nextBoundaryID: String,
        to output: inout [ChatToolInlineSegment]
    ) {
        guard !value.isEmpty else { return }
        output.append(ChatToolInlineSegment(
            id: "text-\(startOffset)-\(previousBoundaryID)-\(nextBoundaryID)",
            kind: .text(value)
        ))
    }

    private static func textSlice(_ text: String, from start: Int, to end: Int) -> String {
        guard start < end else { return "" }
        let lower = text.index(text.startIndex, offsetBy: start)
        let upper = text.index(text.startIndex, offsetBy: end)
        return String(text[lower..<upper])
    }
}
