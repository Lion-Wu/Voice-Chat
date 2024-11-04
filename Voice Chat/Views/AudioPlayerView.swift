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
                    Text("Loading...")
                        .font(.subheadline)
                    Spacer()
                    CloseButton(action: audioManager.closeAudioPlayer)
                }
                .padding()
            } else {
                HStack {
                    ControlButton(icon: "gobackward.15", action: audioManager.backward15Seconds)
                    ControlButton(icon: audioManager.isAudioPlaying ? "pause.circle.fill" : "play.circle.fill", action: audioManager.togglePlayback, isLarge: true)
                    ControlButton(icon: "goforward.15", action: audioManager.forward15Seconds)
                    Text(formatTime(audioManager.currentTime))
                        .font(.system(.body, design: .rounded))
                        .bold()
                        .padding(.leading, 8)
                        .contentTransition(.numericText())
                        .transaction { t in
                            t.animation = .default
                        }

                    if audioManager.isBuffering {
                        HStack(spacing: 5) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Buffering")
                                .font(.footnote)
                        }
                        .padding(.leading, 8)
                    }

                    Spacer()
                    CloseButton(action: audioManager.closeAudioPlayer)
                }
                .padding()

                if let errorMessage = audioManager.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }
            }
        }
        .background(BlurView().opacity(0.95))
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

    struct ControlButton: View {
        let icon: String
        let action: () -> Void
        var isLarge: Bool = false

        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(isLarge ? .largeTitle : .title)
            }
        }
    }

    struct CloseButton: View {
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
            }
        }
    }
}
