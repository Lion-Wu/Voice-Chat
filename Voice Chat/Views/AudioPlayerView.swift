//
//  AudioPlayerView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import SwiftUI

extension Animation {
    static let audioPlayerVisibility = Animation.spring(response: 0.46, dampingFraction: 0.86, blendDuration: 0.18)
}

struct AudioPlayerView: View {
    @EnvironmentObject var audioManager: GlobalAudioManager
    @State private var displayedCurrentTime: TimeInterval = 0
    @State private var displayedTotalDuration: TimeInterval = 0
    @State private var displayedIsPlaybackFullyLoaded: Bool = true
    @State private var displayedIsBuffering: Bool = false
    @State private var displayedIsRetrying: Bool = false
    @State private var displayedRetryAttempt: Int = 0
    @State private var displayedRetryLastError: String? = nil

    private let cardCornerRadius: CGFloat = 22

    private var statusCaptionText: String? {
        if displayedIsRetrying {
            return String(
                format: NSLocalizedString("Retrying (attempt %d)...", comment: "Shown while auto retry is waiting to reconnect"),
                max(1, displayedRetryAttempt)
            )
        }
        return nil
    }

    private var transportDetailText: String? {
        guard displayedIsRetrying else { return nil }
        guard let last = displayedRetryLastError, !last.isEmpty else { return nil }
        return last
    }

    private var shouldDisableTransportControls: Bool {
        audioManager.isLoading && !audioManager.isAudioPlaying
    }

    private var hasLoadedAudioChunk: Bool {
        audioManager.audioChunks.contains { $0 != nil }
    }

    private var hasSeekableAudio: Bool {
        visibleTotalDuration > 0.0005 || audioManager.chunkDurations.contains { $0 > 0.0005 }
    }

    private var shouldDisableSeekControls: Bool {
        shouldDisableTransportControls || !hasSeekableAudio
    }

    private var showsInitialLoadingView: Bool {
        audioManager.isLoading && !hasLoadedAudioChunk
    }

    private var showsDurationLoadingIndicator: Bool {
        !displayedIsPlaybackFullyLoaded || !audioManager.isPlaybackFullyLoaded
    }

    private var showsPlaybackBufferingSpinner: Bool {
        audioManager.isAudioPlaying && (
            showsInitialLoadingView ||
            displayedIsBuffering ||
            audioManager.isBuffering
        )
    }

    private var visibleCurrentTime: TimeInterval {
        let current = audioManager.currentTime
        if displayedCurrentTime <= 0.0001, current > 0.0001 {
            return current
        }
        return displayedCurrentTime
    }

    private var visibleTotalDuration: TimeInterval {
        let total = max(displayedTotalDuration, audioManager.totalDuration)
        guard total.isFinite else { return 0 }
        return max(0, total)
    }

    private var playbackProgress: CGFloat {
        let denominator = max(visibleTotalDuration, visibleCurrentTime, 0.001)
        let fraction = visibleCurrentTime / denominator
        return CGFloat(min(max(fraction, 0), 1))
    }

    var body: some View {
        playerCard
    }

    private var playerCard: some View {
        VStack(spacing: 6) {
            headerRow
            progressBar
            controlsRow

            if let detail = transportDetailText {
                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            if let errorMessage = audioManager.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Color.red.opacity(0.10))
                    )
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 520)
        .background {
            BlurView()
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.09), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.16), value: displayedIsPlaybackFullyLoaded)
        .animation(.easeInOut(duration: 0.16), value: displayedIsBuffering)
        .animation(.easeInOut(duration: 0.16), value: displayedIsRetrying)
        .onAppear {
            displayedCurrentTime = audioManager.currentTime
            displayedTotalDuration = audioManager.totalDuration
            displayedIsPlaybackFullyLoaded = audioManager.isPlaybackFullyLoaded
            displayedIsBuffering = audioManager.isBuffering
            displayedIsRetrying = audioManager.isRetrying
            displayedRetryAttempt = audioManager.retryAttempt
            displayedRetryLastError = audioManager.retryLastError
        }
        .onReceive(audioManager.currentTimePublisher) { newTime in
            displayedCurrentTime = newTime
        }
        .onReceive(audioManager.totalDurationPublisher) { newValue in
            displayedTotalDuration = newValue
        }
        .onReceive(audioManager.isPlaybackFullyLoadedPublisher) { newValue in
            displayedIsPlaybackFullyLoaded = newValue
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

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 5) {
                    Text(formatTime(visibleCurrentTime))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                        .contentTransition(.numericText())
                        .transaction { t in
                            t.animation = .default
                        }

                    Text("/")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.secondary.opacity(0.7))

                    durationAccessory
                }

                if let status = statusCaptionText {
                    Text(status)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CloseButton {
                audioManager.closeAudioPlayer()
            }
        }
    }

    private var controlsRow: some View {
        HStack {
            HStack(spacing: 12) {
                ControlButton(icon: "gobackward.15") {
                    audioManager.backward15Seconds()
                }
                .disabled(shouldDisableSeekControls)
                .opacity(shouldDisableSeekControls ? 0.42 : 1)

                PlaybackToggleButton(
                    isLoading: showsPlaybackBufferingSpinner,
                    isPlaying: audioManager.isAudioPlaying,
                    action: {
                        audioManager.togglePlayback()
                    }
                )
                .disabled(shouldDisableTransportControls)

                ControlButton(icon: "goforward.15") {
                    audioManager.forward15Seconds()
                }
                .disabled(shouldDisableSeekControls)
                .opacity(shouldDisableSeekControls ? 0.42 : 1)
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var durationAccessory: some View {
        HStack(spacing: 6) {
            Text(formatTime(max(visibleTotalDuration, visibleCurrentTime)))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .contentTransition(.numericText())
                .transaction { t in
                    t.animation = .default
                }
            

            if showsDurationLoadingIndicator {
                LoadingIndicatorView(tint: Color.accentColor, dotSize: 4, spacing: 3)
                    .frame(height: 8)
                    .padding(.leading, 2)
                    .transition(.opacity)
            }
        }
    }

    private var progressBar: some View {
        Capsule(style: .continuous)
            .fill(Color.primary.opacity(0.10))
            .overlay {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        if showsDurationLoadingIndicator {
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.10))
                        }

                        Capsule(style: .continuous)
                            .fill(Color.accentColor)
                            .frame(
                                width: max(
                                    playbackProgress > 0 ? 5 : 0,
                                    geometry.size.width * playbackProgress
                                )
                            )
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                }
            }
            .clipShape(Capsule(style: .continuous))
            .frame(height: 4)
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

        var body: some View {
            Button {
                action()
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    struct PlaybackToggleButton: View {
        let isLoading: Bool
        let isPlaying: Bool
        let action: () -> Void

        var body: some View {
            Button {
                action()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.accentColor)

                    if isLoading {
                        LoadingIndicatorView(tint: .white, dotSize: 4.5, spacing: 3)
                            .frame(height: 10)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 42, height: 42)
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.24), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    struct CloseButton: View {
        let action: () -> Void

        var body: some View {
            Button {
                action()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

#Preview("Loaded") {
    let audio: GlobalAudioManager = {
        let audio = GlobalAudioManager()
        audio.isShowingAudioPlayer = true
        audio.isAudioPlaying = true
        audio.isLoading = false
        audio.currentTime = 75
        audio.totalDuration = 214
        audio.isPlaybackFullyLoaded = true
        audio.isBuffering = false
        audio.isRetrying = false
        return audio
    }()

    AudioPlayerView()
        .environmentObject(audio)
        .frame(maxWidth: 520)
}

#Preview("Receiving Audio") {
    let audio: GlobalAudioManager = {
        let audio = GlobalAudioManager()
        audio.isShowingAudioPlayer = true
        audio.isAudioPlaying = true
        audio.isLoading = false
        audio.currentTime = 75
        audio.totalDuration = 128
        audio.isPlaybackFullyLoaded = false
        audio.isBuffering = false
        audio.isRetrying = false
        return audio
    }()

    AudioPlayerView()
        .environmentObject(audio)
        .frame(maxWidth: 520)
}

#Preview("Waiting For First Audio") {
    let audio: GlobalAudioManager = {
        let audio = GlobalAudioManager()
        audio.isShowingAudioPlayer = true
        audio.isAudioPlaying = true
        audio.isLoading = true
        audio.currentTime = 0
        audio.totalDuration = 0
        audio.isPlaybackFullyLoaded = false
        audio.isBuffering = false
        audio.isRetrying = false
        return audio
    }()

    AudioPlayerView()
        .environmentObject(audio)
        .frame(maxWidth: 520)
}
