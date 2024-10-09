//
//  ContentView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var audioManager: GlobalAudioManager

    var body: some View {
        ZStack {
            HomeView()
            if audioManager.isShowingAudioPlayer {
                VStack {
                    AudioPlayerView()
                    Spacer()
                }
                .transition(.move(edge: .top)) // 添加过渡动画
                .animation(.easeInOut, value: audioManager.isShowingAudioPlayer) // 添加动画
                .zIndex(1)
            }
        }
    }
}

#Preview {
    ContentView()
}
