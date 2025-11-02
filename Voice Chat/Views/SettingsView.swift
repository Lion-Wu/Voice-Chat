//
//  SettingsView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.22.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var chatServerErrorMessage: String?

    // Preset deletion confirmation state
    @State private var showDeletePresetAlert = false

    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
#if os(macOS)
    @State private var measuredContentSize: CGSize = .zero
#endif

    init() {
        _viewModel = ObservedObject(wrappedValue: SettingsViewModel())
    }

    var body: some View {
        #if os(macOS)
        applyCommonModifiers(
            macSettingsTabs
                .fixedSize()
                .overlay(WindowSizeReader().allowsHitTesting(false))
        )
        .onPreferenceChange(WindowSizePreferenceKey.self) { newSize in
            updateWindowSizeIfNeeded(newSize)
        }
        #else
        applyCommonModifiers(
            NavigationView {
                Form {
                    serverSection()
                    presetSection()
                    voiceOutputSection()
                    chatSection()
                }
                    .navigationBarTitle("Settings", displayMode: .inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Close") { dismiss() }
                        }
                    }
            }
        )
        #endif
    }

    @ViewBuilder
    private func applyCommonModifiers<Content: View>(_ content: Content) -> some View {
        content
            .onAppear { fetchAvailableModels() }
            .alert("Delete this preset?",
                   isPresented: $showDeletePresetAlert) {
                Button("Delete", role: .destructive) { viewModel.deleteCurrentPreset() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
    }

    // MARK: - Sections

#if os(macOS)
    private var macSettingsTabs: some View {
        TabView {
            macVoiceServerTab
            macModelPresetTab
            macVoiceOutputTab
            macChatServerTab
        }
        .scenePadding()
    }

    private var macVoiceServerTab: some View {
        Form {
            serverSection(hideHeader: true)
        }
        .formStyle(.grouped)
        .tabItem {
            Label("Voice Server", systemImage: "antenna.radiowaves.left.and.right")
        }
    }

    private var macModelPresetTab: some View {
        Form {
            presetSection(hideHeader: true)
        }
        .formStyle(.grouped)
        .tabItem {
            Label("Model Preset", systemImage: "square.stack.3d.up.fill")
        }
    }

    private var macVoiceOutputTab: some View {
        Form {
            voiceOutputSection(hideHeader: true)
        }
        .formStyle(.grouped)
        .tabItem {
            Label("Voice Output", systemImage: "speaker.wave.3.fill")
        }
    }

    private var macChatServerTab: some View {
        Form {
            chatSection(hideHeader: true)
        }
        .formStyle(.grouped)
        .tabItem {
            Label("Chat Server", systemImage: "message.and.waveform.fill")
        }
    }
#endif

    @ViewBuilder
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        #if os(macOS)
        Text(title)
            .font(.headline)
            .textCase(.none)
        #else
        Text(title)
        #endif
    }

    @ViewBuilder
    private func serverSection(hideHeader: Bool = false) -> some View {
        Section {
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
        } header: {
            if hideHeader {
                EmptyView()
            } else {
                sectionHeader("Voice Server")
            }
        }
    }

    @ViewBuilder
    private func presetSection(hideHeader: Bool = false) -> some View {
        Section {
            presetPickerRow
            presetActionButtons
            presetStatusView
            presetDetailFields
            presetApplyRow
        } header: {
            if hideHeader {
                EmptyView()
            } else {
                sectionHeader("Model Preset")
            }
        }
    }

    @ViewBuilder
    private var presetPickerRow: some View {
        #if os(macOS)
        LabeledContent("Current Preset") {
            Picker("", selection: $viewModel.selectedPresetID) {
                ForEach(viewModel.presetList) { p in
                    Text(p.name).tag(Optional.some(p.id))
                }
            }
            .labelsHidden()
        }
        #else
        Picker("Current Preset", selection: $viewModel.selectedPresetID) {
            ForEach(viewModel.presetList) { p in
                Text(p.name).tag(Optional.some(p.id))
            }
        }
        .pickerStyle(.menu)
        #endif
    }

    @ViewBuilder
    private var presetActionButtons: some View {
        #if os(macOS)
        HStack {
            Spacer()
            HStack(spacing: 8) {
                Button {
                    viewModel.addPreset()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .help("Add preset")

                Button(role: .destructive) {
                    showDeletePresetAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .help("Delete selected preset")
                .disabled(viewModel.presetList.count <= 1 || viewModel.selectedPresetID == nil)
            }
        }
        #else
        HStack(spacing: 16) {
            Button {
                viewModel.addPreset()
            } label: {
                Label("Add", systemImage: "plus.circle.fill")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            Button(role: .destructive) {
                showDeletePresetAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .disabled(viewModel.presetList.count <= 1 || viewModel.selectedPresetID == nil)
        }
        #endif
    }

    @ViewBuilder
    private var presetStatusView: some View {
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

    @ViewBuilder
    private var chatServerStatusView: some View {
        if let message = chatServerErrorMessage, !message.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(message)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.top, 2)
        }
    }

    private var presetDetailFields: some View {
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

    private var presetApplyRow: some View {
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

    @ViewBuilder
    private func voiceOutputSection(hideHeader: Bool = false) -> some View {
        Section {
            #if os(macOS)
            Toggle("Enable Streaming", isOn: $viewModel.enableStreaming)
            Toggle("Auto Read After Generation", isOn: $viewModel.autoReadAfterGeneration)
            LabeledContent("Split Method") {
                Picker("", selection: $viewModel.autoSplit) {
                    Text("cut0: No Split").tag("cut0")
                    Text("cut1: every 4 sentences").tag("cut1")
                    Text("cut2: every 50 chars").tag("cut2")
                    Text("cut3: by Chinese period").tag("cut3")
                    Text("cut4: by English period").tag("cut4")
                    Text("cut5: by punctuation").tag("cut5")
                }
                .labelsHidden()
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
        } header: {
            if hideHeader {
                EmptyView()
            } else {
                sectionHeader("Voice Output")
            }
        }
    }

    @ViewBuilder
    private func chatSection(hideHeader: Bool = false) -> some View {
        Section {
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
                LabeledContent("Select Model") {
                    Picker("", selection: $viewModel.selectedModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()
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

            chatServerStatusView
        } header: {
            if hideHeader {
                EmptyView()
            } else {
                sectionHeader("Chat Server Settings")
            }
        }
    }

#if os(macOS)
    private func updateWindowSizeIfNeeded(_ newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        guard measuredContentSize != newSize else { return }
        measuredContentSize = newSize

        DispatchQueue.main.async {
            guard let window = NSApp?.windows.first(where: { $0.isKeyWindow }) else { return }
            let targetSize = NSSize(width: newSize.width, height: newSize.height)
            window.setContentSize(targetSize)
            window.contentMinSize = targetSize
            window.contentMaxSize = targetSize
        }
    }
#endif

    // MARK: - Networking (List Models)

    private func fetchAvailableModels() {
        chatServerErrorMessage = nil

        guard !viewModel.apiURL.isEmpty else {
            isLoadingModels = false
            chatServerErrorMessage = NSLocalizedString("API URL is empty or invalid.", comment: "Shown when the model list URL is missing")
            return
        }

        let urlString = "\(viewModel.apiURL)/v1/models"
        guard let url = URL(string: urlString) else {
            isLoadingModels = false
            chatServerErrorMessage = NSLocalizedString("Invalid API URL", comment: "Shown when the model list URL cannot be parsed")
            return
        }

        isLoadingModels = true

        let request = URLRequest(url: url, timeoutInterval: 30)
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoadingModels = false

                if let error = error {
                    let message = String(format: NSLocalizedString("Request failed: %@", comment: "Model list request failed"), error.localizedDescription)
                    self.chatServerErrorMessage = message
                    return
                }

                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    let message = String(format: NSLocalizedString("Chat server responded with status %d.", comment: "Displayed when the chat server returns an error"), http.statusCode)
                    self.chatServerErrorMessage = message
                    return
                }

                guard let data = data,
                      let modelList = try? JSONDecoder().decode(ModelListResponse.self, from: data) else {
                    self.chatServerErrorMessage = NSLocalizedString("Unable to parse model list", comment: "Decoding the model list failed")
                    return
                }

                self.chatServerErrorMessage = nil
                self.availableModels = modelList.data.map { $0.id }
                if !self.availableModels.contains(self.viewModel.selectedModel),
                   let firstModel = self.availableModels.first {
                    self.viewModel.selectedModel = firstModel
                }
            }
        }.resume()
    }
}

#if os(macOS)
private struct WindowSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct WindowSizeReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: WindowSizePreferenceKey.self, value: proxy.size)
        }
    }
}
#endif

// MARK: - LabeledTextField

struct LabeledTextField: View {
    var label: String
    var placeholder: String
    @Binding var text: String

    var body: some View {
        #if os(macOS)
        LabeledContent(LocalizedStringKey(label)) {
            TextField("", text: $text, prompt: Text(LocalizedStringKey(placeholder)))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(label))
                .font(.subheadline)
                .foregroundColor(.secondary)
            TextField(LocalizedStringKey(placeholder), text: $text)
                .textInputAutocapitalization(.never)
        }
        #endif
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager.shared)
}
