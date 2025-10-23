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

    // Preset deletion confirmation
    @State private var showDeletePresetAlert = false

    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    init() {
        _viewModel = ObservedObject(wrappedValue: SettingsViewModel())
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            Form {
                serverSection
                presetSection
                voiceOutputSection
                chatSection
            }
            .formStyle(.grouped)
        }
        .frame(width: 600, height: 720)
        .onAppear { fetchAvailableModels() }
        .alert(item: $errorMessage) { error in
            Alert(title: Text("Error"),
                  message: Text(error.message),
                  dismissButton: .default(Text("OK")))
        }
        .alert("Delete this preset?",
               isPresented: $showDeletePresetAlert) {
            Button("Delete", role: .destructive) { viewModel.deleteCurrentPreset() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        #else
        NavigationView {
            Form {
                serverSection
                presetSection
                voiceOutputSection
                chatSection
            }
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
            .alert("Delete this preset?",
                   isPresented: $showDeletePresetAlert) {
                Button("Delete", role: .destructive) { viewModel.deleteCurrentPreset() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
        }
        #endif
    }

    // MARK: - Sections

    private var serverSection: some View {
        Section(header: Text("Voice Server")) {
            LabeledTextField(
                label: "Server Address",
                placeholder: "http://127.0.0.1:9880",
                text: $viewModel.serverAddress
            )
            LabeledTextField(
                label: "Text Language",
                placeholder: "text_lang (e.g. auto/zh/en)",
                text: $viewModel.textLang
            )
        }
    }

    private var presetSection: some View {
        Section(header: Text("Model Preset")) {
            // Preset Picker Row + actions
            VStack(spacing: 10) {
                #if os(macOS)
                HStack(alignment: .center, spacing: 12) {
                    Text("Current Preset")
                        .frame(width: 150, alignment: .trailing)
                    Picker("", selection: $viewModel.selectedPresetID) {
                        ForEach(viewModel.presetList) { p in
                            Text(p.name).tag(Optional.some(p.id))
                        }
                    }
                    .pickerStyle(.menu) // macOS: explicit Pop-up style
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Spacer()

                    // Add preset - use plain style and explicit hit shape to avoid overlap
                    Button {
                        viewModel.addPreset()
                    } label: {
                        Label {
                            Text("Add")
                        } icon: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .padding(.horizontal, 2)

                    // Delete preset - destructive role + red trash icon, plain style to avoid menu-like propagation
                    Button(role: .destructive) {
                        showDeletePresetAlert = true
                    } label: {
                        Label {
                            Text("Delete")
                        } icon: {
                            Image(systemName: "trash")
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.red)
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .padding(.horizontal, 2)
                    .disabled(viewModel.presetList.count <= 1 || viewModel.selectedPresetID == nil)
                }
                #else
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Preset").font(.subheadline).foregroundColor(.secondary)
                    Picker("", selection: $viewModel.selectedPresetID) {
                        ForEach(viewModel.presetList) { p in
                            Text(p.name).tag(Optional.some(p.id))
                        }
                    }
                    .pickerStyle(.menu) // iOS: show as menu pop-up instead of navigation link

                    HStack(spacing: 16) {
                        Button {
                            viewModel.addPreset()
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())

                        Button(role: .destructive) {
                            showDeletePresetAlert = true
                        } label: {
                            Label {
                                Text("Delete")
                            } icon: {
                                Image(systemName: "trash")
                                    .symbolRenderingMode(.monochrome)
                                    .foregroundStyle(.red)
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .disabled(viewModel.presetList.count <= 1 || viewModel.selectedPresetID == nil)
                    }
                }
                #endif

                // Applying status / error
                if settingsManager.isApplyingPreset {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Applying preset...")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, 2)
                } else if let err = settingsManager.lastApplyError, !err.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text(err).foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }

            // Preset fields grouped for clarity
            Group {
                LabeledTextField(label: "Preset Name",
                                 placeholder: "Preset name",
                                 text: $viewModel.presetName)

                LabeledTextField(label: "ref_audio_path",
                                 placeholder: "GPT_SoVITS/refs/xxx.wav",
                                 text: $viewModel.presetRefAudioPath)
                LabeledTextField(label: "prompt_text",
                                 placeholder: "Reference text (optional)",
                                 text: $viewModel.presetPromptText)
                LabeledTextField(label: "prompt_lang",
                                 placeholder: "auto/zh/en ...",
                                 text: $viewModel.presetPromptLang)

                LabeledTextField(label: "GPT weights path",
                                 placeholder: "GPT_SoVITS/pretrained_models/s1xxx.ckpt",
                                 text: $viewModel.presetGPTWeightsPath)
                LabeledTextField(label: "SoVITS weights path",
                                 placeholder: "GPT_SoVITS/pretrained_models/s2xxx.pth",
                                 text: $viewModel.presetSoVITSWeightsPath)
            }

            // Apply button
            HStack {
                Spacer()
                Button {
                    viewModel.applySelectedPresetNow()
                } label: {
                    Label("Apply Preset Now", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                }
                .disabled(settingsManager.isApplyingPreset || viewModel.selectedPresetID == nil)
            }
            .padding(.top, 6)
        }
    }

    private var voiceOutputSection: some View {
        Section(header: Text("Voice Output")) {
            #if os(macOS)
            HStack {
                Text("Enable Streaming")
                    .frame(width: 150, alignment: .trailing)
                Toggle("", isOn: $viewModel.enableStreaming)
            }
            HStack {
                Text("Auto Read After Generation")
                    .frame(width: 150, alignment: .trailing)
                Toggle("", isOn: $viewModel.autoReadAfterGeneration)
            }
            HStack {
                Text("Split Method")
                    .frame(width: 150, alignment: .trailing)
                Picker("", selection: $viewModel.autoSplit) {
                    Text("cut0: No Split").tag("cut0")
                    Text("cut1: every 4 sentences").tag("cut1")
                    Text("cut2: every 50 chars").tag("cut2")
                    Text("cut3: by Chinese period").tag("cut3")
                    Text("cut4: by English period").tag("cut4")
                    Text("cut5: by punctuation").tag("cut5")
                }
                .disabled(viewModel.enableStreaming)
            }
            #else
            Toggle("Enable Streaming", isOn: $viewModel.enableStreaming)
            Toggle("Auto Read After Generation", isOn: $viewModel.autoReadAfterGeneration)
            Picker("Split Method", selection: $viewModel.autoSplit) {
                Text("cut0: No Split").tag("cut0")
                Text("cut1: every 4 sentences").tag("cut1")
                Text("cut2: every 50 chars").tag("cut2")
                Text("cut3: by Chinese period").tag("cut3")
                Text("cut4: by English period").tag("cut4")
                Text("cut5: by punctuation").tag("cut5")
            }
            .disabled(viewModel.enableStreaming)
            #endif
        }
    }

    private var chatSection: some View {
        Section(header: Text("Chat Server Settings")) {
            LabeledTextField(label: "Chat API URL",
                             placeholder: "Enter chat API URL",
                             text: $viewModel.apiURL)

            if isLoadingModels {
                HStack {
                    ProgressView("Loading model list...")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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

            HStack {
                Spacer()
                Button(action: fetchAvailableModels) {
                    Label("Refresh Model List", systemImage: "arrow.clockwise.circle")
                }
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Networking (List Models)

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
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .frame(width: 150, alignment: .trailing)
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 2)
        #else
        HStack(spacing: 12) {
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
        .environmentObject(SettingsManager.shared)
}
