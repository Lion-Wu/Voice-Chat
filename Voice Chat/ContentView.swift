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
                .transition(.move(edge: .top)) // Add transition animation
                .animation(.easeInOut, value: audioManager.isShowingAudioPlayer)
                .zIndex(1)
            }
        }
    }
}

#Preview {
    ContentView()
}
