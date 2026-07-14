//
//  ChatToolInlineContentView.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.23.
//

import SwiftUI

struct ChatToolInlineContentView: View {
    let text: String
    let placements: [ChatToolActivityPlacement]
    let maxBubbleWidth: CGFloat?
    var searchHighlightQuery: String? = nil
    var animateNewText = false
    var developerModeEnabled = false
    var onAuthorizeTool: ((String, Bool) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if placements.isEmpty {
                if !text.isEmpty {
                    textView(text)
                }
            } else {
                ForEach(segments) { segment in
                    switch segment.kind {
                    case let .text(value):
                        textView(value)
                    case let .tools(placements):
                        ToolActivityBubble(
                            activities: placements.map(\.activity),
                            maxBubbleWidth: maxBubbleWidth,
                            isEmbeddedInMessage: true,
                            developerModeEnabled: developerModeEnabled,
                            onAuthorize: onAuthorizeTool
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func textView(_ value: String) -> some View {
        RichMarkdownView(
            markdown: value,
            searchHighlightQuery: searchHighlightQuery,
            animateNewText: animateNewText
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var segments: [ChatToolInlineSegment] {
        ChatToolInlineSegmentBuilder.segments(text: text, placements: placements)
    }
}

struct ChatToolInlineSegment: Identifiable, Equatable {
    enum Kind: Equatable {
        case text(String)
        case tools([ChatToolActivityPlacement])
    }

    let id: String
    let kind: Kind
}

enum ChatToolInlineSegmentBuilder {
    static func segments(
        text: String,
        placements: [ChatToolActivityPlacement]
    ) -> [ChatToolInlineSegment] {
        var output: [ChatToolInlineSegment] = []
        var cursor = 0
        var previousBoundaryID = "start"
        let length = text.count

        for group in ChatToolActivityPlacementGrouper.groups(placements) {
            let offset = min(max(group.offset, 0), length)
            if cursor < offset {
                appendTextSegment(
                    textSlice(text, from: cursor, to: offset),
                    startOffset: cursor,
                    previousBoundaryID: previousBoundaryID,
                    nextBoundaryID: group.id,
                    to: &output
                )
            }
            output.append(ChatToolInlineSegment(
                id: "tool-\(group.id)",
                kind: .tools(group.placements)
            ))
            cursor = offset
            previousBoundaryID = group.id
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

struct ChatToolActivityPlacementGroup: Identifiable, Equatable {
    let id: String
    let offset: Int
    var placements: [ChatToolActivityPlacement]
}

enum ChatToolActivityPlacementGrouper {
    static func groups(
        _ placements: [ChatToolActivityPlacement]
    ) -> [ChatToolActivityPlacementGroup] {
        let sorted = placements.enumerated().sorted { lhs, rhs in
            if lhs.element.offset == rhs.element.offset {
                return lhs.offset < rhs.offset
            }
            return lhs.element.offset < rhs.element.offset
        }.map(\.element)
        var groups: [ChatToolActivityPlacementGroup] = []

        for placement in sorted {
            if let lastIndex = groups.indices.last,
               groups[lastIndex].offset == placement.offset,
               groups[lastIndex].placements.last?.scope == placement.scope {
                groups[lastIndex].placements.append(placement)
            } else {
                groups.append(ChatToolActivityPlacementGroup(
                    id: placement.id,
                    offset: placement.offset,
                    placements: [placement]
                ))
            }
        }
        return groups
    }
}
