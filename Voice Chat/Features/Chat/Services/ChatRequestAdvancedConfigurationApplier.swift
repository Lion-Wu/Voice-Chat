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
        case .openAIResponses:
            applyPositiveInteger(settings.openAIResponsesMaxOutputTokens, key: "max_output_tokens", to: &requestBody)
            applyOpenAIResponsesSamplingConfiguration(settings.openAIResponsesSampling, to: &requestBody)

        case .openAIChatCompletions:
            switch endpoint.provider {
            case .openAI, .lmStudio, .unknown:
                applyPositiveInteger(
                    settings.openAIChatMaxCompletionTokens,
                    key: openAIChatTokenLimitKey(for: endpoint),
                    to: &requestBody
                )
                applyOpenAIChatSamplingConfiguration(settings.openAIChatSampling, to: &requestBody)
            case .anthropic:
                break
            }

        case .lmStudioRESTV1:
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

    private func openAIChatTokenLimitKey(for endpoint: ChatAPIEndpointCandidate) -> String {
        let host = (endpoint.chatURL.host ?? "").lowercased()
        if ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: "openai.com") ||
            ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: "openrouter.ai") ||
            ChatEndpointBaseURL.hostMatchesOfficialDomain(host, domain: "openai.azure.com") {
            return "max_completion_tokens"
        }
        return "max_tokens"
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

}
