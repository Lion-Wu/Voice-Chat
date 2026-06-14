//
//  GlobalAudioManager+AppDependencies.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

@MainActor
private let appGlobalAudioManager = GlobalAudioManager(
    ttsSettingsSnapshotProvider: { SettingsManager.shared.ttsSettingsSnapshot },
    noticePublisher: AppErrorCenter.shared
)

@MainActor
private let appServerReachabilityMonitor = ServerReachabilityMonitor(
    noticePublisher: AppErrorCenter.shared
)

@MainActor
extension GlobalAudioManager {
    static var shared: GlobalAudioManager {
        appGlobalAudioManager
    }
}

@MainActor
extension ServerReachabilityMonitor {
    static var shared: ServerReachabilityMonitor {
        appServerReachabilityMonitor
    }
}
