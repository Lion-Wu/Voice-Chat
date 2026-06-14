//
//  ChatModelMetadata.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.22.
//

import Foundation

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
