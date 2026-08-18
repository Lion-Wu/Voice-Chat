//
//  ChatMessageList.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.13.
//

import SwiftUI

@MainActor
struct ChatMessageList: View {
    @ObservedObject var visibleMessageController: ChatVisibleMessageController
    let branchRenderEpoch: Int
    let isLoading: Bool
    let isPriming: Bool
    let isToolContinuationLoading: Bool
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
    let isInitialContentReady: Bool
    let searchHighlightQuery: (ChatMessage) -> String?
    let onSelectText: (String) -> Void
    let onRegenerate: (ChatMessage) -> Void
    let onEditUserMessage: (ChatMessage) -> Void
    let onSwitchVersion: (ChatMessage) -> Void
    let onRetry: (ChatMessage) -> Void
    let onAuthorizeTool: (String, Bool) -> Void

    private var visibleMessages: [ChatMessage] {
        visibleMessageController.visibleMessages
    }

    private var fingerprintCache: [UUID: ContentFingerprint] {
        visibleMessageController.fingerprintCache
    }

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
        let visibleMessageIDs = Set(visibleMessages.map(\.id))
        let displayMessages = visibleMessages.filter {
            !shouldInlineErrorMessage($0, visibleMessageIDs: visibleMessageIDs)
        }
        let statusHostID = inlineStatusHostMessageID(in: displayMessages)
        let animationKey = ChatMessageListAnimationKey(
            messageIDs: displayMessages.map(\.id),
            standaloneStatus: standaloneStatusAnimationKey(
                statusHostID: statusHostID
            )
        )

        return VStack(spacing: 12) {
            ForEach(displayMessages, id: \.id) { message in
                messageRow(for: message, inlineStatusHostID: statusHostID)
                    .id(message.id)
                    .transition(ChatScrollContentMotion.transition)
            }

            if statusHostID == nil, isRetrying {
                AssistantAlignedRetryingBubble(
                    attempt: retryAttempt,
                    lastError: retryLastError,
                    maxBubbleWidth: availableMessageWidth
                )
                .transition(ChatScrollContentMotion.transition)
            } else if statusHostID == nil, isPriming || isToolContinuationLoading {
                AssistantAlignedLoadingBubble(maxBubbleWidth: availableMessageWidth)
                    .transition(ChatScrollContentMotion.transition)
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
        .animation(
            isInitialContentReady
                ? ChatScrollContentMotion.animation
                : nil,
            value: animationKey
        )
    }

    private func standaloneStatusAnimationKey(statusHostID: UUID?) -> String {
        guard statusHostID == nil else { return "inline" }
        if isRetrying {
            return "retry-\(retryAttempt)-\(retryLastError ?? "")"
        }
        return isPriming || isToolContinuationLoading ? "loading" : "none"
    }

    private func messageRow(for message: ChatMessage, inlineStatusHostID: UUID?) -> some View {
        let isStreamingAssistant = isLoading && !message.isUser && message.isActive
        let isInlineStatusHost = inlineStatusHostID == message.id
        let showButtons = !(isStreamingAssistant || isInlineStatusHost)
        let fingerprint = fingerprintCache[message.id] ?? ContentFingerprint.make(message.renderFingerprintSource)
        let highlightQuery = searchHighlightQuery(message)
        let searchHighlightID = highlightQuery == nil ? nil : activeSearchHighlightTargetID
        let messageActivityPlacements = mergedToolActivityPlacements(for: message)
        let messageActivities = mergedToolActivities(
            storedPlacements: message.toolActivityPlacements,
            runtimeActivities: messageToolActivities[message.id] ?? [],
            mergedPlacements: messageActivityPlacements
        )
        let inlineErrorMessage = inlineErrorMessage(for: message)
        let inlineErrorFingerprint = inlineErrorMessage.map { ContentFingerprint.make($0.content) }
        let key = VoiceMessageEqKey(
            id: message.id,
            isUser: message.isUser,
            isActive: message.isActive,
            imageAttachmentsFP: message.imageAttachmentsFingerprint,
            branchRenderEpoch: branchRenderEpoch,
            showActionButtons: showButtons,
            branchControlsEnabled: branchControlsEnabled,
            layoutWidth: availableMessageWidth.rounded(),
            contentFP: fingerprint,
            inlineErrorFP: inlineErrorFingerprint,
            inlineLoading: isInlineStatusHost && !isRetrying,
            inlineRetryAttempt: isInlineStatusHost && isRetrying ? retryAttempt : nil,
            inlineRetryLastError: isInlineStatusHost && isRetrying ? retryLastError : nil,
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
                inlineErrorMessage: inlineErrorMessage,
                inlineLoading: isInlineStatusHost && !isRetrying,
                inlineRetryAttempt: isInlineStatusHost && isRetrying ? retryAttempt : nil,
                inlineRetryLastError: isInlineStatusHost && isRetrying ? retryLastError : nil,
                toolActivities: messageActivities,
                toolActivityPlacements: messageActivityPlacements,
                searchHighlightQuery: highlightQuery,
                onSelectText: onSelectText,
                onRegenerate: onRegenerate,
                onEditUserMessage: onEditUserMessage,
                onSwitchVersion: onSwitchVersion,
                onRetry: onRetry,
                onAuthorizeTool: onAuthorizeTool
            )
        }
    }

    private func inlineStatusHostMessageID(in messages: [ChatMessage]) -> UUID? {
        ChatInlineStatusHostResolver.resolve(
            in: messages,
            hasTransientStatus: isRetrying || isPriming || isToolContinuationLoading
        )
    }

    private func shouldInlineErrorMessage(_ message: ChatMessage, visibleMessageIDs: Set<UUID>) -> Bool {
        guard message.content.hasPrefix("!error:"),
              let parent = message.parentMessage,
              !parent.isUser,
              visibleMessageIDs.contains(parent.id),
              parent.activeChildMessageID == message.id else {
            return false
        }
        return true
    }

    private func inlineErrorMessage(for message: ChatMessage) -> ChatMessage? {
        guard !message.isUser,
              !message.content.hasPrefix("!error:"),
              let activeChildMessageID = message.activeChildMessageID else {
            return nil
        }
        return message.childMessages.first {
            $0.id == activeChildMessageID && $0.content.hasPrefix("!error:")
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
        return merged
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
        for (index, placement) in mergedPlacements.enumerated() where placementOrder[placement.id] == nil {
            placementOrder[placement.id] = index
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

struct ChatMessageListAnimationKey: Equatable {
    let messageIDs: [UUID]
    let standaloneStatus: String
}

enum ChatInlineStatusHostResolver {
    static func resolve(
        in messages: [ChatMessage],
        hasTransientStatus: Bool
    ) -> UUID? {
        guard hasTransientStatus else { return nil }
        return messages.last(where: {
            !$0.isUser && $0.isActive && !$0.content.hasPrefix("!error:")
        })?.id
    }
}
