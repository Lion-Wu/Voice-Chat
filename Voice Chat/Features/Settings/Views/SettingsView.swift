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

enum SettingsDeletionTarget: String, Identifiable {
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

#if os(macOS)
private enum MacSettingsTab: Hashable {
    case servers
    case chat
    case voiceOutput
    case developer
}
#endif

// MARK: - Settings View

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @ObservedObject private var settingsManager: SettingsManager
    @State private var pendingDeletionTarget: SettingsDeletionTarget?
    @Environment(\.dismiss) private var dismiss
#if os(macOS)
    @State private var measuredContentSize: CGSize = .zero
    @State private var macSelectedSettingsTab: MacSettingsTab = .servers
    @State private var macShowingAdvancedAPIResetConfirmation = false
    @State private var macShowingDeveloperDefaultsConfirmation = false
#endif

    init(settingsManager: SettingsManager = .shared) {
        _settingsManager = ObservedObject(wrappedValue: settingsManager)
        _viewModel = StateObject(wrappedValue: SettingsViewModel(settingsManager: settingsManager))
    }

    private var detectedChatAPIFormatName: String {
        let base = viewModel.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedProvider = settingsManager.chatModelCapabilities.detectedProvider(for: base)
            ?? ChatAPIEndpointResolver.officialProviderHint(for: base)
        let detectedStyle = settingsManager.chatModelCapabilities.detectedRequestStyle(for: base)
            ?? SettingsAPIRequestStyleResolver.inferredStyle(
                for: base,
                providerHint: detectedProvider
            )
        return detectedAPIFormatName(provider: detectedProvider, requestStyle: detectedStyle)
    }

    private func detectedAPIFormatName(provider: ChatProvider?, requestStyle: ChatRequestStyle?) -> String {
        switch requestStyle {
        case .openAIResponses:
            return provider == .unknown
                ? NSLocalizedString("Unknown, using OpenAI Responses", comment: "Detected API format name")
                : NSLocalizedString("OpenAI Responses", comment: "Detected API format name")
        case .openAIChatCompletions:
            return NSLocalizedString("OpenAI Chat Completions", comment: "Detected API format name")
        case .anthropicMessages:
            return ChatProvider.anthropic.displayName
        case .lmStudioRESTV1:
            return ChatProvider.lmStudio.displayName
        case nil:
            if let provider, provider != .unknown {
                return provider.displayName
            }
            return NSLocalizedString("Unknown", comment: "Provider display name")
        }
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
        #else
        applyCommonModifiers(
            NavigationStack {
                Form {
                    chatSection()
                    serverSection()
                    chatModelSection()
                    toolUseSection()
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
            toolUseSection()
            systemPromptSection()
        }
        .formStyle(.grouped)
        .tabItem {
            Label("Chat", systemImage: "text.bubble.fill")
        }
    }

    private var macDeveloperTab: some View {
        macDeveloperSettingsPage
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
                placeholder: "Enter preset name",
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
        SettingsVoicePresetSection(
            viewModel: viewModel,
            settingsManager: settingsManager,
            hideHeader: hideHeader,
            requestDeletion: requestDeletion(_:)
        )
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
        SettingsChatServerSection(
            viewModel: viewModel,
            hideHeader: hideHeader,
            detectedChatAPIFormatName: detectedChatAPIFormatName,
            requestDeletion: requestDeletion(_:)
        )
    }

    @ViewBuilder
    private func chatModelSection(hideHeader: Bool = false) -> some View {
        SettingsChatModelSection(viewModel: viewModel, hideHeader: hideHeader)
    }

    @ViewBuilder
    private func toolUseSection(hideHeader: Bool = false) -> some View {
        SettingsToolUseSection(viewModel: viewModel, hideHeader: hideHeader)
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

        #if os(macOS)
        if settingsManager.developerModeEnabled {
            SettingsDeveloperRequestPolicySection(viewModel: viewModel)
            SettingsDeveloperToolUseSection(viewModel: viewModel)
            SettingsAdvancedAPISectionsContent(
                viewModel: viewModel,
                settingsManager: settingsManager,
                showingResetConfirmation: $macShowingAdvancedAPIResetConfirmation,
                includeDefaultsSection: false
            )
            SettingsDeveloperDefaultsSection(
                viewModel: viewModel,
                showingResetConfirmation: $macShowingDeveloperDefaultsConfirmation
            )
        }
        #else
        advancedAPIEntrySection()
        #endif
    }

    @ViewBuilder
    private func advancedAPIEntrySection() -> some View {
        if settingsManager.developerModeEnabled {
            Section {
                NavigationLink(value: SettingsNavigationDestination.advancedAPISettings) {
                    Label("Advanced Options", systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    private var advancedAPISettingsView: some View {
        SettingsAdvancedAPIView(
            viewModel: viewModel,
            settingsManager: settingsManager,
            includeDeveloperSections: settingsManager.developerModeEnabled
        )
    }

    private func systemPromptSection() -> some View {
        SettingsSystemPromptSection(
            viewModel: viewModel,
            onDeleteNormalPromptPreset: { requestDeletion(.normalPromptPreset) },
            onDeleteVoicePromptPreset: { requestDeletion(.voicePromptPreset) }
        )
    }

#if os(macOS)
    private func updateWindowSizeIfNeeded(_ newSize: CGSize) {
        if newSize.width > 0, newSize.height > 0 {
            measuredContentSize = newSize
        }

        SettingsWindowSizer.updateWindowSizeIfNeeded()
    }
#endif
}

#Preview {
    SettingsView(settingsManager: .shared)
}
