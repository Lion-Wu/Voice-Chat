//
//  AudioTimers.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
final class AudioDisplayLinkDriver {
    private let onTick: () -> Void
    private var fallbackTimer: Timer?

#if canImport(UIKit) || canImport(AppKit)
    private var displayLink: CADisplayLink?
    private var proxy: AudioDisplayLinkProxy?
#endif

    init(onTick: @escaping () -> Void) {
        self.onTick = onTick
    }

    func start() {
        stop()

#if canImport(UIKit)
        let proxy = AudioDisplayLinkProxy { [weak self] in
            self?.onTick()
        }
        let displayLink = CADisplayLink(target: proxy, selector: #selector(AudioDisplayLinkProxy.handleDisplayLink))
        displayLink.preferredFramesPerSecond = max(UIScreen.main.maximumFramesPerSecond, 60)
        displayLink.add(to: .main, forMode: .common)
        self.proxy = proxy
        self.displayLink = displayLink
#elseif canImport(AppKit)
        let proxy = AudioDisplayLinkProxy { [weak self] in
            self?.onTick()
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            startFallbackTimer()
            return
        }
        let displayLink = screen.displayLink(target: proxy, selector: #selector(AudioDisplayLinkProxy.handleDisplayLink))
        displayLink.add(to: .main, forMode: .common)
        self.proxy = proxy
        self.displayLink = displayLink
#else
        startFallbackTimer()
#endif
    }

    func stop() {
#if canImport(UIKit) || canImport(AppKit)
        displayLink?.invalidate()
        displayLink = nil
        proxy = nil
#endif
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func startFallbackTimer() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onTick()
            }
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }
}

#if canImport(UIKit) || canImport(AppKit)
@MainActor
final class AudioDisplayLinkProxy: NSObject {
    private let onTick: () -> Void

    init(onTick: @escaping () -> Void) {
        self.onTick = onTick
    }

    @objc func handleDisplayLink() {
        onTick()
    }
}
#endif

@MainActor
extension GlobalAudioManager {

    // MARK: - Timers
    func startAudioTimer() {
        stopAudioTimer()
        let driver = AudioDisplayLinkDriver { [weak self] in
            self?.handleAudioTick()
        }
        audioDisplayDriver = driver
        driver.start()
    }

    func stopAudioTimer() {
        audioDisplayDriver?.stop()
        audioDisplayDriver = nil
        // Reset output level when the timer stops updating.
        outputLevel = 0
    }

    private func handleAudioTick() {
        guard let p = audioPlayer, !isBuffering else { return }

        // Enable metering and update the output level.
        if !p.isMeteringEnabled { p.isMeteringEnabled = true }
        p.updateMeters()
        let power = p.averagePower(forChannel: 0) // dB [-160, 0]
        // Convert the decibel reading into a normalized 0...1 range.
        let norm = max(0, min(1, pow(10.0, power / 20.0)))
        if abs(norm - outputLevel) > 0.01 { outputLevel = Float(norm) }

        let segStart = startTime(forSegment: currentPlayingIndex)
        let newTime = segStart + p.currentTime

        if allChunksLoaded() && newTime >= (totalDuration - endEpsilon) {
            currentTime = totalDuration
            finishPlayback()
            return
        }

        if newTime + 0.0005 >= currentTime {
            currentTime = newTime
        } else {
            currentTime = max(currentTime, newTime)
        }

        lastObservedPlaybackTime = p.currentTime
        lastProgressTimestamp = Date()
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
