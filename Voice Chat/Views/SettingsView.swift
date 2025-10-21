//
//  SettingsView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.22.
//

import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    // Controls the confirmation alert when deleting a preset.
    @State private var showDeletePresetAlert = false

    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    init(viewModel: SettingsViewModel = SettingsViewModel()) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        #if os(macOS)
        settingsForm
            .formStyle(.grouped)
            .frame(width: 600, height: 720)
            .task { viewModel.refreshAvailableModels() }
            .alert(String(localized: "Error"), isPresented: errorBinding) {
                Button(String(localized: "OK")) { viewModel.clearErrorMessage() }
            } message: {
                if let message = viewModel.errorMessage {
                    Text(message)
                }
            }
            .alert(String(localized: "Delete this preset?"),
                   isPresented: $showDeletePresetAlert) {
                Button(String(localized: "Delete"), role: .destructive) { viewModel.deleteCurrentPreset() }
                Button(String(localized: "Cancel"), role: .cancel) { }
            } message: {
                Text(String(localized: "This action cannot be undone."))
            }
        #else
        NavigationView {
            settingsForm
                .navigationBarTitle("Settings", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { viewModel.refreshAvailableModels() }
        .alert(String(localized: "Error"), isPresented: errorBinding) {
            Button(String(localized: "OK")) { viewModel.clearErrorMessage() }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
        .alert(String(localized: "Delete this preset?"),
               isPresented: $showDeletePresetAlert) {
            Button(String(localized: "Delete"), role: .destructive) { viewModel.deleteCurrentPreset() }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "This action cannot be undone."))
        }
        #endif
    }

    private var settingsForm: some View {
        Form {
            serverSection
            presetSection
            voiceOutputSection
            chatSection
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearErrorMessage() } }
        )
    }

    // MARK: - Sections

    private var serverSection: some View {
        Section(header: Text("Voice Server")) {
            SettingsFieldRow(
                label: "Server Address",
                placeholder: "http://127.0.0.1:9880",
                text: $viewModel.serverAddress
            )
            SettingsFieldRow(
                label: "Text Language",
                placeholder: "text_lang (e.g. auto/zh/en)",
                text: $viewModel.textLang
            )
        }
    }

    private var presetSection: some View {
        Section(header: Text("Model Preset")) {
            // Preset picker row and related actions.
            VStack(spacing: 10) {
                #if os(macOS)
                SettingsPickerRow(label: "Current Preset") {
                    Picker("", selection: $viewModel.selectedPresetID) {
                        ForEach(viewModel.presetList) { preset in
                            Text(preset.name).tag(Optional.some(preset.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: macFieldWidth)
                }

                if #available(macOS 13.0, *) {
                    ControlGroup {
                        Button {
                            viewModel.addPreset()
                        } label: {
                            Label("Add", systemImage: "plus.circle")
                        }

                        Button(role: .destructive) {
                            showDeletePresetAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(!viewModel.canDeleteSelectedPreset)
                    }
                    .controlGroupStyle(.compactMenu)
                    .controlSize(.small)
                } else {
                    HStack(spacing: 12) {
                        Button {
                            viewModel.addPreset()
                        } label: {
                            Label("Add", systemImage: "plus.circle")
                        }

                        Button(role: .destructive) {
                            showDeletePresetAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(!viewModel.canDeleteSelectedPreset)
                    }
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
                        .disabled(!viewModel.canDeleteSelectedPreset)
                    }
                }
                #endif

                // Applying status / error state feedback.
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

            // Preset fields grouped for clarity.
            Group {
                SettingsFieldRow(label: "Preset Name",
                                  placeholder: "Preset name",
                                  text: $viewModel.presetName)

                SettingsFieldRow(label: "ref_audio_path",
                                  placeholder: "GPT_SoVITS/refs/xxx.wav",
                                  text: $viewModel.presetRefAudioPath)
                SettingsFieldRow(label: "prompt_text",
                                  placeholder: "Reference text (optional)",
                                  text: $viewModel.presetPromptText)
                SettingsFieldRow(label: "prompt_lang",
                                  placeholder: "auto/zh/en ...",
                                  text: $viewModel.presetPromptLang)

                SettingsFieldRow(label: "GPT weights path",
                                  placeholder: "GPT_SoVITS/pretrained_models/s1xxx.ckpt",
                                  text: $viewModel.presetGPTWeightsPath)
                SettingsFieldRow(label: "SoVITS weights path",
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
            SettingsToggleRow(label: "Enable Streaming", isOn: $viewModel.enableStreaming)
            SettingsToggleRow(label: "Auto Read After Generation", isOn: $viewModel.autoReadAfterGeneration)
            SettingsPickerRow(label: "Split Method") {
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
                .frame(maxWidth: macFieldWidth)
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
            SettingsFieldRow(label: "Chat API URL",
                              placeholder: "Enter chat API URL",
                              text: $viewModel.apiURL)

            if viewModel.isFetchingModels {
                HStack {
                    ProgressView("Loading model list...")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                #if os(macOS)
                SettingsPickerRow(label: "Select Model") {
                    Picker("", selection: $viewModel.selectedModel) {
                        ForEach(viewModel.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: macFieldWidth)
                }
                #else
                Picker("Select Model", selection: $viewModel.selectedModel) {
                    ForEach(viewModel.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                #endif
            }

            HStack {
                Spacer()
                Button(action: viewModel.refreshAvailableModels) {
                    Label("Refresh Model List", systemImage: "arrow.clockwise.circle")
                }
            }
            .padding(.top, 6)
        }
    }
}

#if os(macOS)
private let macFieldWidth: CGFloat = 320
#endif

// MARK: - Shared Form Helpers

private struct SettingsFieldRow: View {
    let label: LocalizedStringKey
    let placeholder: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        #if os(macOS)
        LabeledContent(label) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: macFieldWidth)
        }
        .padding(.vertical, 2)
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            #if canImport(UIKit)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            #else
            TextField(placeholder, text: $text)
            #endif
        }
        #endif
    }
}

private struct SettingsPickerRow<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(macOS)
        LabeledContent(label) {
            content()
        }
        .padding(.vertical, 2)
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            content()
        }
        #endif
    }
}

private struct SettingsToggleRow: View {
    let label: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        #if os(macOS)
        LabeledContent(label) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 2)
        #else
        Toggle(label, isOn: $isOn)
        #endif
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager.shared)
}
