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
                .navigationTitle(L10n.Common.fullScreenEditorTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.Common.close) {
                            dismiss()
                            onDone()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.Common.done) {
                            dismiss()
                            onDone()
                        }
                    }
                }
        }
        .ignoresSafeArea()
    }
}
#endif
