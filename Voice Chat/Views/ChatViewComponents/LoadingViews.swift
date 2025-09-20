//
//  LoadingViews.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI

struct LoadingIndicatorView: View {
    @State private var phase: CGFloat = 0
    var body: some View {
        HStack(spacing: 6) {
            Circle().frame(width: 8, height: 8).opacity(dotOpacity(0))
            Circle().frame(width: 8, height: 8).opacity(dotOpacity(0.2))
            Circle().frame(width: 8, height: 8).opacity(dotOpacity(0.4))
        }
        .foregroundColor(.secondary)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
    private func dotOpacity(_ delay: CGFloat) -> Double {
        let value = sin((phase + delay) * .pi)
        return Double(0.35 + 0.65 * max(0, value))
    }
}

struct AssistantAlignedLoadingBubble: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack {
                    LoadingIndicatorView()
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(PlatformColor.secondaryBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 6)
        #if os(macOS)
        .padding(.horizontal)
        #else
        .padding(.horizontal, 2)
        #endif
    }
}
