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
    @ObservedObject var settingsManager = SettingsManager.shared
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
                Section(header: Text("服务器设置")) {
                    TextField("服务器IP", text: $settingsManager.serverSettings.serverIP)
                        .onChange(of: settingsManager.serverSettings.serverIP) { _ in
                            settingsManager.saveServerSettings()
                        }
                    TextField("端口", text: $settingsManager.serverSettings.port)
                        .onChange(of: settingsManager.serverSettings.port) { _ in
                            settingsManager.saveServerSettings()
                        }
                }

                Section(header: Text("模型设置")) {
                    if isLoadingModels {
                        ProgressView("加载模型列表...")
                    } else {
                        Picker("选择模型", selection: $settingsManager.chatSettings.selectedModel) {
                            ForEach(availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .onChange(of: settingsManager.chatSettings.selectedModel) { _ in
                            settingsManager.saveChatSettings()
                        }
                    }

                    Button(action: {
                        fetchAvailableModels()
                    }) {
                        Text("刷新模型列表")
                    }
                }

                Section(header: Text("聊天API设置")) {
                    TextField("聊天API URL", text: $settingsManager.chatSettings.apiURL)
                        .onChange(of: settingsManager.chatSettings.apiURL) { _ in
                            settingsManager.saveChatSettings()
                        }
                }
            }
            .navigationBarTitle("设置")
            .navigationBarItems(trailing: Button("关闭") {
                self.isPresented = false
            })
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
        let urlString = "\(settingsManager.chatSettings.apiURL)/models"
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
                    if !self.availableModels.contains(self.settingsManager.chatSettings.selectedModel) {
                        self.settingsManager.chatSettings.selectedModel = self.availableModels.first ?? ""
                        self.settingsManager.saveChatSettings()
                    }
                } else {
                    self.errorMessage = AlertError(message: "无法解析模型列表")
                }
            }
        }.resume()
    }
}

#Preview {
    SettingsView(isPresented: .constant(true))
}
