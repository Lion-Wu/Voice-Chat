//
//  SettingsChatServerSection.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

struct SettingsChatServerSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    let hideHeader: Bool
    let detectedChatAPIFormatName: String
    let requestDeletion: (SettingsDeletionTarget) -> Void

    var body: some View {
        Section {
            #if os(macOS)
            LabeledContent("Preset") {
                Picker("", selection: $viewModel.selectedChatServerPresetID) {
                    ForEach(viewModel.chatServerPresetList) { preset in
                        Text(preset.name).tag(Optional.some(preset.id))
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
                ForEach(viewModel.chatServerPresetList) { preset in
                    Text(preset.name).tag(Optional.some(preset.id))
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
                placeholder: "Enter preset name",
                text: $viewModel.chatServerPresetName,
                onCommit: { viewModel.commitChatServerEdits() }
            )

            LabeledTextField(
                label: "Server URL",
                placeholder: "http://localhost:1234",
                text: $viewModel.apiURL,
                onCommit: { viewModel.commitChatServerEdits() }
            )

            LabeledContent("API Format") {
                Picker("", selection: $viewModel.selectedChatAPIFormatPreference) {
                    ForEach(ChatProviderDescriptorRegistry.apiFormatOptions) { option in
                        Text(option.displayName).tag(option.preference)
                    }
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
                text: $viewModel.chatAPIKey,
                onCommit: { viewModel.commitChatServerEdits() }
            )
        } header: {
            header
        }
        .onChange(of: viewModel.selectedChatServerPresetID) {
            viewModel.fetchAvailableModels()
        }
    }

    @ViewBuilder
    private var header: some View {
        if hideHeader {
            EmptyView()
        } else {
            #if os(macOS)
            Text("Chat Server")
                .font(.headline)
                .textCase(.none)
            #else
            Text("Chat Server")
            #endif
        }
    }
}
