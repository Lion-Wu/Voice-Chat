//
//  ModelCapabilityResolver.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

enum ModelCapabilityResolver {
    static func providerHint(from requestStyle: ChatRequestStyle?) -> ChatProvider? {
        switch requestStyle {
        case .lmStudioRESTV1:
            return .lmStudio
        case .anthropicMessages:
            return .anthropic
        case .openAIResponses, .openAIChatCompletions, nil:
            return nil
        }
    }

    static func imageInputSupport(fromModelIdentifier identifier: String) -> Bool? {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        let knownVisionHints = [
            // OpenAI
            "gpt-5", "gpt-5.1", "gpt-5.2", "gpt-5.4", "gpt-5.5", "gpt-4o", "gpt-4.1", "gpt-4.5", "o1", "o3", "o4",
            // Anthropic
            "claude-3", "claude-4",
            // Google
            "gemini", "gemma-3", "gemma-3n",
            // xAI
            "grok-3", "grok-4",
            // Mistral
            "pixtral", "mistral-large-25", "mistral-medium-25", "mistral-small-25", "ministral-",
            // Cohere
            "aya-vision", "command-a-vision",
            // Alibaba / Qwen
            "qwen-vl", "qwen2-vl", "qwen2.5-vl", "qwen3-vl", "qwen3.5", "qvq", "qwen-omni", "qwen2.5-omni", "qwen3-omni",
            // Meta / open-source VLM families
            "llama-3.2-vision", "llama-4-scout", "llama-4-maverick",
            "llava", "internvl", "minicpm-v", "paligemma", "idefics", "moondream",
            "deepseek-vl", "glm-4v",
            // Generic signals
            "vision", "multimodal", "vlm"
        ]

        if knownVisionHints.contains(where: { normalized.contains($0) }) {
            return true
        }

        return nil
    }

    static func thinkingCapability(
        fromModelIdentifier identifier: String,
        provider: ChatProvider,
        requestStyle: ChatRequestStyle?
    ) -> ModelThinkingCapability? {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        switch provider {
        case .openAI, .unknown:
            if normalized.contains("gpt-5-pro") {
                return nil
            }
            if normalized.contains("gpt-5.6") {
                return ModelThinkingCapability(
                    options: [.none, .low, .medium, .high, .xhigh, .max],
                    defaultOption: .medium
                )
            }
            if normalized.contains("gpt-5.5") {
                return ModelThinkingCapability(options: [.low, .medium, .high, .xhigh], defaultOption: .medium)
            }
            if normalized.contains("gpt-5.4-pro") {
                return ModelThinkingCapability(options: [.medium, .high, .xhigh], defaultOption: .medium)
            }
            if normalized.contains("gpt-5.4") {
                return ModelThinkingCapability(options: [.none, .low, .medium, .high, .xhigh], defaultOption: ModelThinkingOption.none)
            }
            if normalized.contains("gpt-5.3-codex") ||
                normalized.contains("gpt-5.2-codex") ||
                normalized.contains("gpt-5.1-codex-max") {
                return ModelThinkingCapability(options: [.low, .medium, .high, .xhigh], defaultOption: .medium)
            }
            if normalized.contains("gpt-5.2-pro") {
                return ModelThinkingCapability(options: [.medium, .high, .xhigh], defaultOption: .medium)
            }
            if normalized.contains("gpt-5.2") {
                return ModelThinkingCapability(options: [.none, .low, .medium, .high, .xhigh], defaultOption: ModelThinkingOption.none)
            }
            if normalized.contains("gpt-5.1") {
                return ModelThinkingCapability(options: [.none, .low, .medium, .high], defaultOption: ModelThinkingOption.none)
            }
            if normalized.contains("gpt-5") {
                return ModelThinkingCapability(options: [.minimal, .low, .medium, .high], defaultOption: .medium)
            }
            if normalized.contains("o1") || normalized.contains("o3") || normalized.contains("o4") || normalized.contains("gpt-oss") {
                return ModelThinkingCapability(options: [.low, .medium, .high], defaultOption: .medium)
            }
            if normalized.contains("gemini-3") {
                if normalized.contains("pro") {
                    return ModelThinkingCapability(options: [.minimal, .low, .high], defaultOption: .high)
                }
                return ModelThinkingCapability(options: [.minimal, .low, .medium, .high], defaultOption: .high)
            }
            if normalized.contains("gemini-2.5") {
                if normalized.contains("pro") {
                    return ModelThinkingCapability(options: [.minimal, .low, .medium, .high], defaultOption: .high)
                }
                return ModelThinkingCapability(options: [.none, .minimal, .low, .medium, .high], defaultOption: ModelThinkingOption.none)
            }
            if normalized.contains("deepseek-v4") ||
                normalized.contains("deepseek-reasoner") ||
                normalized.contains("deepseek-chat") {
                return ModelThinkingCapability(options: [.off, .high, .max], defaultOption: .high, requestParameter: .reasoning)
            }
            if normalized.contains("multi-agent") {
                return ModelThinkingCapability(
                    options: [.low, .medium, .high, .xhigh],
                    defaultOption: .medium,
                    requestParameter: .reasoning
                )
            }
            return nil

        case .anthropic:
            if normalized.contains("claude-opus-4-7") {
                return ModelThinkingCapability(options: [.off, .low, .medium, .high, .xhigh, .max], defaultOption: .off)
            }
            if normalized.contains("claude-opus-4-6") ||
                normalized.contains("claude-sonnet-4-6") {
                return ModelThinkingCapability(options: [.off, .low, .medium, .high, .max], defaultOption: .off)
            }
            if normalized.contains("claude-mythos") {
                return ModelThinkingCapability(options: [.low, .medium, .high, .max], defaultOption: .high)
            }
            if normalized.contains("claude-opus-4") ||
                normalized.contains("claude-sonnet-4") ||
                normalized.contains("claude-3-7-sonnet") {
                return ModelThinkingCapability(options: [.off, .low, .medium, .high], defaultOption: .off)
            }
            return nil

        case .lmStudio:
            return nil
        }
    }
}
