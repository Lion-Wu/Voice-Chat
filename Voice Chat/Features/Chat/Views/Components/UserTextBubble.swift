//
//  UserTextBubble.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

struct UserTextBubble: View {
    let text: String
    let attachments: [ChatImageAttachment]
    let maxBubbleWidth: CGFloat?
    let searchHighlightQuery: String?
    let onPreviewImage: (ChatImageAttachment) -> Void
    @State private var expanded = false
    private let maxCharacters = 1000

    private var shouldShowFullText: Bool {
        expanded || searchHighlightQuery != nil || text.count <= maxCharacters
    }

    var body: some View {
        let display = shouldShowFullText ? text : (String(text.prefix(maxCharacters)) + "...")

        VStack(alignment: .trailing, spacing: 6) {
            if !attachments.isEmpty {
                ChatImageAttachmentStrip(
                    attachments: attachments,
                    removable: false,
                    maxItemSize: 160,
                    onPreview: onPreviewImage,
                    onRemove: nil,
                    horizontalAlignment: .trailing
                )
                .frame(maxWidth: contentMaxWidthForUser(availableWidth: maxBubbleWidth), alignment: .trailing)
            }

            if !display.isEmpty {
                Text(highlightedUserText(display))
                    .fixedSize(horizontal: false, vertical: true)
                    .bubbleStyle(isUser: true)
                    .frame(maxWidth: contentMaxWidthForUser(availableWidth: maxBubbleWidth), alignment: .trailing)
            }

            if text.count > maxCharacters {
                Button(expanded ? "Collapse" : "Show Full Message") {
                    withAnimation(.easeInOut) { expanded.toggle() }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)
                .frame(maxWidth: contentMaxWidthForUser(availableWidth: maxBubbleWidth), alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func highlightedUserText(_ display: String) -> AttributedString {
        var attributed = AttributedString(display)
        attributed.foregroundColor = .white

        let query = searchHighlightQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else { return attributed }

        var searchRange = attributed.startIndex..<attributed.endIndex
        while let foundRange = attributed[searchRange].range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            attributed[foundRange].backgroundColor = Color.yellow.opacity(0.68)
            attributed[foundRange].foregroundColor = .black
            guard foundRange.upperBound < attributed.endIndex else { break }
            searchRange = foundRange.upperBound..<attributed.endIndex
        }

        return attributed
    }
}
