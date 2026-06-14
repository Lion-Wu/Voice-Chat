//
//  AutoSizingTextEditorPreviews.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

private struct ComposerChromePreview: View {
    @State private var text: String = ""
    @State private var height: CGFloat = InputMetrics.defaultHeight

    @ViewBuilder
    private var editorView: some View {
        #if os(macOS)
        AutoSizingTextEditor(
            text: $text,
            height: $height,
            placeholder: "在此输入消息...",
            maxLines: 6,
            onOverflowChange: { _ in },
            onCommit: {}
        )
        #else
        AutoSizingTextEditor(
            text: $text,
            height: $height,
            placeholder: "在此输入消息...",
            maxLines: 6,
            onOverflowChange: { _ in }
        )
        #endif
    }

    var body: some View {
        HStack(alignment: .center, spacing: InputMetrics.composerRowSpacing) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ChatTheme.accent)
                .frame(width: 30, height: 30)

            editorView
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .padding(.vertical, InputMetrics.composerOuterV)
                .padding(.leading, InputMetrics.composerOuterLeading)
                .padding(.trailing, 6)

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ChatTheme.accent)
                .frame(minHeight: 38)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

#Preview("Editor Placeholder") {
    @Previewable @State var text: String = ""
    @Previewable @State var height: CGFloat = InputMetrics.defaultHeight

    VStack(alignment: .leading, spacing: 12) {
        #if os(macOS)
        AutoSizingTextEditor(
            text: $text,
            height: $height,
            placeholder: "在此输入消息...",
            maxLines: 6,
            onOverflowChange: { _ in },
            onCommit: {}
        )
        #else
        AutoSizingTextEditor(
            text: $text,
            height: $height,
            placeholder: "在此输入消息...",
            maxLines: 6,
            onOverflowChange: { _ in }
        )
        #endif
    }
    .padding(16)
    .frame(width: 420, alignment: .leading)
    .background(
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.thinMaterial)
    )
    .padding()
    .background(AppBackgroundView())
}

#Preview("Composer macOS", traits: .fixedLayout(width: 420, height: 116)) {
    ComposerChromePreview()
        .padding()
        .background(AppBackgroundView())
}

#Preview("Composer iPhone Width", traits: .fixedLayout(width: 390, height: 116)) {
    ComposerChromePreview()
        .padding()
        .background(AppBackgroundView())
}
