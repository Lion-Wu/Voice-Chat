//
//  SettingsChatModelSection.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

struct SettingsChatModelSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    let hideHeader: Bool

    private var hasModelListError: Bool {
        !(viewModel.chatServerErrorMessage?.isEmpty ?? true)
    }

    private var showModelPicker: Bool {
        !(viewModel.isLoadingModels || hasModelListError)
    }

    var body: some View {
        Section {
            modelPickerRow

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
            header
        }
    }

    private var modelPickerRow: some View {
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
                    #if !os(macOS)
                    .pickerStyle(.menu)
                    #endif
                }
                .opacity(showModelPicker ? 1 : 0)
                .allowsHitTesting(showModelPicker)
                .accessibilityHidden(!showModelPicker)

                modelListStatusView
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var modelListStatusView: some View {
        if viewModel.isLoadingModels {
            HStack(spacing: 8) {
                ProgressView()
                    #if os(macOS)
                    .controlSize(.small)
                    #endif
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
            #if os(macOS)
            .help(viewModel.modelRetryLastError ?? "")
            #endif
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
            #if os(macOS)
            .help(message)
            #endif
        }
    }

    @ViewBuilder
    private var header: some View {
        if hideHeader {
            EmptyView()
        } else {
            #if os(macOS)
            Text("Chat Model")
                .font(.headline)
                .textCase(.none)
            #else
            Text("Chat Model")
            #endif
        }
    }
}
