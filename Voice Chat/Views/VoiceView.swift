//
//  SwiftUIView.swift
//  Voice Chat
//
//  Created by 小吴苹果机器人 on 2024/1/5.
//

import SwiftUI

struct VoiceView: View {
    @StateObject private var viewModel = VoiceViewModel()
    @EnvironmentObject var audioManager: GlobalAudioManager

    var body: some View {
        ZStack(alignment: .top) {
            VStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        TextContentEditor(text: $viewModel.text)
                        VoiceActionButton(action: {
                            audioManager.getVoice(for: viewModel.text)
                        })
                        StatusSection(
                            loading: audioManager.isLoading,
                            errorMessage: viewModel.errorMessage,
                            connectionStatus: viewModel.connectionStatus
                        )
                    }
                    .padding(.top, audioManager.isShowingAudioPlayer ? 150 : 20)
                    .animation(.easeInOut, value: audioManager.isShowingAudioPlayer)
                }
            }
            .padding()
            if audioManager.isShowingAudioPlayer {
                VStack {
                    AudioPlayerView()
                        .environmentObject(audioManager)
                    Spacer()
                }
                .transition(.move(edge: .top))
                .animation(.easeInOut, value: audioManager.isShowingAudioPlayer)
            }
        }
        .navigationBarTitle("语音生成器", displayMode: .inline)
        .onAppear {
            viewModel.setupAudioSession()
        }
    }

    // MARK: - UI Components

    struct TextContentEditor: View {
        @Binding var text: String

        var body: some View {
            VStack(alignment: .leading) {
                Text("内容设置")
                    .font(.headline)
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
            Button(action: action) {
                Text("获取语音")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange)
                    .cornerRadius(10)
            }
        }
    }

    struct StatusSection: View {
        let loading: Bool
        let errorMessage: String?
        let connectionStatus: String

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                if loading {
                    HStack {
                        ProgressView()
                        Text("正在加载...")
                    }
                }
                if let errorMessage = errorMessage {
                    Text("错误: \(errorMessage)")
                        .foregroundColor(.red)
                }
                Text(connectionStatus)
                    .foregroundColor(.blue)
            }
        }
    }
}

#Preview {
    VoiceView()
        .environmentObject(GlobalAudioManager.shared)
}
