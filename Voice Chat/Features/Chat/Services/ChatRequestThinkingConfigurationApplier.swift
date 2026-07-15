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
        case .lmStudioRESTV1:
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
                removeAnthropicThinkingSamplingConflicts(from: &requestBody)
                return
            }

            let budget = anthropicThinkingBudget(for: option, settings: settings)
            requestBody["thinking"] = [
                "type": "enabled",
                "budget_tokens": budget
            ]
            let currentMaxTokens = (requestBody["max_tokens"] as? Int) ?? settings.anthropicMaxTokens
            requestBody["max_tokens"] = max(currentMaxTokens, budget + settings.anthropicThinkingResponseReserve)
            removeAnthropicThinkingSamplingConflicts(from: &requestBody)

        case .openAIResponses:
            requestBody["reasoning"] = [
                "effort": openAIReasoningEffort(for: option, capability: thinkingCapability)
            ]

        case .openAIChatCompletions:
            if ChatEndpointBaseURL.hostMatchesOfficialDomain(
                endpoint.chatURL.host ?? "",
                domain: "deepseek.com"
            ) {
                requestBody["thinking"] = ["type": option.isDisabled ? "disabled" : "enabled"]
                if option.isDisabled {
                    requestBody.removeValue(forKey: "reasoning_effort")
                } else {
                    requestBody["reasoning_effort"] = deepSeekReasoningEffort(for: option)
                }
                return
            }

            if let requestParameter {
                switch requestParameter {
                case .reasoningEffort:
                    requestBody["reasoning_effort"] = reasoningEffortValue(
                        for: option,
                        endpoint: endpoint,
                        capability: thinkingCapability
                    )
                case .reasoning:
                    requestBody["reasoning"] = [
                        "effort": reasoningEffortValue(
                            for: option,
                            endpoint: endpoint,
                            capability: thinkingCapability
                        )
                    ]
                case .thinking:
                    requestBody["thinking"] = ["type": option.isDisabled ? "disabled" : "enabled"]
                }
                return
            }

            switch endpoint.provider {
            case .openAI, .lmStudio, .unknown:
                requestBody["reasoning_effort"] = openAIReasoningEffort(
                    for: option,
                    capability: thinkingCapability
                )
            case .anthropic:
                break
            }
        }
    }

    private func reasoningEffortValue(
        for option: ModelThinkingOption,
        endpoint: ChatAPIEndpointCandidate,
        capability: ModelThinkingCapability?
    ) -> String {
        switch endpoint.provider {
        case .openAI, .lmStudio, .unknown, .anthropic:
            return openAIReasoningEffort(for: option, capability: capability)
        }
    }

    private func lmStudioReasoningValue(for option: ModelThinkingOption) -> String {
        if option == .none {
            return "off"
        }
        if option == .minimal {
            return "low"
        }
        if option == .xhigh || option == .max {
            return "high"
        }
        return option.rawValue
    }

    private func openAIReasoningEffort(
        for option: ModelThinkingOption,
        capability: ModelThinkingCapability?
    ) -> String {
        if option == .off {
            return "none"
        }
        if option == .on {
            return "medium"
        }
        if option == .max, capability?.options.contains(.max) != true {
            return "xhigh"
        }
        return option.rawValue
    }

    private func deepSeekReasoningEffort(for option: ModelThinkingOption) -> String {
        option == .max || option == .xhigh ? "max" : "high"
    }

    private func anthropicThinkingBudget(for option: ModelThinkingOption, settings: APIAdvancedSettings) -> Int {
        if option == .minimal || option == .low || option == .on {
            return settings.anthropicLowThinkingBudget
        }
        if option == .medium {
            return settings.anthropicMediumThinkingBudget
        }
        if option == .high || option == .xhigh || option == .max || option == .ultra {
            return settings.anthropicHighThinkingBudget
        }
        if option == .off || option == .none {
            return 0
        }
        return settings.anthropicMediumThinkingBudget
    }

    private func removeAnthropicThinkingSamplingConflicts(from requestBody: inout [String: Any]) {
        requestBody.removeValue(forKey: "temperature")
        requestBody.removeValue(forKey: "top_k")
        if let topP = requestBody["top_p"] as? Double,
           !(0.95...1).contains(topP) {
            requestBody.removeValue(forKey: "top_p")
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
        if option == .xhigh {
            let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.contains("claude-opus-4-7") ? "xhigh" : "max"
        }
        if option == .max {
            return "max"
        }
        if option == .minimal || option == .low || option == .on {
            return "low"
        }
        if option == .medium {
            return "medium"
        }
        if option == .high {
            return "high"
        }
        if option == .off || option == .none {
            return "low"
        }
        return option.rawValue
    }
}
