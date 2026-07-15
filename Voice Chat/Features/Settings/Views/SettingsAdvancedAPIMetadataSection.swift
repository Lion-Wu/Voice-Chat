//
//  SettingsAdvancedAPIMetadataSection.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import SwiftUI

struct SettingsAdvancedAPIMetadataSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var settingsManager: SettingsManager

    private var context: SettingsAdvancedAPIContext {
        SettingsAdvancedAPIContext(
            viewModel: viewModel,
            settingsManager: settingsManager
        )
    }

    var body: some View {
        Section {
            SettingsAdvancedAPIMetadataRow("Provider", context.currentProvider.displayName)
            SettingsAdvancedAPIMetadataRow("Request Style", context.currentRequestStyleDisplayName)
            SettingsAdvancedAPIMetadataRow("API Format", context.selectedAPIFormatDisplayName)
            SettingsAdvancedAPIMetadataRow("Fetched Models", "\(viewModel.availableModels.count)")
            if let endpoint = viewModel.lastModelFetchEndpoint {
                SettingsAdvancedAPIMetadataRow("Models Endpoint", endpoint.modelsURL.absoluteString)
                SettingsAdvancedAPIMetadataRow("Chat Endpoint", endpoint.chatURL.absoluteString)
            } else {
                SettingsAdvancedAPIMetadataRow("Models Endpoint", String(localized: "Not fetched"))
            }

            if let metadata = context.selectedModelMetadata {
                SettingsAdvancedAPISelectedModelMetadataDisclosure(
                    metadata: metadata,
                    context: context
                )
            }

            if !viewModel.lastFetchedModelMetadata.isEmpty {
                SettingsAdvancedAPIFetchedModelsMetadataDisclosure(
                    models: viewModel.lastFetchedModelMetadata,
                    context: context
                )
            }
        } header: {
            SettingsAdvancedAPISectionHeader(title: "Model List Metadata")
        }
    }
}

private struct SettingsAdvancedAPISelectedModelMetadataDisclosure: View {
    let metadata: ModelInfo
    let context: SettingsAdvancedAPIContext

    var body: some View {
        DisclosureGroup("Selected Model Metadata") {
            SettingsAdvancedAPIMetadataRow("ID", metadata.id)
            SettingsAdvancedAPIMetadataRow("Object", metadata.object ?? context.localizedUnknown)
            SettingsAdvancedAPIMetadataRow("Owner", metadata.owned_by ?? context.localizedUnknown)
            SettingsAdvancedAPIMetadataRow("Type", metadata.type ?? metadata.arch ?? context.localizedUnknown)
            SettingsAdvancedAPIMetadataRow(
                "Input Modalities",
                context.joined(
                    metadata.architecture?.input_modalities ??
                        metadata.input_modalities ??
                        metadata.capabilities?.input_modalities
                )
            )
            SettingsAdvancedAPIMetadataRow("Modalities", context.joined(metadata.modalities ?? metadata.capabilities?.modalities))
            SettingsAdvancedAPIMetadataRow("Supported Parameters", context.joined(metadata.supported_parameters ?? metadata.capabilities?.supported_parameters))
            SettingsAdvancedAPIMetadataRow("Image Input", context.optionalBool(metadata.supportsImageInputHint))
            if let thinking = metadata.thinkingCapabilityHint(
                provider: context.currentProvider,
                requestStyle: context.currentRequestStyle
            ) {
                SettingsAdvancedAPIMetadataRow("Thinking Options", thinking.options.map(\.rawValue).joined(separator: ", "))
                SettingsAdvancedAPIMetadataRow("Thinking Parameter", thinking.requestParameter?.rawValue ?? String(localized: "Provider default"))
            } else {
                SettingsAdvancedAPIMetadataRow("Thinking Options", String(localized: "Not detected"))
            }
            SettingsAdvancedAPIRawJSONBlock(
                title: "Raw Model JSON",
                value: metadata.rawMetadata
            )
        }
    }
}

private struct SettingsAdvancedAPIFetchedModelsMetadataDisclosure: View {
    let models: [ModelInfo]
    let context: SettingsAdvancedAPIContext

    var body: some View {
        DisclosureGroup("Fetched Models Metadata") {
            ForEach(Array(models.enumerated()), id: \.offset) { _, model in
                SettingsAdvancedAPIFetchedModelMetadataDisclosure(
                    model: model,
                    context: context
                )
            }
        }
    }
}

private struct SettingsAdvancedAPIFetchedModelMetadataDisclosure: View {
    let model: ModelInfo
    let context: SettingsAdvancedAPIContext

    var body: some View {
        DisclosureGroup(model.id) {
            SettingsAdvancedAPIMetadataRow("Object", model.object ?? context.localizedUnknown)
            SettingsAdvancedAPIMetadataRow("Owner", model.owned_by ?? context.localizedUnknown)
            SettingsAdvancedAPIMetadataRow("Type", model.type ?? model.arch ?? context.localizedUnknown)
            SettingsAdvancedAPIMetadataRow(
                "Input Modalities",
                context.joined(
                    model.architecture?.input_modalities ??
                        model.input_modalities ??
                        model.capabilities?.input_modalities
                )
            )
            SettingsAdvancedAPIMetadataRow("Supported Parameters", context.joined(model.supported_parameters ?? model.capabilities?.supported_parameters))
            SettingsAdvancedAPIMetadataRow("Image Input", context.optionalBool(model.supportsImageInputHint))
            SettingsAdvancedAPIRawJSONBlock(
                title: "Raw JSON",
                value: model.rawMetadata
            )
        }
    }
}

private struct SettingsAdvancedAPIRawJSONBlock: View {
    let title: LocalizedStringKey
    let value: JSONValue?

    var body: some View {
        RawJSONPreviewBlock(
            title: title,
            value: value,
            missingText: String(localized: "Raw metadata was not captured.")
        )
    }
}
