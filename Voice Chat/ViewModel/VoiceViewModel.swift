//
//  VoiceViewModel.swift
//  Voice Chat
//
//  Created by 小吴苹果机器人 on 2024/1/8.
//

import Foundation
import AVFoundation

class VoiceViewModel: ObservableObject {
    @Published var text = "先帝创业未半而中道崩殂，今天下三分，益州疲弊，此诚危急存亡之秋也。"
    @Published var connectionStatus = "等待连接"
    @Published var errorMessage: String?
    @Published var isLoading = false

    private var settingsManager = SettingsManager.shared

    func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            errorMessage = "无法设置音频会话: \(error)"
        }
    }
}
