//
//  RawJSONPreviewBlock.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

struct RawJSONPreviewBlock: View {
    let title: LocalizedStringKey
    let value: JSONValue?
    let missingText: String

    @State private var previewText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let previewText {
                ScrollView(.horizontal) {
                    Text(previewText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if value == nil {
                Text(missingText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
                .task {
                    loadPreviewIfNeeded()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func loadPreviewIfNeeded() {
        guard previewText == nil else { return }
        previewText = value?.debugPreviewJSONString() ?? missingText
    }
}
