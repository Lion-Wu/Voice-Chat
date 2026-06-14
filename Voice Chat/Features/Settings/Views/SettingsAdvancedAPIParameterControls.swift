//
//  SettingsAdvancedAPIParameterControls.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import SwiftUI

struct SettingsAdvancedAPIParameterControls: View {
    @ObservedObject var viewModel: SettingsViewModel
    let profile: SettingsAdvancedAPIParameterProfile

    var body: some View {
        switch profile {
        case .openAIResponses:
            SettingsAdvancedAPIIntegerField(
                title: "max_output_tokens",
                value: $viewModel.apiAdvancedSettings.openAIResponsesMaxOutputTokens
            )
            SettingsAdvancedAPISamplingControls(
                sampling: $viewModel.apiAdvancedSettings.openAIResponsesSampling,
                includePenalties: false,
                includeSeed: false,
                includeJSONMode: true,
                includeLogprobs: false
            )
            SettingsAdvancedAPIVerbosityControl(
                sampling: $viewModel.apiAdvancedSettings.openAIResponsesSampling,
                title: "text.verbosity",
                options: ["low", "medium", "high"]
            )
        case .openAIChat:
            SettingsAdvancedAPIIntegerField(
                title: "max_completion_tokens",
                value: $viewModel.apiAdvancedSettings.openAIChatMaxCompletionTokens
            )
            SettingsAdvancedAPISamplingControls(sampling: $viewModel.apiAdvancedSettings.openAIChatSampling)
        case .openAICompatible:
            SettingsAdvancedAPIIntegerField(
                title: "max_tokens",
                value: $viewModel.apiAdvancedSettings.openAICompatibleMaxTokens
            )
            SettingsAdvancedAPISamplingControls(sampling: $viewModel.apiAdvancedSettings.openAICompatibleSampling)
        case .anthropic:
            SettingsAdvancedAPIIntegerField(
                title: "max_tokens",
                value: $viewModel.apiAdvancedSettings.anthropicMaxTokens
            )
            SettingsAdvancedAPIIntegerField(
                title: "Extended thinking response reserve tokens",
                value: $viewModel.apiAdvancedSettings.anthropicThinkingResponseReserve
            )
            SettingsAdvancedAPIIntegerField(
                title: "Extended thinking low budget_tokens",
                value: $viewModel.apiAdvancedSettings.anthropicLowThinkingBudget
            )
            SettingsAdvancedAPIIntegerField(
                title: "Extended thinking medium budget_tokens",
                value: $viewModel.apiAdvancedSettings.anthropicMediumThinkingBudget
            )
            SettingsAdvancedAPIIntegerField(
                title: "Extended thinking high budget_tokens",
                value: $viewModel.apiAdvancedSettings.anthropicHighThinkingBudget
            )
            SettingsAdvancedAPISamplingControls(
                sampling: $viewModel.apiAdvancedSettings.anthropicSampling,
                includeTopK: true,
                includePenalties: false,
                includeSeed: false,
                includeJSONMode: false,
                includeLogprobs: false
            )
        case .gemini:
            SettingsAdvancedAPIIntegerField(
                title: "max_tokens",
                value: $viewModel.apiAdvancedSettings.geminiMaxTokens
            )
            SettingsAdvancedAPISamplingControls(
                sampling: $viewModel.apiAdvancedSettings.geminiSampling,
                includePenalties: false,
                includeSeed: false,
                includeJSONMode: false,
                includeLogprobs: false
            )
        case .deepSeek:
            SettingsAdvancedAPIIntegerField(
                title: "max_tokens",
                value: $viewModel.apiAdvancedSettings.deepSeekMaxTokens
            )
            SettingsAdvancedAPISamplingControls(
                sampling: $viewModel.apiAdvancedSettings.deepSeekSampling,
                includePenalties: true,
                includeSeed: false,
                includeJSONMode: true,
                includeLogprobs: true
            )
        case .xAI:
            SettingsAdvancedAPIIntegerField(
                title: "max_tokens",
                value: $viewModel.apiAdvancedSettings.xAIMaxTokens
            )
            SettingsAdvancedAPISamplingControls(sampling: $viewModel.apiAdvancedSettings.xAISampling)
        case .openRouter:
            SettingsAdvancedAPIIntegerField(
                title: "max_tokens",
                value: $viewModel.apiAdvancedSettings.openRouterMaxTokens
            )
            SettingsAdvancedAPIIntegerField(
                title: "max_completion_tokens",
                value: $viewModel.apiAdvancedSettings.openRouterMaxCompletionTokens
            )
            SettingsAdvancedAPISamplingControls(
                sampling: $viewModel.apiAdvancedSettings.openRouterSampling,
                includeTopK: true,
                includeMinP: true,
                includeTopA: true,
                includeRepetitionPenalty: true,
                includeStructuredOutputs: true
            )
            SettingsAdvancedAPIVerbosityControl(
                sampling: $viewModel.apiAdvancedSettings.openRouterSampling,
                title: "verbosity",
                options: ["low", "medium", "high", "max"]
            )
        case .lmStudioREST:
            SettingsAdvancedAPIIntegerField(
                title: "max_output_tokens",
                value: $viewModel.apiAdvancedSettings.lmStudioMaxTokens
            )
            SettingsAdvancedAPIIntegerToggleField(
                title: "context_length",
                enabled: $viewModel.apiAdvancedSettings.lmStudioSampling.contextLengthEnabled,
                value: $viewModel.apiAdvancedSettings.lmStudioSampling.contextLength
            )
            SettingsAdvancedAPISamplingControls(
                sampling: $viewModel.apiAdvancedSettings.lmStudioSampling,
                includeTopK: true,
                includeMinP: true,
                includePenalties: false,
                includeRepetitionPenalty: true,
                repetitionPenaltyTitle: "repeat_penalty",
                includeSeed: false,
                includeJSONMode: false,
                includeLogprobs: false
            )
        case .lmStudioOpenAICompatible:
            SettingsAdvancedAPIIntegerField(
                title: "max_tokens",
                value: $viewModel.apiAdvancedSettings.lmStudioOpenAICompatibleMaxTokens
            )
            SettingsAdvancedAPISamplingControls(
                sampling: $viewModel.apiAdvancedSettings.lmStudioOpenAICompatibleSampling,
                includeTopK: true,
                includeRepetitionPenalty: true,
                repetitionPenaltyTitle: "repeat_penalty"
            )
        case .llamaCpp:
            SettingsAdvancedAPIIntegerField(
                title: "max_tokens",
                value: $viewModel.apiAdvancedSettings.llamaCppMaxTokens
            )
            SettingsAdvancedAPISamplingControls(
                sampling: $viewModel.apiAdvancedSettings.llamaCppSampling,
                includeTopK: true,
                includeMinP: true,
                includeRepetitionPenalty: true,
                repetitionPenaltyTitle: "repeat_penalty"
            )
        }
    }
}

struct SettingsAdvancedAPISamplingControls: View {
    @Binding var sampling: APIAdvancedSamplingSettings
    var includeTopK = false
    var includeMinP = false
    var includeTopA = false
    var includePenalties = true
    var includeRepetitionPenalty = false
    var repetitionPenaltyTitle: LocalizedStringKey = "repetition_penalty"
    var includeSeed = true
    var includeJSONMode = true
    var includeStructuredOutputs = false
    var includeLogprobs = true

    var body: some View {
        SettingsAdvancedAPIDoubleToggleField(
            title: "temperature",
            enabled: $sampling.temperatureEnabled,
            value: $sampling.temperature
        )
        SettingsAdvancedAPIDoubleToggleField(
            title: "top_p",
            enabled: $sampling.topPEnabled,
            value: $sampling.topP
        )
        if includeTopK {
            SettingsAdvancedAPIIntegerToggleField(
                title: "top_k",
                enabled: $sampling.topKEnabled,
                value: $sampling.topK
            )
        }
        if includeMinP {
            SettingsAdvancedAPIDoubleToggleField(
                title: "min_p",
                enabled: $sampling.minPEnabled,
                value: $sampling.minP
            )
        }
        if includeTopA {
            SettingsAdvancedAPIDoubleToggleField(
                title: "top_a",
                enabled: $sampling.topAEnabled,
                value: $sampling.topA
            )
        }
        if includePenalties {
            SettingsAdvancedAPIDoubleToggleField(
                title: "presence_penalty",
                enabled: $sampling.presencePenaltyEnabled,
                value: $sampling.presencePenalty
            )
            SettingsAdvancedAPIDoubleToggleField(
                title: "frequency_penalty",
                enabled: $sampling.frequencyPenaltyEnabled,
                value: $sampling.frequencyPenalty
            )
        }
        if includeRepetitionPenalty {
            SettingsAdvancedAPIDoubleToggleField(
                title: repetitionPenaltyTitle,
                enabled: $sampling.repetitionPenaltyEnabled,
                value: $sampling.repetitionPenalty
            )
        }
        if includeSeed {
            SettingsAdvancedAPIIntegerToggleField(
                title: "seed",
                enabled: $sampling.seedEnabled,
                value: $sampling.seed
            )
        }
        if includeJSONMode {
            SettingsAdvancedAPIBooleanToggleField(
                title: "JSON mode",
                isOn: $sampling.jsonModeEnabled
            )
        }
        if includeStructuredOutputs {
            SettingsAdvancedAPIBooleanToggleField(
                title: "structured_outputs",
                isOn: $sampling.structuredOutputsEnabled
            )
        }
        if includeLogprobs {
            SettingsAdvancedAPIBooleanToggleField(
                title: "logprobs",
                isOn: $sampling.logprobsEnabled
            )
            if sampling.logprobsEnabled {
                SettingsAdvancedAPIIntegerToggleField(
                    title: "top_logprobs",
                    enabled: $sampling.topLogprobsEnabled,
                    value: $sampling.topLogprobs
                )
            }
        }
    }
}
