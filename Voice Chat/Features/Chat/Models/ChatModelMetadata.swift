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
    let loaded_instances: [LMStudioRESTLoadedInstance]?

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
            supports_image_input: capabilities?.supports_image_input ?? capabilities?.supports_vision ?? capabilities?.vision
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
            model_info: nil
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

