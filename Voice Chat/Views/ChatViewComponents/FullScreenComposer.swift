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
                .navigationTitle(Text(L10n.Chat.fullScreenComposerTitle))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.General.close) {
                            dismiss()
                            onDone()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.General.done) {
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
