//
//  VoiceView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/5.
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
                        Text("Content Settings")
                            .font(.title2)
                            .bold()
                            .padding(.top)

                        TextEditor(text: $viewModel.text)
                            .frame(minHeight: 150)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.5)))

                        Button(action: {
                            audioManager.startProcessing(text: viewModel.text)
                        }) {
                            Text("Generate Voice")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(LinearGradient(gradient: Gradient(colors: [Color.orange, Color.red]),
                                                           startPoint: .leading, endPoint: .trailing))
                                .cornerRadius(15)
                        }
                        .padding(.horizontal)

                        if audioManager.isLoading || audioManager.isBuffering {
                            HStack {
                                ProgressView()
                                Text("Loading...")
                                    .font(.subheadline)
                            }
                            .padding(.top)
                        }

                        if let errorMessage = viewModel.errorMessage {
                            Text("Error: \(errorMessage)")
                                .foregroundColor(.red)
                                .padding(.top)
                        }

                        Spacer()
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
        .navigationTitle("Voice Generator")
        .onAppear {
            viewModel.setupAudioSession()
        }
    }
}

struct VoiceView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceView()
            .environmentObject(GlobalAudioManager.shared)
    }
}
