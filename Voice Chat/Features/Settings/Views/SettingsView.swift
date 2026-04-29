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

private enum SettingsDeletionTarget: String, Identifiable {
    case voicePreset
    case chatServerPreset
    case voiceServerPreset
    case normalPromptPreset
    case voicePromptPreset

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .voicePreset, .chatServerPreset, .voiceServerPreset:
            return "Delete this preset?"
        case .normalPromptPreset, .voicePromptPreset:
            return "Delete this prompt preset?"
        }
    }
}

private enum SettingsNavigationDestination: Hashable {
    case advancedAPISettings
}

private enum AdvancedAPISettingsSectionID: String, CaseIterable, Identifiable {
    case metadata
    case currentBackend
    case backendOverrides
    case defaults

    var id: String { rawValue }
}

private enum AdvancedAPIBackendOverrideID: String, CaseIterable, Identifiable {
    case openAIResponses
    case openAIChat
    case anthropic
    case gemini
    case deepSeek
    case xAI
    case openRouter
    case lmStudioREST
    case lmStudioOpenAICompatible
    case llamaCpp
    case genericOpenAICompatible

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .openAIResponses:
            return "OpenAI Responses"
        case .openAIChat:
            return "OpenAI Chat Completions"
        case .anthropic:
            return "Anthropic Messages"
        case .gemini:
            return "Gemini OpenAI Compatibility"
        case .deepSeek:
            return "DeepSeek Chat Completions"
        case .xAI:
            return "xAI Chat Completions"
        case .openRouter:
            return "OpenRouter Chat Completions"
        case .lmStudioREST:
            return "LM Studio REST v1"
        case .lmStudioOpenAICompatible:
            return "LM Studio OpenAI Compatibility"
        case .llamaCpp:
            return "llama.cpp OpenAI Compatibility"
        case .genericOpenAICompatible:
            return "Generic OpenAI Compatible"
        }
    }
}

private struct RawJSONPreviewBlock: View {
    let title: LocalizedStringKey
    let value: JSONValue?
    let missingText: String

    @State private var previewText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let previewText {
                ScrollView(.horizontal) {
                    Text(previewText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if value == nil {
                Text(missingText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
                .task {
                    loadPreviewIfNeeded()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func loadPreviewIfNeeded() {
        guard previewText == nil else { return }
        previewText = value?.debugPreviewJSONString() ?? missingText
    }
}

#if os(macOS)
private enum MacSettingsTab: Hashable {
    case servers
    case chat
    case voiceOutput
    case developer
}

private enum MacSettingsLayout {
    static let minContentSize = NSSize(width: 500, height: 180)
    static let fallbackMaxContentSize = NSSize(width: 860, height: 720)
    static let topLevelContentSize = NSSize(width: 560, height: 540)
    static let screenMargin: CGFloat = 72
    static let resizeThreshold: CGFloat = 1
}
#endif

// MARK: - Settings View

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @ObservedObject private var settingsManager: SettingsManager
    @State private var pendingDeletionTarget: SettingsDeletionTarget?
    @State private var showingAPIAdvancedResetConfirmation = false
    @Environment(\.dismiss) private var dismiss
#if os(macOS)
    @State private var measuredContentSize: CGSize = .zero
    @State private var macSelectedSettingsTab: MacSettingsTab = .servers
    @State private var macShowsAdvancedSettings = false
#endif

    init(settingsManager: SettingsManager = .shared) {
        _settingsManager = ObservedObject(wrappedValue: settingsManager)
        _viewModel = StateObject(wrappedValue: SettingsViewModel(settingsManager: settingsManager))
    }

    private var detectedChatAPIFormatName: String {
        let base = viewModel.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detected = settingsManager.detectedChatProvider(for: base),
           detected != .unknown {
            return detected.displayName
        }
        if let official = ChatAPIEndpointResolver.officialProviderHint(for: base) {
            return official.displayName
        }
        return NSLocalizedString("Unknown", comment: "Provider display name")
    }

    var body: some View {
        #if os(macOS)
        applyCommonModifiers(
            macSettingsContent
                .overlay(WindowSizeReader().allowsHitTesting(false))
        )
        .onPreferenceChange(WindowSizePreferenceKey.self) { newSize in
            updateWindowSizeIfNeeded(newSize)
        }
        .onChange(of: macShowsAdvancedSettings) { _, _ in
            updateWindowSizeIfNeeded(measuredContentSize)
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
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { dismiss() }
                    }
                }
                .navigationDestination(for: SettingsNavigationDestination.self) { destination in
                    switch destination {
                    case .advancedAPISettings:
                        advancedAPISettingsView
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
            .task {
                viewModel.refreshFromSettingsManager()
                viewModel.fetchAvailableModels()
            }
            .alert(
                pendingDeletionTarget?.title ?? LocalizedStringKey("Delete"),
                isPresented: deletionAlertBinding
            ) {
                Button("Delete", role: .destructive, action: performPendingDeletion)
                Button("Cancel", role: .cancel) {
                    pendingDeletionTarget = nil
                }
            } message: {
                Text("This action cannot be undone.")
            }
    }

    private var deletionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletionTarget != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletionTarget = nil
                }
            }
        )
    }

    private func requestDeletion(_ target: SettingsDeletionTarget) {
        pendingDeletionTarget = target
    }

    private func performPendingDeletion() {
        guard let target = pendingDeletionTarget else { return }
        pendingDeletionTarget = nil

        switch target {
        case .voicePreset:
            viewModel.deleteCurrentPreset()
        case .chatServerPreset:
            viewModel.deleteSelectedChatServerPreset()
        case .voiceServerPreset:
            viewModel.deleteSelectedVoiceServerPreset()
        case .normalPromptPreset:
            viewModel.deleteSelectedNormalSystemPromptPreset()
        case .voicePromptPreset:
            viewModel.deleteSelectedVoiceSystemPromptPreset()
        }
    }

    // MARK: - Sections

#if os(macOS)
    @ViewBuilder
    private var macSettingsContent: some View {
        macSettingsTabs
            .frame(
                width: MacSettingsLayout.topLevelContentSize.width,
                height: MacSettingsLayout.topLevelContentSize.height,
                alignment: .top
            )
    }

    private var macSettingsTabs: some View {
        TabView(selection: $macSelectedSettingsTab) {
            macServersTab
                .tag(MacSettingsTab.servers)
            macChatTab
                .tag(MacSettingsTab.chat)
            macVoiceOutputTab
                .tag(MacSettingsTab.voiceOutput)
            macDeveloperTab
                .tag(MacSettingsTab.developer)
        }
        .scenePadding()
        .onChange(of: macSelectedSettingsTab) { _, newTab in
            if newTab != .developer {
                macShowsAdvancedSettings = false
            }
        }
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
        Group {
            if macShowsAdvancedSettings {
                macAdvancedSettingsPage
            } else {
                macDeveloperSettingsPage
            }
        }
        .tabItem {
            Label("Developer", systemImage: "ladybug")
        }
    }

    private var macDeveloperSettingsPage: some View {
        Form {
            developerSection()
        }
        .formStyle(.grouped)
    }

    private var macAdvancedSettingsPage: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    macShowsAdvancedSettings = false
                    macSelectedSettingsTab = .developer
                } label: {
                    Label("Developer", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Back to Developer settings")

                Spacer()

                Text("Advanced Options")
                    .font(.headline)

                Spacer()

                Label("Developer", systemImage: "chevron.left")
                    .hidden()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)

            advancedAPISettingsView
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
                        requestDeletion(.voiceServerPreset)
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
                    requestDeletion(.voiceServerPreset)
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
                placeholder: "http://localhost:9880",
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
                    requestDeletion(.voicePreset)
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
                requestDeletion(.voicePreset)
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

            LabeledTextField(label: "Reference Audio Path",
                             placeholder: "GPT_SoVITS/refs/xxx.wav",
                             text: $viewModel.presetRefAudioPath)
            LabeledTextField(label: "Reference Text",
                             placeholder: "Reference text (optional)",
                             text: $viewModel.presetPromptText)
            LabeledTextField(label: "Reference Language",
                             placeholder: "e.g. auto/zh/en",
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

        return Group {
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
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                #if os(macOS)
                .help(settingsManager.presetApplyRetryLastError ?? "")
                #endif
            } else if let err = settingsManager.lastApplyError, !err.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(.top, 1)
                    Text(err)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
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
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EmptyView()
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
                placeholder: "e.g. auto/zh/en",
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
                        requestDeletion(.chatServerPreset)
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
                    requestDeletion(.chatServerPreset)
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

            LabeledContent("API Format") {
                Picker("", selection: $viewModel.selectedChatAPIFormatPreference) {
                    Text("Automatic").tag(ChatAPIFormatPreference.automatic)
                    Text("OpenAI").tag(ChatAPIFormatPreference.openAI)
                    Text("Anthropic").tag(ChatAPIFormatPreference.anthropic)
                    Text("Gemini").tag(ChatAPIFormatPreference.gemini)
                    Text("DeepSeek").tag(ChatAPIFormatPreference.deepSeek)
                    Text("xAI").tag(ChatAPIFormatPreference.xAI)
                    Text("OpenRouter").tag(ChatAPIFormatPreference.openRouter)
                    Text("LM Studio").tag(ChatAPIFormatPreference.lmStudio)
                    Text("llama.cpp").tag(ChatAPIFormatPreference.llamaCpp)
                    Text("OpenAI Compatible").tag(ChatAPIFormatPreference.openAICompatible)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            if viewModel.selectedChatAPIFormatPreference == .automatic {
                Text(
                    String(
                        format: NSLocalizedString(
                            "Detected API Format: %@",
                            comment: "Shows the auto-detected API format under the API format picker"
                        ),
                        detectedChatAPIFormatName
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

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
            viewModel.fetchAvailableModels()
        }
    }

    @ViewBuilder
    private func chatModelSection(hideHeader: Bool = false) -> some View {
        let hasModelListError = !(viewModel.chatServerErrorMessage?.isEmpty ?? true)
        let showModelPicker = !(viewModel.isLoadingModels || hasModelListError)

        Section {
            #if os(macOS)
            LabeledContent("Model") {
                ZStack(alignment: .trailing) {
                    HStack {
                        Spacer(minLength: 0)
                        Picker("", selection: $viewModel.selectedModel) {
                            ForEach(viewModel.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                    }
                    .opacity(showModelPicker ? 1 : 0)
                    .allowsHitTesting(showModelPicker)
                    .accessibilityHidden(!showModelPicker)

                    if viewModel.isLoadingModels {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            if viewModel.isRetryingModels {
                                Text(String(format: NSLocalizedString("Retrying (attempt %d)...", comment: "Shown while auto retry is waiting to reconnect"), max(1, viewModel.modelRetryAttempt)))
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
                        .help(viewModel.modelRetryLastError ?? "")
                    } else if let message = viewModel.chatServerErrorMessage, !message.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .padding(.top, 1)
                            Text(message)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
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
                            ForEach(viewModel.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                    }
                    .pickerStyle(.menu)
                    .opacity(showModelPicker ? 1 : 0)
                    .allowsHitTesting(showModelPicker)
                    .accessibilityHidden(!showModelPicker)

                    if viewModel.isLoadingModels {
                        HStack(spacing: 8) {
                            ProgressView()
                            if viewModel.isRetryingModels {
                                Text(String(format: NSLocalizedString("Retrying (attempt %d)...", comment: "Shown while auto retry is waiting to reconnect"), max(1, viewModel.modelRetryAttempt)))
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
                    } else if let message = viewModel.chatServerErrorMessage, !message.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .padding(.top, 1)
                            Text(message)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            #endif

            HStack {
                Spacer()
                Button(action: viewModel.fetchAvailableModels) {
                    Label("Refresh Model List", systemImage: "arrow.clockwise.circle")
                }
                .settingsActionButtonStyle()
                #if os(macOS)
                .help("Refresh available model list")
                #endif
                .disabled(viewModel.isLoadingModels)
            }
            .padding(.top, 6)

            if viewModel.shouldShowUnknownModelImageInputToggle {
                Toggle(
                    "Enable image input for this model",
                    isOn: Binding(
                        get: { viewModel.isSelectedUnknownModelImageInputEnabled },
                        set: { viewModel.setSelectedUnknownModelImageInputEnabled($0) }
                    )
                )

                Text("This model's metadata does not clearly report image-input capability. Turn this on only if you are sure the backend can accept image content for this model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            #if !os(macOS)
            Toggle("Haptic Feedback", isOn: $viewModel.hapticFeedbackEnabled)
            #endif
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

        advancedAPIEntrySection()
    }

    @ViewBuilder
    private func advancedAPIEntrySection() -> some View {
        if settingsManager.developerModeEnabled {
            Section {
                #if os(macOS)
                Button {
                    macShowsAdvancedSettings = true
                    macSelectedSettingsTab = .developer
                } label: {
                    Label("Advanced Options", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                #else
                NavigationLink(value: SettingsNavigationDestination.advancedAPISettings) {
                    Label("Advanced Options", systemImage: "slider.horizontal.3")
                }
                #endif
            }
        }
    }

    private var advancedAPISettingsView: some View {
        Form {
            ForEach(AdvancedAPISettingsSectionID.allCases) { section in
                advancedAPISettingsSection(section)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Advanced Options")
    }

    private func advancedAPISettingsSection(_ section: AdvancedAPISettingsSectionID) -> AnyView {
        switch section {
        case .metadata:
            return advancedMetadataSection()
        case .currentBackend:
            return currentBackendAdvancedSettingsSection()
        case .backendOverrides:
            return allBackendAdvancedSettingsSection()
        case .defaults:
            return restoreAdvancedDefaultsSection()
        }
    }

    private func restoreAdvancedDefaultsSection() -> AnyView {
        AnyView(Section {
            Button(role: .destructive) {
                showingAPIAdvancedResetConfirmation = true
            } label: {
                Label("Restore Defaults", systemImage: "arrow.counterclockwise")
            }
            .confirmationDialog(
                "Restore defaults?",
                isPresented: $showingAPIAdvancedResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Restore Defaults", role: .destructive) {
                    viewModel.resetAPIAdvancedSettingsToDefaults()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will reset all options to defaults.")
            }
        } header: {
            sectionHeader("Defaults")
        })
    }

    private func advancedMetadataSection() -> AnyView {
        AnyView(Section {
            metadataRow("Provider", currentAdvancedProvider.displayName)
            metadataRow("Request Style", currentAdvancedRequestStyleDisplayName)
            metadataRow("API Format", selectedAPIFormatDisplayName)
            metadataRow("Fetched Models", "\(viewModel.availableModels.count)")
            if let endpoint = viewModel.lastModelFetchEndpoint {
                metadataRow("Models Endpoint", endpoint.modelsURL.absoluteString)
                metadataRow("Chat Endpoint", endpoint.chatURL.absoluteString)
            } else {
                metadataRow("Models Endpoint", String(localized: "Not fetched"))
            }

            if let metadata = selectedModelMetadata {
                selectedModelMetadataDisclosure(metadata)
            }

            if !viewModel.lastFetchedModelMetadata.isEmpty {
                fetchedModelsMetadataDisclosure()
            }
        } header: {
            sectionHeader("Model List Metadata")
        })
    }

    private func selectedModelMetadataDisclosure(_ metadata: ModelInfo) -> AnyView {
        AnyView(DisclosureGroup("Selected Model Metadata") {
            metadataRow("ID", metadata.id)
            metadataRow("Object", metadata.object ?? localizedUnknown)
            metadataRow("Owner", metadata.owned_by ?? localizedUnknown)
            metadataRow("Type", metadata.type ?? metadata.arch ?? localizedUnknown)
            metadataRow("Input Modalities", joined(metadata.input_modalities ?? metadata.capabilities?.input_modalities))
            metadataRow("Modalities", joined(metadata.modalities ?? metadata.capabilities?.modalities))
            metadataRow("Supported Parameters", joined(metadata.supported_parameters ?? metadata.capabilities?.supported_parameters))
            metadataRow("Image Input", optionalBool(metadata.supportsImageInputHint))
            if let thinking = metadata.thinkingCapabilityHint(
                provider: currentAdvancedProvider,
                requestStyle: currentAdvancedRequestStyle
            ) {
                metadataRow("Thinking Options", thinking.options.map(\.rawValue).joined(separator: ", "))
                metadataRow("Thinking Parameter", thinking.requestParameter?.rawValue ?? String(localized: "Provider default"))
            } else {
                metadataRow("Thinking Options", String(localized: "Not detected"))
            }
            rawJSONBlock("Raw Model JSON", metadata.rawMetadata)
        })
    }

    private func fetchedModelsMetadataDisclosure() -> AnyView {
        AnyView(DisclosureGroup("Fetched Models Metadata") {
            ForEach(Array(viewModel.lastFetchedModelMetadata.enumerated()), id: \.offset) { _, model in
                fetchedModelMetadataDisclosure(model)
            }
        })
    }

    private func fetchedModelMetadataDisclosure(_ model: ModelInfo) -> AnyView {
        AnyView(DisclosureGroup(model.id) {
            metadataRow("Object", model.object ?? localizedUnknown)
            metadataRow("Owner", model.owned_by ?? localizedUnknown)
            metadataRow("Type", model.type ?? model.arch ?? localizedUnknown)
            metadataRow("Supported Parameters", joined(model.supported_parameters ?? model.capabilities?.supported_parameters))
            metadataRow("Image Input", optionalBool(model.supportsImageInputHint))
            rawJSONBlock("Raw JSON", model.rawMetadata)
        })
    }

    private func currentBackendAdvancedSettingsSection() -> AnyView {
        AnyView(Section {
            currentBackendControls()
        } header: {
            sectionHeader("Current Backend Parameters")
        } footer: {
            Text("Only enabled sampling fields are added to requests.")
        })
    }

    private func currentBackendControls() -> AnyView {
        switch currentAdvancedRequestStyle {
        case .anthropicMessages:
            return anthropicControls()
        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            return lmStudioRESTControls()
        case .openAIChatCompletions:
            return openAICompatibleBackendControls()
        }
    }

    private func allBackendAdvancedSettingsSection() -> AnyView {
        AnyView(Section {
            ForEach(AdvancedAPIBackendOverrideID.allCases) { backend in
                backendOverrideDisclosure(backend)
            }
        } header: {
            sectionHeader("Backend Request Overrides")
        })
    }

    private func backendOverrideDisclosure(_ backend: AdvancedAPIBackendOverrideID) -> AnyView {
        AnyView(DisclosureGroup(backend.title) {
            backendOverrideControls(backend)
        })
    }

    private func backendOverrideControls(_ backend: AdvancedAPIBackendOverrideID) -> AnyView {
        switch backend {
        case .openAIResponses:
            return openAIResponsesControls()
        case .openAIChat:
            return openAIChatControls()
        case .anthropic:
            return anthropicControls()
        case .gemini:
            return geminiControls()
        case .deepSeek:
            return deepSeekControls()
        case .xAI:
            return xAIControls()
        case .openRouter:
            return openRouterControls()
        case .lmStudioREST:
            return lmStudioRESTControls()
        case .lmStudioOpenAICompatible:
            return lmStudioOpenAICompatibleControls()
        case .llamaCpp:
            return llamaCppControls()
        case .genericOpenAICompatible:
            return openAICompatibleControls()
        }
    }

    private func openAICompatibleBackendControls() -> AnyView {
        if isCurrentOpenAIResponsesEndpoint {
            return openAIResponsesControls()
        } else {
            switch currentAdvancedProvider {
            case .openAI:
                return openAIChatControls()
            case .gemini:
                return geminiControls()
            case .deepSeek:
                return deepSeekControls()
            case .xAI:
                return xAIControls()
            case .openRouter:
                return openRouterControls()
            case .lmStudio:
                return lmStudioOpenAICompatibleControls()
            case .llamaCpp:
                return llamaCppControls()
            case .openAICompatible, .unknown, .anthropic:
                return openAICompatibleControls()
            }
        }
    }

    private func openAIResponsesControls() -> AnyView {
        AnyView(Group {
            apiIntegerField("max_output_tokens", value: $viewModel.apiAdvancedSettings.openAIResponsesMaxOutputTokens)
            apiSamplingControls(
                $viewModel.apiAdvancedSettings.openAIResponsesSampling,
                includePenalties: false,
                includeSeed: false,
                includeJSONMode: true,
                includeLogprobs: false
            )
            verbosityControl(
                $viewModel.apiAdvancedSettings.openAIResponsesSampling,
                title: "text.verbosity",
                options: ["low", "medium", "high"]
            )
        })
    }

    private func openAIChatControls() -> AnyView {
        AnyView(Group {
            apiIntegerField("max_completion_tokens", value: $viewModel.apiAdvancedSettings.openAIChatMaxCompletionTokens)
            apiSamplingControls($viewModel.apiAdvancedSettings.openAIChatSampling)
        })
    }

    private func openAICompatibleControls() -> AnyView {
        AnyView(Group {
            apiIntegerField("max_tokens", value: $viewModel.apiAdvancedSettings.openAICompatibleMaxTokens)
            apiSamplingControls($viewModel.apiAdvancedSettings.openAICompatibleSampling)
        })
    }

    private func anthropicControls() -> AnyView {
        AnyView(Group {
            apiIntegerField("max_tokens", value: $viewModel.apiAdvancedSettings.anthropicMaxTokens)
            apiIntegerField(
                "Extended thinking response reserve tokens",
                value: $viewModel.apiAdvancedSettings.anthropicThinkingResponseReserve
            )
            apiIntegerField(
                "Extended thinking low budget_tokens",
                value: $viewModel.apiAdvancedSettings.anthropicLowThinkingBudget
            )
            apiIntegerField(
                "Extended thinking medium budget_tokens",
                value: $viewModel.apiAdvancedSettings.anthropicMediumThinkingBudget
            )
            apiIntegerField(
                "Extended thinking high budget_tokens",
                value: $viewModel.apiAdvancedSettings.anthropicHighThinkingBudget
            )
            apiSamplingControls(
                $viewModel.apiAdvancedSettings.anthropicSampling,
                includeTopK: true,
                includePenalties: false,
                includeSeed: false,
                includeJSONMode: false,
                includeLogprobs: false
            )
        })
    }

    private func geminiControls() -> AnyView {
        AnyView(Group {
            apiIntegerField("max_tokens", value: $viewModel.apiAdvancedSettings.geminiMaxTokens)
            apiSamplingControls(
                $viewModel.apiAdvancedSettings.geminiSampling,
                includePenalties: false,
                includeSeed: false,
                includeJSONMode: false,
                includeLogprobs: false
            )
        })
    }

    private func deepSeekControls() -> AnyView {
        AnyView(Group {
            apiIntegerField("max_tokens", value: $viewModel.apiAdvancedSettings.deepSeekMaxTokens)
            apiSamplingControls(
                $viewModel.apiAdvancedSettings.deepSeekSampling,
                includePenalties: true,
                includeSeed: false,
                includeJSONMode: true,
                includeLogprobs: true
            )
        })
    }

    private func xAIControls() -> AnyView {
        AnyView(Group {
            apiIntegerField("max_tokens", value: $viewModel.apiAdvancedSettings.xAIMaxTokens)
            apiSamplingControls($viewModel.apiAdvancedSettings.xAISampling)
        })
    }

    private func openRouterControls() -> AnyView {
        AnyView(Group {
            apiIntegerField("max_tokens", value: $viewModel.apiAdvancedSettings.openRouterMaxTokens)
            apiIntegerField("max_completion_tokens", value: $viewModel.apiAdvancedSettings.openRouterMaxCompletionTokens)
            apiSamplingControls(
                $viewModel.apiAdvancedSettings.openRouterSampling,
                includeTopK: true,
                includeMinP: true,
                includeTopA: true,
                includeRepetitionPenalty: true,
                includeStructuredOutputs: true
            )
            verbosityControl(
                $viewModel.apiAdvancedSettings.openRouterSampling,
                title: "verbosity",
                options: ["low", "medium", "high", "max"]
            )
        })
    }

    private func lmStudioRESTControls() -> AnyView {
        AnyView(Group {
            apiIntegerField("max_output_tokens", value: $viewModel.apiAdvancedSettings.lmStudioMaxTokens)
            apiIntegerToggleField(
                "context_length",
                enabled: $viewModel.apiAdvancedSettings.lmStudioSampling.contextLengthEnabled,
                value: $viewModel.apiAdvancedSettings.lmStudioSampling.contextLength
            )
            apiSamplingControls(
                $viewModel.apiAdvancedSettings.lmStudioSampling,
                includeTopK: true,
                includeMinP: true,
                includePenalties: false,
                includeRepetitionPenalty: true,
                repetitionPenaltyTitle: "repeat_penalty",
                includeSeed: false,
                includeJSONMode: false,
                includeLogprobs: false
            )
        })
    }

    private func lmStudioOpenAICompatibleControls() -> AnyView {
        AnyView(Group {
            apiIntegerField("max_tokens", value: $viewModel.apiAdvancedSettings.lmStudioOpenAICompatibleMaxTokens)
            apiSamplingControls(
                $viewModel.apiAdvancedSettings.lmStudioOpenAICompatibleSampling,
                includeTopK: true,
                includeRepetitionPenalty: true,
                repetitionPenaltyTitle: "repeat_penalty"
            )
        })
    }

    private func llamaCppControls() -> AnyView {
        AnyView(Group {
            apiIntegerField("max_tokens", value: $viewModel.apiAdvancedSettings.llamaCppMaxTokens)
            apiSamplingControls(
                $viewModel.apiAdvancedSettings.llamaCppSampling,
                includeTopK: true,
                includeMinP: true,
                includeRepetitionPenalty: true,
                repetitionPenaltyTitle: "repeat_penalty"
            )
        })
    }

    private func apiSamplingControls(
        _ sampling: Binding<APIAdvancedSamplingSettings>,
        includeTopK: Bool = false,
        includeMinP: Bool = false,
        includeTopA: Bool = false,
        includePenalties: Bool = true,
        includeRepetitionPenalty: Bool = false,
        repetitionPenaltyTitle: LocalizedStringKey = "repetition_penalty",
        includeSeed: Bool = true,
        includeJSONMode: Bool = true,
        includeStructuredOutputs: Bool = false,
        includeLogprobs: Bool = true
    ) -> AnyView {
        AnyView(Group {
            apiDoubleToggleField(
                "temperature",
                enabled: sampling.temperatureEnabled,
                value: sampling.temperature
            )
            apiDoubleToggleField(
                "top_p",
                enabled: sampling.topPEnabled,
                value: sampling.topP
            )
            if includeTopK {
                apiIntegerToggleField("top_k", enabled: sampling.topKEnabled, value: sampling.topK)
            }
            if includeMinP {
                apiDoubleToggleField("min_p", enabled: sampling.minPEnabled, value: sampling.minP)
            }
            if includeTopA {
                apiDoubleToggleField("top_a", enabled: sampling.topAEnabled, value: sampling.topA)
            }
            if includePenalties {
                apiDoubleToggleField(
                    "presence_penalty",
                    enabled: sampling.presencePenaltyEnabled,
                    value: sampling.presencePenalty
                )
                apiDoubleToggleField(
                    "frequency_penalty",
                    enabled: sampling.frequencyPenaltyEnabled,
                    value: sampling.frequencyPenalty
                )
            }
            if includeRepetitionPenalty {
                apiDoubleToggleField(repetitionPenaltyTitle, enabled: sampling.repetitionPenaltyEnabled, value: sampling.repetitionPenalty)
            }
            if includeSeed {
                apiIntegerToggleField("seed", enabled: sampling.seedEnabled, value: sampling.seed)
            }
            if includeJSONMode {
                apiBooleanToggleField("JSON mode", isOn: sampling.jsonModeEnabled)
            }
            if includeStructuredOutputs {
                apiBooleanToggleField("structured_outputs", isOn: sampling.structuredOutputsEnabled)
            }
            if includeLogprobs {
                apiBooleanToggleField("logprobs", isOn: sampling.logprobsEnabled)
                if sampling.logprobsEnabled.wrappedValue {
                    apiIntegerToggleField("top_logprobs", enabled: sampling.topLogprobsEnabled, value: sampling.topLogprobs)
                }
            }
        })
    }

    private func verbosityControl(
        _ sampling: Binding<APIAdvancedSamplingSettings>,
        title: LocalizedStringKey,
        options: [String]
    ) -> AnyView {
        #if os(macOS)
        return AnyView(apiLabeledContent(title) {
            HStack(spacing: 10) {
                Toggle("", isOn: sampling.verbosityEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)

                if sampling.verbosityEnabled.wrappedValue {
                    Picker("verbosity", selection: sampling.verbosity) {
                        ForEach(options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
            }
        })
        #else
        return AnyView(VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: sampling.verbosityEnabled)
            if sampling.verbosityEnabled.wrappedValue {
                Picker("verbosity", selection: sampling.verbosity) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.vertical, 4))
        #endif
    }

    private func apiBooleanToggleField(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> AnyView {
        #if os(macOS)
        return AnyView(apiLabeledContent(title) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        })
        #else
        return AnyView(Toggle(title, isOn: isOn))
        #endif
    }

    private func apiIntegerField(_ title: LocalizedStringKey, value: Binding<Int>) -> AnyView {
        #if os(macOS)
        return AnyView(apiLabeledContent(title) {
            TextField("", value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
        })
        #else
        return AnyView(VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("", value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
        }
        .padding(.vertical, 4))
        #endif
    }

    private func apiIntegerToggleField(
        _ title: LocalizedStringKey,
        enabled: Binding<Bool>,
        value: Binding<Int>
    ) -> AnyView {
        #if os(macOS)
        return AnyView(apiLabeledContent(title) {
            HStack(spacing: 10) {
                Toggle("", isOn: enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)

                if enabled.wrappedValue {
                    TextField("", value: value, format: .number)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
            }
        })
        #else
        return AnyView(VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: enabled)
            if enabled.wrappedValue {
                TextField("", value: value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
            }
        }
        .padding(.vertical, 4))
        #endif
    }

    private func apiDoubleToggleField(
        _ title: LocalizedStringKey,
        enabled: Binding<Bool>,
        value: Binding<Double>
    ) -> AnyView {
        #if os(macOS)
        return AnyView(apiLabeledContent(title) {
            HStack(spacing: 10) {
                Toggle("", isOn: enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)

                if enabled.wrappedValue {
                    TextField("", value: value, format: .number.precision(.fractionLength(0...3)))
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
            }
        })
        #else
        return AnyView(VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: enabled)
            if enabled.wrappedValue {
                TextField("", value: value, format: .number.precision(.fractionLength(0...3)))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
            }
        }
        .padding(.vertical, 4))
        #endif
    }

    #if os(macOS)
    private func apiLabeledContent<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LabeledContent {
            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        } label: {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    #endif

    private func metadataRow(_ title: LocalizedStringKey, _ value: String) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? String(localized: "None") : value)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2))
    }

    private func rawJSONBlock(_ title: LocalizedStringKey, _ value: JSONValue?) -> AnyView {
        AnyView(RawJSONPreviewBlock(
            title: title,
            value: value,
            missingText: String(localized: "Raw metadata was not captured.")
        ))
    }

    private var currentAdvancedProvider: ChatProvider {
        let base = viewModel.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return viewModel.selectedChatAPIFormatPreference.providerHint
            ?? settingsManager.detectedChatProvider(for: base)
            ?? ChatAPIEndpointResolver.officialProviderHint(for: base)
            ?? .openAICompatible
    }

    private var currentAdvancedRequestStyle: ChatRequestStyle {
        let base = viewModel.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return viewModel.selectedChatAPIFormatPreference.requestStyleHint
            ?? settingsManager.detectedChatRequestStyle(for: base)
            ?? .openAIChatCompletions
    }

    private var currentAdvancedRequestStyleDisplayName: String {
        switch currentAdvancedRequestStyle {
        case .openAIChatCompletions:
            return isCurrentOpenAIResponsesEndpoint ? String(localized: "OpenAI Responses") : String(localized: "OpenAI Chat Completions")
        case .lmStudioRESTV1:
            return String(localized: "LM Studio REST v1")
        case .lmStudioRESTV1LegacyMessage:
            return String(localized: "LM Studio REST legacy message")
        case .anthropicMessages:
            return String(localized: "Anthropic Messages")
        }
    }

    private var selectedAPIFormatDisplayName: String {
        switch viewModel.selectedChatAPIFormatPreference {
        case .automatic:
            return String(localized: "Automatic")
        case .openAI:
            return ChatProvider.openAI.displayName
        case .anthropic:
            return ChatProvider.anthropic.displayName
        case .gemini:
            return ChatProvider.gemini.displayName
        case .deepSeek:
            return ChatProvider.deepSeek.displayName
        case .xAI:
            return ChatProvider.xAI.displayName
        case .openRouter:
            return ChatProvider.openRouter.displayName
        case .lmStudio:
            return ChatProvider.lmStudio.displayName
        case .llamaCpp:
            return ChatProvider.llamaCpp.displayName
        case .openAICompatible:
            return ChatProvider.openAICompatible.displayName
        }
    }

    private var isCurrentOpenAIResponsesEndpoint: Bool {
        guard currentAdvancedRequestStyle == .openAIChatCompletions else { return false }
        if let endpoint = viewModel.lastModelFetchEndpoint {
            return endpoint.chatURL.path.lowercased().hasSuffix("/responses")
        }
        return viewModel.apiURL.lowercased().contains("/responses")
    }

    private var selectedModelMetadata: ModelInfo? {
        viewModel.lastFetchedModelMetadata.first { $0.id == viewModel.selectedModel }
    }

    private var localizedUnknown: String {
        String(localized: "Unknown")
    }

    private func joined(_ values: [String]?) -> String {
        guard let values, !values.isEmpty else { return String(localized: "None") }
        return values.joined(separator: ", ")
    }

    private func optionalBool(_ value: Bool?) -> String {
        guard let value else { return localizedUnknown }
        return value ? String(localized: "Yes") : String(localized: "No")
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
                        requestDeletion(.normalPromptPreset)
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
                    requestDeletion(.normalPromptPreset)
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
                        requestDeletion(.voicePromptPreset)
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
                    requestDeletion(.voicePromptPreset)
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
        if newSize.width > 0, newSize.height > 0 {
            measuredContentSize = newSize
        }

        DispatchQueue.main.async {
            guard let window = NSApp?.windows.first(where: { $0.isKeyWindow }) else { return }
            let maxContentSize = maxSettingsContentSize(for: window)
            let targetSize = clampedSettingsContentSize(preferredSettingsContentSize, maxContentSize: maxContentSize)

            window.contentMinSize = targetSize
            window.contentMaxSize = targetSize

            let currentSize = window.contentView?.bounds.size ?? .zero
            if abs(currentSize.width - targetSize.width) > MacSettingsLayout.resizeThreshold ||
                abs(currentSize.height - targetSize.height) > MacSettingsLayout.resizeThreshold {
                window.setContentSize(targetSize)
                keepSettingsWindowVisible(window)
            }
        }
    }

    private var preferredSettingsContentSize: NSSize {
        MacSettingsLayout.topLevelContentSize
    }

    private func clampedSettingsContentSize(_ preferredSize: NSSize, maxContentSize: NSSize) -> NSSize {
        NSSize(
            width: min(max(preferredSize.width, MacSettingsLayout.minContentSize.width), maxContentSize.width),
            height: min(max(preferredSize.height, MacSettingsLayout.minContentSize.height), maxContentSize.height)
        )
    }

    private func maxSettingsContentSize(for window: NSWindow) -> NSSize {
        guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else {
            return MacSettingsLayout.fallbackMaxContentSize
        }

        return NSSize(
            width: max(
                MacSettingsLayout.minContentSize.width,
                min(MacSettingsLayout.fallbackMaxContentSize.width, visibleFrame.width - MacSettingsLayout.screenMargin)
            ),
            height: max(
                MacSettingsLayout.minContentSize.height,
                min(MacSettingsLayout.fallbackMaxContentSize.height, visibleFrame.height - MacSettingsLayout.screenMargin)
            )
        )
    }

    private func keepSettingsWindowVisible(_ window: NSWindow) {
        guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame

        if frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.maxX - frame.width
        }
        if frame.minX < visibleFrame.minX {
            frame.origin.x = visibleFrame.minX
        }
        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.height
        }
        if frame.minY < visibleFrame.minY {
            frame.origin.y = visibleFrame.minY
        }

        if frame.origin != window.frame.origin {
            window.setFrameOrigin(frame.origin)
        }
    }
#endif
}

#Preview {
    SettingsView(settingsManager: .shared)
}
