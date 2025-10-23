//
//  AudioRequests.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation
import AVFoundation
import SwiftUI

@MainActor
extension GlobalAudioManager {

    // MARK: - URL Builder
    func constructTTSURL() -> URL? {
        let addr = settingsManager.serverSettings.serverAddress
        return URL(string: "\(addr)/tts")
    }

    // MARK: - Request queue (used only in non-streaming mode)
    func sendNextSegment() {
        guard currentChunkIndex < textSegments.count else { return }
        guard !isRealtimeMode else { return } // Real-time mode does not use the recursive chain.
        let idx = currentChunkIndex
        currentChunkIndex += 1
        sendTTSRequest(for: textSegments[idx], index: idx)
    }

    func sendTTSRequest(for segmentText: String, index: Int) {
        guard !inFlightIndexes.contains(index) else { return }
        guard let url = constructTTSURL() else {
            self.errorMessage = "Unable to construct TTS URL"
            return
        }
        inFlightIndexes.insert(index)

        let s = settingsManager
        let refAudioPath = s.selectedPreset?.refAudioPath ?? ""
        let promptText   = s.selectedPreset?.promptText ?? ""
        let promptLang   = s.selectedPreset?.promptLang ?? "auto"

        var params: [String: Any] = [
            "text": segmentText,
            "text_lang": s.serverSettings.textLang,
            "ref_audio_path": refAudioPath,
            "prompt_text": promptText,
            "prompt_lang": promptLang,
            "batch_size": 1,
            "media_type": mediaType
        ]
        params["text_split_method"] = s.voiceSettings.enableStreaming ? "cut0" : s.modelSettings.autoSplit

        guard let body = try? JSONSerialization.data(withJSONObject: params) else {
            self.errorMessage = "Unable to serialize JSON"
            inFlightIndexes.remove(index)
            // In real-time mode continue the queue to avoid stalls.
            if isRealtimeMode { processRealtimeQueueIfNeeded() }
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let genAtRequest = self.currentGenerationID

        let task = URLSession.shared.dataTask(with: req) { [weak self] data, resp, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard genAtRequest == self.currentGenerationID else { return }

                defer {
                    self.inFlightIndexes.remove(index)
                    if self.isRealtimeMode {
                        self.processRealtimeQueueIfNeeded()
                    } else {
                        // Non-streaming mode sends segments sequentially.
                        self.sendNextSegment()
                    }
                }

                if let err = error as NSError? {
                    if err.domain == NSURLErrorDomain && err.code == NSURLErrorCancelled {
                        return
                    }
                    self.errorMessage = err.localizedDescription
                    return
                }

                if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    self.errorMessage = "TTS server error: \(http.statusCode)"
                    return
                }

                guard let data = data, !data.isEmpty else {
                    self.errorMessage = "No data received"
                    return
                }

                // Guard against out-of-bounds access while the array grows in real time.
                if index >= self.audioChunks.count {
                    let delta = index - self.audioChunks.count + 1
                    for _ in 0..<delta {
                        self.audioChunks.append(nil)
                        self.chunkDurations.append(0)
                    }
                }

                if index < self.audioChunks.count {
                    self.audioChunks[index] = data
                    if let p = try? AVAudioPlayer(data: data) {
                        self.chunkDurations[index] = max(0, p.duration)
                    } else {
                        self.chunkDurations[index] = 0
                    }
                    self.recalcTotalDuration()
                }

                if self.playbackFinished() {
                    self.finishPlayback()
                    return
                }

                if index == self.currentPlayingIndex {
                    let shouldAutoplay = self.isRealtimeMode ? true : self.isAudioPlaying
                    let didStart = self.playAudioChunk(at: index,
                                                       fromTime: self.seekTime,
                                                       shouldPlay: shouldAutoplay)
                    if self.isRealtimeMode {
                        self.isLoading = !didStart
                        self.isAudioPlaying = didStart
                    } else {
                        self.isLoading = false
                    }
                    self.seekTime = nil
                } else if self.isBuffering && index == self.currentPlayingIndex {
                    let shouldAutoplay = self.isRealtimeMode ? true : self.isAudioPlaying
                    let didStart = self.playAudioChunk(at: index,
                                                       fromTime: self.seekTime ?? self.currentTime,
                                                       shouldPlay: shouldAutoplay)
                    if self.isRealtimeMode {
                        self.isLoading = !didStart
                        self.isAudioPlaying = didStart
                    } else {
                        self.isLoading = false
                    }
                    self.seekTime = nil
                }

                if index == self.currentPlayingIndex + 1 {
                    self.prepareNextAudioChunk(at: index)
                }
            }
        }
        task.resume()
        dataTasks.append(task)
    }
}
