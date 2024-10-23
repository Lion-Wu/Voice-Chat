//
//  AudioPlayerView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import SwiftUI

struct AudioPlayerView: View {
    @EnvironmentObject var audioManager: GlobalAudioManager

    var body: some View {
        VStack {
            if audioManager.isLoading {
                HStack {
                    ProgressView()
                    Text("Loading audio...")
                    Spacer()
                    Button(action: {
                        audioManager.closeAudioPlayer()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                    }
                }
                .padding()
            } else {
                HStack {
                    // Always show Rewind Button
                    Button(action: {
                        audioManager.backward15Seconds()
                    }) {
                        Image(systemName: "gobackward.15")
                            .font(.title)
                    }

                    // Play/Pause Button
                    Button(action: {
                        audioManager.togglePlayback()
                    }) {
                        Image(systemName: audioManager.isAudioPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.largeTitle)
                    }

                    // Always show Fast-Forward Button
                    Button(action: {
                        audioManager.forward15Seconds()
                    }) {
                        Image(systemName: "goforward.15")
                            .font(.title)
                    }

                    // Current Time Display
                    withAnimation {
                        Text(formatTime(audioManager.currentTime))
                            .font(.system(.body, design: .rounded))
                            .bold()
                            .padding(.leading, 8)
                            .contentTransition(.numericText())
                            .transaction { t in
                                t.animation = .default
                            }
                    }

                    Spacer()

                    // Close Button
                    Button(action: {
                        audioManager.closeAudioPlayer()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                    }
                }
                .padding()
            }
        }
        .background(Color(UIColor.systemBackground).opacity(0.95))
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding()
        .transition(.move(edge: .top))
        .animation(.easeInOut, value: audioManager.isShowingAudioPlayer)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN, !time.isInfinite else { return "00:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
