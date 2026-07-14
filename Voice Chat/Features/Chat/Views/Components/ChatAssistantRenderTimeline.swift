//
//  ChatAssistantRenderTimeline.swift
//  Voice Chat
//
//  Created by Codex on 2026/7/10.
//

import Foundation

struct ChatAssistantRenderBlock: Identifiable, Equatable {
    let id: String
    let kind: ChatAssistantSegmentKind
    var text: String
    var toolActivityPlacements: [ChatToolActivityPlacement]
}

enum ChatAssistantRenderBlockBuilder {
    static func blocks(
        segments: [ChatAssistantSegment],
        placements: [ChatToolActivityPlacement]
    ) -> [ChatAssistantRenderBlock] {
        guard !segments.isEmpty else { return [] }

        var rawBlocks = segments.enumerated().map { index, segment in
            ChatAssistantRenderBlock(
                id: "assistant-segment-\(index)-\(segment.kind.rawValue)-\(segment.itemID ?? "")",
                kind: segment.kind,
                text: segment.text,
                toolActivityPlacements: []
            )
        }

        for placement in placements {
            guard let anchor = placement.assistantSegmentAnchor else { continue }
            let blockIndex = min(anchor.segmentIndex, rawBlocks.count - 1)
            let localOffset = min(anchor.characterOffset, rawBlocks[blockIndex].text.count)
            rawBlocks[blockIndex].toolActivityPlacements.append(
                rebased(placement, offset: localOffset)
            )
        }

        return mergingAdjacentReasoningBlocks(rawBlocks)
    }

    private static func mergingAdjacentReasoningBlocks(
        _ blocks: [ChatAssistantRenderBlock]
    ) -> [ChatAssistantRenderBlock] {
        var mergedBlocks: [ChatAssistantRenderBlock] = []
        mergedBlocks.reserveCapacity(blocks.count)

        for block in blocks {
            guard block.kind == .reasoning,
                  let previousIndex = mergedBlocks.indices.last,
                  mergedBlocks[previousIndex].kind == .reasoning else {
                mergedBlocks.append(block)
                continue
            }

            let textOffset = mergedBlocks[previousIndex].text.count
            mergedBlocks[previousIndex].text += block.text
            mergedBlocks[previousIndex].toolActivityPlacements.append(
                contentsOf: block.toolActivityPlacements.map {
                    rebased($0, offset: textOffset + $0.offset)
                }
            )
        }

        return mergedBlocks
    }

    private static func rebased(
        _ placement: ChatToolActivityPlacement,
        offset: Int
    ) -> ChatToolActivityPlacement {
        ChatToolActivityPlacement(
            activity: placement.activity,
            scope: placement.scope,
            offset: offset,
            assistantSegmentAnchor: placement.assistantSegmentAnchor
        )
    }
}
