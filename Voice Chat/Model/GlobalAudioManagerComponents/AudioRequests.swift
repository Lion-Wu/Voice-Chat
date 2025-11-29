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
        let trimmed = settingsManager.serverSettings.serverAddress
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var comps = URLComponents(string: trimmed) else { return nil }
        comps.path = comps.path.appending("/tts")
        return comps.url
    }

    // MARK: - Request Queue (used only in full-text mode)
    func sendNextSegment() {
        guard currentChunkIndex < textSegments.count else { return }
        guard !isRealtimeMode else { return } // Realtime mode does not recurse through the queue.
        let idx = currentChunkIndex
        currentChunkIndex += 1
        sendTTSRequest(for: textSegments[idx], index: idx)
    }

    func sendTTSRequest(for segmentText: String, index: Int) {
        guard !inFlightIndexes.contains(index) else { return }
        guard let url = constructTTSURL() else {
            let address = settingsManager.serverSettings.serverAddress
            let message = String(format: NSLocalizedString("Unable to construct TTS URL from %@", comment: "Shown when the TTS endpoint URL cannot be built"), address)
            self.surfaceTTSIssue(message)
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
        if isRealtimeMode {
            params["text_split_method"] = "cut0"
        } else {
            params["text_split_method"] = s.voiceSettings.enableStreaming ? "cut0" : s.modelSettings.autoSplit
        }

        guard let body = try? JSONSerialization.data(withJSONObject: params) else {
            self.surfaceTTSIssue(NSLocalizedString("Unable to serialize JSON", comment: "Shown when encoding the TTS request body fails"))
            inFlightIndexes.remove(index)
            // In realtime mode continue with the queue to avoid stalling.
            if isRealtimeMode { processRealtimeQueueIfNeeded() }
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let genAtRequest = self.currentGenerationID

        var task: URLSessionDataTask?
        task = ttsSession.dataTask(with: req) { [weak self, weak task] (data: Data?, resp: URLResponse?, error: Error?) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let task {
                    self.dataTasks.removeAll(where: { $0 === task })
                }
                guard genAtRequest == self.currentGenerationID else { return }

                defer {
                    self.inFlightIndexes.remove(index)
                    if self.isRealtimeMode {
                        self.processRealtimeQueueIfNeeded()
                    } else {
                        // Non-realtime mode continues with the next segment immediately.
                        self.sendNextSegment()
                    }
                }

                if let err = error as NSError? {
                    if err.domain == NSURLErrorDomain && err.code == NSURLErrorCancelled {
                        return
                    }
                    self.surfaceTTSIssue(self.formatTTSNetworkError(err))
                    return
                }

                if let http = resp as? HTTPURLResponse {
                    if !(200...299).contains(http.statusCode) {
                        let preview = data.flatMap { String(data: $0, encoding: .utf8) }?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let message: String
                        if preview.isEmpty {
                            message = String(format: NSLocalizedString("TTS server error: %d", comment: "Shown when the TTS server returns a non-success status"), http.statusCode)
                        } else {
                            let snippet = preview.prefix(180)
                            message = String(format: NSLocalizedString("TTS server error: %d (%@)", comment: "Shown when the TTS server returns a non-success status plus body"), http.statusCode, String(snippet))
                        }
                        self.surfaceTTSIssue(message)
                        return
                    }

                    if let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
                       !type.contains("audio") && !type.contains("octet-stream") {
                        let preview = data.flatMap { String(data: $0, encoding: .utf8) }?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let message: String
                        if preview.isEmpty {
                            message = NSLocalizedString("TTS response was not audio data.", comment: "Shown when TTS returns a non-audio MIME type")
                        } else {
                            let snippet = preview.prefix(180)
                            message = String(format: NSLocalizedString("TTS response was not audio: %@", comment: "Shown when TTS returns non-audio body"), String(snippet))
                        }
                        self.surfaceTTSIssue(message)
                        return
                    }
                }

                guard let data = data, !data.isEmpty else {
                    self.surfaceTTSIssue(NSLocalizedString("No data received", comment: "Shown when the TTS server returns an empty body"))
                    return
                }

                // Ensure the arrays grow safely when realtime mode extends them dynamically.
                if index >= self.audioChunks.count {
                    let delta = index - self.audioChunks.count + 1
                    for _ in 0..<delta {
                        self.audioChunks.append(nil)
                        self.chunkDurations.append(0)
                    }
                }

                    if index < self.audioChunks.count {
                        self.audioChunks[index] = data
                        do {
                            let p = try AVAudioPlayer(data: data)
                            self.chunkDurations[index] = max(0, p.duration)
                        } catch {
                            self.chunkDurations[index] = 0
                            self.surfaceTTSIssue(NSLocalizedString("Received audio data could not be played.", comment: "Shown when AVAudioPlayer fails to read TTS audio data"))
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
        if let task {
            task.resume()
            dataTasks.append(task)
        }
    }
}
