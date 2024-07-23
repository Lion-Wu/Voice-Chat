//
//  SwiftUIView.swift
//  Voice Chat
//
//  Created by 小吴苹果机器人 on 2024/1/5.
//

import SwiftUI

struct VoiceView: View {
    @StateObject private var viewModel = VoiceViewModel()

    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextContentEditor(text: $viewModel.text)
                    VoiceActionButton(action: viewModel.getVoice)
                    AudioControlPanel(isAudioPlaying: $viewModel.isAudioPlaying, action: viewModel.togglePlayback)
                    StatusSection(loading: viewModel.isLoading, errorMessage: viewModel.errorMessage, connectionStatus: viewModel.connectionStatus)
                }
                .padding()
            }
        }
        .navigationBarTitle("语音生成器", displayMode: .inline)
        .onAppear {
            viewModel.setupAudioSession()
        }
    }
}

// MARK: - UI Components

struct TextContentEditor: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading) {
            Text("内容设置").font(.headline)
            TextEditor(text: $text)
                .frame(minHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.gray, lineWidth: 1)
                )
                .padding(.bottom)
        }
    }
}

struct VoiceActionButton: View {
    var action: () -> Void

    var body: some View {
        Button("获取语音", action: action)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.orange)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
}

struct AudioControlPanel: View {
    @Binding var isAudioPlaying: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isAudioPlaying ? "pause.circle.fill" : "play.circle.fill")
                Text(isAudioPlaying ? "暂停" : "播放")
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color.blue)
        .foregroundColor(.white)
        .cornerRadius(10)
    }
}

struct StatusSection: View {
    let loading: Bool
    let errorMessage: String?
    let connectionStatus: String

    var body: some View {
        VStack {
            if loading {
                ProgressView("加载中...")
            }
            if let errorMessage = errorMessage {
                Text("错误: \(errorMessage)").foregroundColor(.red)
            }
            Text(connectionStatus).foregroundColor(.blue)
        }
    }
}

#Preview {
    VoiceView()
}
