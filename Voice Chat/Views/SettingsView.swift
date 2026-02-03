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
    @StateObject private var viewModel = SettingsViewModel()

    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var isRetryingModels = false
    @State private var modelRetryAttempt: Int = 0
    @State private var modelRetryLastError: String?
    @State private var chatServerErrorMessage: String?
    @State private var modelFetchRequestID = UUID()

    // Preset deletion confirmation state
    @State private var showDeletePresetAlert = false
    @State private var showDeleteChatServerPresetAlert = false
    @State private var showDeleteVoiceServerPresetAlert = false
    @State private var showDeleteNormalPromptPresetAlert = false
    @State private var showDeleteVoicePromptPresetAlert = false

    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss
#if os(macOS)
    @State private var measuredContentSize: CGSize = .zero
#endif

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
            NavigationStack {
                Form {
                    chatSection()
                    serverSection()
                    chatModelSection()
                    systemPromptSection()
                    presetSection()
                    voiceOutputSection()
                    developerSection()
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
            .background(AppBackgroundView())
            .onAppear {
                viewModel.refreshFromSettingsManager()
                fetchAvailableModels()
            }
            .alert("Delete this preset?",
                   isPresented: $showDeletePresetAlert) {
                Button("Delete", role: .destructive) { viewModel.deleteCurrentPreset() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
            .alert("Delete this preset?",
                   isPresented: $showDeleteChatServerPresetAlert) {
                Button("Delete", role: .destructive) { viewModel.deleteSelectedChatServerPreset() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
            .alert("Delete this preset?",
                   isPresented: $showDeleteVoiceServerPresetAlert) {
                Button("Delete", role: .destructive) { viewModel.deleteSelectedVoiceServerPreset() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
            .alert("Delete this prompt preset?",
                   isPresented: $showDeleteNormalPromptPresetAlert) {
                Button("Delete", role: .destructive) { viewModel.deleteSelectedNormalSystemPromptPreset() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
            .alert("Delete this prompt preset?",
                   isPresented: $showDeleteVoicePromptPresetAlert) {
                Button("Delete", role: .destructive) { viewModel.deleteSelectedVoiceSystemPromptPreset() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
    }

    // MARK: - Sections

#if os(macOS)
    private var macSettingsTabs: some View {
        TabView {
            macServersTab
            macChatTab
            macVoiceOutputTab
            macDeveloperTab
        }
        .scenePadding()
    }

    private var macServersTab: some View {
        Form {
            chatSection()
            serverSection()
        }
        .formStyle(.grouped)
        .tabItem {
            Label("Servers", systemImage: "server.rack")
        }
    }

    private var macVoiceOutputTab: some View {
        Form {
            presetSection()
            voiceOutputSection()
        }
        .formStyle(.grouped)
        .tabItem {
            Label("Voice Settings", systemImage: "speaker.wave.3.fill")
        }
    }

    private var macChatTab: some View {
        Form {
            chatModelSection()
            systemPromptSection()
        }
        .formStyle(.grouped)
        .tabItem {
            Label("Chat", systemImage: "text.bubble.fill")
        }
    }

    private var macDeveloperTab: some View {
        Form {
            developerSection()
        }
        .formStyle(.grouped)
        .tabItem {
            Label("Developer", systemImage: "ladybug")
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
            #if os(macOS)
            LabeledContent("Preset") {
                Picker("", selection: $viewModel.selectedVoiceServerPresetID) {
                    ForEach(viewModel.voiceServerPresetList) { p in
                        Text(p.name).tag(Optional.some(p.id))
                    }
                }
                .labelsHidden()
            }

            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        viewModel.addVoiceServerPreset()
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help("Add preset")

                    Button(role: .destructive) {
                        showDeleteVoiceServerPresetAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help("Delete selected preset")
                    .disabled(viewModel.voiceServerPresetList.count <= 1 || viewModel.selectedVoiceServerPresetID == nil)
                }
            }
            #else
            Picker("Preset", selection: $viewModel.selectedVoiceServerPresetID) {
                ForEach(viewModel.voiceServerPresetList) { p in
                    Text(p.name).tag(Optional.some(p.id))
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 16) {
                Button {
                    viewModel.addVoiceServerPreset()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                Button(role: .destructive) {
                    showDeleteVoiceServerPresetAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(viewModel.voiceServerPresetList.count <= 1 || viewModel.selectedVoiceServerPresetID == nil)
            }
            #endif

            LabeledTextField(
                label: "Preset Name",
                placeholder: "Preset name",
                text: $viewModel.voiceServerPresetName
            )

            LabeledTextField(
                label: "Server URL",
                placeholder: "http://127.0.0.1:9880",
                text: $viewModel.serverAddress
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
            presetDetailFields
            presetApplyStatusRow
            presetApplyRow
        } header: {
            if hideHeader {
                EmptyView()
            } else {
                sectionHeader("Voice Model")
            }
        }
    }

    @ViewBuilder
    private var presetPickerRow: some View {
        #if os(macOS)
        LabeledContent("Preset") {
            Picker("", selection: $viewModel.selectedPresetID) {
                ForEach(viewModel.presetList) { p in
                    Text(p.name).tag(Optional.some(p.id))
                }
            }
            .labelsHidden()
        }
        #else
        Picker("Preset", selection: $viewModel.selectedPresetID) {
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
                Label("Apply Preset Now", systemImage: "arrow.triangle.2.circlepath.circle")
            }
            .settingsActionButtonStyle()
            #if os(macOS)
            .help("Apply selected preset now")
            #endif
            .disabled(settingsManager.isApplyingPreset || viewModel.selectedPresetID == nil)
        }
    }

    private var presetApplyStatusRow: some View {
        let shouldShowMessage = settingsManager.isApplyingPreset
            || !(settingsManager.lastApplyError?.isEmpty ?? true)
            || (settingsManager.lastPresetApplyAt != nil && settingsManager.lastPresetApplySucceeded)

        return HStack { Spacer() }
            .frame(minHeight: 22)
            .overlay(alignment: .leading) {
                if settingsManager.isApplyingPreset {
                    HStack(spacing: 8) {
                        ProgressView()
                            #if os(macOS)
                            .controlSize(.small)
                            #endif
                        if settingsManager.isRetryingPresetApply {
                            Text(String(format: NSLocalizedString("Retrying (attempt %d)...", comment: "Shown while auto retry is waiting to reconnect"), max(1, settingsManager.presetApplyRetryAttempt)))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text("Applying preset...")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(macOS)
                    .help(settingsManager.presetApplyRetryLastError ?? "")
                    #endif
                } else if let err = settingsManager.lastApplyError, !err.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(err)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(macOS)
                    .help(err)
                    #endif
                } else if settingsManager.lastPresetApplyAt != nil, settingsManager.lastPresetApplySucceeded {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Preset applied successfully.")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .opacity(shouldShowMessage ? 1 : 0)
            .accessibilityHidden(!shouldShowMessage)
            #if !os(macOS)
            .listRowSeparator(shouldShowMessage ? .visible : .hidden)
            #endif
    }

    @ViewBuilder
    private func voiceOutputSection(hideHeader: Bool = false) -> some View {
        Section {
            LabeledTextField(
                label: "Text Language",
                placeholder: "text_lang (e.g. auto/zh/en)",
                text: $viewModel.textLang
            )

            #if os(macOS)
            Toggle("Enable Streaming", isOn: $viewModel.enableStreaming)
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
                sectionHeader("Voice Settings")
            }
        }
    }

    @ViewBuilder
    private func chatSection(hideHeader: Bool = false) -> some View {
        Section {
            #if os(macOS)
            LabeledContent("Preset") {
                Picker("", selection: $viewModel.selectedChatServerPresetID) {
                    ForEach(viewModel.chatServerPresetList) { p in
                        Text(p.name).tag(Optional.some(p.id))
                    }
                }
                .labelsHidden()
            }

            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        viewModel.addChatServerPreset()
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help("Add preset")

                    Button(role: .destructive) {
                        showDeleteChatServerPresetAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help("Delete selected preset")
                    .disabled(viewModel.chatServerPresetList.count <= 1 || viewModel.selectedChatServerPresetID == nil)
                }
            }
            #else
            Picker("Preset", selection: $viewModel.selectedChatServerPresetID) {
                ForEach(viewModel.chatServerPresetList) { p in
                    Text(p.name).tag(Optional.some(p.id))
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 16) {
                Button {
                    viewModel.addChatServerPreset()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                Button(role: .destructive) {
                    showDeleteChatServerPresetAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(viewModel.chatServerPresetList.count <= 1 || viewModel.selectedChatServerPresetID == nil)
            }
            #endif

            LabeledTextField(
                label: "Preset Name",
                placeholder: "Preset name",
                text: $viewModel.chatServerPresetName
            )

            LabeledTextField(label: "Server URL",
                             placeholder: "http://localhost:1234",
                             text: $viewModel.apiURL)

            LabeledSecureField(
                label: "API Key",
                placeholder: "Enter API key",
                text: $viewModel.chatAPIKey
            )
        } header: {
            if hideHeader {
                EmptyView()
            } else {
                sectionHeader("Chat Server")
            }
        }
        .onChange(of: viewModel.selectedChatServerPresetID) {
            fetchAvailableModels()
        }
    }

    @ViewBuilder
    private func chatModelSection(hideHeader: Bool = false) -> some View {
        let hasModelListError = !(chatServerErrorMessage?.isEmpty ?? true)
        let showModelPicker = !(isLoadingModels || hasModelListError)

        Section {
            #if os(macOS)
            LabeledContent("Model") {
                ZStack(alignment: .trailing) {
                    HStack {
                        Spacer(minLength: 0)
                        Picker("", selection: $viewModel.selectedModel) {
                            ForEach(availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                    }
                    .opacity(showModelPicker ? 1 : 0)
                    .allowsHitTesting(showModelPicker)
                    .accessibilityHidden(!showModelPicker)

                    if isLoadingModels {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            if isRetryingModels {
                                Text(String(format: NSLocalizedString("Retrying (attempt %d)...", comment: "Shown while auto retry is waiting to reconnect"), max(1, modelRetryAttempt)))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } else {
                                Text("Loading model list...")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .help(modelRetryLastError ?? "")
                    } else if let message = chatServerErrorMessage, !message.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(message)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .help(message)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            #else
            LabeledContent("Model") {
                ZStack(alignment: .trailing) {
                    HStack {
                        Spacer(minLength: 0)
                        Picker("", selection: $viewModel.selectedModel) {
                            ForEach(availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                    }
                    .pickerStyle(.menu)
                    .opacity(showModelPicker ? 1 : 0)
                    .allowsHitTesting(showModelPicker)
                    .accessibilityHidden(!showModelPicker)

                    if isLoadingModels {
                        HStack(spacing: 8) {
                            ProgressView()
                            if isRetryingModels {
                                Text(String(format: NSLocalizedString("Retrying (attempt %d)...", comment: "Shown while auto retry is waiting to reconnect"), max(1, modelRetryAttempt)))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } else {
                                Text("Loading model list...")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    } else if let message = chatServerErrorMessage, !message.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(message)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            #endif

            HStack {
                Spacer()
                Button(action: fetchAvailableModels) {
                    Label("Refresh Model List", systemImage: "arrow.clockwise.circle")
                }
                .settingsActionButtonStyle()
                #if os(macOS)
                .help("Refresh available model list")
                #endif
                .disabled(isLoadingModels)
            }
            .padding(.top, 6)
        } header: {
            if hideHeader {
                EmptyView()
            } else {
                sectionHeader("Chat Model")
            }
        }
    }

    @ViewBuilder
    private func developerSection(hideHeader: Bool = false) -> some View {
        Section {
            Toggle(
                "Developer Mode",
                isOn: Binding(
                    get: { settingsManager.developerModeEnabled },
                    set: { settingsManager.updateDeveloperModeEnabled($0) }
                )
            )
        } header: {
            if hideHeader {
                EmptyView()
            } else {
                sectionHeader("Developer")
            }
        }
    }

    @ViewBuilder
    private func systemPromptSection(hideHeader _: Bool = false) -> some View {
        normalSystemPromptSection
        voiceSystemPromptSection
    }

    private var normalSystemPromptSection: some View {
        Section {
            #if os(macOS)
            LabeledContent("Preset") {
                Picker("", selection: $viewModel.selectedNormalSystemPromptPresetID) {
                    ForEach(viewModel.normalSystemPromptPresetList) { p in
                        Text(p.name).tag(Optional.some(p.id))
                    }
                }
                .labelsHidden()
            }

            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        viewModel.addNormalSystemPromptPreset()
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help("Add prompt preset")

                    Button(role: .destructive) {
                        showDeleteNormalPromptPresetAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help("Delete selected prompt preset")
                    .disabled(viewModel.normalSystemPromptPresetList.count <= 1 || viewModel.selectedNormalSystemPromptPresetID == nil)
                }
            }
            #else
            Picker("Preset", selection: $viewModel.selectedNormalSystemPromptPresetID) {
                ForEach(viewModel.normalSystemPromptPresetList) { p in
                    Text(p.name).tag(Optional.some(p.id))
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 16) {
                Button {
                    viewModel.addNormalSystemPromptPreset()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                Button(role: .destructive) {
                    showDeleteNormalPromptPresetAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(viewModel.normalSystemPromptPresetList.count <= 1 || viewModel.selectedNormalSystemPromptPresetID == nil)
            }
            #endif

            LabeledTextField(
                label: "Preset Name",
                placeholder: "Preset name",
                text: $viewModel.normalSystemPromptPresetName
            )
            LabeledTextEditor(
                label: "Prompt",
                placeholder: "Used for chat mode",
                text: $viewModel.normalSystemPromptPrompt
            )
        } header: {
            sectionHeader("Chat Prompt")
        }
    }

    private var voiceSystemPromptSection: some View {
        Section {
            #if os(macOS)
            LabeledContent("Preset") {
                Picker("", selection: $viewModel.selectedVoiceSystemPromptPresetID) {
                    ForEach(viewModel.voiceSystemPromptPresetList) { p in
                        Text(p.name).tag(Optional.some(p.id))
                    }
                }
                .labelsHidden()
            }

            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        viewModel.addVoiceSystemPromptPreset()
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help("Add prompt preset")

                    Button(role: .destructive) {
                        showDeleteVoicePromptPresetAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help("Delete selected prompt preset")
                    .disabled(viewModel.voiceSystemPromptPresetList.count <= 1 || viewModel.selectedVoiceSystemPromptPresetID == nil)
                }
            }
            #else
            Picker("Preset", selection: $viewModel.selectedVoiceSystemPromptPresetID) {
                ForEach(viewModel.voiceSystemPromptPresetList) { p in
                    Text(p.name).tag(Optional.some(p.id))
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 16) {
                Button {
                    viewModel.addVoiceSystemPromptPreset()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                Button(role: .destructive) {
                    showDeleteVoicePromptPresetAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(viewModel.voiceSystemPromptPresetList.count <= 1 || viewModel.selectedVoiceSystemPromptPresetID == nil)
            }
            #endif

            LabeledTextField(
                label: "Preset Name",
                placeholder: "Preset name",
                text: $viewModel.voiceSystemPromptPresetName
            )
            LabeledTextEditor(
                label: "Prompt",
                placeholder: "Used for voice mode",
                text: $viewModel.voiceSystemPromptPrompt
            )
        } header: {
            sectionHeader("Voice Prompt")
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
        let requestID = UUID()
        modelFetchRequestID = requestID

        isLoadingModels = true
        isRetryingModels = false
        modelRetryAttempt = 0
        modelRetryLastError = nil
        chatServerErrorMessage = nil

        let apiURL = viewModel.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiURL.isEmpty else {
            isLoadingModels = false
            chatServerErrorMessage = NSLocalizedString("Server URL is empty or invalid.", comment: "Shown when the model list URL is missing")
            return
        }

        guard let url = buildModelsURL(from: apiURL) else {
            isLoadingModels = false
            chatServerErrorMessage = NSLocalizedString("Invalid Server URL", comment: "Shown when the model list URL cannot be parsed")
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        let rawKey = viewModel.chatAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawKey.isEmpty {
            let headerValue = rawKey.lowercased().hasPrefix("bearer ") ? rawKey : "Bearer \(rawKey)"
            request.setValue(headerValue, forHTTPHeaderField: "Authorization")
        }

        let retryPolicy = NetworkRetryPolicy(
            maxAttempts: 4,
            baseDelay: 0.5,
            maxDelay: 4.0,
            backoffFactor: 1.6,
            jitterRatio: 0.2
        )

        Task { [requestID, request, retryPolicy] in
            do {
                let (data, _) = try await NetworkRetry.run(
                    policy: retryPolicy,
                    onRetry: { nextAttempt, _, error in
                        await MainActor.run {
                            guard self.modelFetchRequestID == requestID else { return }
                            self.isRetryingModels = true
                            self.modelRetryAttempt = max(1, nextAttempt - 1)
                            self.modelRetryLastError = error.localizedDescription
                        }
                    },
                    operation: {
                        let (data, resp) = try await URLSession.shared.data(for: request)
                        if let http = resp as? HTTPURLResponse,
                           !(200...299).contains(http.statusCode) {
                            let preview = String(data: data, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            let snippet = preview.isEmpty ? nil : String(preview.prefix(180))
                            throw HTTPStatusError(statusCode: http.statusCode, bodyPreview: snippet)
                        }
                        return (data, resp)
                    }
                )

                let modelList: ModelListResponse
                do {
                    modelList = try JSONDecoder().decode(ModelListResponse.self, from: data)
                } catch {
                    await MainActor.run {
                        guard self.modelFetchRequestID == requestID else { return }
                        self.isLoadingModels = false
                        self.isRetryingModels = false
                        self.modelRetryAttempt = 0
                        self.modelRetryLastError = nil
                        self.chatServerErrorMessage = NSLocalizedString("Unable to parse model list", comment: "Decoding the model list failed")
                    }
                    return
                }

                await MainActor.run {
                    guard self.modelFetchRequestID == requestID else { return }
                    self.isLoadingModels = false
                    self.isRetryingModels = false
                    self.modelRetryAttempt = 0
                    self.modelRetryLastError = nil
                    self.chatServerErrorMessage = nil
                    self.availableModels = modelList.data.map { $0.id }
                    if !self.availableModels.contains(self.viewModel.selectedModel),
                       let firstModel = self.availableModels.first {
                        self.viewModel.selectedModel = firstModel
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.modelFetchRequestID == requestID else { return }
                    self.isLoadingModels = false
                    self.isRetryingModels = false
                    self.modelRetryAttempt = 0
                    self.modelRetryLastError = nil

                    if let statusError = error as? HTTPStatusError {
                        self.chatServerErrorMessage = String(format: NSLocalizedString("Chat server responded with status %d.", comment: "Displayed when the chat server returns an error"), statusError.statusCode)
                        return
                    }

                    let message = String(format: NSLocalizedString("Request failed: %@", comment: "Model list request failed"), error.localizedDescription)
                    self.chatServerErrorMessage = message
                }
            }
        }
    }

    private func buildModelsURL(from base: String) -> URL? {
        var sanitized = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return nil }

        if !sanitized.contains("://") {
            sanitized = "http://\(sanitized)"
        }
        while sanitized.hasSuffix("/") { sanitized.removeLast() }

        guard var comps = URLComponents(string: sanitized) else { return nil }
        var path = comps.path
        while path.hasSuffix("/") { path.removeLast() }

        if path.hasSuffix("/v1/models") {
            // Keep as-is.
        } else if path.hasSuffix("/v1/chat/completions") {
            comps.path = String(path.dropLast("/chat/completions".count)) + "/models"
        } else if path.hasSuffix("/v1/chat") {
            comps.path = String(path.dropLast("/chat".count)) + "/models"
        } else if path.hasSuffix("/v1") {
            comps.path = path + "/models"
        } else {
            comps.path = path + "/v1/models"
        }

        return comps.url
    }
}

#if os(macOS)
private struct WindowSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

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

private extension View {
    @ViewBuilder
    func settingsActionButtonStyle() -> some View {
        #if os(macOS)
        self
            .buttonStyle(.bordered)
            .controlSize(.small)
        #else
        self
            .buttonStyle(.bordered)
            .controlSize(.regular)
        #endif
    }
}

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

// MARK: - LabeledTextEditor

struct LabeledTextEditor: View {
    var label: String
    var placeholder: String
    @Binding var text: String

    var body: some View {
        #if os(macOS)
        LabeledContent(LocalizedStringKey(label)) {
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .background(Color(NSColor.textBackgroundColor))
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(label))
                .font(.subheadline)
                .foregroundColor(.secondary)
            TextEditor(text: $text)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .background(Color(.secondarySystemBackground))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(LocalizedStringKey(placeholder))
                            .foregroundColor(.secondary)
                            .padding(.top, 10)
                            .padding(.leading, 6)
                    }
                }
        }
        #endif
    }
}

// MARK: - LabeledSecureField

struct LabeledSecureField: View {
    var label: String
    var placeholder: String
    @Binding var text: String

    var body: some View {
        #if os(macOS)
        LabeledContent(LocalizedStringKey(label)) {
            SecureField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .privacySensitive()
                .frame(maxWidth: .infinity)
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(label))
                .font(.subheadline)
                .foregroundColor(.secondary)
            SecureField(LocalizedStringKey(placeholder), text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
        }
        #endif
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager.shared)
}
