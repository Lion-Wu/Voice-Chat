//
//  AudioPlayerView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import SwiftUI

struct AudioPlayerView: View {
    @EnvironmentObject var audioManager: GlobalAudioManager
    @State private var displayedCurrentTime: TimeInterval = 0
    @State private var displayedIsBuffering: Bool = false
    @State private var displayedIsRetrying: Bool = false
    @State private var displayedRetryAttempt: Int = 0
    @State private var displayedRetryLastError: String? = nil
    
    private var transportStatusText: String? {
        if audioManager.isLoading {
            if displayedIsRetrying {
                return String(
                    format: NSLocalizedString("Retrying (attempt %d)...", comment: "Shown while auto retry is waiting to reconnect"),
                    max(1, displayedRetryAttempt)
                )
            }
            return NSLocalizedString("Loading...", comment: "Shown while preparing audio playback")
        }
        if displayedIsBuffering {
            return NSLocalizedString("Buffering", comment: "Shown while waiting for more streamed audio")
        }
        if displayedIsRetrying {
            return String(
                format: NSLocalizedString("Retrying (attempt %d)...", comment: "Shown while auto retry is waiting to reconnect"),
                max(1, displayedRetryAttempt)
            )
        }
        return nil
    }
    
    private var transportDetailText: String? {
        guard (audioManager.isLoading || displayedIsRetrying) else { return nil }
        guard let last = displayedRetryLastError, !last.isEmpty else { return nil }
        return last
    }
    
    private var shouldDisableTransportControls: Bool {
        audioManager.isLoading && !audioManager.isAudioPlaying
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ControlButton(icon: "gobackward.15", action: audioManager.backward15Seconds)
                    .disabled(shouldDisableTransportControls)
                ControlButton(icon: audioManager.isAudioPlaying ? "pause.circle.fill" : "play.circle.fill",
                              action: audioManager.togglePlayback,
                              isLarge: true)
                    .disabled(shouldDisableTransportControls)
                ControlButton(icon: "goforward.15", action: audioManager.forward15Seconds)
                    .disabled(shouldDisableTransportControls)

                Text(formatTime(displayedCurrentTime))
                    .font(.system(.body, design: .rounded))
                    .bold()
                    .padding(.leading, 8)
                    .contentTransition(.numericText())
                    .transaction { t in
                        t.animation = .default
                    }

                HStack(spacing: 6) {
                    if transportStatusText != nil {
                        ProgressView()
                            .scaleEffect(0.7)
                            .transition(.opacity)
                    }
                    Text(transportStatusText ?? " ")
                        .font(.footnote)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 150, alignment: .leading)
                .opacity(transportStatusText == nil ? 0 : 1)
                .animation(.easeInOut(duration: 0.18), value: transportStatusText)

                Spacer(minLength: 8)
                CloseButton(action: audioManager.closeAudioPlayer)
            }
            .padding()
            .opacity(shouldDisableTransportControls ? 0.92 : 1)

            if let detail = transportDetailText {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }

            if let errorMessage = audioManager.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom)
                    .transition(.opacity)
            }
        }
        .background(BlurView().opacity(0.95))
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding()
        .transition(.move(edge: .top))
        .animation(.easeInOut, value: audioManager.isShowingAudioPlayer)
        .animation(.easeInOut(duration: 0.18), value: audioManager.isLoading)
        .animation(.easeInOut(duration: 0.18), value: displayedIsBuffering)
        .animation(.easeInOut(duration: 0.18), value: displayedIsRetrying)
        .onAppear {
            displayedCurrentTime = audioManager.currentTime
            displayedIsBuffering = audioManager.isBuffering
            displayedIsRetrying = audioManager.isRetrying
            displayedRetryAttempt = audioManager.retryAttempt
            displayedRetryLastError = audioManager.retryLastError
        }
        .onReceive(audioManager.currentTimePublisher) { newTime in
            displayedCurrentTime = newTime
        }
        .onReceive(audioManager.isBufferingPublisher) { newValue in
            displayedIsBuffering = newValue
        }
        .onReceive(audioManager.isRetryingPublisher) { newValue in
            displayedIsRetrying = newValue
        }
        .onReceive(audioManager.retryAttemptPublisher) { newValue in
            displayedRetryAttempt = newValue
        }
        .onReceive(audioManager.retryLastErrorPublisher) { newValue in
            displayedRetryLastError = newValue
        }
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
            .buttonStyle(PlainButtonStyle())
        }
    }

    struct CloseButton: View {
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

#Preview {
    let audio: GlobalAudioManager = {
        let audio = GlobalAudioManager()
        audio.isShowingAudioPlayer = true
        audio.isAudioPlaying = true
        audio.isLoading = false
        audio.currentTime = 75
        audio.isBuffering = false
        audio.isRetrying = false
        return audio
    }()

    AudioPlayerView()
        .environmentObject(audio)
        .frame(maxWidth: 520)
}
