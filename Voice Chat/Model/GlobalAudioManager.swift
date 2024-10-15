//
//  GlobalAudioManager.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//


import Foundation
import AVFoundation
import UIKit

class GlobalAudioManager: NSObject, ObservableObject {
    static let shared = GlobalAudioManager()

    @Published var isShowingAudioPlayer = false
    @Published var isAudioPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isLoading = false
    @Published var isFastForwardRewindEnabled = false  // Controls visibility of fast-forward/rewind buttons

    private var audioPlayer: AVAudioPlayer?
    private var audioTimer: Timer?
    private var session: URLSession?
    private var task: URLSessionDataTask?

    private var tempAudioURL: URL?
    private var audioFileHandle: FileHandle?
    private var isRequestCompleted = false
    private var isFirstPlayStarted = false

    var mediaType: String = "aac" // Default to AAC format

    func getVoice(for text: String) {
        // Reset before starting a new request
        resetPlayer()

        isLoading = true
        isShowingAudioPlayer = true
        isRequestCompleted = false
        isFastForwardRewindEnabled = false
        isFirstPlayStarted = false

        // Build TTS request URL
        guard let url = constructTTSURL() else {
            print("Unable to construct TTS URL")
            isLoading = false
            isShowingAudioPlayer = false
            return
        }

        // Fetch audio data via streaming
        fetchAudioStreaming(from: url, text: text)
    }

    // Construct TTS URL
    private func constructTTSURL() -> URL? {
        // Fetch the latest server settings
        let serverSettings = SettingsManager.shared.serverSettings
        let urlString = "\(serverSettings.serverAddress)/tts"
        return URL(string: urlString)
    }

    // Fetch audio streaming via URLSession
    private func fetchAudioStreaming(from url: URL, text: String) {
        // Fetch the latest settings
        let settingsManager = SettingsManager.shared
        let modelSettings = settingsManager.modelSettings
        let serverSettings = settingsManager.serverSettings

        // Prepare parameters
        let parameters: [String: Any] = [
            "text": text,
            "text_lang": serverSettings.textLang,
            "ref_audio_path": serverSettings.refAudioPath,
            "prompt_text": serverSettings.promptText,
            "prompt_lang": serverSettings.promptLang,
            "text_split_method": modelSettings.autoSplit,
            "batch_size": 4,
            "streaming_mode": true,
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

        // Create URLSession with delegate
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        // Create dataTask
        task = session?.dataTask(with: request)
        task?.resume()
    }

    // Reset player
    private func resetPlayer() {
        audioPlayer?.stop()
        audioPlayer = nil
        task?.cancel()
        session = nil

        // Close file handle and delete temp file
        if let audioFileHandle = audioFileHandle {
            try? audioFileHandle.close()
            self.audioFileHandle = nil
        }
        if let tempAudioURL = tempAudioURL {
            try? FileManager.default.removeItem(at: tempAudioURL)
            self.tempAudioURL = nil
        }
        isRequestCompleted = false
        isFastForwardRewindEnabled = false
        isFirstPlayStarted = false
        duration = 0
        currentTime = 0
        stopAudioTimer()
    }

    // Start playback
    private func startPlayback() {
        // Initialize AVAudioPlayer with temp file
        guard let tempAudioURL = tempAudioURL else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: tempAudioURL)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isAudioPlaying = true
            isLoading = false
            isFirstPlayStarted = true
            startAudioTimer()
        } catch {
            print("Failed to initialize AVAudioPlayer: \(error)")
        }
    }

    // Handle received data
    private func handleReceivedData(_ data: Data) {
        if audioFileHandle == nil {
            // Create temp file
            tempAudioURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(mediaType)
            FileManager.default.createFile(atPath: tempAudioURL!.path, contents: nil, attributes: nil)
            do {
                audioFileHandle = try FileHandle(forWritingTo: tempAudioURL!)
            } catch {
                print("Failed to open file handle: \(error)")
                return
            }
        }
        // Write data
        audioFileHandle?.write(data)

        // Start playback when enough data is available
        if !isFirstPlayStarted && ((try? audioFileHandle?.seekToEnd()) ?? 0) > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.startPlayback()
            }
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
        guard isFastForwardRewindEnabled else { return }
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
        }
    }

    // Rewind 15 seconds
    func backward15Seconds() {
        guard isFastForwardRewindEnabled else { return }
        guard let player = audioPlayer else { return }
        let newTime = max(player.currentTime - 15, 0)
        player.currentTime = newTime
        currentTime = newTime
    }

    // Implement the seek(to:) method
    func seek(to time: TimeInterval) {
        guard isFastForwardRewindEnabled else { return }
        guard let player = audioPlayer else { return }
        let maxTime = player.duration - 0.1  // Subtract a small value to avoid exceeding duration
        let clampedTime = min(max(time, 0), maxTime)
        player.currentTime = clampedTime
        currentTime = clampedTime

        if clampedTime >= maxTime {
            player.pause()
            isAudioPlaying = false
        }
    }

    // Close audio player
    func closeAudioPlayer() {
        resetPlayer()
        isAudioPlaying = false
        isShowingAudioPlayer = false
        isLoading = false
    }

    // Start audio timer
    private func startAudioTimer() {
        stopAudioTimer()
        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true, block: { [weak self] timer in
            guard let self = self else { return }
            if let player = self.audioPlayer {
                let maxTime = player.duration - 0.1
                self.currentTime = min(player.currentTime, maxTime)
                if player.duration > 0 {
                    self.duration = player.duration
                }

                // Automatically pause if playback reaches the end
                if player.currentTime >= maxTime {
                    player.pause()
                    self.isAudioPlaying = false
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
        if isRequestCompleted {
            // Playback finished naturally
            isAudioPlaying = false
            stopAudioTimer()
            player.currentTime = 0  // Reset currentTime after playback finishes
            currentTime = 0

            // Enable fast-forward/rewind after first playback completes
            isFastForwardRewindEnabled = true
        }
    }
}

// MARK: - URLSessionDataDelegate
extension GlobalAudioManager: URLSessionDataDelegate {
    // Handle streaming data
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        handleReceivedData(data)
    }

    // Request completed
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Close file handle
        try? audioFileHandle?.close()
        audioFileHandle = nil

        if let error = error {
            print("Audio stream request failed: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isShowingAudioPlayer = false
                self.isLoading = false
            }
        } else {
            print("Audio stream request completed")
        }

        isRequestCompleted = true

        DispatchQueue.main.async {
            if let player = self.audioPlayer {
                self.duration = player.duration
            }
            // Do not enable fast-forward/rewind here
        }
    }
}
