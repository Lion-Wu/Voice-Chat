//
//  ChatMessageList.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.13.
//

import SwiftUI

@MainActor
struct ChatMessageList: View {
    let visibleMessages: [ChatMessage]
    let fingerprintCache: [UUID: ContentFingerprint]
    let branchRenderEpoch: Int
    let isLoading: Bool
    let isPriming: Bool
    let isRetrying: Bool
    let retryAttempt: Int
    let retryLastError: String?
    let messageToolActivities: [UUID: [ChatToolActivity]]
    let messageToolActivityPlacements: [UUID: [ChatToolActivityPlacement]]
    let branchControlsEnabled: Bool
    let developerModeEnabled: Bool
    let activeSearchHighlightTargetID: UUID?
    let availableMessageWidth: CGFloat
    let messageListBottomInset: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let scrollTargetsEnabled: Bool
    let searchHighlightQuery: (ChatMessage) -> String?
    let onSelectText: (String) -> Void
    let onRegenerate: (ChatMessage) -> Void
    let onEditUserMessage: (ChatMessage) -> Void
    let onSwitchVersion: (ChatMessage) -> Void
    let onRetry: (ChatMessage) -> Void

    var body: some View {
        let content = core
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .frame(maxWidth: contentColumnMaxWidth(availableWidth: availableMessageWidth))
            .frame(maxWidth: .infinity, alignment: .center)

        if scrollTargetsEnabled {
            content.scrollTargetLayout()
        } else {
            content
        }
    }

    private var core: some View {
        let visibleMessageIDs = visibleMessages.map(\.id)

        return VStack(spacing: 12) {
            ForEach(visibleMessages, id: \.id) { message in
                messageRow(for: message)
                    .id(message.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if isRetrying {
                AssistantAlignedRetryingBubble(
                    attempt: retryAttempt,
                    lastError: retryLastError,
                    maxBubbleWidth: availableMessageWidth
                )
            } else if isPriming {
                AssistantAlignedLoadingBubble(maxBubbleWidth: availableMessageWidth)
            }

            Color.clear
                .frame(height: messageListBottomInset)
                .id(ScrollTarget.bottom)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: BottomAnchorKey.self,
                            value: proxy.frame(in: .named("ChatScroll")).maxY
                        )
                    }
                )
        }
        .background(
            GeometryReader { contentGeo in
                Color.clear.preference(key: ContentHeightKey.self, value: contentGeo.size.height)
            }
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: visibleMessageIDs)
    }

    private func messageRow(for message: ChatMessage) -> some View {
        let isStreamingAssistant = isLoading && !message.isUser && message.isActive
        let showButtons = !isStreamingAssistant
        let fingerprint = fingerprintCache[message.id] ?? ContentFingerprint.make(message.content)
        let highlightQuery = searchHighlightQuery(message)
        let searchHighlightID = highlightQuery == nil ? nil : activeSearchHighlightTargetID
        let messageActivityPlacements = mergedToolActivityPlacements(for: message)
        let messageActivities = mergedToolActivities(
            storedPlacements: message.toolActivityPlacements,
            runtimeActivities: messageToolActivities[message.id] ?? [],
            mergedPlacements: messageActivityPlacements
        )
        let key = VoiceMessageEqKey(
            id: message.id,
            isUser: message.isUser,
            isActive: message.isActive,
            imageAttachmentsFP: message.imageAttachmentsFingerprint,
            branchRenderEpoch: branchRenderEpoch,
            showActionButtons: showButtons,
            branchControlsEnabled: branchControlsEnabled,
            contentFP: fingerprint,
            toolActivityPlacements: messageActivityPlacements,
            developerModeEnabled: developerModeEnabled,
            searchHighlightID: searchHighlightID
        )

        return EquatableRender(value: key) {
            VoiceMessageView(
                message: message,
                isStreamingAssistant: isStreamingAssistant,
                showActionButtons: showButtons,
                branchControlsEnabled: branchControlsEnabled,
                developerModeEnabled: developerModeEnabled,
                maxBubbleWidth: availableMessageWidth,
                contentFingerprint: fingerprint,
                toolActivities: messageActivities,
                toolActivityPlacements: messageActivityPlacements,
                searchHighlightQuery: highlightQuery,
                onSelectText: onSelectText,
                onRegenerate: onRegenerate,
                onEditUserMessage: onEditUserMessage,
                onSwitchVersion: onSwitchVersion,
                onRetry: onRetry
            )
        }
    }

    private func mergedToolActivityPlacements(for message: ChatMessage) -> [ChatToolActivityPlacement] {
        var merged = message.toolActivityPlacements
        for placement in messageToolActivityPlacements[message.id] ?? [] {
            if let index = merged.firstIndex(where: { $0.id == placement.id }) {
                merged[index] = placement
            } else {
                merged.append(placement)
            }
        }
        return merged.sorted {
            if $0.offset == $1.offset {
                return $0.id < $1.id
            }
            return $0.offset < $1.offset
        }
    }

    private func mergedToolActivities(
        storedPlacements: [ChatToolActivityPlacement],
        runtimeActivities: [ChatToolActivity],
        mergedPlacements: [ChatToolActivityPlacement]
    ) -> [ChatToolActivity] {
        var activities = storedPlacements.map(\.activity)
        for activity in runtimeActivities {
            if let index = activities.firstIndex(where: { $0.id == activity.id }) {
                activities[index] = activity
            } else {
                activities.append(activity)
            }
        }
        var placementOrder: [String: Int] = [:]
        for placement in mergedPlacements where placementOrder[placement.id] == nil {
            placementOrder[placement.id] = placement.offset
        }
        return activities.sorted {
            let lhs = placementOrder[$0.id] ?? Int.max
            let rhs = placementOrder[$1.id] ?? Int.max
            if lhs == rhs {
                return $0.id < $1.id
            }
            return lhs < rhs
        }
    }
}
