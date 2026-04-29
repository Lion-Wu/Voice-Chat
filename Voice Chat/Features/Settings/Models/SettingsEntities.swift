//
//  SettingsModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import Foundation
import SwiftData

// MARK: - Value Types (lightweight structures used by the UI)

struct ServerSettings: Codable, Equatable {
    var serverAddress: String
    var textLang: String
}

struct ModelSettings: Codable, Equatable {
    var modelId: String
    var language: String
    var autoSplit: String
}

struct ChatSettings: Codable, Equatable {
    var apiURL: String
    var selectedModel: String
    var apiKey: String
}

struct VoiceSettings: Codable, Equatable {
    var enableStreaming: Bool
}

struct APIAdvancedSettings: Codable, Equatable, Sendable {
    static let defaults = APIAdvancedSettings()

    var openAIResponsesMaxOutputTokens: Int
    var openAIResponsesSampling: APIAdvancedSamplingSettings
    var openAIChatMaxCompletionTokens: Int
    var openAIChatSampling: APIAdvancedSamplingSettings
    var openAICompatibleMaxTokens: Int
    var openAICompatibleSampling: APIAdvancedSamplingSettings
    var geminiMaxTokens: Int
    var geminiSampling: APIAdvancedSamplingSettings
    var deepSeekMaxTokens: Int
    var deepSeekSampling: APIAdvancedSamplingSettings
    var xAIMaxTokens: Int
    var xAISampling: APIAdvancedSamplingSettings
    var openRouterMaxTokens: Int
    var openRouterMaxCompletionTokens: Int
    var openRouterSampling: APIAdvancedSamplingSettings
    var lmStudioMaxTokens: Int
    var lmStudioSampling: APIAdvancedSamplingSettings
    var lmStudioOpenAICompatibleMaxTokens: Int
    var lmStudioOpenAICompatibleSampling: APIAdvancedSamplingSettings
    var llamaCppMaxTokens: Int
    var llamaCppSampling: APIAdvancedSamplingSettings
    var anthropicMaxTokens: Int
    var anthropicSampling: APIAdvancedSamplingSettings
    var anthropicThinkingResponseReserve: Int
    var anthropicLowThinkingBudget: Int
    var anthropicMediumThinkingBudget: Int
    var anthropicHighThinkingBudget: Int

    init(
        openAIResponsesMaxOutputTokens: Int = 0,
        openAIResponsesSampling: APIAdvancedSamplingSettings = .defaults,
        openAIChatMaxCompletionTokens: Int = 0,
        openAIChatSampling: APIAdvancedSamplingSettings = .defaults,
        openAICompatibleMaxTokens: Int = 0,
        openAICompatibleSampling: APIAdvancedSamplingSettings = .defaults,
        geminiMaxTokens: Int = 0,
        geminiSampling: APIAdvancedSamplingSettings = .defaults,
        deepSeekMaxTokens: Int = 0,
        deepSeekSampling: APIAdvancedSamplingSettings = .defaults,
        xAIMaxTokens: Int = 0,
        xAISampling: APIAdvancedSamplingSettings = .defaults,
        openRouterMaxTokens: Int = 0,
        openRouterMaxCompletionTokens: Int = 0,
        openRouterSampling: APIAdvancedSamplingSettings = .defaults,
        lmStudioMaxTokens: Int = 0,
        lmStudioSampling: APIAdvancedSamplingSettings = .defaults,
        lmStudioOpenAICompatibleMaxTokens: Int = 0,
        lmStudioOpenAICompatibleSampling: APIAdvancedSamplingSettings = .defaults,
        llamaCppMaxTokens: Int = 0,
        llamaCppSampling: APIAdvancedSamplingSettings = .defaults,
        anthropicMaxTokens: Int = 4096,
        anthropicSampling: APIAdvancedSamplingSettings = .defaults,
        anthropicThinkingResponseReserve: Int = 1024,
        anthropicLowThinkingBudget: Int = 1024,
        anthropicMediumThinkingBudget: Int = 4096,
        anthropicHighThinkingBudget: Int = 10_000
    ) {
        self.openAIResponsesMaxOutputTokens = openAIResponsesMaxOutputTokens
        self.openAIResponsesSampling = openAIResponsesSampling
        self.openAIChatMaxCompletionTokens = openAIChatMaxCompletionTokens
        self.openAIChatSampling = openAIChatSampling
        self.openAICompatibleMaxTokens = openAICompatibleMaxTokens
        self.openAICompatibleSampling = openAICompatibleSampling
        self.geminiMaxTokens = geminiMaxTokens
        self.geminiSampling = geminiSampling
        self.deepSeekMaxTokens = deepSeekMaxTokens
        self.deepSeekSampling = deepSeekSampling
        self.xAIMaxTokens = xAIMaxTokens
        self.xAISampling = xAISampling
        self.openRouterMaxTokens = openRouterMaxTokens
        self.openRouterMaxCompletionTokens = openRouterMaxCompletionTokens
        self.openRouterSampling = openRouterSampling
        self.lmStudioMaxTokens = lmStudioMaxTokens
        self.lmStudioSampling = lmStudioSampling
        self.lmStudioOpenAICompatibleMaxTokens = lmStudioOpenAICompatibleMaxTokens
        self.lmStudioOpenAICompatibleSampling = lmStudioOpenAICompatibleSampling
        self.llamaCppMaxTokens = llamaCppMaxTokens
        self.llamaCppSampling = llamaCppSampling
        self.anthropicMaxTokens = anthropicMaxTokens
        self.anthropicSampling = anthropicSampling
        self.anthropicThinkingResponseReserve = anthropicThinkingResponseReserve
        self.anthropicLowThinkingBudget = anthropicLowThinkingBudget
        self.anthropicMediumThinkingBudget = anthropicMediumThinkingBudget
        self.anthropicHighThinkingBudget = anthropicHighThinkingBudget
    }

    var sanitized: APIAdvancedSettings {
        APIAdvancedSettings(
            openAIResponsesMaxOutputTokens: max(0, openAIResponsesMaxOutputTokens),
            openAIResponsesSampling: openAIResponsesSampling.sanitized,
            openAIChatMaxCompletionTokens: max(0, openAIChatMaxCompletionTokens),
            openAIChatSampling: openAIChatSampling.sanitized,
            openAICompatibleMaxTokens: max(0, openAICompatibleMaxTokens),
            openAICompatibleSampling: openAICompatibleSampling.sanitized,
            geminiMaxTokens: max(0, geminiMaxTokens),
            geminiSampling: geminiSampling.sanitized,
            deepSeekMaxTokens: max(0, deepSeekMaxTokens),
            deepSeekSampling: deepSeekSampling.sanitized,
            xAIMaxTokens: max(0, xAIMaxTokens),
            xAISampling: xAISampling.sanitized,
            openRouterMaxTokens: max(0, openRouterMaxTokens),
            openRouterMaxCompletionTokens: max(0, openRouterMaxCompletionTokens),
            openRouterSampling: openRouterSampling.sanitized,
            lmStudioMaxTokens: max(0, lmStudioMaxTokens),
            lmStudioSampling: lmStudioSampling.sanitized,
            lmStudioOpenAICompatibleMaxTokens: max(0, lmStudioOpenAICompatibleMaxTokens),
            lmStudioOpenAICompatibleSampling: lmStudioOpenAICompatibleSampling.sanitized,
            llamaCppMaxTokens: max(0, llamaCppMaxTokens),
            llamaCppSampling: llamaCppSampling.sanitized,
            anthropicMaxTokens: max(1, anthropicMaxTokens),
            anthropicSampling: anthropicSampling.sanitized,
            anthropicThinkingResponseReserve: max(1, anthropicThinkingResponseReserve),
            anthropicLowThinkingBudget: max(1024, anthropicLowThinkingBudget),
            anthropicMediumThinkingBudget: max(1024, anthropicMediumThinkingBudget),
            anthropicHighThinkingBudget: max(1024, anthropicHighThinkingBudget)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case openAIResponsesMaxOutputTokens
        case openAIResponsesSampling
        case openAIChatMaxCompletionTokens
        case openAIChatSampling
        case openAICompatibleMaxTokens
        case openAICompatibleSampling
        case geminiMaxTokens
        case geminiSampling
        case deepSeekMaxTokens
        case deepSeekSampling
        case xAIMaxTokens
        case xAISampling
        case openRouterMaxTokens
        case openRouterMaxCompletionTokens
        case openRouterSampling
        case lmStudioMaxTokens
        case lmStudioSampling
        case lmStudioOpenAICompatibleMaxTokens
        case lmStudioOpenAICompatibleSampling
        case llamaCppMaxTokens
        case llamaCppSampling
        case anthropicMaxTokens
        case anthropicSampling
        case anthropicThinkingResponseReserve
        case anthropicLowThinkingBudget
        case anthropicMediumThinkingBudget
        case anthropicHighThinkingBudget

        case temperatureEnabled
        case temperature
        case topPEnabled
        case topP
        case topK
        case presencePenaltyEnabled
        case presencePenalty
        case frequencyPenaltyEnabled
        case frequencyPenalty
        case seed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = APIAdvancedSettings.defaults
        let legacyTopK = try container.decodeIfPresent(Int.self, forKey: .topK) ?? 0
        let legacySeed = try container.decodeIfPresent(Int.self, forKey: .seed) ?? 0
        let legacySampling = APIAdvancedSamplingSettings(
            temperatureEnabled: try container.decodeIfPresent(Bool.self, forKey: .temperatureEnabled) ?? false,
            temperature: try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 1,
            topPEnabled: try container.decodeIfPresent(Bool.self, forKey: .topPEnabled) ?? false,
            topP: try container.decodeIfPresent(Double.self, forKey: .topP) ?? 1,
            topKEnabled: legacyTopK > 0,
            topK: legacyTopK,
            presencePenaltyEnabled: try container.decodeIfPresent(Bool.self, forKey: .presencePenaltyEnabled) ?? false,
            presencePenalty: try container.decodeIfPresent(Double.self, forKey: .presencePenalty) ?? 0,
            frequencyPenaltyEnabled: try container.decodeIfPresent(Bool.self, forKey: .frequencyPenaltyEnabled) ?? false,
            frequencyPenalty: try container.decodeIfPresent(Double.self, forKey: .frequencyPenalty) ?? 0,
            seedEnabled: legacySeed > 0,
            seed: legacySeed
        ).sanitized

        self.init(
            openAIResponsesMaxOutputTokens: try container.decodeIfPresent(Int.self, forKey: .openAIResponsesMaxOutputTokens) ?? defaults.openAIResponsesMaxOutputTokens,
            openAIResponsesSampling: try container.decodeIfPresent(APIAdvancedSamplingSettings.self, forKey: .openAIResponsesSampling) ?? legacySampling,
            openAIChatMaxCompletionTokens: try container.decodeIfPresent(Int.self, forKey: .openAIChatMaxCompletionTokens) ?? defaults.openAIChatMaxCompletionTokens,
            openAIChatSampling: try container.decodeIfPresent(APIAdvancedSamplingSettings.self, forKey: .openAIChatSampling) ?? legacySampling,
            openAICompatibleMaxTokens: try container.decodeIfPresent(Int.self, forKey: .openAICompatibleMaxTokens) ?? defaults.openAICompatibleMaxTokens,
            openAICompatibleSampling: try container.decodeIfPresent(APIAdvancedSamplingSettings.self, forKey: .openAICompatibleSampling) ?? legacySampling,
            geminiMaxTokens: try container.decodeIfPresent(Int.self, forKey: .geminiMaxTokens) ?? defaults.geminiMaxTokens,
            geminiSampling: try container.decodeIfPresent(APIAdvancedSamplingSettings.self, forKey: .geminiSampling) ?? legacySampling,
            deepSeekMaxTokens: try container.decodeIfPresent(Int.self, forKey: .deepSeekMaxTokens) ?? defaults.deepSeekMaxTokens,
            deepSeekSampling: try container.decodeIfPresent(APIAdvancedSamplingSettings.self, forKey: .deepSeekSampling) ?? legacySampling,
            xAIMaxTokens: try container.decodeIfPresent(Int.self, forKey: .xAIMaxTokens) ?? defaults.xAIMaxTokens,
            xAISampling: try container.decodeIfPresent(APIAdvancedSamplingSettings.self, forKey: .xAISampling) ?? legacySampling,
            openRouterMaxTokens: try container.decodeIfPresent(Int.self, forKey: .openRouterMaxTokens) ?? defaults.openRouterMaxTokens,
            openRouterMaxCompletionTokens: try container.decodeIfPresent(Int.self, forKey: .openRouterMaxCompletionTokens) ?? defaults.openRouterMaxCompletionTokens,
            openRouterSampling: try container.decodeIfPresent(APIAdvancedSamplingSettings.self, forKey: .openRouterSampling) ?? legacySampling,
            lmStudioMaxTokens: try container.decodeIfPresent(Int.self, forKey: .lmStudioMaxTokens) ?? defaults.lmStudioMaxTokens,
            lmStudioSampling: try container.decodeIfPresent(APIAdvancedSamplingSettings.self, forKey: .lmStudioSampling) ?? legacySampling,
            lmStudioOpenAICompatibleMaxTokens: try container.decodeIfPresent(Int.self, forKey: .lmStudioOpenAICompatibleMaxTokens) ?? defaults.lmStudioOpenAICompatibleMaxTokens,
            lmStudioOpenAICompatibleSampling: try container.decodeIfPresent(APIAdvancedSamplingSettings.self, forKey: .lmStudioOpenAICompatibleSampling) ?? legacySampling,
            llamaCppMaxTokens: try container.decodeIfPresent(Int.self, forKey: .llamaCppMaxTokens) ?? defaults.llamaCppMaxTokens,
            llamaCppSampling: try container.decodeIfPresent(APIAdvancedSamplingSettings.self, forKey: .llamaCppSampling) ?? legacySampling,
            anthropicMaxTokens: try container.decodeIfPresent(Int.self, forKey: .anthropicMaxTokens) ?? defaults.anthropicMaxTokens,
            anthropicSampling: try container.decodeIfPresent(APIAdvancedSamplingSettings.self, forKey: .anthropicSampling) ?? legacySampling,
            anthropicThinkingResponseReserve: try container.decodeIfPresent(Int.self, forKey: .anthropicThinkingResponseReserve) ?? defaults.anthropicThinkingResponseReserve,
            anthropicLowThinkingBudget: try container.decodeIfPresent(Int.self, forKey: .anthropicLowThinkingBudget) ?? defaults.anthropicLowThinkingBudget,
            anthropicMediumThinkingBudget: try container.decodeIfPresent(Int.self, forKey: .anthropicMediumThinkingBudget) ?? defaults.anthropicMediumThinkingBudget,
            anthropicHighThinkingBudget: try container.decodeIfPresent(Int.self, forKey: .anthropicHighThinkingBudget) ?? defaults.anthropicHighThinkingBudget
        )
    }

    func encode(to encoder: Encoder) throws {
        let sanitized = sanitized
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sanitized.openAIResponsesMaxOutputTokens, forKey: .openAIResponsesMaxOutputTokens)
        try container.encode(sanitized.openAIResponsesSampling, forKey: .openAIResponsesSampling)
        try container.encode(sanitized.openAIChatMaxCompletionTokens, forKey: .openAIChatMaxCompletionTokens)
        try container.encode(sanitized.openAIChatSampling, forKey: .openAIChatSampling)
        try container.encode(sanitized.openAICompatibleMaxTokens, forKey: .openAICompatibleMaxTokens)
        try container.encode(sanitized.openAICompatibleSampling, forKey: .openAICompatibleSampling)
        try container.encode(sanitized.geminiMaxTokens, forKey: .geminiMaxTokens)
        try container.encode(sanitized.geminiSampling, forKey: .geminiSampling)
        try container.encode(sanitized.deepSeekMaxTokens, forKey: .deepSeekMaxTokens)
        try container.encode(sanitized.deepSeekSampling, forKey: .deepSeekSampling)
        try container.encode(sanitized.xAIMaxTokens, forKey: .xAIMaxTokens)
        try container.encode(sanitized.xAISampling, forKey: .xAISampling)
        try container.encode(sanitized.openRouterMaxTokens, forKey: .openRouterMaxTokens)
        try container.encode(sanitized.openRouterMaxCompletionTokens, forKey: .openRouterMaxCompletionTokens)
        try container.encode(sanitized.openRouterSampling, forKey: .openRouterSampling)
        try container.encode(sanitized.lmStudioMaxTokens, forKey: .lmStudioMaxTokens)
        try container.encode(sanitized.lmStudioSampling, forKey: .lmStudioSampling)
        try container.encode(sanitized.lmStudioOpenAICompatibleMaxTokens, forKey: .lmStudioOpenAICompatibleMaxTokens)
        try container.encode(sanitized.lmStudioOpenAICompatibleSampling, forKey: .lmStudioOpenAICompatibleSampling)
        try container.encode(sanitized.llamaCppMaxTokens, forKey: .llamaCppMaxTokens)
        try container.encode(sanitized.llamaCppSampling, forKey: .llamaCppSampling)
        try container.encode(sanitized.anthropicMaxTokens, forKey: .anthropicMaxTokens)
        try container.encode(sanitized.anthropicSampling, forKey: .anthropicSampling)
        try container.encode(sanitized.anthropicThinkingResponseReserve, forKey: .anthropicThinkingResponseReserve)
        try container.encode(sanitized.anthropicLowThinkingBudget, forKey: .anthropicLowThinkingBudget)
        try container.encode(sanitized.anthropicMediumThinkingBudget, forKey: .anthropicMediumThinkingBudget)
        try container.encode(sanitized.anthropicHighThinkingBudget, forKey: .anthropicHighThinkingBudget)
    }
}

struct APIAdvancedSamplingSettings: Codable, Equatable, Sendable {
    static let defaults = APIAdvancedSamplingSettings()

    var temperatureEnabled: Bool
    var temperature: Double
    var topPEnabled: Bool
    var topP: Double
    var topKEnabled: Bool
    var topK: Int
    var minPEnabled: Bool
    var minP: Double
    var topAEnabled: Bool
    var topA: Double
    var presencePenaltyEnabled: Bool
    var presencePenalty: Double
    var frequencyPenaltyEnabled: Bool
    var frequencyPenalty: Double
    var repetitionPenaltyEnabled: Bool
    var repetitionPenalty: Double
    var seedEnabled: Bool
    var seed: Int
    var contextLengthEnabled: Bool
    var contextLength: Int
    var jsonModeEnabled: Bool
    var structuredOutputsEnabled: Bool
    var logprobsEnabled: Bool
    var topLogprobsEnabled: Bool
    var topLogprobs: Int
    var verbosityEnabled: Bool
    var verbosity: String

    init(
        temperatureEnabled: Bool = false,
        temperature: Double = 1,
        topPEnabled: Bool = false,
        topP: Double = 1,
        topKEnabled: Bool = false,
        topK: Int = 0,
        minPEnabled: Bool = false,
        minP: Double = 0,
        topAEnabled: Bool = false,
        topA: Double = 0,
        presencePenaltyEnabled: Bool = false,
        presencePenalty: Double = 0,
        frequencyPenaltyEnabled: Bool = false,
        frequencyPenalty: Double = 0,
        repetitionPenaltyEnabled: Bool = false,
        repetitionPenalty: Double = 1,
        seedEnabled: Bool = false,
        seed: Int = 0,
        contextLengthEnabled: Bool = false,
        contextLength: Int = 0,
        jsonModeEnabled: Bool = false,
        structuredOutputsEnabled: Bool = false,
        logprobsEnabled: Bool = false,
        topLogprobsEnabled: Bool = false,
        topLogprobs: Int = 0,
        verbosityEnabled: Bool = false,
        verbosity: String = "medium"
    ) {
        self.temperatureEnabled = temperatureEnabled
        self.temperature = temperature
        self.topPEnabled = topPEnabled
        self.topP = topP
        self.topKEnabled = topKEnabled
        self.topK = topK
        self.minPEnabled = minPEnabled
        self.minP = minP
        self.topAEnabled = topAEnabled
        self.topA = topA
        self.presencePenaltyEnabled = presencePenaltyEnabled
        self.presencePenalty = presencePenalty
        self.frequencyPenaltyEnabled = frequencyPenaltyEnabled
        self.frequencyPenalty = frequencyPenalty
        self.repetitionPenaltyEnabled = repetitionPenaltyEnabled
        self.repetitionPenalty = repetitionPenalty
        self.seedEnabled = seedEnabled
        self.seed = seed
        self.contextLengthEnabled = contextLengthEnabled
        self.contextLength = contextLength
        self.jsonModeEnabled = jsonModeEnabled
        self.structuredOutputsEnabled = structuredOutputsEnabled
        self.logprobsEnabled = logprobsEnabled
        self.topLogprobsEnabled = topLogprobsEnabled
        self.topLogprobs = topLogprobs
        self.verbosityEnabled = verbosityEnabled
        self.verbosity = verbosity
    }

    var sanitized: APIAdvancedSamplingSettings {
        APIAdvancedSamplingSettings(
            temperatureEnabled: temperatureEnabled,
            temperature: temperature.clamped(to: 0...2),
            topPEnabled: topPEnabled,
            topP: topP.clamped(to: 0...1),
            topKEnabled: topKEnabled,
            topK: max(0, topK),
            minPEnabled: minPEnabled,
            minP: minP.clamped(to: 0...1),
            topAEnabled: topAEnabled,
            topA: topA.clamped(to: 0...1),
            presencePenaltyEnabled: presencePenaltyEnabled,
            presencePenalty: presencePenalty.clamped(to: -2...2),
            frequencyPenaltyEnabled: frequencyPenaltyEnabled,
            frequencyPenalty: frequencyPenalty.clamped(to: -2...2),
            repetitionPenaltyEnabled: repetitionPenaltyEnabled,
            repetitionPenalty: repetitionPenalty.clamped(to: 0...2),
            seedEnabled: seedEnabled,
            seed: max(0, seed),
            contextLengthEnabled: contextLengthEnabled,
            contextLength: max(0, contextLength),
            jsonModeEnabled: jsonModeEnabled,
            structuredOutputsEnabled: structuredOutputsEnabled,
            logprobsEnabled: logprobsEnabled,
            topLogprobsEnabled: topLogprobsEnabled,
            topLogprobs: max(0, min(topLogprobs, 20)),
            verbosityEnabled: verbosityEnabled,
            verbosity: Self.sanitizedVerbosity(verbosity)
        )
    }

    private static func sanitizedVerbosity(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "low":
            return "low"
        case "high":
            return "high"
        case "max":
            return "max"
        default:
            return "medium"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case temperatureEnabled
        case temperature
        case topPEnabled
        case topP
        case topKEnabled
        case topK
        case minPEnabled
        case minP
        case topAEnabled
        case topA
        case presencePenaltyEnabled
        case presencePenalty
        case frequencyPenaltyEnabled
        case frequencyPenalty
        case repetitionPenaltyEnabled
        case repetitionPenalty
        case seedEnabled
        case seed
        case contextLengthEnabled
        case contextLength
        case jsonModeEnabled
        case structuredOutputsEnabled
        case logprobsEnabled
        case topLogprobsEnabled
        case topLogprobs
        case verbosityEnabled
        case verbosity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let temperatureEnabled = try container.decodeIfPresent(Bool.self, forKey: .temperatureEnabled) ?? false
        let temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 1
        let topPEnabled = try container.decodeIfPresent(Bool.self, forKey: .topPEnabled) ?? false
        let topP = try container.decodeIfPresent(Double.self, forKey: .topP) ?? 1
        let topK = try container.decodeIfPresent(Int.self, forKey: .topK) ?? 0
        let topKEnabled = try container.decodeIfPresent(Bool.self, forKey: .topKEnabled) ?? (topK > 0)
        let minPEnabled = try container.decodeIfPresent(Bool.self, forKey: .minPEnabled) ?? false
        let minP = try container.decodeIfPresent(Double.self, forKey: .minP) ?? 0
        let topAEnabled = try container.decodeIfPresent(Bool.self, forKey: .topAEnabled) ?? false
        let topA = try container.decodeIfPresent(Double.self, forKey: .topA) ?? 0
        let presencePenaltyEnabled = try container.decodeIfPresent(Bool.self, forKey: .presencePenaltyEnabled) ?? false
        let presencePenalty = try container.decodeIfPresent(Double.self, forKey: .presencePenalty) ?? 0
        let frequencyPenaltyEnabled = try container.decodeIfPresent(Bool.self, forKey: .frequencyPenaltyEnabled) ?? false
        let frequencyPenalty = try container.decodeIfPresent(Double.self, forKey: .frequencyPenalty) ?? 0
        let repetitionPenaltyEnabled = try container.decodeIfPresent(Bool.self, forKey: .repetitionPenaltyEnabled) ?? false
        let repetitionPenalty = try container.decodeIfPresent(Double.self, forKey: .repetitionPenalty) ?? 1
        let seed = try container.decodeIfPresent(Int.self, forKey: .seed) ?? 0
        let seedEnabled = try container.decodeIfPresent(Bool.self, forKey: .seedEnabled) ?? (seed > 0)
        let contextLength = try container.decodeIfPresent(Int.self, forKey: .contextLength) ?? 0
        let contextLengthEnabled = try container.decodeIfPresent(Bool.self, forKey: .contextLengthEnabled) ?? (contextLength > 0)
        let jsonModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .jsonModeEnabled) ?? false
        let structuredOutputsEnabled = try container.decodeIfPresent(Bool.self, forKey: .structuredOutputsEnabled) ?? false
        let logprobsEnabled = try container.decodeIfPresent(Bool.self, forKey: .logprobsEnabled) ?? false
        let topLogprobs = try container.decodeIfPresent(Int.self, forKey: .topLogprobs) ?? 0
        let topLogprobsEnabled = try container.decodeIfPresent(Bool.self, forKey: .topLogprobsEnabled) ?? (topLogprobs > 0)
        let verbosityEnabled = try container.decodeIfPresent(Bool.self, forKey: .verbosityEnabled) ?? false
        let verbosity = try container.decodeIfPresent(String.self, forKey: .verbosity) ?? "medium"

        self.init(
            temperatureEnabled: temperatureEnabled,
            temperature: temperature,
            topPEnabled: topPEnabled,
            topP: topP,
            topKEnabled: topKEnabled,
            topK: topK,
            minPEnabled: minPEnabled,
            minP: minP,
            topAEnabled: topAEnabled,
            topA: topA,
            presencePenaltyEnabled: presencePenaltyEnabled,
            presencePenalty: presencePenalty,
            frequencyPenaltyEnabled: frequencyPenaltyEnabled,
            frequencyPenalty: frequencyPenalty,
            repetitionPenaltyEnabled: repetitionPenaltyEnabled,
            repetitionPenalty: repetitionPenalty,
            seedEnabled: seedEnabled,
            seed: seed,
            contextLengthEnabled: contextLengthEnabled,
            contextLength: contextLength,
            jsonModeEnabled: jsonModeEnabled,
            structuredOutputsEnabled: structuredOutputsEnabled,
            logprobsEnabled: logprobsEnabled,
            topLogprobsEnabled: topLogprobsEnabled,
            topLogprobs: topLogprobs,
            verbosityEnabled: verbosityEnabled,
            verbosity: verbosity
        )
    }

    func encode(to encoder: Encoder) throws {
        let sanitized = sanitized
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sanitized.temperatureEnabled, forKey: .temperatureEnabled)
        try container.encode(sanitized.temperature, forKey: .temperature)
        try container.encode(sanitized.topPEnabled, forKey: .topPEnabled)
        try container.encode(sanitized.topP, forKey: .topP)
        try container.encode(sanitized.topKEnabled, forKey: .topKEnabled)
        try container.encode(sanitized.topK, forKey: .topK)
        try container.encode(sanitized.minPEnabled, forKey: .minPEnabled)
        try container.encode(sanitized.minP, forKey: .minP)
        try container.encode(sanitized.topAEnabled, forKey: .topAEnabled)
        try container.encode(sanitized.topA, forKey: .topA)
        try container.encode(sanitized.presencePenaltyEnabled, forKey: .presencePenaltyEnabled)
        try container.encode(sanitized.presencePenalty, forKey: .presencePenalty)
        try container.encode(sanitized.frequencyPenaltyEnabled, forKey: .frequencyPenaltyEnabled)
        try container.encode(sanitized.frequencyPenalty, forKey: .frequencyPenalty)
        try container.encode(sanitized.repetitionPenaltyEnabled, forKey: .repetitionPenaltyEnabled)
        try container.encode(sanitized.repetitionPenalty, forKey: .repetitionPenalty)
        try container.encode(sanitized.seedEnabled, forKey: .seedEnabled)
        try container.encode(sanitized.seed, forKey: .seed)
        try container.encode(sanitized.contextLengthEnabled, forKey: .contextLengthEnabled)
        try container.encode(sanitized.contextLength, forKey: .contextLength)
        try container.encode(sanitized.jsonModeEnabled, forKey: .jsonModeEnabled)
        try container.encode(sanitized.structuredOutputsEnabled, forKey: .structuredOutputsEnabled)
        try container.encode(sanitized.logprobsEnabled, forKey: .logprobsEnabled)
        try container.encode(sanitized.topLogprobsEnabled, forKey: .topLogprobsEnabled)
        try container.encode(sanitized.topLogprobs, forKey: .topLogprobs)
        try container.encode(sanitized.verbosityEnabled, forKey: .verbosityEnabled)
        try container.encode(sanitized.verbosity, forKey: .verbosity)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Preset Entity (SwiftData)

@Model
final class VoicePreset {
    var id: UUID
    var name: String

    // Consolidated fields originally scattered across `ServerSettings` plus weight paths.
    var refAudioPath: String
    var promptText: String
    var promptLang: String
    var gptWeightsPath: String
    var sovitsWeightsPath: String

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        refAudioPath: String = "",
        promptText: String = "",
        promptLang: String = "auto",
        gptWeightsPath: String = "",
        sovitsWeightsPath: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.refAudioPath = refAudioPath
        self.promptText = promptText
        self.promptLang = promptLang
        self.gptWeightsPath = gptWeightsPath
        self.sovitsWeightsPath = sovitsWeightsPath
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Chat Server Preset Entity (SwiftData)

@Model
final class ChatServerPreset {
    var id: UUID
    var name: String

    var apiURL: String
    var selectedModel: String
    var apiFormatPreferenceRaw: String?

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        apiURL: String = "",
        selectedModel: String = "",
        apiFormatPreferenceRaw: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.apiURL = apiURL
        self.selectedModel = selectedModel
        self.apiFormatPreferenceRaw = apiFormatPreferenceRaw
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Voice Server Preset Entity (SwiftData)

@Model
final class VoiceServerPreset {
    var id: UUID
    var name: String

    var serverAddress: String

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        serverAddress: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.serverAddress = serverAddress
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - System Prompt Preset Entity (SwiftData)

@Model
final class SystemPromptPreset {
    var id: UUID
    var name: String

    /// Which mode this preset belongs to ("normal" / "voice").
    /// Nil means the preset was created before mode separation was introduced.
    var mode: String?

    /// Prompt used for normal (text) chat requests.
    var normalPrompt: String
    /// Prompt used for voice (realtime) chat requests.
    var voicePrompt: String

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        mode: String? = nil,
        normalPrompt: String = "",
        voicePrompt: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.mode = mode
        self.normalPrompt = normalPrompt
        self.voicePrompt = voicePrompt
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - SwiftData Entity (single-row table storing global settings)

@Model
final class AppSettings {
    var id: UUID
    var serverAddress: String
    var textLang: String

    var modelId: String
    var language: String
    var autoSplit: String

    var apiURL: String
    var selectedModel: String
    var selectedChatServerPresetID: UUID?
    var selectedVoiceServerPresetID: UUID?

    var enableStreaming: Bool
    var developerModeEnabled: Bool?
    var hapticFeedbackEnabled: Bool?

    // Currently selected preset identifier (optional when nothing is selected).
    var selectedPresetID: UUID?

    // Separate selections for normal/voice chat modes.
    var selectedNormalSystemPromptPresetID: UUID?
    var selectedVoiceSystemPromptPresetID: UUID?
    var modelImageInputOverrideJSON: String?
    var apiAdvancedSettingsJSON: String?

    init(
        serverAddress: String = "http://localhost:9880",
        textLang: String = "auto",
        modelId: String = "",
        language: String = "auto",
        autoSplit: String = "cut0",
        apiURL: String = "http://localhost:1234",
        selectedModel: String = "",
        selectedChatServerPresetID: UUID? = nil,
        selectedVoiceServerPresetID: UUID? = nil,
        enableStreaming: Bool = true,
        developerModeEnabled: Bool = false,
        hapticFeedbackEnabled: Bool? = true,
        selectedPresetID: UUID? = nil,
        selectedNormalSystemPromptPresetID: UUID? = nil,
        selectedVoiceSystemPromptPresetID: UUID? = nil,
        modelImageInputOverrideJSON: String? = nil,
        apiAdvancedSettingsJSON: String? = nil
    ) {
        self.id = UUID()
        self.serverAddress = serverAddress
        self.textLang = textLang
        self.modelId = modelId
        self.language = language
        self.autoSplit = autoSplit
        self.apiURL = apiURL
        self.selectedModel = selectedModel
        self.selectedChatServerPresetID = selectedChatServerPresetID
        self.selectedVoiceServerPresetID = selectedVoiceServerPresetID
        self.enableStreaming = enableStreaming
        self.developerModeEnabled = developerModeEnabled
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.selectedPresetID = selectedPresetID
        self.selectedNormalSystemPromptPresetID = selectedNormalSystemPromptPresetID
        self.selectedVoiceSystemPromptPresetID = selectedVoiceSystemPromptPresetID
        self.modelImageInputOverrideJSON = modelImageInputOverrideJSON
        self.apiAdvancedSettingsJSON = apiAdvancedSettingsJSON
    }
}
