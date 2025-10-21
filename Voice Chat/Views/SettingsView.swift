//
//  SettingsView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.22.
//  Updated by OpenAI Assistant on 2024/05/25.
//

import SwiftUI

// MARK: - Alert Model

struct AlertError: Identifiable {
    var id = UUID()
    var message: String
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var errorMessage: AlertError?
    @State private var showDeletePresetAlert = false

    var body: some View {
#if os(macOS)
        macOSBody
            .frame(minWidth: 560, idealWidth: 620, minHeight: 520, idealHeight: 640)
#else
        iOSBody
#endif
    }

    // MARK: - Platform Specific Bodies

#if os(macOS)
    private var macOSBody: some View {
        SettingsTabView {
            Form {
                voiceServerSection
                chatSection
            }
            .tabItem { Label(L10n.Settings.generalTab, systemImage: "gearshape") }

            Form {
                presetSection
            }
            .tabItem { Label(L10n.Settings.presetsTab, systemImage: "slider.horizontal.3") }

            Form {
                voiceOutputSection
            }
            .tabItem { Label(L10n.Settings.voiceTab, systemImage: "waveform") }
        }
        .onAppear { fetchAvailableModels() }
        .alert(item: $errorMessage) { error in
            Alert(title: Text(L10n.Common.error),
                  message: Text(error.message),
                  dismissButton: .default(Text(L10n.Common.ok)))
        }
        .alert(L10n.Settings.deletePresetTitle,
               isPresented: $showDeletePresetAlert) {
            Button(L10n.Common.delete, role: .destructive) { viewModel.deleteCurrentPreset() }
            Button(L10n.Common.cancel, role: .cancel) { }
        } message: {
            Text(L10n.Settings.deletePresetMessage)
        }
    }
#else
    private var iOSBody: some View {
        NavigationStack {
            Form {
                voiceServerSection
                presetSection
                voiceOutputSection
                chatSection
            }
            .navigationTitle(L10n.Settings.navigationTitle)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Common.close) { dismiss() }
                }
            }
            .onAppear { fetchAvailableModels() }
            .alert(item: $errorMessage) { error in
                Alert(title: Text(L10n.Common.error),
                      message: Text(error.message),
                      dismissButton: .default(Text(L10n.Common.ok)))
            }
            .alert(L10n.Settings.deletePresetTitle,
                   isPresented: $showDeletePresetAlert) {
                Button(L10n.Common.delete, role: .destructive) { viewModel.deleteCurrentPreset() }
                Button(L10n.Common.cancel, role: .cancel) { }
            } message: {
                Text(L10n.Settings.deletePresetMessage)
            }
        }
    }
#endif

    // MARK: - Sections

    private var voiceServerSection: some View {
        Section(header: Text(L10n.Settings.voiceServerSection)) {
            LabeledTextField(
                label: L10n.Settings.serverAddress,
                placeholder: L10n.Settings.serverAddressPlaceholder,
                text: $viewModel.serverAddress
            )
            LabeledTextField(
                label: L10n.Settings.textLanguage,
                placeholder: L10n.Settings.textLanguagePlaceholder,
                text: $viewModel.textLang
            )
        }
    }

    private var presetSection: some View {
        Section(header: Text(L10n.Settings.modelPresetSection)) {
            VStack(spacing: 12) {
#if os(macOS)
                HStack(spacing: 12) {
                    Text(L10n.Settings.currentPreset)
                        .frame(width: 160, alignment: .trailing)
                    Picker("", selection: $viewModel.selectedPresetID) {
                        ForEach(viewModel.presetList) { preset in
                            Text(preset.name).tag(Optional.some(preset.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Spacer()
                    Button { viewModel.addPreset() } label: {
                        Label(L10n.Settings.addPreset, systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) { showDeletePresetAlert = true } label: {
                        Label(L10n.Settings.deletePreset, systemImage: "trash")
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.presetList.count <= 1 || viewModel.selectedPresetID == nil)
                }
#else
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Settings.currentPreset)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $viewModel.selectedPresetID) {
                        ForEach(viewModel.presetList) { preset in
                            Text(preset.name).tag(Optional.some(preset.id))
                        }
                    }
                    .pickerStyle(.menu)

                    HStack(spacing: 16) {
                        Button { viewModel.addPreset() } label: {
                            Label(L10n.Settings.addPreset, systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) { showDeletePresetAlert = true } label: {
                            Label(L10n.Settings.deletePreset, systemImage: "trash")
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.presetList.count <= 1 || viewModel.selectedPresetID == nil)
                    }
                }
#endif

                if settingsManager.isApplyingPreset {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(L10n.Settings.applyingPreset)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if let error = settingsManager.lastApplyError, !error.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }

            Group {
                LabeledTextField(label: L10n.Settings.presetName, placeholder: "", text: $viewModel.presetName)
                LabeledTextField(label: L10n.Settings.refAudioPath, placeholder: L10n.Settings.refAudioPlaceholder, text: $viewModel.presetRefAudioPath)
                LabeledTextField(label: L10n.Settings.promptText, placeholder: L10n.Settings.promptTextPlaceholder, text: $viewModel.presetPromptText)
                LabeledTextField(label: L10n.Settings.promptLanguage, placeholder: "auto/zh/en", text: $viewModel.presetPromptLang)
                LabeledTextField(label: L10n.Settings.gptWeightsPath, placeholder: "GPT_SoVITS/pretrained_models/s1xxx.ckpt", text: $viewModel.presetGPTWeightsPath)
                LabeledTextField(label: L10n.Settings.sovitsWeightsPath, placeholder: "GPT_SoVITS/pretrained_models/s2xxx.pth", text: $viewModel.presetSoVITSWeightsPath)
            }

            HStack {
                Spacer()
                Button(action: viewModel.applySelectedPresetNow) {
                    Label(L10n.Settings.applyPresetNow, systemImage: "arrow.triangle.2.circlepath.circle.fill")
                }
                .disabled(settingsManager.isApplyingPreset || viewModel.selectedPresetID == nil)
            }
        }
    }

    private var voiceOutputSection: some View {
        Section(header: Text(L10n.Settings.voiceOutputSection)) {
#if os(macOS)
            SettingsToggleRow(label: L10n.Settings.enableStreaming, isOn: $viewModel.enableStreaming)
            SettingsToggleRow(label: L10n.Settings.autoReadAfterGeneration, isOn: $viewModel.autoReadAfterGeneration)
            SettingsPickerRow(label: L10n.Settings.splitMethod, selection: $viewModel.autoSplit) {
                splitPickerOptions
            }
            .disabled(viewModel.enableStreaming)
#else
            Toggle(L10n.Settings.enableStreaming, isOn: $viewModel.enableStreaming)
            Toggle(L10n.Settings.autoReadAfterGeneration, isOn: $viewModel.autoReadAfterGeneration)
            Picker(L10n.Settings.splitMethod, selection: $viewModel.autoSplit) {
                splitPickerOptions
            }
            .disabled(viewModel.enableStreaming)
#endif
        }
    }

    private var chatSection: some View {
        Section(header: Text(L10n.Settings.chatServerSection)) {
            LabeledTextField(label: L10n.Settings.chatApiUrl, placeholder: "https://example.com", text: $viewModel.apiURL)

            if isLoadingModels {
                ProgressView(L10n.Settings.loadingModels)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
#if os(macOS)
                SettingsPickerRow(label: L10n.Settings.selectModel, selection: $viewModel.selectedModel) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
#else
                Picker(L10n.Settings.selectModel, selection: $viewModel.selectedModel) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
#endif
            }

            HStack {
                Spacer()
                Button(action: fetchAvailableModels) {
                    Label(L10n.Settings.refreshModelList, systemImage: "arrow.clockwise.circle")
                }
            }
        }
    }

    private var splitPickerOptions: some View {
        Group {
            Text("cut0: No Split").tag("cut0")
            Text("cut1: every 4 sentences").tag("cut1")
            Text("cut2: every 50 chars").tag("cut2")
            Text("cut3: by Chinese period").tag("cut3")
            Text("cut4: by English period").tag("cut4")
            Text("cut5: by punctuation").tag("cut5")
        }
    }

    // MARK: - Networking

    private func fetchAvailableModels() {
        guard !viewModel.apiURL.isEmpty else {
            errorMessage = AlertError(message: L10n.Settings.apiUrlEmptyErrorText)
            return
        }

        guard let url = URL(string: "\(viewModel.apiURL)/v1/models") else {
            errorMessage = AlertError(message: L10n.Settings.invalidApiUrlErrorText)
            return
        }

        isLoadingModels = true
        errorMessage = nil

        let request = URLRequest(url: url, timeoutInterval: 30)
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isLoadingModels = false

                if let error = error {
                    errorMessage = AlertError(message: "\(L10n.Settings.requestFailedErrorText) \(error.localizedDescription)")
                    return
                }

                guard let data = data,
                      let modelList = try? JSONDecoder().decode(ModelListResponse.self, from: data) else {
                    errorMessage = AlertError(message: L10n.Settings.failedToParseModelsErrorText)
                    return
                }

                availableModels = modelList.data.map { $0.id }
                if !availableModels.contains(viewModel.selectedModel), let firstModel = availableModels.first {
                    viewModel.selectedModel = firstModel
                }
            }
        }.resume()
    }
}

// MARK: - Helper Views

private struct SettingsToggleRow: View {
    var label: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 200, alignment: .trailing)
                .foregroundStyle(.primary)
            Toggle("", isOn: $isOn)
        }
    }
}

private struct SettingsPickerRow<SelectionValue: Hashable, Content: View>: View {
    var label: LocalizedStringKey
    @Binding var selection: SelectionValue
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 200, alignment: .trailing)
                .foregroundStyle(.primary)
            Picker("", selection: $selection) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LabeledTextField: View {
    var label: LocalizedStringKey
    var placeholder: LocalizedStringKey
    @Binding var text: String

    var body: some View {
#if os(macOS)
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .frame(width: 200, alignment: .trailing)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
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
        .environmentObject(SettingsViewModel())
        .environmentObject(SettingsManager.shared)
}
