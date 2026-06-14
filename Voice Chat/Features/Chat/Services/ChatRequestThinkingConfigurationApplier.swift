//
//  ChatRequestThinkingConfigurationApplier.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

struct ChatRequestThinkingConfigurationApplier: Sendable {
    func apply(
        to requestBody: inout [String: Any],
        model: String,
        endpoint: ChatAPIEndpointCandidate,
        settings: APIAdvancedSettings,
        thinkingCapability: ModelThinkingCapability?,
        thinkingOption: ModelThinkingOption?
    ) {
        guard let option = thinkingOption else { return }
        if let capability = thinkingCapability,
           !capability.isConfigurable {
            return
        }
        let requestParameter = thinkingCapability?.requestParameter

        switch endpoint.style {
        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            requestBody["reasoning"] = lmStudioReasoningValue(for: option)

        case .anthropicMessages:
            guard !option.isDisabled else { return }
            if isAnthropicAdaptiveThinkingModel(model) {
                requestBody["thinking"] = [
                    "type": "adaptive",
                    "display": "summarized"
                ]
                requestBody["output_config"] = [
                    "effort": anthropicAdaptiveEffort(for: option, model: model)
                ]
                return
            }

            let budget = anthropicThinkingBudget(for: option, settings: settings)
            requestBody["thinking"] = [
                "type": "enabled",
                "budget_tokens": budget
            ]
            let currentMaxTokens = (requestBody["max_tokens"] as? Int) ?? settings.anthropicMaxTokens
            requestBody["max_tokens"] = max(currentMaxTokens, budget + settings.anthropicThinkingResponseReserve)

        case .openAIChatCompletions:
            if endpoint.provider == .deepSeek {
                applyDeepSeekThinkingConfiguration(to: &requestBody, option: option)
                return
            }

            if ChatRequestBodyEndpointClassifier.isOpenAIResponsesEndpoint(endpoint.chatURL) {
                requestBody["reasoning"] = ["effort": openAIReasoningEffort(for: option)]
                return
            }

            if let requestParameter {
                switch requestParameter {
                case .reasoningEffort:
                    requestBody["reasoning_effort"] = reasoningEffortValue(for: option, endpoint: endpoint)
                case .reasoning:
                    requestBody["reasoning"] = ["effort": reasoningEffortValue(for: option, endpoint: endpoint)]
                case .thinking:
                    requestBody["thinking"] = ["type": option.isDisabled ? "disabled" : "enabled"]
                }
                return
            }

            switch endpoint.provider {
            case .deepSeek:
                if !option.isDisabled {
                    requestBody["thinking"] = ["type": "enabled"]
                }
            case .gemini:
                requestBody["reasoning_effort"] = geminiReasoningEffort(for: option)
            case .openRouter:
                requestBody["reasoning"] = ["effort": openRouterReasoningEffort(for: option)]
            case .openAI, .lmStudio, .openAICompatible, .llamaCpp, .unknown:
                requestBody["reasoning_effort"] = openAIReasoningEffort(for: option)
            case .xAI, .anthropic:
                break
            }
        }
    }

    private func reasoningEffortValue(for option: ModelThinkingOption, endpoint: ChatAPIEndpointCandidate) -> String {
        switch endpoint.provider {
        case .gemini:
            return geminiReasoningEffort(for: option)
        case .openRouter:
            return openRouterReasoningEffort(for: option)
        case .openAI, .lmStudio, .openAICompatible, .llamaCpp, .unknown, .deepSeek, .anthropic, .xAI:
            return openAIReasoningEffort(for: option)
        }
    }

    private func lmStudioReasoningValue(for option: ModelThinkingOption) -> String {
        switch option {
        case .none:
            return "off"
        case .minimal:
            return "low"
        case .xhigh, .max:
            return "high"
        default:
            return option.rawValue
        }
    }

    private func openAIReasoningEffort(for option: ModelThinkingOption) -> String {
        switch option {
        case .off:
            return "none"
        case .on:
            return "medium"
        case .max:
            return "xhigh"
        default:
            return option.rawValue
        }
    }

    private func geminiReasoningEffort(for option: ModelThinkingOption) -> String {
        switch option {
        case .off:
            return "none"
        case .on:
            return "medium"
        case .xhigh, .max:
            return "high"
        default:
            return option.rawValue
        }
    }

    private func openRouterReasoningEffort(for option: ModelThinkingOption) -> String {
        switch option {
        case .off:
            return "none"
        case .on:
            return "medium"
        case .max:
            return "xhigh"
        default:
            return option.rawValue
        }
    }

    private func applyDeepSeekThinkingConfiguration(to requestBody: inout [String: Any], option: ModelThinkingOption) {
        requestBody["thinking"] = ["type": option.isDisabled ? "disabled" : "enabled"]
        guard !option.isDisabled else { return }
        requestBody["reasoning_effort"] = deepSeekReasoningEffort(for: option)
    }

    private func deepSeekReasoningEffort(for option: ModelThinkingOption) -> String {
        switch option {
        case .xhigh, .max:
            return "max"
        case .off, .none:
            return "high"
        case .minimal, .low, .medium, .high, .on:
            return "high"
        }
    }

    private func anthropicThinkingBudget(for option: ModelThinkingOption, settings: APIAdvancedSettings) -> Int {
        switch option {
        case .minimal, .low, .on:
            return settings.anthropicLowThinkingBudget
        case .medium:
            return settings.anthropicMediumThinkingBudget
        case .high, .xhigh, .max:
            return settings.anthropicHighThinkingBudget
        case .off, .none:
            return 0
        }
    }

    private func isAnthropicAdaptiveThinkingModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("claude-opus-4-7") ||
            normalized.contains("claude-opus-4-6") ||
            normalized.contains("claude-sonnet-4-6") ||
            normalized.contains("claude-mythos")
    }

    private func anthropicAdaptiveEffort(for option: ModelThinkingOption, model: String) -> String {
        switch option {
        case .xhigh:
            let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.contains("claude-opus-4-7") ? "xhigh" : "max"
        case .max:
            return "max"
        case .minimal, .low, .on:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .off, .none:
            return "low"
        }
    }
}
