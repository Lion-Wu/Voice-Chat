import SwiftUI

struct SettingsVoicePresetSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var settingsManager: SettingsManager
    var hideHeader = false
    var requestDeletion: (SettingsDeletionTarget) -> Void

    var body: some View {
        Section {
            switch viewModel.ttsProvider {
            case .gptSoVITS:
                presetPickerRow
                presetActionButtons
                presetDetailFields
                presetApplyStatusRow
                presetApplyRow
            case .appleSpeech:
                appleSpeechSettings
            case .personalVoice:
                personalVoiceSettings
            }
        } header: {
            if hideHeader {
                EmptyView()
            } else {
                SettingsSectionHeader("Voice Model")
            }
        }
    }

    @ViewBuilder
    private var appleSpeechSettings: some View {
        Picker("Apple Speech", selection: $viewModel.appleSpeechVoiceIdentifier) {
            Text("System Default").tag(String?.none)
            if let selectedIdentifier = viewModel.appleSpeechVoiceIdentifier,
               !viewModel.availableSystemVoices.contains(where: { $0.id == selectedIdentifier }) {
                Text("Selected voice is not installed").tag(Optional.some(selectedIdentifier))
            }
            ForEach(viewModel.availableSystemVoices) { voice in
                Text(voice.displayName).tag(Optional.some(voice.id))
            }
        }
    }

    @ViewBuilder
    private var personalVoiceSettings: some View {
        switch viewModel.personalVoiceAuthorizationStatus {
        case .notDetermined:
            if viewModel.isRequestingPersonalVoiceAuthorization {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Requesting Apple Personal Voice access…")
                }
                .foregroundStyle(.secondary)
            } else {
                Text("Apple Personal Voice access is not authorized.")
                    .foregroundStyle(.secondary)
            }
        case .authorized:
            if viewModel.availablePersonalVoices.isEmpty {
                Text("No Apple Personal Voice is available.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Apple Personal Voice", selection: $viewModel.personalVoiceIdentifier) {
                    ForEach(viewModel.availablePersonalVoices) { voice in
                        Text(voice.displayName).tag(Optional.some(voice.id))
                    }
                }
            }
        case .denied:
            Text("Apple Personal Voice access is not authorized.")
                .foregroundStyle(.secondary)
        case .unsupported:
            Text("Apple Personal Voice is not supported on this device.")
                .foregroundStyle(.secondary)
        @unknown default:
            EmptyView()
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
                             placeholder: "Enter preset name",
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
}
