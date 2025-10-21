//
//  SettingsView.swift
//  Voice Chat
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
    @State private var showDeletePresetAlert = false

    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    init() {
        _viewModel = ObservedObject(wrappedValue: SettingsViewModel())
    }

    var body: some View {
#if os(macOS)
        macSettingsView
#else
        iOSSettingsView
#endif
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
            .task(fetchAvailableModels)
    }

#if os(macOS)
    private var macSettingsView: some View {
        SettingsTabView {
            settingsForm
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }
        }
        .frame(minWidth: 560, minHeight: 640)
    }
#endif

    private var iOSSettingsView: some View {
        NavigationStack {
            settingsForm
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var settingsForm: some View {
        Form {
            serverSection
            presetSection
            voiceOutputSection
            chatSection
        }
        .formStyle(.grouped)
    }

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
            presetPicker
            presetFields
            presetApplyButton
        }
    }

    @ViewBuilder
    private var presetPicker: some View {
#if os(macOS)
        HStack(alignment: .center, spacing: 12) {
            Text("Current Preset")
                .frame(width: 150, alignment: .trailing)
            Picker("", selection: $viewModel.selectedPresetID) {
                ForEach(viewModel.presetList) { preset in
                    Text(preset.name).tag(Optional.some(preset.id))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        presetActions
#else
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Preset")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Picker("", selection: $viewModel.selectedPresetID) {
                ForEach(viewModel.presetList) { preset in
                    Text(preset.name).tag(Optional.some(preset.id))
                }
            }
            .pickerStyle(.menu)
            presetActions
        }
#endif
        if settingsManager.isApplyingPreset {
            HStack(spacing: 8) {
                ProgressView()
                Text("Applying preset...")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.top, 2)
        } else if let error = settingsManager.lastApplyError, !error.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.top, 2)
        }
    }

    private var presetActions: some View {
        HStack(spacing: 12) {
#if os(macOS)
            Spacer()
#endif
            Button(action: viewModel.addPreset) {
                Label("Add", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            Button(role: .destructive) {
                showDeletePresetAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .disabled(viewModel.presetList.count <= 1 || viewModel.selectedPresetID == nil)
        }
    }

    private var presetFields: some View {
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
    }

    private var presetApplyButton: some View {
        HStack {
            Spacer()
            Button(action: viewModel.applySelectedPresetNow) {
                Label("Apply Preset Now", systemImage: "arrow.triangle.2.circlepath.circle.fill")
            }
            .disabled(settingsManager.isApplyingPreset || viewModel.selectedPresetID == nil)
        }
        .padding(.top, 6)
    }

    private var voiceOutputSection: some View {
        Section(header: Text("Voice Output")) {
#if os(macOS)
            macVoiceSettings
#else
            Toggle("Enable Streaming", isOn: $viewModel.enableStreaming)
            Toggle("Auto Read After Generation", isOn: $viewModel.autoReadAfterGeneration)
            Picker("Split Method", selection: $viewModel.autoSplit) {
                splitOptions
            }
            .disabled(viewModel.enableStreaming)
#endif
        }
    }

#if os(macOS)
    private var macVoiceSettings: some View {
        VStack(spacing: 8) {
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
                    splitOptions
                }
                .disabled(viewModel.enableStreaming)
            }
        }
    }
#endif

    @ViewBuilder
    private var splitOptions: some View {
        Text("cut0: No Split").tag("cut0")
        Text("cut1: every 4 sentences").tag("cut1")
        Text("cut2: every 50 chars").tag("cut2")
        Text("cut3: by Chinese period").tag("cut3")
        Text("cut4: by English period").tag("cut4")
        Text("cut5: by punctuation").tag("cut5")
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
        URLSession.shared.dataTask(with: request) { data, _, error in
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

// MARK: - Labeled Text Field

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
