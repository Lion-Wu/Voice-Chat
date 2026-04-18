//
//  SettingsViewSupport.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import SwiftUI

#if os(macOS)
struct WindowSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct WindowSizeReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: WindowSizePreferenceKey.self, value: proxy.size)
        }
    }
}
#endif

extension View {
    @ViewBuilder
    func settingsActionButtonStyle() -> some View {
        #if os(macOS)
        self
            .buttonStyle(.bordered)
            .controlSize(.small)
        #else
        self
            .buttonStyle(.bordered)
            .controlSize(.regular)
        #endif
    }
}
