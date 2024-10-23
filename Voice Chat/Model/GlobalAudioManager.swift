//
//  GlobalAudioManager.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//


import Foundation
import AVFoundation
import UIKit
import Combine

class GlobalAudioManager: NSObject, ObservableObject {
    static let shared = GlobalAudioManager()

    @Published var isShowingAudioPlayer = false
    @Published var isAudioPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isLoading = false

    private var audioPlayer: AVAudioPlayer?
    private var audioTimer: Timer?

    var mediaType: String = "aac" // Default to AAC format

    func getVoice(for text: String) {
        // Reset before starting a new request
        resetPlayer()

        isLoading = true
        isShowingAudioPlayer = true

        // Build TTS request URL
        guard let url = constructTTSURL() else {
            print("Unable to construct TTS URL")
            isLoading = false
            isShowingAudioPlayer = false
            return
        }

        // Fetch audio data via standard POST request
        fetchAudio(from: url, text: text)
    }

    // Construct TTS URL
    private func constructTTSURL() -> URL? {
        // Fetch the latest server settings
        let serverSettings = SettingsManager.shared.serverSettings
        let urlString = "\(serverSettings.serverAddress)/tts"
        return URL(string: urlString)
    }

    // Fetch audio via standard POST request
    private func fetchAudio(from url: URL, text: String) {
        // Fetch the latest settings
        let settingsManager = SettingsManager.shared
        let modelSettings = settingsManager.modelSettings
        let serverSettings = settingsManager.serverSettings

        // Prepare parameters with streaming_mode set to false
        let parameters: [String: Any] = [
            "text": text,
            "text_lang": serverSettings.textLang,
            "ref_audio_path": serverSettings.refAudioPath,
            "prompt_text": serverSettings.promptText,
            "prompt_lang": serverSettings.promptLang,
            "text_split_method": modelSettings.autoSplit,
            "batch_size": 4,
            "streaming_mode": false,  // Disable streaming
            "media_type": mediaType
        ]

        // Convert parameters to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: parameters, options: []) else {
            print("Unable to serialize JSON")
            isLoading = false
            isShowingAudioPlayer = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // Create URLSession without delegate
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)

        // Create dataTask with completion handler
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false

                if let error = error {
                    print("Audio request failed: \(error.localizedDescription)")
                    self.isShowingAudioPlayer = false
                    return
                }

                guard let data = data else {
                    print("No data received")
                    self.isShowingAudioPlayer = false
                    return
                }

                // Save data to a temporary file
                self.saveAudioData(data)
            }
        }

        task.resume()
    }

    // Save received audio data to a temporary file and start playback
    private func saveAudioData(_ data: Data) {
        // Create a temporary file URL
        let tempAudioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(mediaType)

        do {
            try data.write(to: tempAudioURL)
            self.startPlayback(from: tempAudioURL)
        } catch {
            print("Failed to write audio data to file: \(error)")
            self.isShowingAudioPlayer = false
        }
    }

    // Start playback from the given file URL
    private func startPlayback(from url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isAudioPlaying = true
            duration = audioPlayer?.duration ?? 0
            startAudioTimer()
        } catch {
            print("Failed to initialize AVAudioPlayer: \(error)")
            isShowingAudioPlayer = false
        }
    }

    // Toggle playback
    func togglePlayback() {
        guard let player = audioPlayer else { return }

        if isAudioPlaying {
            player.pause()
            isAudioPlaying = false
            stopAudioTimer()  // Stop timer when paused
        } else {
            if player.currentTime >= player.duration - 0.1 {
                // Reset to beginning if playback has finished
                player.currentTime = 0
                currentTime = 0
            }
            player.play()
            isAudioPlaying = true
            startAudioTimer()  // Start timer when playback resumes
        }
    }

    // Fast forward 15 seconds
    func forward15Seconds() {
        guard let player = audioPlayer else { return }
        let maxTime = player.duration - 0.1  // Subtract a small value to avoid exceeding duration

        if player.currentTime >= maxTime {
            // Already at or near the end, do nothing
            return
        }

        let newTime = min(player.currentTime + 15, maxTime)
        player.currentTime = newTime
        currentTime = newTime

        if newTime >= maxTime {
            player.pause()
            isAudioPlaying = false
            stopAudioTimer()
        }
    }

    // Rewind 15 seconds
    func backward15Seconds() {
        guard let player = audioPlayer else { return }
        let newTime = max(player.currentTime - 15, 0)
        player.currentTime = newTime
        currentTime = newTime
    }

    // Implement the seek(to:) method
    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        let maxTime = player.duration - 0.1  // Subtract a small value to avoid exceeding duration
        let clampedTime = min(max(time, 0), maxTime)
        player.currentTime = clampedTime
        currentTime = clampedTime

        if clampedTime >= maxTime {
            player.pause()
            isAudioPlaying = false
            stopAudioTimer()
        }
    }

    // Close audio player
    func closeAudioPlayer() {
        resetPlayer()
        isAudioPlaying = false
        isShowingAudioPlayer = false
        isLoading = false
    }

    // Reset player
    private func resetPlayer() {
        audioPlayer?.stop()
        audioPlayer = nil
        duration = 0
        currentTime = 0
        stopAudioTimer()
    }

    // Start audio timer
    private func startAudioTimer() {
        stopAudioTimer()
        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true, block: { [weak self] timer in
            guard let self = self else { return }
            if let player = self.audioPlayer {
                self.currentTime = min(player.currentTime, player.duration)
                self.duration = player.duration

                // Automatically pause if playback reaches the end
                if player.currentTime >= player.duration - 0.1 {
                    player.pause()
                    self.isAudioPlaying = false
                    self.stopAudioTimer()
                }
            }
        })
    }

    // Stop audio timer
    private func stopAudioTimer() {
        audioTimer?.invalidate()
        audioTimer = nil
    }
}

// MARK: - AVAudioPlayerDelegate
extension GlobalAudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isAudioPlaying = false
        stopAudioTimer()
        currentTime = 0

        // Optionally reset player to allow replay
        player.currentTime = 0
    }
}
