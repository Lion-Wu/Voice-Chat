//
//  ChatViewSupport.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.13.
//

import SwiftUI
import Foundation

/// Wrapper that invalidates the view only when the equatable value changes.
@MainActor
struct EquatableRender<Value: Equatable & Sendable, Content: View>: View, Equatable {
    nonisolated static func == (lhs: EquatableRender<Value, Content>, rhs: EquatableRender<Value, Content>) -> Bool {
        lhs.value == rhs.value
    }

    nonisolated let value: Value
    let content: () -> Content
    var body: some View { content() }
}

/// Equatable key for message rendering that keeps only UI-relevant fields.
struct VoiceMessageEqKey: Equatable, Sendable {
    let id: UUID
    let isUser: Bool
    let isActive: Bool
    let imageAttachmentsFP: Int
    let branchRenderEpoch: Int
    let showActionButtons: Bool
    let branchControlsEnabled: Bool
    let layoutWidth: CGFloat
    let contentFP: ContentFingerprint
    let inlineErrorFP: ContentFingerprint?
    let inlineLoading: Bool
    let inlineRetryAttempt: Int?
    let inlineRetryLastError: String?
    let toolActivityPlacements: [ChatToolActivityPlacement]
    let developerModeEnabled: Bool
    let searchHighlightID: UUID?
}

enum ScrollTarget: Hashable {
    case bottom
}

struct TextSelectionSheetItem: Identifiable {
    let id = UUID()
    let text: String
}

enum ChatAlert: Identifiable {
    case startVoiceModeInterrupt
    case unsupportedImageSend
    case deleteQueuedDraft(UUID)

    var id: String {
        switch self {
        case .startVoiceModeInterrupt:
            return "startVoiceModeInterrupt"
        case .unsupportedImageSend:
            return "unsupportedImageSend"
        case .deleteQueuedDraft(let draftID):
            return "deleteQueuedDraft-\(draftID.uuidString)"
        }
    }
}

struct ChatViewPlatformTitleModifier: ViewModifier {
    let title: String

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content.navigationTitle(title)
        #elseif os(iOS) || os(tvOS)
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        #else
        content
        #endif
    }
}
