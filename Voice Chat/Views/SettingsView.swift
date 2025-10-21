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
    @State private var showDeletePresetAlert = false

    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    init() {
        _viewModel = ObservedObject(wrappedValue: SettingsViewModel())
    }

    #if os(macOS)
    var body: some View { macContent }
    #else
    var body: some View { iosContent }
    #endif

    // MARK: - Platform Containers

    #if os(macOS)
    private var macContent: some View {
        applyAlerts(
            settingsForm
                .padding(24)
                .frame(width: 560, height: 720)
                .formStyle(.grouped)
        )
        .onAppear(perform: fetchAvailableModels)
    }
    #else
    private var iosContent: some View {
        applyAlerts(
            NavigationView {
                settingsForm
                    .navigationBarTitle(Text(L10n.Settings.title), displayMode: .inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(L10n.General.close) { dismiss() }
                        }
                    }
            }
        )
        .onAppear(perform: fetchAvailableModels)
    }
    #endif

    private var settingsForm: some View {
        Form {
            serverSection
            presetSection
            voiceOutputSection
            chatSection
        }
    }

    private func applyAlerts<Content: View>(_ content: Content) -> some View {
        content
            .alert(item: $errorMessage) { error in
                Alert(title: Text(L10n.General.errorTitle),
                      message: Text(error.message),
                      dismissButton: .default(Text(L10n.General.ok)))
            }
            .alert(L10n.Settings.deletePresetPrompt,
                   isPresented: $showDeletePresetAlert) {
                Button(L10n.General.delete, role: .destructive) { viewModel.deleteCurrentPreset() }
                Button(L10n.General.cancel, role: .cancel) { }
            } message: {
                Text(L10n.Settings.deletePresetConfirmation)
            }
    }

    // MARK: - Sections

    private var serverSection: some View {
        Section(header: Text(L10n.Settings.voiceServerSection)) {
            LabeledTextField(
                label: L10n.Settings.serverAddressLabel,
                placeholder: L10n.Settings.serverAddressPlaceholder,
                text: $viewModel.serverAddress
            )
            LabeledTextField(
                label: L10n.Settings.textLanguageLabel,
                placeholder: L10n.Settings.textLanguagePlaceholder,
                text: $viewModel.textLang
            )
        }
    }

    private var presetSection: some View {
        Section(header: Text(L10n.Settings.modelPresetSection)) {
            VStack(spacing: 10) {
                #if os(macOS)
                HStack(alignment: .center, spacing: 12) {
                    Text(L10n.Settings.currentPreset)
                        .frame(width: 150, alignment: .trailing)
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
                        Label { Text(L10n.Settings.addPreset) } icon: { Image(systemName: "plus.circle.fill") }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .padding(.horizontal, 2)

                    Button(role: .destructive) { showDeletePresetAlert = true } label: {
                        Label { Text(L10n.Settings.deletePreset) } icon: {
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
                    Text(L10n.Settings.currentPreset)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
                        .contentShape(Rectangle())

                        Button(role: .destructive) { showDeletePresetAlert = true } label: {
                            Label(L10n.Settings.deletePreset, systemImage: "trash")
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .disabled(viewModel.presetList.count <= 1 || viewModel.selectedPresetID == nil)
                    }
                }
                #endif

                if settingsManager.isApplyingPreset {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(L10n.Settings.applyingPreset)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, 2)
                } else if let err = settingsManager.lastApplyError, !err.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(err)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }

            Group {
                LabeledTextField(label: L10n.Settings.presetNameLabel,
                                 placeholder: L10n.Settings.presetNamePlaceholder,
                                 text: $viewModel.presetName)

                LabeledTextField(label: L10n.Settings.refAudioPathLabel,
                                 placeholder: L10n.Settings.refAudioPathPlaceholder,
                                 text: $viewModel.presetRefAudioPath)

                LabeledTextField(label: L10n.Settings.promptTextLabel,
                                 placeholder: L10n.Settings.referenceTextPlaceholder,
                                 text: $viewModel.presetPromptText)

                LabeledTextField(label: L10n.Settings.promptLangLabel,
                                 placeholder: L10n.Settings.promptLangPlaceholder,
                                 text: $viewModel.presetPromptLang)

                LabeledTextField(label: L10n.Settings.gptWeightsLabel,
                                 placeholder: L10n.Settings.gptWeightsPlaceholder,
                                 text: $viewModel.presetGPTWeightsPath)

                LabeledTextField(label: L10n.Settings.sovitsWeightsLabel,
                                 placeholder: L10n.Settings.sovitsWeightsPlaceholder,
                                 text: $viewModel.presetSoVITSWeightsPath)
            }

            HStack {
                Spacer()
                Button { viewModel.applySelectedPresetNow() } label: {
                    Label { Text(L10n.Settings.applyPresetNow) } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    }
                }
                .disabled(settingsManager.isApplyingPreset || viewModel.selectedPresetID == nil)
            }
            .padding(.top, 6)
        }
    }

    private var voiceOutputSection: some View {
        Section(header: Text(L10n.Settings.voiceOutputSection)) {
            #if os(macOS)
            HStack {
                Text(L10n.Settings.enableStreaming)
                    .frame(width: 150, alignment: .trailing)
                Toggle("", isOn: $viewModel.enableStreaming)
            }
            HStack {
                Text(L10n.Settings.autoReadAfterGeneration)
                    .frame(width: 150, alignment: .trailing)
                Toggle("", isOn: $viewModel.autoReadAfterGeneration)
            }
            HStack {
                Text(L10n.Settings.splitMethod)
                    .frame(width: 150, alignment: .trailing)
                Picker("", selection: $viewModel.autoSplit) {
                    Text(L10n.Settings.splitOptionCut0).tag("cut0")
                    Text(L10n.Settings.splitOptionCut1).tag("cut1")
                    Text(L10n.Settings.splitOptionCut2).tag("cut2")
                    Text(L10n.Settings.splitOptionCut3).tag("cut3")
                    Text(L10n.Settings.splitOptionCut4).tag("cut4")
                    Text(L10n.Settings.splitOptionCut5).tag("cut5")
                }
                .disabled(viewModel.enableStreaming)
            }
            #else
            Toggle(L10n.Settings.enableStreaming, isOn: $viewModel.enableStreaming)
            Toggle(L10n.Settings.autoReadAfterGeneration, isOn: $viewModel.autoReadAfterGeneration)
            Picker(L10n.Settings.splitMethod, selection: $viewModel.autoSplit) {
                Text(L10n.Settings.splitOptionCut0).tag("cut0")
                Text(L10n.Settings.splitOptionCut1).tag("cut1")
                Text(L10n.Settings.splitOptionCut2).tag("cut2")
                Text(L10n.Settings.splitOptionCut3).tag("cut3")
                Text(L10n.Settings.splitOptionCut4).tag("cut4")
                Text(L10n.Settings.splitOptionCut5).tag("cut5")
            }
            .disabled(viewModel.enableStreaming)
            #endif
        }
    }

    private var chatSection: some View {
        Section(header: Text(L10n.Settings.chatServerSection)) {
            LabeledTextField(label: L10n.Settings.chatApiUrlLabel,
                             placeholder: L10n.Settings.chatApiUrlPlaceholder,
                             text: $viewModel.apiURL)

            if isLoadingModels {
                HStack {
                    ProgressView(L10n.Settings.loadingModelList)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                #if os(macOS)
                HStack {
                    Text(L10n.Settings.selectModel)
                        .frame(width: 150, alignment: .trailing)
                    Picker("", selection: $viewModel.selectedModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
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
            .padding(.top, 6)
        }
    }

    // MARK: - Networking (List Models)

    private func fetchAvailableModels() {
        guard !viewModel.apiURL.isEmpty else {
            errorMessage = AlertError(message: L10n.Settings.errorEmptyApiUrl)
            return
        }
        isLoadingModels = true
        errorMessage = nil

        let urlString = "\(viewModel.apiURL)/v1/models"
        guard let url = URL(string: urlString) else {
            isLoadingModels = false
            errorMessage = AlertError(message: L10n.Settings.errorInvalidApiUrl)
            return
        }

        let request = URLRequest(url: url, timeoutInterval: 30)
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoadingModels = false
                if let error = error {
                    self.errorMessage = AlertError(message: L10n.Settings.errorRequestFailed(error.localizedDescription))
                    return
                }
                guard let data = data,
                      let modelList = try? JSONDecoder().decode(ModelListResponse.self, from: data) else {
                    self.errorMessage = AlertError(message: L10n.Settings.errorParseFailed)
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
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 2)
        #endif
    }
}
