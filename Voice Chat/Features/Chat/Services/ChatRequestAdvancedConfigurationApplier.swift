//
//  ChatRequestAdvancedConfigurationApplier.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

struct ChatRequestAdvancedConfigurationApplier: Sendable {
    func apply(
        to requestBody: inout [String: Any],
        model: String,
        endpoint: ChatAPIEndpointCandidate,
        settings: APIAdvancedSettings
    ) {
        switch endpoint.style {
        case .openAIChatCompletions:
            if ChatRequestBodyEndpointClassifier.isOpenAIResponsesEndpoint(endpoint.chatURL) {
                applyPositiveInteger(settings.openAIResponsesMaxOutputTokens, key: "max_output_tokens", to: &requestBody)
                applyOpenAIResponsesSamplingConfiguration(settings.openAIResponsesSampling, to: &requestBody)
                return
            }

            switch endpoint.provider {
            case .openAI:
                applyPositiveInteger(settings.openAIChatMaxCompletionTokens, key: "max_completion_tokens", to: &requestBody)
                applyOpenAIChatSamplingConfiguration(settings.openAIChatSampling, to: &requestBody)
            case .gemini:
                applyPositiveInteger(settings.geminiMaxTokens, key: "max_tokens", to: &requestBody)
                applyGeminiSamplingConfiguration(settings.geminiSampling, to: &requestBody)
            case .deepSeek:
                applyPositiveInteger(settings.deepSeekMaxTokens, key: "max_tokens", to: &requestBody)
                applyDeepSeekSamplingConfiguration(settings.deepSeekSampling, model: model, to: &requestBody)
            case .xAI:
                applyPositiveInteger(settings.xAIMaxTokens, key: "max_tokens", to: &requestBody)
                applyOpenAIChatSamplingConfiguration(settings.xAISampling, to: &requestBody, topLogprobsLimit: 8)
            case .openRouter:
                applyPositiveInteger(settings.openRouterMaxTokens, key: "max_tokens", to: &requestBody)
                applyPositiveInteger(settings.openRouterMaxCompletionTokens, key: "max_completion_tokens", to: &requestBody)
                applyOpenRouterSamplingConfiguration(settings.openRouterSampling, to: &requestBody)
            case .lmStudio:
                applyPositiveInteger(settings.lmStudioOpenAICompatibleMaxTokens, key: "max_tokens", to: &requestBody)
                applyLMStudioOpenAICompatibleSamplingConfiguration(settings.lmStudioOpenAICompatibleSampling, to: &requestBody)
            case .llamaCpp:
                applyPositiveInteger(settings.llamaCppMaxTokens, key: "max_tokens", to: &requestBody)
                applyLlamaCppSamplingConfiguration(settings.llamaCppSampling, to: &requestBody)
            case .openAICompatible, .unknown, .anthropic:
                applyPositiveInteger(settings.openAICompatibleMaxTokens, key: "max_tokens", to: &requestBody)
                applyOpenAIChatSamplingConfiguration(settings.openAICompatibleSampling, to: &requestBody)
            }

        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            applyPositiveInteger(settings.lmStudioMaxTokens, key: "max_output_tokens", to: &requestBody)
            applyLMStudioRESTSamplingConfiguration(settings.lmStudioSampling, to: &requestBody)

        case .anthropicMessages:
            applyAnthropicSamplingConfiguration(settings.anthropicSampling, to: &requestBody)
        }
    }

    private func applyPositiveInteger(_ value: Int, key: String, to requestBody: inout [String: Any]) {
        guard value > 0 else { return }
        requestBody[key] = value
    }

    private func applyIntegerOverride(_ isEnabled: Bool, _ value: Int, key: String, to requestBody: inout [String: Any]) {
        guard isEnabled else { return }
        requestBody[key] = max(0, value)
    }

    private func applyOpenAIChatSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any],
        includeSeed: Bool = true,
        includeJSONMode: Bool = true,
        includeLogprobs: Bool = true,
        topLogprobsLimit: Int = 20
    ) {
        if sampling.temperatureEnabled {
            requestBody["temperature"] = sampling.temperature
        }
        if sampling.topPEnabled {
            requestBody["top_p"] = sampling.topP
        }
        if sampling.presencePenaltyEnabled {
            requestBody["presence_penalty"] = sampling.presencePenalty
        }
        if sampling.frequencyPenaltyEnabled {
            requestBody["frequency_penalty"] = sampling.frequencyPenalty
        }
        if includeJSONMode, sampling.jsonModeEnabled {
            requestBody["response_format"] = ["type": "json_object"]
        }
        if includeLogprobs, sampling.logprobsEnabled {
            requestBody["logprobs"] = true
            applyIntegerOverride(
                sampling.topLogprobsEnabled,
                min(sampling.topLogprobs, topLogprobsLimit),
                key: "top_logprobs",
                to: &requestBody
            )
        }
        if includeSeed {
            applyIntegerOverride(sampling.seedEnabled, sampling.seed, key: "seed", to: &requestBody)
        }
    }

    private func applyAnthropicSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any]
    ) {
        if sampling.temperatureEnabled {
            requestBody["temperature"] = min(sampling.temperature, 1)
        }
        if sampling.topPEnabled {
            requestBody["top_p"] = sampling.topP
        }
        applyIntegerOverride(sampling.topKEnabled, sampling.topK, key: "top_k", to: &requestBody)
    }

    private func applyOpenAIResponsesSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any]
    ) {
        if sampling.temperatureEnabled {
            requestBody["temperature"] = sampling.temperature
        }
        if sampling.topPEnabled {
            requestBody["top_p"] = sampling.topP
        }
        if sampling.jsonModeEnabled {
            mergeOpenAIResponsesTextOptions(["format": ["type": "json_object"]], into: &requestBody)
        }
        if sampling.verbosityEnabled {
            mergeOpenAIResponsesTextOptions(["verbosity": openAIResponsesVerbosity(sampling.verbosity)], into: &requestBody)
        }
    }

    private func mergeOpenAIResponsesTextOptions(_ options: [String: Any], into requestBody: inout [String: Any]) {
        var textOptions = requestBody["text"] as? [String: Any] ?? [:]
        for (key, value) in options {
            textOptions[key] = value
        }
        requestBody["text"] = textOptions
    }

    private func openAIResponsesVerbosity(_ verbosity: String) -> String {
        switch verbosity {
        case "low", "high":
            return verbosity
        default:
            return "medium"
        }
    }

    private func applyGeminiSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any]
    ) {
        if sampling.temperatureEnabled {
            requestBody["temperature"] = sampling.temperature
        }
        if sampling.topPEnabled {
            requestBody["top_p"] = sampling.topP
        }
    }

    private func applyDeepSeekSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        model: String,
        to requestBody: inout [String: Any]
    ) {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isReasoner = normalizedModel.contains("reasoner")
        if !isReasoner {
            if sampling.temperatureEnabled {
                requestBody["temperature"] = sampling.temperature
            }
            if sampling.topPEnabled {
                requestBody["top_p"] = sampling.topP
            }
            if sampling.presencePenaltyEnabled {
                requestBody["presence_penalty"] = sampling.presencePenalty
            }
            if sampling.frequencyPenaltyEnabled {
                requestBody["frequency_penalty"] = sampling.frequencyPenalty
            }
            if sampling.logprobsEnabled {
                requestBody["logprobs"] = true
                applyIntegerOverride(sampling.topLogprobsEnabled, sampling.topLogprobs, key: "top_logprobs", to: &requestBody)
            }
        }
        if sampling.jsonModeEnabled {
            requestBody["response_format"] = ["type": "json_object"]
        }
    }

    private func applyOpenRouterSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any]
    ) {
        applyOpenAIChatSamplingConfiguration(sampling, to: &requestBody)
        applyIntegerOverride(sampling.topKEnabled, sampling.topK, key: "top_k", to: &requestBody)
        if sampling.minPEnabled {
            requestBody["min_p"] = sampling.minP
        }
        if sampling.topAEnabled {
            requestBody["top_a"] = sampling.topA
        }
        if sampling.repetitionPenaltyEnabled {
            requestBody["repetition_penalty"] = sampling.repetitionPenalty
        }
        if sampling.structuredOutputsEnabled {
            requestBody["structured_outputs"] = true
        }
        if sampling.verbosityEnabled {
            requestBody["verbosity"] = sampling.verbosity
        }
    }

    private func applyLMStudioRESTSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any]
    ) {
        if sampling.temperatureEnabled {
            requestBody["temperature"] = min(sampling.temperature, 1)
        }
        if sampling.topPEnabled {
            requestBody["top_p"] = sampling.topP
        }
        applyIntegerOverride(sampling.topKEnabled, sampling.topK, key: "top_k", to: &requestBody)
        if sampling.minPEnabled {
            requestBody["min_p"] = sampling.minP
        }
        if sampling.repetitionPenaltyEnabled {
            requestBody["repeat_penalty"] = sampling.repetitionPenalty
        }
        applyIntegerOverride(sampling.contextLengthEnabled, sampling.contextLength, key: "context_length", to: &requestBody)
    }

    private func applyLMStudioOpenAICompatibleSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any]
    ) {
        applyOpenAIChatSamplingConfiguration(sampling, to: &requestBody, includeLogprobs: false)
        applyIntegerOverride(sampling.topKEnabled, sampling.topK, key: "top_k", to: &requestBody)
        if sampling.repetitionPenaltyEnabled {
            requestBody["repeat_penalty"] = sampling.repetitionPenalty
        }
    }

    private func applyLlamaCppSamplingConfiguration(
        _ sampling: APIAdvancedSamplingSettings,
        to requestBody: inout [String: Any]
    ) {
        applyOpenAIChatSamplingConfiguration(sampling, to: &requestBody)
        applyIntegerOverride(sampling.topKEnabled, sampling.topK, key: "top_k", to: &requestBody)
        if sampling.minPEnabled {
            requestBody["min_p"] = sampling.minP
        }
        if sampling.repetitionPenaltyEnabled {
            requestBody["repeat_penalty"] = sampling.repetitionPenalty
        }
    }
}
