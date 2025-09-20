//
//  BubbleBackground.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI

struct BubbleBackground: ViewModifier {
    let isUser: Bool
    let contentPadding: EdgeInsets

    init(isUser: Bool, contentPadding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) {
        self.isUser = isUser
        self.contentPadding = contentPadding
    }

    func body(content: Content) -> some View {
        content
            .padding(contentPadding)
            .background(isUser ? AnyView(ChatTheme.userBubbleGradient) : AnyView(ChatTheme.systemBubbleFill))
            .overlay(
                RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous)
                    .stroke(ChatTheme.subtleStroke, lineWidth: isUser ? 0 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous))
            .shadow(color: ChatTheme.bubbleShadow, radius: 8, x: 0, y: 4)
    }
}

extension View {
    func bubbleStyle(isUser: Bool, contentPadding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) -> some View {
        modifier(BubbleBackground(isUser: isUser, contentPadding: contentPadding))
    }
}
