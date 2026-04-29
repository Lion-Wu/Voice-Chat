//
//  ChatModelMetadata.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.22.
//

import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

extension JSONValue {
    var prettyPrintedJSONString: String {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let output = String(data: prettyData, encoding: .utf8) else {
            return String(describing: self)
        }
        return output
    }

    func debugPreviewJSONString(
        maxCharacters: Int = 12_000,
        maxDepth: Int = 8,
        maxCollectionItems: Int = 80
    ) -> String {
        var renderer = JSONValuePreviewRenderer(
            maxCharacters: maxCharacters,
            maxDepth: maxDepth,
            maxCollectionItems: maxCollectionItems
        )
        renderer.append(self, depth: 0, indent: 0)
        if renderer.truncated, !renderer.output.hasSuffix("\n...") {
            renderer.appendTruncationMarker()
        }
        return renderer.output
    }
}

private struct JSONValuePreviewRenderer {
    private(set) var output = ""
    private let maxCharacters: Int
    private let maxDepth: Int
    private let maxCollectionItems: Int
    private(set) var truncated = false

    init(maxCharacters: Int, maxDepth: Int, maxCollectionItems: Int) {
        self.maxCharacters = max(256, maxCharacters)
        self.maxDepth = max(1, maxDepth)
        self.maxCollectionItems = max(1, maxCollectionItems)
    }

    mutating func append(_ value: JSONValue, depth: Int, indent: Int) {
        guard !truncated else { return }
        guard depth <= maxDepth else {
            append("\"...\"")
            truncated = true
            return
        }

        switch value {
        case let .string(value):
            append(quoted(value))
        case let .number(value):
            append(String(value))
        case let .bool(value):
            append(value ? "true" : "false")
        case .null:
            append("null")
        case let .array(values):
            appendArray(values, depth: depth, indent: indent)
        case let .object(values):
            appendObject(values, depth: depth, indent: indent)
        }
    }

    mutating func appendTruncationMarker() {
        output += "\n..."
    }

    private mutating func appendArray(_ values: [JSONValue], depth: Int, indent: Int) {
        guard !values.isEmpty else {
            append("[]")
            return
        }

        append("[\n")
        let visibleValues = values.prefix(maxCollectionItems)
        for (index, value) in visibleValues.enumerated() {
            appendIndent(indent + 1)
            append(value, depth: depth + 1, indent: indent + 1)
            if index < visibleValues.count - 1 || values.count > maxCollectionItems {
                append(",")
            }
            append("\n")
        }
        if values.count > maxCollectionItems {
            appendIndent(indent + 1)
            append("\"...\"")
            append("\n")
            truncated = true
        }
        appendIndent(indent)
        append("]")
    }

    private mutating func appendObject(_ values: [String: JSONValue], depth: Int, indent: Int) {
        guard !values.isEmpty else {
            append("{}")
            return
        }

        append("{\n")
        let entries = values.sorted { $0.key < $1.key }
        let visibleEntries = entries.prefix(maxCollectionItems)
        for (index, entry) in visibleEntries.enumerated() {
            appendIndent(indent + 1)
            append(quoted(entry.key))
            append(": ")
            append(entry.value, depth: depth + 1, indent: indent + 1)
            if index < visibleEntries.count - 1 || entries.count > maxCollectionItems {
                append(",")
            }
            append("\n")
        }
        if entries.count > maxCollectionItems {
            appendIndent(indent + 1)
            append(quoted("..."))
            append(": ")
            append(quoted("..."))
            append("\n")
            truncated = true
        }
        appendIndent(indent)
        append("}")
    }

    private mutating func appendIndent(_ level: Int) {
        append(String(repeating: "  ", count: level))
    }

    private mutating func append(_ text: String) {
        guard !truncated else { return }
        let remaining = maxCharacters - output.count
        guard remaining > 0 else {
            truncated = true
            return
        }

        if text.count <= remaining {
            output += text
        } else {
            output += String(text.prefix(remaining))
            truncated = true
        }
    }

    private func quoted(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                result += "\\\""
            case "\\":
                result += "\\\\"
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        result += "\""
        return result
    }
}

struct ModelListResponse: Decodable {
    let object: String?
    let data: [ModelInfo]

    private enum CodingKeys: String, CodingKey {
        case object
        case data
        case models
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decodeIfPresent(String.self, forKey: .object)

        if let standardData = try? container.decode([ModelInfo].self, forKey: .data) {
            data = standardData
            return
        }

        if let lmStudioModels = try? container.decode([LMStudioRESTModelRecord].self, forKey: .models) {
            data = lmStudioModels.compactMap { $0.asModelInfo() }
            return
        }

        data = []
    }
}

private struct LMStudioRESTModelRecord: Decodable {
    let type: String?
    let key: String?
    let id: String?
    let architecture: String?
    let input_modalities: [String]?
    let modalities: [String]?
    let capabilities: LMStudioRESTModelCapabilities?
    let reasoning: ModelThinkingCapabilityDescriptor?
    let loaded_instances: [LMStudioRESTLoadedInstance]?
    let rawMetadata: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case type
        case key
        case id
        case architecture
        case input_modalities
        case modalities
        case capabilities
        case reasoning
        case loaded_instances
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        architecture = try container.decodeIfPresent(String.self, forKey: .architecture)
        input_modalities = try container.decodeIfPresent([String].self, forKey: .input_modalities)
        modalities = try container.decodeIfPresent([String].self, forKey: .modalities)
        capabilities = try container.decodeIfPresent(LMStudioRESTModelCapabilities.self, forKey: .capabilities)
        reasoning = try container.decodeIfPresent(ModelThinkingCapabilityDescriptor.self, forKey: .reasoning)
        loaded_instances = try container.decodeIfPresent([LMStudioRESTLoadedInstance].self, forKey: .loaded_instances)
        rawMetadata = try? JSONValue(from: decoder)
    }

    func asModelInfo() -> ModelInfo? {
        let candidates: [String?] = [
            loaded_instances?.first?.identifier,
            loaded_instances?.first?.id,
            key,
            id
        ]
        guard let modelID = candidates
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else {
            return nil
        }

        let capabilityModalities = capabilities?.input_modalities ?? capabilities?.modalities
        let mergedInputModalities = input_modalities ?? capabilityModalities
        let mergedModalities = modalities ?? capabilityModalities

        let visionFlag = capabilities?.supports_image_input ?? capabilities?.supports_vision ?? capabilities?.vision
        let multimodalFlag = capabilities?.multimodal
        let capabilityFlags = ModelCapabilityFlags(
            type: type,
            architecture: architecture,
            input_modalities: mergedInputModalities,
            modalities: mergedModalities,
            vision: capabilities?.vision,
            multimodal: capabilities?.multimodal,
            supports_vision: capabilities?.supports_vision ?? capabilities?.vision,
            supports_image_input: capabilities?.supports_image_input ?? capabilities?.supports_vision ?? capabilities?.vision,
            reasoning: capabilities?.reasoning ?? reasoning,
            supported_parameters: nil
        )

        return ModelInfo(
            id: modelID,
            object: "model",
            created: nil,
            owned_by: nil,
            type: type,
            arch: architecture,
            input_modalities: mergedInputModalities,
            modalities: mergedModalities,
            vision: visionFlag,
            multimodal: multimodalFlag,
            supports_vision: capabilities?.supports_vision ?? capabilities?.vision,
            supports_image_input: capabilities?.supports_image_input ?? capabilities?.supports_vision ?? capabilities?.vision,
            capabilities: capabilityFlags,
            details: nil,
            model_info: nil,
            reasoning: capabilities?.reasoning ?? reasoning,
            supported_parameters: nil,
            rawMetadata: rawMetadata
        )
    }
}

private struct LMStudioRESTModelCapabilities: Decodable {
    let vision: Bool?
    let multimodal: Bool?
    let supports_vision: Bool?
    let supports_image_input: Bool?
    let input_modalities: [String]?
    let modalities: [String]?
    let reasoning: ModelThinkingCapabilityDescriptor?
}

private struct LMStudioRESTLoadedInstance: Decodable {
    let id: String?
    let identifier: String?
}

struct ModelInfo: Codable {
    let id: String
    let object: String?
    let created: Int?
    let owned_by: String?
    let type: String?
    let arch: String?
    let input_modalities: [String]?
    let modalities: [String]?
    let vision: Bool?
    let multimodal: Bool?
    let supports_vision: Bool?
    let supports_image_input: Bool?
    let capabilities: ModelCapabilityFlags?
    let details: ModelCapabilityFlags?
    let model_info: ModelCapabilityFlags?
    let reasoning: ModelThinkingCapabilityDescriptor?
    let supported_parameters: [String]?
    let rawMetadata: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case owned_by
        case type
        case arch
        case input_modalities
        case modalities
        case vision
        case multimodal
        case supports_vision
        case supports_image_input
        case capabilities
        case details
        case model_info
        case reasoning
        case supported_parameters
        case rawMetadata
    }

    init(
        id: String,
        object: String?,
        created: Int?,
        owned_by: String?,
        type: String?,
        arch: String?,
        input_modalities: [String]?,
        modalities: [String]?,
        vision: Bool?,
        multimodal: Bool?,
        supports_vision: Bool?,
        supports_image_input: Bool?,
        capabilities: ModelCapabilityFlags?,
        details: ModelCapabilityFlags?,
        model_info: ModelCapabilityFlags?,
        reasoning: ModelThinkingCapabilityDescriptor?,
        supported_parameters: [String]?,
        rawMetadata: JSONValue? = nil
    ) {
        self.id = id
        self.object = object
        self.created = created
        self.owned_by = owned_by
        self.type = type
        self.arch = arch
        self.input_modalities = input_modalities
        self.modalities = modalities
        self.vision = vision
        self.multimodal = multimodal
        self.supports_vision = supports_vision
        self.supports_image_input = supports_image_input
        self.capabilities = capabilities
        self.details = details
        self.model_info = model_info
        self.reasoning = reasoning
        self.supported_parameters = supported_parameters
        self.rawMetadata = rawMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        created = try container.decodeIfPresent(Int.self, forKey: .created)
        owned_by = try container.decodeIfPresent(String.self, forKey: .owned_by)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        arch = try container.decodeIfPresent(String.self, forKey: .arch)
        input_modalities = try container.decodeIfPresent([String].self, forKey: .input_modalities)
        modalities = try container.decodeIfPresent([String].self, forKey: .modalities)
        vision = try container.decodeIfPresent(Bool.self, forKey: .vision)
        multimodal = try container.decodeIfPresent(Bool.self, forKey: .multimodal)
        supports_vision = try container.decodeIfPresent(Bool.self, forKey: .supports_vision)
        supports_image_input = try container.decodeIfPresent(Bool.self, forKey: .supports_image_input)
        capabilities = try container.decodeIfPresent(ModelCapabilityFlags.self, forKey: .capabilities)
        details = try container.decodeIfPresent(ModelCapabilityFlags.self, forKey: .details)
        model_info = try container.decodeIfPresent(ModelCapabilityFlags.self, forKey: .model_info)
        reasoning = try container.decodeIfPresent(ModelThinkingCapabilityDescriptor.self, forKey: .reasoning)
        supported_parameters = try container.decodeIfPresent([String].self, forKey: .supported_parameters)
        rawMetadata = try? JSONValue(from: decoder)
    }

    var supportsImageInputHint: Bool? {
        if let explicit = supports_image_input ?? supports_vision ?? vision {
            return explicit
        }
        if let explicit = multimodal {
            return explicit
        }

        let modalityCandidates: [[String]?] = [
            input_modalities,
            modalities,
            capabilities?.input_modalities,
            capabilities?.modalities,
            details?.input_modalities,
            details?.modalities,
            model_info?.input_modalities,
            model_info?.modalities
        ]
        let resolvedModalities = modalityCandidates.compactMap { $0 }.first
        let tokens = normalizedTokens(resolvedModalities)
        if !tokens.isEmpty {
            return tokens.contains("image") || tokens.contains("vision")
        }

        let typeCandidates: [String?] = [
            type,
            arch,
            capabilities?.type,
            details?.type,
            model_info?.type,
            capabilities?.architecture,
            details?.architecture,
            model_info?.architecture
        ]
        let typeTokens = normalizedTokens(typeCandidates.compactMap { $0 })
        if typeTokens.contains("vlm") || typeTokens.contains("vision") || typeTokens.contains("multimodal") {
            return true
        }

        return nil
    }

    var thinkingCapabilityHint: ModelThinkingCapability? {
        thinkingCapabilityHint(provider: nil, requestStyle: nil)
    }

    func thinkingCapabilityHint(
        provider: ChatProvider?,
        requestStyle: ChatRequestStyle?
    ) -> ModelThinkingCapability? {
        let explicitCandidates: [ModelThinkingCapabilityDescriptor?] = [
            reasoning,
            capabilities?.reasoning,
            details?.reasoning,
            model_info?.reasoning
        ]
        let parameterCandidates: [[String]?] = [
            supported_parameters,
            capabilities?.supported_parameters,
            details?.supported_parameters,
            model_info?.supported_parameters
        ]
        let requestParameter = Self.requestParameterHint(from: parameterCandidates)
        for candidate in explicitCandidates {
            if let capability = candidate?.asThinkingCapability(requestParameter: requestParameter) {
                return capability
            }
        }

        let normalizedParameters = Set(
            parameterCandidates
                .compactMap { $0 }
                .flatMap { $0 }
                .map {
                    $0
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                        .replacingOccurrences(of: "-", with: "_")
                }
                .filter { !$0.isEmpty }
        )
        if normalizedParameters.contains("reasoning_effort") ||
            normalizedParameters.contains("reasoning.effort") {
            return ModelThinkingCapability(
                options: [.low, .medium, .high],
                defaultOption: .medium,
                requestParameter: .reasoningEffort
            )
        }
        if normalizedParameters.contains("thinking") ||
            normalizedParameters.contains("reasoning") {
            if Self.shouldTreatGenericThinkingParameterAsCompatibleEffort(provider: provider, requestStyle: requestStyle) {
                return ModelThinkingCapability(
                    options: [.off, .minimal, .low, .medium, .high, .xhigh],
                    defaultOption: .off,
                    requestParameter: requestParameter
                )
            }
            return ModelThinkingCapability(
                options: [.off, .on],
                defaultOption: .off,
                requestParameter: requestParameter
            )
        }

        return nil
    }

    private static func requestParameterHint(from parameterCandidates: [[String]?]) -> ModelThinkingRequestParameter? {
        let normalizedParameters = Set(
            parameterCandidates
                .compactMap { $0 }
                .flatMap { $0 }
                .map {
                    $0
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                        .replacingOccurrences(of: "-", with: "_")
                }
                .filter { !$0.isEmpty }
        )
        if normalizedParameters.contains("reasoning_effort") ||
            normalizedParameters.contains("reasoning.effort") {
            return .reasoningEffort
        }
        if normalizedParameters.contains("reasoning") {
            return .reasoning
        }
        if normalizedParameters.contains("thinking") {
            return .thinking
        }
        return nil
    }

    private static func shouldTreatGenericThinkingParameterAsCompatibleEffort(
        provider: ChatProvider?,
        requestStyle: ChatRequestStyle?
    ) -> Bool {
        requestStyle == .openAIChatCompletions && provider == .openRouter
    }

    private func normalizedTokens(_ values: [String]?) -> Set<String> {
        guard let values else { return [] }
        var out: Set<String> = []
        out.reserveCapacity(values.count * 2)
        for value in values {
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalized.isEmpty else { continue }
            out.insert(normalized)

            let pieces = normalized
                .replacingOccurrences(of: "-", with: "_")
                .split(separator: "_")
                .map(String.init)
            for piece in pieces where !piece.isEmpty {
                out.insert(piece)
            }
        }
        return out
    }
}

struct ModelCapabilityFlags: Codable {
    let type: String?
    let architecture: String?
    let input_modalities: [String]?
    let modalities: [String]?
    let vision: Bool?
    let multimodal: Bool?
    let supports_vision: Bool?
    let supports_image_input: Bool?
    let reasoning: ModelThinkingCapabilityDescriptor?
    let supported_parameters: [String]?
}

enum ModelThinkingOption: String, Codable, CaseIterable, Sendable, Identifiable {
    case off
    case on
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max

    var id: String { rawValue }

    var isDisabled: Bool {
        self == .off || self == .none
    }

    var isEffortLevel: Bool {
        switch self {
        case .minimal, .low, .medium, .high, .xhigh, .max:
            return true
        case .off, .on, .none:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .off, .none:
            return NSLocalizedString("Off", comment: "Thinking control option")
        case .on:
            return NSLocalizedString("On", comment: "Thinking control option")
        case .minimal:
            return NSLocalizedString("Minimal", comment: "Thinking effort option")
        case .low:
            return NSLocalizedString("Low", comment: "Thinking effort option")
        case .medium:
            return NSLocalizedString("Medium", comment: "Thinking effort option")
        case .high:
            return NSLocalizedString("High", comment: "Thinking effort option")
        case .xhigh:
            return NSLocalizedString("Extra High", comment: "Thinking effort option")
        case .max:
            return NSLocalizedString("Max", comment: "Thinking effort option")
        }
    }

    static func normalized(_ raw: String) -> ModelThinkingOption? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "off", "disabled", "disable", "false":
            return .off
        case "none", "no_reasoning":
            return ModelThinkingOption.none
        case "on", "enabled", "enable", "true", "auto", "dynamic":
            return .on
        case "minimal", "minimum":
            return .minimal
        case "low":
            return .low
        case "medium", "normal", "default":
            return .medium
        case "high":
            return .high
        case "xhigh", "extra_high", "extrahigh":
            return .xhigh
        case "max", "maximum":
            return .max
        default:
            return nil
        }
    }
}

enum ModelThinkingRequestParameter: String, Codable, CaseIterable, Sendable {
    case reasoningEffort = "reasoning_effort"
    case reasoning
    case thinking
}

struct ModelThinkingCapability: Codable, Equatable, Sendable {
    var options: [ModelThinkingOption]
    var defaultOption: ModelThinkingOption?
    var requestParameter: ModelThinkingRequestParameter?

    static let compatibleReasoningEffort = ModelThinkingCapability(
        options: [.off, .minimal, .low, .medium, .high, .xhigh],
        defaultOption: .off,
        requestParameter: nil
    )

    init(
        options: [ModelThinkingOption],
        defaultOption: ModelThinkingOption? = nil,
        requestParameter: ModelThinkingRequestParameter? = nil
    ) {
        var unique: [ModelThinkingOption] = []
        for option in options where !unique.contains(option) {
            unique.append(option)
        }
        self.options = unique
        if let defaultOption, unique.contains(defaultOption) {
            self.defaultOption = defaultOption
        } else {
            self.defaultOption = nil
        }
        self.requestParameter = requestParameter
    }

    var enabledOptions: [ModelThinkingOption] {
        options.filter { !$0.isDisabled }
    }

    var disabledOption: ModelThinkingOption? {
        options.first(where: \.isDisabled)
    }

    var supportsToggle: Bool {
        disabledOption != nil && !enabledOptions.isEmpty
    }

    var supportsEffortSelection: Bool {
        options.filter(\.isEffortLevel).count > 1
    }

    var isConfigurable: Bool {
        supportsToggle || supportsEffortSelection
    }

    var defaultSelection: ModelThinkingOption? {
        if let defaultOption, options.contains(defaultOption) {
            return defaultOption
        }
        if supportsEffortSelection {
            return options.contains(.medium) ? .medium : enabledOptions.first
        }
        if supportsToggle {
            return disabledOption ?? enabledOptions.first
        }
        return nil
    }

    func normalizedSelection(_ option: ModelThinkingOption?) -> ModelThinkingOption? {
        guard let option, options.contains(option) else {
            return defaultSelection
        }
        return option
    }

    func toggledSelection(from option: ModelThinkingOption?) -> ModelThinkingOption? {
        let current = normalizedSelection(option)
        if current?.isDisabled == true {
            if let defaultOption, !defaultOption.isDisabled, options.contains(defaultOption) {
                return defaultOption
            }
            return enabledOptions.first
        }
        return disabledOption
    }

    func withRequestParameter(_ requestParameter: ModelThinkingRequestParameter?) -> ModelThinkingCapability {
        ModelThinkingCapability(
            options: options,
            defaultOption: defaultOption,
            requestParameter: requestParameter
        )
    }
}

struct ModelThinkingCapabilityDescriptor: Codable, Equatable, Sendable {
    let allowed_options: [String]?
    let allowedOptions: [String]?
    let options: [String]?
    let values: [String]?
    let defaultValue: String?
    let default_option: String?

    private enum CodingKeys: String, CodingKey {
        case allowed_options
        case allowedOptions
        case options
        case values
        case defaultValue = "default"
        case default_option
    }

    init(
        allowed_options: [String]? = nil,
        allowedOptions: [String]? = nil,
        options: [String]? = nil,
        values: [String]? = nil,
        defaultValue: String? = nil,
        default_option: String? = nil
    ) {
        self.allowed_options = allowed_options
        self.allowedOptions = allowedOptions
        self.options = options
        self.values = values
        self.defaultValue = defaultValue
        self.default_option = default_option
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            allowed_options = try container.decodeIfPresent([String].self, forKey: .allowed_options)
            allowedOptions = try container.decodeIfPresent([String].self, forKey: .allowedOptions)
            options = try container.decodeIfPresent([String].self, forKey: .options)
            values = try container.decodeIfPresent([String].self, forKey: .values)
            defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
            default_option = try container.decodeIfPresent(String.self, forKey: .default_option)
            return
        }

        let singleValue = try decoder.singleValueContainer()
        if let rawOptions = try? singleValue.decode([String].self) {
            allowed_options = rawOptions
            allowedOptions = nil
            options = nil
            values = nil
            defaultValue = nil
            default_option = nil
            return
        }
        if let rawOption = try? singleValue.decode(String.self) {
            allowed_options = [rawOption]
            allowedOptions = nil
            options = nil
            values = nil
            defaultValue = rawOption
            default_option = nil
            return
        }
        if let supported = try? singleValue.decode(Bool.self) {
            allowed_options = supported ? ["off", "on"] : ["off"]
            allowedOptions = nil
            options = nil
            values = nil
            defaultValue = supported ? "on" : "off"
            default_option = nil
            return
        }

        allowed_options = nil
        allowedOptions = nil
        options = nil
        values = nil
        defaultValue = nil
        default_option = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(allowed_options, forKey: .allowed_options)
        try container.encodeIfPresent(allowedOptions, forKey: .allowedOptions)
        try container.encodeIfPresent(options, forKey: .options)
        try container.encodeIfPresent(values, forKey: .values)
        try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        try container.encodeIfPresent(default_option, forKey: .default_option)
    }

    func asThinkingCapability() -> ModelThinkingCapability? {
        asThinkingCapability(requestParameter: nil)
    }

    func asThinkingCapability(requestParameter: ModelThinkingRequestParameter?) -> ModelThinkingCapability? {
        let rawOptions = allowed_options ?? allowedOptions ?? options ?? values ?? []
        let parsedOptions = rawOptions.compactMap(ModelThinkingOption.normalized)
        let parsedDefault = [defaultValue, default_option]
            .compactMap { $0 }
            .compactMap(ModelThinkingOption.normalized)
            .first
        guard !parsedOptions.isEmpty else { return nil }
        return ModelThinkingCapability(
            options: parsedOptions,
            defaultOption: parsedDefault,
            requestParameter: requestParameter
        )
    }
}

struct ChatImageAttachment: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var mimeType: String
    var data: Data

    init(id: UUID = UUID(), mimeType: String, data: Data) {
        self.id = id
        self.mimeType = mimeType
        self.data = data
    }

    var dataURLString: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    static func encodeList(_ attachments: [ChatImageAttachment]) -> Data? {
        guard !attachments.isEmpty else { return nil }
        return try? JSONEncoder().encode(attachments)
    }

    static func decodeList(from data: Data?) -> [ChatImageAttachment] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ChatImageAttachment].self, from: data)) ?? []
    }
}

struct QueuedChatDraft: Identifiable, Equatable, Sendable {
    var id: UUID
    var text: String
    var imageAttachments: [ChatImageAttachment]
    var editingBaseMessageID: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        imageAttachments: [ChatImageAttachment] = [],
        editingBaseMessageID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.imageAttachments = imageAttachments
        self.editingBaseMessageID = editingBaseMessageID
        self.createdAt = createdAt
    }
}

extension QueuedChatDraft {
    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        trimmedText.isEmpty && imageAttachments.isEmpty
    }

    var previewText: String {
        let collapsed = trimmedText.replacingOccurrences(of: "\n", with: " ")
        if !collapsed.isEmpty {
            return collapsed
        }
        return String(localized: "Image-only message")
    }
}
