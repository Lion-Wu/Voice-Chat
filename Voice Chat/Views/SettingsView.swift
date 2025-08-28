//
//  SettingsView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.22.
//

import SwiftUI

// MARK: - Alert Model

struct AlertError: Identifiable {
    var id = UUID()
    var message: String
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var errorMessage: AlertError?

    init() {
        _viewModel = ObservedObject(wrappedValue: SettingsViewModel())
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    formContent()
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
        .onAppear { fetchAvailableModels() }
        .alert(item: $errorMessage) { error in
            Alert(title: Text("Error"),
                  message: Text(error.message),
                  dismissButton: .default(Text("OK")))
        }
        #else
        NavigationView {
            formContent()
                .navigationBarTitle("Settings", displayMode: .inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Close") { dismiss() }
                    }
                }
                .onAppear { fetchAvailableModels() }
                .alert(item: $errorMessage) { error in
                    Alert(title: Text("Error"),
                          message: Text(error.message),
                          dismissButton: .default(Text("OK")))
                }
        }
        #endif
    }

    // MARK: - Form Content

    @ViewBuilder
    private func formContent() -> some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 20) {
            Text("Voice Generation Settings")
                .font(.headline)
            voiceGenerationSettingsSection

            Text("Chat Server Settings")
                .font(.headline)
                .padding(.top, 20)
            chatSettingsSection
        }
        #else
        Form {
            Section(header: Text("Voice Generation Settings").font(.headline)) {
                voiceGenerationSettingsSection
            }
            Section(header: Text("Chat Server Settings").font(.headline)) {
                chatSettingsSection
            }
        }
        #endif
    }

    // MARK: - Sections

    private var voiceGenerationSettingsSection: some View {
        Group {
            LabeledTextField(label: "Server Address",
                             placeholder: "Enter server address",
                             text: $viewModel.serverAddress)
            LabeledTextField(label: "Text Language",
                             placeholder: "text_lang",
                             text: $viewModel.textLang)
            LabeledTextField(label: "Reference Audio Path",
                             placeholder: "ref_audio_path",
                             text: $viewModel.refAudioPath)
            LabeledTextField(label: "Prompt Text",
                             placeholder: "prompt_text",
                             text: $viewModel.promptText)
            LabeledTextField(label: "Prompt Language",
                             placeholder: "prompt_lang",
                             text: $viewModel.promptLang)

            #if os(macOS)
            HStack {
                Text("Enable Streaming")
                    .frame(width: 150, alignment: .trailing)
                Toggle("", isOn: $viewModel.enableStreaming)
            }
            HStack {
                Text("Split Method")
                    .frame(width: 150, alignment: .trailing)
                Picker("", selection: $viewModel.autoSplit) {
                    Text("cut0: No Split").tag("cut0")
                    Text("cut1: Split every 4 sentences").tag("cut1")
                    Text("cut2: Split every 50 characters").tag("cut2")
                    Text("cut3: Split by Chinese period").tag("cut3")
                    Text("cut4: Split by English period").tag("cut4")
                    Text("cut5: Split by punctuation").tag("cut5")
                }
                .disabled(viewModel.enableStreaming)
            }
            #else
            Toggle("Enable Streaming", isOn: $viewModel.enableStreaming)
            Picker("Split Method", selection: $viewModel.autoSplit) {
                Text("cut0: No Split").tag("cut0")
                Text("cut1: Split every 4 sentences").tag("cut1")
                Text("cut2: Split every 50 characters").tag("cut2")
                Text("cut3: Split by Chinese period").tag("cut3")
                Text("cut4: Split by English period").tag("cut4")
                Text("cut5: Split by punctuation").tag("cut5")
            }
            .disabled(viewModel.enableStreaming)
            #endif
        }
    }

    private var chatSettingsSection: some View {
        Group {
            LabeledTextField(label: "Chat API URL",
                             placeholder: "Enter chat API URL",
                             text: $viewModel.apiURL)

            if isLoadingModels {
                #if os(macOS)
                HStack {
                    ProgressView("Loading model list...")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                #else
                ProgressView("Loading model list...")
                #endif
            } else {
                #if os(macOS)
                HStack {
                    Text("Select Model")
                        .frame(width: 150, alignment: .trailing)
                    Picker("", selection: $viewModel.selectedModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }
                #else
                Picker("Select Model", selection: $viewModel.selectedModel) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                #endif
            }

            #if os(macOS)
            Button(action: fetchAvailableModels) {
                Text("Refresh Model List")
            }
            .padding(.top, 10)
            #else
            Button(action: fetchAvailableModels) {
                Text("Refresh Model List")
            }
            .padding(.top, 0)
            #endif
        }
    }

    // MARK: - Networking

    private func fetchAvailableModels() {
        guard !viewModel.apiURL.isEmpty else {
            errorMessage = AlertError(message: "API URL is empty or invalid.")
            return
        }
        isLoadingModels = true
        errorMessage = nil

        let urlString = "\(viewModel.apiURL)/v1/models"
        guard let url = URL(string: urlString) else {
            isLoadingModels = false
            errorMessage = AlertError(message: "Invalid API URL")
            return
        }

        let request = URLRequest(url: url, timeoutInterval: 30)
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoadingModels = false
                if let error = error {
                    self.errorMessage = AlertError(message: "Request failed: \(error.localizedDescription)")
                    return
                }
                guard let data = data,
                      let modelList = try? JSONDecoder().decode(ModelListResponse.self, from: data) else {
                    self.errorMessage = AlertError(message: "Unable to parse model list")
                    return
                }
                self.availableModels = modelList.data.map { $0.id }
                if !self.availableModels.contains(self.viewModel.selectedModel),
                   let firstModel = self.availableModels.first {
                    self.viewModel.selectedModel = firstModel
                }
            }
        }.resume()
    }
}

// MARK: - LabeledTextField

struct LabeledTextField: View {
    var label: String
    var placeholder: String
    @Binding var text: String

    var body: some View {
        #if os(macOS)
        HStack(alignment: .center) {
            Text(label)
                .frame(width: 150, alignment: .trailing)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
        #else
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
        }
        #endif
    }
}

#Preview {
    SettingsView()
}
