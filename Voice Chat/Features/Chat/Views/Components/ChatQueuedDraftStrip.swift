//
//  ChatQueuedDraftStrip.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import SwiftUI

struct ChatQueuedDraftStrip: View {
    let drafts: [QueuedChatDraft]
    let rowHeight: CGFloat
    let stripHeight: CGFloat
    let accessoryTapSize: CGFloat
    let onMove: (IndexSet, Int) -> Void
    let onDelete: (UUID) -> Void
    let onEdit: (UUID) -> Void
    let onSend: (UUID) -> Void

    var body: some View {
        reorderableList
            .environment(\.defaultMinListRowHeight, rowHeight)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .frame(height: stripHeight)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.secondary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(ChatTheme.subtleStroke.opacity(0.2), lineWidth: 0.75)
            )
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    @ViewBuilder
    private var reorderableList: some View {
        #if os(macOS)
        draftList
        #else
        draftList.environment(\.editMode, .constant(.active))
        #endif
    }

    private var draftList: some View {
        List {
            ForEach(drafts) { draft in
                draftCard(for: draft)
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    .listRowSeparatorTint(ChatTheme.separator.opacity(0.28))
                    .listRowBackground(Color.clear)
            }
            .onMove(perform: onMove)
        }
    }

    private func draftCard(for draft: QueuedChatDraft) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                if draft.editingBaseMessageID != nil {
                    Image(systemName: "pencil")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if !draft.imageAttachments.isEmpty {
                    Image(systemName: "photo")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(draft.previewText)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 4)

            Button {
                onDelete(draft.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: accessoryTapSize, height: accessoryTapSize)
                    .background(
                        Circle()
                            .fill(Color.secondary.opacity(0.075))
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Delete")

            Menu {
                Button {
                    onEdit(draft.id)
                } label: {
                    Label("Edit Message", systemImage: "pencil")
                }

                Button {
                    onSend(draft.id)
                } label: {
                    Label("Send Now", systemImage: "arrow.turn.down.right")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: accessoryTapSize, height: accessoryTapSize)
                    .background(
                        Circle()
                            .fill(Color.secondary.opacity(0.075))
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .frame(height: rowHeight, alignment: .leading)
    }
}
