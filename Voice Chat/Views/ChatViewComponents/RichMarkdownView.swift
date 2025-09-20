//
//  RichMarkdownView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI
import MarkdownUI

struct RichMarkdownView: View {
    let markdown: String
    var body: some View {
        Markdown(markdown)
            .markdownImageProvider(.default)
            .textSelection(.enabled)
            .tint(ChatTheme.accent)
    }
}
