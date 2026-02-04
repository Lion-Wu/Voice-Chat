//
//  RichMarkdownView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

@preconcurrency import Foundation
import SwiftUI
import Markdown

struct RichMarkdownView: View {
    let markdown: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sizeCategory) private var sizeCategory

    var body: some View {
        MarkdownTextView(markdown: markdown, colorScheme: colorScheme, sizeCategory: sizeCategory)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    RichMarkdownView(markdown: """
    # Rich Markdown

    This view renders **Markdown** with inline `code`, lists, and tables.

    - Item 1
    - Item 2

    > Block quote

    ```swift
    struct Hello { let value = 42 }
    ```
    """)
    .padding()
    .background(AppBackgroundView())
    .frame(maxWidth: 520)
}
