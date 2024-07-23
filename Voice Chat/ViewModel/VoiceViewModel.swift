//
//  VoiceViewModel.swift
//  Voice Chat
//
//  Created by 小吴苹果机器人 on 2024/1/8.
//

import Foundation
import AVKit

class VoiceViewModel: ObservableObject {
    @Published var text = "你好啊"
    @Published var connectionStatus = "等待连接"
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isAudioPlaying = false

    private var audioPlayerManager = VoiceAudioPlayerManager()
    private var voiceService = VoiceService()
    private var audioPlayer: AVAudioPlayer?
    private var settingsManager = SettingsManager.shared

    init() {
        audioPlayerManager.didFinishPlaying = { [weak self] in
            DispatchQueue.main.async {
                self?.isAudioPlaying = false
            }
        }
    }

    func getVoice() {
        isLoading = true
        connectionStatus = "请求语音中..."
        errorMessage = nil

        voiceService.getVoice(with: settingsManager.serverSettings, modelSettings: settingsManager.modelSettings, text: text) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let data):
                    self?.connectionStatus = "请求成功"
                    self?.playAudio(data: data)
                case .failure(let error):
                    self?.errorMessage = "请求失败: \(error.localizedDescription)"
                    self?.connectionStatus = "连接失败"
                }
            }
        }
    }

    private func playAudio(data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = audioPlayerManager
            audioPlayer?.prepareToPlay()
            isAudioPlaying = true
            audioPlayer?.play()
        } catch {
            errorMessage = "音频播放失败: \(error)"
        }
    }

    func togglePlayback() {
        guard let player = audioPlayer else { return }
        if isAudioPlaying {
            player.pause()
        } else {
            player.play()
        }
        isAudioPlaying.toggle()
    }

    func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            errorMessage = "无法设置音频会话: \(error)"
        }
        audioPlayerManager.didFinishPlaying = { [weak self] in
            DispatchQueue.main.async {
                self?.isAudioPlaying = false
            }
        }
    }
}

// MARK: - AudioPlayerManager
class VoiceAudioPlayerManager: NSObject, AVAudioPlayerDelegate {
    var didFinishPlaying: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        didFinishPlaying?()
    }
}
