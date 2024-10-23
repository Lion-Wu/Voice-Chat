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
                    Text("正在加载...")
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
                    // Rewind Button
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

                    // Fast-Forward Button
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

                    // Buffering Indicator
                    if audioManager.isBuffering {
                        HStack(spacing: 5) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("缓冲中")
                                .font(.footnote)
                        }
                        .padding(.leading, 8)
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

                // Error Message Display
                if let errorMessage = audioManager.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }
            }
        }
        .background(Color(UIColor.systemBackground).opacity(0.95))
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding()
        .transition(.move(edge: .top))
        .animation(.easeInOut, value: audioManager.isShowingAudioPlayer)
    }

    private func formatTime(_ currentTime: TimeInterval) -> String {
        guard !currentTime.isNaN, !currentTime.isInfinite else { return "00:00" }
        let currentMinutes = Int(currentTime) / 60
        let currentSeconds = Int(currentTime) % 60

        return String(format: "%02d:%02d", currentMinutes, currentSeconds)
    }
}
