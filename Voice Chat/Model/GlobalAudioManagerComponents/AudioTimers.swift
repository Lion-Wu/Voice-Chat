//
//  AudioTimers.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation
import AVFoundation

@MainActor
extension GlobalAudioManager {

    // MARK: - Timers
    func startAudioTimer() {
        stopAudioTimer()
        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      let p = self.audioPlayer,
                      !self.isBuffering else { return }

                // Enable metering and update the output level.
                if !p.isMeteringEnabled { p.isMeteringEnabled = true }
                p.updateMeters()
                let power = p.averagePower(forChannel: 0) // dB [-160, 0]
                // Convert the decibel reading into a normalized 0...1 range.
                let norm = max(0, min(1, pow(10.0, power / 20.0)))
                if abs(norm - self.outputLevel) > 0.01 { self.outputLevel = Float(norm) }

                let segStart = self.startTime(forSegment: self.currentPlayingIndex)
                let newTime = segStart + p.currentTime

                if self.allChunksLoaded() && newTime >= (self.totalDuration - self.endEpsilon) {
                    self.currentTime = self.totalDuration
                    self.finishPlayback()
                    return
                }

                if newTime + 0.0005 >= self.currentTime {
                    self.currentTime = newTime
                } else {
                    self.currentTime = max(self.currentTime, newTime)
                }

                self.lastObservedPlaybackTime = p.currentTime
                self.lastProgressTimestamp = Date()
            }
        }
        if let timer = audioTimer {
            timer.tolerance = 0.02
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    func stopAudioTimer() {
        audioTimer?.invalidate()
        audioTimer = nil
        // Reset output level when the timer stops updating.
        outputLevel = 0
    }

    func startStallWatchdog() {
        stopStallWatchdog()
        stallWatchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                if self.playbackFinished() {
                    self.finishPlayback()
                    return
                }

                if self.isBuffering {
                    let elapsed = Date().timeIntervalSince(self.lastProgressTimestamp)
                    if elapsed > 8 {
                        let idx = self.currentPlayingIndex
                        if self.audioChunks[safe: idx] == nil && !self.inFlightIndexes.contains(idx) {
                            self.sendTTSRequest(for: self.textSegments[idx], index: idx)
                        }
                        self.lastProgressTimestamp = Date()
                    }
                    return
                }

                if self.isAudioPlaying, let p = self.audioPlayer {
                    let elapsedNoProgress = Date().timeIntervalSince(self.lastProgressTimestamp)
                    let isNotAdvancing = abs(p.currentTime - self.lastObservedPlaybackTime) < 0.01
                    let isNotPlaying = !p.isPlaying

                    if (isNotPlaying || isNotAdvancing) && elapsedNoProgress > 2 {
                        let segStart = self.startTime(forSegment: self.currentPlayingIndex)
                        let projectedGlobal = segStart + p.currentTime
                        if self.allChunksLoaded() && projectedGlobal >= (self.totalDuration - self.endEpsilon) {
                            self.finishPlayback()
                            return
                        }

                        p.stop()
                        let resumeGlobal = max(segStart, self.currentTime)
                        _ = self.playAudioChunk(at: self.currentPlayingIndex,
                                                fromTime: resumeGlobal,
                                                shouldPlay: self.isAudioPlaying)
                        self.lastProgressTimestamp = Date()
                    }
                }
            }
        }
        if let t = stallWatchdog {
            t.tolerance = 0.2
            RunLoop.current.add(t, forMode: .common)
        }
    }

    func stopStallWatchdog() {
        stallWatchdog?.invalidate()
        stallWatchdog = nil
    }
}
