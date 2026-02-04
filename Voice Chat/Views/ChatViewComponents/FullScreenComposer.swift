//
//  FullScreenComposer.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI

#if os(iOS) || os(tvOS)
struct FullScreenComposer: View {
    @Binding var text: String
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            TextEditor(text: $text)
                .font(.system(size: 17))
                .padding()
                .navigationTitle("Full Screen Editor")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                            onDone()
                        }
                    }
                }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    @Previewable @State var text: String = """
    This is a full-screen editor preview.

    You can type multiple lines here.
    """

    FullScreenComposer(text: $text, onDone: {})
}
#endif
