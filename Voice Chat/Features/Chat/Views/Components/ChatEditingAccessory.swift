//
//  ChatEditingAccessory.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import SwiftUI

struct ChatEditingAccessory: View {
    let accessoryTapSize: CGFloat
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.orange)
                    .frame(width: 3, height: 18)

                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)

                Text("Edit Message")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: accessoryTapSize, height: accessoryTapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel editing and restore the conversation")
                .help("Cancel editing and restore the conversation")
            }
            .padding(.top, 8)
            .padding(.bottom, 6)
            .padding(.horizontal, 12)
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: EditingBannerHeightKey.self, value: proxy.size.height)
            }
        )
    }
}
