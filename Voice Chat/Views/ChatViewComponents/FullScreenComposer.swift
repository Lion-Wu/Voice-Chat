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
                .navigationTitle("全屏编辑")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
                            dismiss()
                            onDone()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
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
