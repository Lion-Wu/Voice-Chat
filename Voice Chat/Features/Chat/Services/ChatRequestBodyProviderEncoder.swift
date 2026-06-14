//
//  ChatRequestBodyProviderEncoder.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatRequestBodyEncodingContext {
    let model: String
    let messagePayload: [[String: Any]]
    let developerPrompt: String?
    let endpoint: ChatAPIEndpointCandidate
    let apiAdvancedSettings: APIAdvancedSettings
}

protocol ChatRequestBodyProviderEncoding {
    func makeBaseRequestBody(_ context: ChatRequestBodyEncodingContext) -> [String: Any]
}

enum ChatRequestBodyProviderEncoder {
    static func makeBaseRequestBody(
        model: String,
        messagePayload: [[String: Any]],
        developerPrompt: String?,
        endpoint: ChatAPIEndpointCandidate,
        apiAdvancedSettings: APIAdvancedSettings
    ) -> [String: Any] {
        let context = ChatRequestBodyEncodingContext(
            model: model,
            messagePayload: messagePayload,
            developerPrompt: developerPrompt,
            endpoint: endpoint,
            apiAdvancedSettings: apiAdvancedSettings.sanitized
        )
        return encoder(for: endpoint).makeBaseRequestBody(context)
    }

    private static func encoder(for endpoint: ChatAPIEndpointCandidate) -> ChatRequestBodyProviderEncoding {
        switch endpoint.style {
        case .openAIChatCompletions:
            return OpenAICompatibleRequestBodyEncoder()
        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            return LMStudioRESTRequestBodyEncoder()
        case .anthropicMessages:
            return AnthropicMessagesRequestBodyEncoder()
        }
    }
}

enum ChatRequestBodyEndpointClassifier {
    static func isOpenAIResponsesEndpoint(_ url: URL) -> Bool {
        let canonicalPath = url.path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return canonicalPath.hasSuffix("responses")
    }
}

private struct OpenAICompatibleRequestBodyEncoder: ChatRequestBodyProviderEncoding {
    func makeBaseRequestBody(_ context: ChatRequestBodyEncodingContext) -> [String: Any] {
        if ChatRequestBodyEndpointClassifier.isOpenAIResponsesEndpoint(context.endpoint.chatURL) {
            return [
                "model": context.model,
                "stream": true,
                "input": ChatProviderMessagePayloadEncoder.openAIResponsesInput(from: context.messagePayload)
            ]
        }

        return [
            "model": context.model,
            "stream": true,
            "messages": context.messagePayload
        ]
    }
}

private struct LMStudioRESTRequestBodyEncoder: ChatRequestBodyProviderEncoding {
    func makeBaseRequestBody(_ context: ChatRequestBodyEncodingContext) -> [String: Any] {
        let lmStudioInput = ChatProviderMessagePayloadEncoder.lmStudioRESTInput(
            from: context.messagePayload,
            textDiscriminator: context.endpoint.style == .lmStudioRESTV1LegacyMessage ? "message" : "text"
        )
        var requestBody: [String: Any] = [
            "model": context.model,
            "stream": true,
            "input": lmStudioInput
        ]
        if let prompt = context.developerPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            requestBody["system_prompt"] = prompt
        }
        return requestBody
    }
}

private struct AnthropicMessagesRequestBodyEncoder: ChatRequestBodyProviderEncoding {
    func makeBaseRequestBody(_ context: ChatRequestBodyEncodingContext) -> [String: Any] {
        var requestBody: [String: Any] = [
            "model": context.model,
            "stream": true,
            "max_tokens": context.apiAdvancedSettings.anthropicMaxTokens,
            "messages": ChatProviderMessagePayloadEncoder.anthropicMessagesInput(from: context.messagePayload)
        ]
        if let prompt = context.developerPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            requestBody["system"] = prompt
        }
        return requestBody
    }
}

enum ChatProviderMessagePayloadEncoder {
    static func openAIResponsesInput(from messagePayload: [[String: Any]]) -> [[String: Any]] {
        var input: [[String: Any]] = []
        input.reserveCapacity(messagePayload.count)

        for item in messagePayload {
            let rawRole = ((item["role"] as? String) ?? "user").lowercased()
            let role: String
            switch rawRole {
            case "assistant", "system", "developer":
                role = rawRole
            default:
                role = "user"
            }

            var parts: [[String: Any]] = []
            if let text = item["content"] as? String {
                parts.append([
                    "type": "input_text",
                    "text": text
                ])
            } else if let content = item["content"] as? [[String: Any]] {
                for part in content {
                    let partType = ((part["type"] as? String) ?? "").lowercased()
                    if partType == "text", let text = part["text"] as? String {
                        parts.append([
                            "type": "input_text",
                            "text": text
                        ])
                    } else if let dataURL = imageDataURL(from: part) {
                        parts.append([
                            "type": "input_image",
                            "image_url": dataURL
                        ])
                    }
                }
            }

            if parts.isEmpty { continue }
            input.append([
                "role": role,
                "content": parts
            ])
        }

        if input.isEmpty {
            input.append([
                "role": "user",
                "content": [
                    ["type": "input_text", "text": ""]
                ]
            ])
        }
        return input
    }

    static func lmStudioRESTInput(
        from messagePayload: [[String: Any]],
        textDiscriminator: String
    ) -> Any {
        var transcriptLines: [String] = []
        transcriptLines.reserveCapacity(messagePayload.count)

        var lastUserPayloadIndex: Int?
        for (index, item) in messagePayload.enumerated() {
            if (item["role"] as? String)?.lowercased() == "user" {
                lastUserPayloadIndex = index
            }
        }

        var latestUserImages: [[String: Any]] = []
        for (index, item) in messagePayload.enumerated() {
            let role = ((item["role"] as? String) ?? "user").lowercased()
            if role == "developer" || role == "system" {
                continue
            }

            var collectedText = ""
            var collectedImages: [[String: Any]] = []

            if let text = item["content"] as? String {
                collectedText = text
            } else if let parts = item["content"] as? [[String: Any]] {
                for part in parts {
                    let partType = ((part["type"] as? String) ?? "").lowercased()
                    if partType == "text" {
                        if let text = part["text"] as? String {
                            collectedText += text
                        }
                    } else if let dataURL = imageDataURL(from: part) {
                        collectedImages.append([
                            "type": "image",
                            "data_url": dataURL
                        ])
                    }
                }
            }

            let trimmedText = collectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                let speaker = role == "assistant" ? "Assistant" : "User"
                transcriptLines.append("\(speaker): \(trimmedText)")
            }

            if role == "user", index == lastUserPayloadIndex, !collectedImages.isEmpty {
                latestUserImages = collectedImages
            }
        }

        let transcript = transcriptLines.joined(separator: "\n\n")
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        // LM Studio `/api/v1/chat` accepts plain strings, which avoids discriminator mismatches
        // when a text-only request is sent to different server versions.
        if latestUserImages.isEmpty {
            return trimmedTranscript.isEmpty ? "" : transcript
        }

        var input: [[String: Any]] = []
        if !trimmedTranscript.isEmpty {
            input.append([
                "type": textDiscriminator,
                "content": transcript
            ])
        }
        input.append(contentsOf: latestUserImages)
        return input
    }

    static func anthropicMessagesInput(from messagePayload: [[String: Any]]) -> [[String: Any]] {
        var output: [[String: Any]] = []
        output.reserveCapacity(messagePayload.count)

        for item in messagePayload {
            let rawRole = ((item["role"] as? String) ?? "").lowercased()
            guard rawRole == "user" || rawRole == "assistant" else { continue }

            var contentParts: [[String: Any]] = []
            if let text = item["content"] as? String {
                if !text.isEmpty {
                    contentParts.append(["type": "text", "text": text])
                }
            } else if let parts = item["content"] as? [[String: Any]] {
                for part in parts {
                    let partType = ((part["type"] as? String) ?? "").lowercased()
                    if partType == "text" {
                        if let text = part["text"] as? String, !text.isEmpty {
                            contentParts.append(["type": "text", "text": text])
                        }
                        continue
                    }

                    guard let dataURL = imageDataURL(from: part),
                          let parsed = parseDataURL(dataURL) else {
                        continue
                    }
                    contentParts.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": parsed.mimeType,
                            "data": parsed.base64Data
                        ]
                    ])
                }
            }

            if contentParts.isEmpty {
                continue
            }
            output.append([
                "role": rawRole,
                "content": contentParts
            ])
        }

        if output.isEmpty {
            output.append([
                "role": "user",
                "content": [
                    ["type": "text", "text": ""]
                ]
            ])
        }
        return output
    }

    static func imageDataURL(from part: [String: Any]) -> String? {
        if let dataURL = part["data_url"] as? String,
           !dataURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return dataURL
        }

        let partType = ((part["type"] as? String) ?? "").lowercased()
        guard partType == "image_url" else { return nil }

        guard let imageURL = part["image_url"] as? [String: Any],
              let urlString = imageURL["url"] as? String else {
            return nil
        }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseDataURL(_ raw: String) -> (mimeType: String, base64Data: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("data:"),
              let separator = trimmed.firstIndex(of: ",") else {
            return nil
        }
        let header = String(trimmed[..<separator])
        let payload = String(trimmed[trimmed.index(after: separator)...])
        guard !payload.isEmpty else { return nil }

        let mediaAndEncoding = String(header.dropFirst("data:".count))
        let parts = mediaAndEncoding.split(separator: ";")
        guard let media = parts.first, !media.isEmpty else { return nil }
        let isBase64 = parts.dropFirst().contains { $0.caseInsensitiveCompare("base64") == .orderedSame }
        guard isBase64 else { return nil }
        return (mimeType: String(media), base64Data: payload)
    }
}
