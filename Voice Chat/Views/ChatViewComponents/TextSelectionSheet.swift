//
//  TextSelectionSheet.swift
//  Voice Chat
//
//  Created by Lion Wu on 2026/01/26.
//

import SwiftUI

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif

struct TextSelectionSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            selectionBody
            .navigationTitle("Select Text")
#if os(iOS) || os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
#endif
    }

    @ViewBuilder
    private var selectionBody: some View {
#if os(iOS)
        SelectableTextView(text: text)
#else
        ScrollView {
            Text(verbatim: text)
                .textSelection(.enabled)
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
#endif
    }
}

#if os(iOS)
private struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.contentInsetAdjustmentBehavior = .never
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.font = .systemFont(ofSize: 15)
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.text = text
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.disableTextDragAndDrop()
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard uiView.text != text else { return }
        uiView.text = text
        uiView.disableTextDragAndDrop()
    }
}
#endif

#Preview {
    TextSelectionSheet(text: """
    This is some selectable text.

    - You can copy it
    - Or select a range

    ```swift
    print(\"Hello, preview\")
    ```
    """)
}
