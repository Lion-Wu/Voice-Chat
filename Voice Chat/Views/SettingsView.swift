//
//  SettingsView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.22.
//

import SwiftUI

struct AlertError: Identifiable {
    var id = UUID()
    var message: String
}

struct SettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel()
    @Binding var isPresented: Bool

    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var errorMessage: AlertError?

    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("语音生成设置")) {
                    LabeledTextField(label: "服务器地址", placeholder: "请输入服务器地址", text: $viewModel.serverAddress)
                    LabeledTextField(label: "文本语言", placeholder: "text_lang", text: $viewModel.textLang)
                    LabeledTextField(label: "参考音频路径", placeholder: "ref_audio_path", text: $viewModel.refAudioPath)
                    LabeledTextField(label: "参考音频提示词", placeholder: "prompt_text", text: $viewModel.promptText)
                    LabeledTextField(label: "参考音频语言", placeholder: "prompt_lang", text: $viewModel.promptLang)
                    Toggle("启用流式请求", isOn: $viewModel.enableStreaming)
                        .onChange(of: viewModel.enableStreaming) { _, _ in
                            viewModel.saveVoiceSettings()
                            if viewModel.enableStreaming {
                                // When streaming is enabled, set autoSplit to "cut0" and disable picker
                                viewModel.autoSplit = "cut0"
                                viewModel.saveModelSettings()
                            }
                        }
                    Picker("切分方式", selection: $viewModel.autoSplit) {
                        Text("cut0：不切割").tag("cut0")
                        Text("cut1：每四句切割").tag("cut1")
                        Text("cut2：每50字切割").tag("cut2")
                        Text("cut3：按中文句号切割").tag("cut3")
                        Text("cut4：按英文句号切割").tag("cut4")
                        Text("cut5：按标点符号切割").tag("cut5")
                    }
                    .disabled(viewModel.enableStreaming)
                    .onChange(of: viewModel.autoSplit) { _, _ in
                        viewModel.saveModelSettings()
                    }
                }

                Section(header: Text("聊天服务器设置")) {
                    LabeledTextField(label: "聊天API URL", placeholder: "请输入聊天API URL", text: $viewModel.apiURL)

                    if isLoadingModels {
                        ProgressView("加载模型列表...")
                    } else {
                        Picker("选择模型", selection: $viewModel.selectedModel) {
                            ForEach(availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .onChange(of: viewModel.selectedModel) { _, _ in
                            viewModel.saveChatSettings()
                        }
                    }

                    Button(action: {
                        fetchAvailableModels()
                    }) {
                        Text("刷新模型列表")
                    }
                }
            }
            .navigationBarTitle("设置")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        self.isPresented = false
                    }
                }
            }
            .onAppear {
                fetchAvailableModels()
            }
            .alert(item: $errorMessage) { error in
                Alert(title: Text("错误"), message: Text(error.message), dismissButton: .default(Text("确定")))
            }
        }
    }

    private func fetchAvailableModels() {
        isLoadingModels = true
        errorMessage = nil
        let urlString = "\(viewModel.apiURL)/v1/models"
        guard let url = URL(string: urlString) else {
            errorMessage = AlertError(message: "无效的API URL")
            isLoadingModels = false
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                self.isLoadingModels = false
                if let error = error {
                    self.errorMessage = AlertError(message: "请求失败: \(error.localizedDescription)")
                } else if let data = data, let modelList = try? JSONDecoder().decode(ModelListResponse.self, from: data) {
                    self.availableModels = modelList.data.map { $0.id }
                    // Only reset selectedModel if it's empty or not in the new list
                    if !self.availableModels.contains(self.viewModel.selectedModel) {
                        if let firstModel = self.availableModels.first {
                            self.viewModel.selectedModel = firstModel
                            self.viewModel.saveChatSettings()
                        }
                    }
                } else {
                    self.errorMessage = AlertError(message: "无法解析模型列表")
                }
            }
        }.resume()
    }
}

struct LabeledTextField: View {
    var label: String
    var placeholder: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .leading)
            TextField(placeholder, text: $text)
                .textFieldStyle(DefaultTextFieldStyle())
        }
    }
}

#Preview {
    SettingsView(isPresented: .constant(true))
}
