//
//  ChatWithVoiceViewModel.swift
//  Voice Chat
//
//  Created by 小吴苹果机器人 on 2024/1/18.
//

import Foundation
import AVKit

class ChatViewModel: ObservableObject {
    @Published var userMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var messages: [ChatMessage] = []
    @Published var isAudioPlaying = false

    private var chatService = ChatService()
    private var voiceService = VoiceService()
    private var audioPlayerManager = ChatAudioPlayerManager()
    private var audioPlayer: AVAudioPlayer?
    private var settingsManager = SettingsManager.shared

    // 错误信息
    @Published var errorMessageVoice: String?
    @Published var isLoadingVoice = false
    @Published var connectionStatusVoice = "等待连接"

    init() {
        chatService.onMessageReceived = { [weak self] message in
            DispatchQueue.main.async {
                if let lastMessage = self?.messages.last, !lastMessage.isUser && lastMessage.isActive {
                    self?.messages[self!.messages.count - 1].content += message.content
                } else {
                    self?.messages.append(message)
                }
                self?.isLoading = false
            }
        }

        chatService.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                // 处理错误信息
            }
        }

        audioPlayerManager.didFinishPlaying = { [weak self] in
            DispatchQueue.main.async {
                self?.isAudioPlaying = false
            }
        }
    }

    func sendMessage() {
        let userMsg = ChatMessage(content: userMessage, isUser: true)
        messages.append(userMsg)
        isLoading = true
        chatService.fetchStreamedData(messages: messages)
        userMessage = ""
    }

    func getVoice(for text: String) {
        isLoadingVoice = true
        connectionStatusVoice = "请求语音中..."
        errorMessageVoice = nil

        voiceService.getVoice(with: settingsManager.serverSettings, modelSettings: settingsManager.modelSettings, text: text) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingVoice = false
                switch result {
                case .success(let data):
                    self?.connectionStatusVoice = "请求成功"
                    self?.playAudio(data: data)
                case .failure(let error):
                    self?.errorMessageVoice = "请求失败: \(error.localizedDescription)"
                    self?.connectionStatusVoice = "连接失败"
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
            errorMessageVoice = "音频播放失败: \(error)"
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
}

// MARK: - AudioPlayerManager
class ChatAudioPlayerManager: NSObject, AVAudioPlayerDelegate {
    var didFinishPlaying: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        didFinishPlaying?()
    }
}
