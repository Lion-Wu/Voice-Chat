//
//  AVAudioDelegate.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation
import AVFoundation

extension GlobalAudioManager {

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedID = ObjectIdentifier(player)
        Task { @MainActor in
            guard let current = self.audioPlayer,
                  ObjectIdentifier(current) == finishedID else { return }

            self.currentPlayingIndex += 1

            if self.currentPlayingIndex >= self.audioChunks.count {
                self.recalcTotalDuration()
                self.currentTime = self.totalDuration
                self.finishPlayback()
                return
            }

            if let next = self.nextAudioPlayer {
                self.audioPlayer = next
                self.nextAudioPlayer = nil
                self.audioPlayer?.delegate = self

                let segStart = self.startTime(forSegment: self.currentPlayingIndex)
                self.currentTime = segStart

                if self.isAudioPlaying {
                    self.audioPlayer?.currentTime = 0
                    self.audioPlayer?.play()
                    self.startAudioTimer()
                    self.startStallWatchdog()
                }
                self.prepareNextAudioChunk(at: self.currentPlayingIndex + 1)
            } else {
                if let chunkOpt = self.audioChunks[safe: self.currentPlayingIndex], let _ = chunkOpt {
                    _ = self.playAudioChunk(at: self.currentPlayingIndex,
                                            fromTime: self.startTime(forSegment: self.currentPlayingIndex),
                                            shouldPlay: self.isAudioPlaying)
                } else {
                    self.isBuffering = self.isAudioPlaying
                    self.stopAudioTimer()
                    self.startStallWatchdog()
                    if self.isRealtimeMode {
                        self.isLoading = true
                        self.isAudioPlaying = false
                    }
                }
            }
        }
    }
}
