//
//  SettingsSystemPromptSection.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

struct SettingsSystemPromptSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    let onDeleteNormalPromptPreset: () -> Void
    let onDeleteVoicePromptPreset: () -> Void

    var body: some View {
        SettingsPromptPresetSection(
            title: "Chat Prompt",
            promptPlaceholder: "Used for chat mode",
            presets: viewModel.normalSystemPromptPresetList,
            selectedPresetID: $viewModel.selectedNormalSystemPromptPresetID,
            presetName: $viewModel.normalSystemPromptPresetName,
            prompt: $viewModel.normalSystemPromptPrompt,
            onCommit: viewModel.commitNormalSystemPromptEdits,
            onAdd: viewModel.addNormalSystemPromptPreset,
            onDelete: onDeleteNormalPromptPreset
        )

        SettingsPromptPresetSection(
            title: "Voice Prompt",
            promptPlaceholder: "Used for voice mode",
            presets: viewModel.voiceSystemPromptPresetList,
            selectedPresetID: $viewModel.selectedVoiceSystemPromptPresetID,
            presetName: $viewModel.voiceSystemPromptPresetName,
            prompt: $viewModel.voiceSystemPromptPrompt,
            onCommit: viewModel.commitVoiceSystemPromptEdits,
            onAdd: viewModel.addVoiceSystemPromptPreset,
            onDelete: onDeleteVoicePromptPreset
        )
    }
}

private struct SettingsPromptPresetSection: View {
    let title: LocalizedStringKey
    let promptPlaceholder: String
    let presets: [SettingsViewModel.PresetSummary]
    @Binding var selectedPresetID: UUID?
    @Binding var presetName: String
    @Binding var prompt: String
    let onCommit: () -> Void
    let onAdd: () -> Void
    let onDelete: () -> Void

    private var deleteDisabled: Bool {
        presets.count <= 1 || selectedPresetID == nil
    }

    var body: some View {
        Section {
            presetPickerRow
            presetActionRow

            LabeledTextField(
                label: "Preset Name",
                placeholder: "Enter preset name",
                text: $presetName,
                onCommit: onCommit
            )
            LabeledTextEditor(
                label: "Prompt",
                placeholder: promptPlaceholder,
                text: $prompt,
                onCommit: onCommit
            )
        } header: {
            sectionHeader(title)
        }
    }

    @ViewBuilder
    private var presetPickerRow: some View {
        #if os(macOS)
        LabeledContent("Preset") {
            Picker("", selection: $selectedPresetID) {
                ForEach(presets) { preset in
                    Text(preset.name).tag(Optional.some(preset.id))
                }
            }
            .labelsHidden()
        }
        #else
        Picker("Preset", selection: $selectedPresetID) {
            ForEach(presets) { preset in
                Text(preset.name).tag(Optional.some(preset.id))
            }
        }
        .pickerStyle(.menu)
        #endif
    }

    @ViewBuilder
    private var presetActionRow: some View {
        #if os(macOS)
        HStack {
            Spacer()
            HStack(spacing: 8) {
                addButton
                    .controlSize(.small)
                    .help("Add prompt preset")

                deleteButton
                    .controlSize(.small)
                    .help("Delete selected prompt preset")
            }
        }
        #else
        HStack(spacing: 16) {
            addButton
                .contentShape(Rectangle())

            deleteButton
                .contentShape(Rectangle())
        }
        #endif
    }

    private var addButton: some View {
        Button {
            onAdd()
        } label: {
            Label("Add", systemImage: "plus.circle.fill")
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
                .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .disabled(deleteDisabled)
    }

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
}
