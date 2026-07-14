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
    let previousResponseID: String?
}

protocol ChatRequestBodyProviderEncoding {
    func makeBaseRequestBody(_ context: ChatRequestBodyEncodingContext) -> [String: Any]
}

enum ChatRequestBodyProviderEncoder {
    static func supportsPreviousResponseContinuation(_ endpoint: ChatAPIEndpointCandidate) -> Bool {
        switch endpoint.style {
        case .lmStudioRESTV1:
            return true
        case .openAIResponses:
            return ToolUseSettings.supportsProviderContinuationIDPreference(for: endpoint)
        case .openAIChatCompletions:
            return false
        case .anthropicMessages:
            return false
        }
    }

    static func isPreviousResponseContinuation(
        previousResponseID: String?,
        endpoint: ChatAPIEndpointCandidate
    ) -> Bool {
        normalizedPreviousResponseID(previousResponseID, endpoint: endpoint) != nil
    }

    static func normalizedPreviousResponseID(
        _ responseID: String?,
        endpoint: ChatAPIEndpointCandidate
    ) -> String? {
        guard supportsPreviousResponseContinuation(endpoint) else { return nil }
        let trimmed = responseID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func previousResponseCarriesInstructions(_ endpoint: ChatAPIEndpointCandidate) -> Bool {
        switch endpoint.style {
        case .lmStudioRESTV1:
            return true
        case .openAIResponses:
            return false
        case .openAIChatCompletions:
            return true
        case .anthropicMessages:
            return true
        }
    }

    static func makeBaseRequestBody(
        model: String,
        messagePayload: [[String: Any]],
        developerPrompt: String?,
        endpoint: ChatAPIEndpointCandidate,
        apiAdvancedSettings: APIAdvancedSettings,
        previousResponseID: String? = nil
    ) -> [String: Any] {
        let context = ChatRequestBodyEncodingContext(
            model: model,
            messagePayload: messagePayload,
            developerPrompt: developerPrompt,
            endpoint: endpoint,
            apiAdvancedSettings: apiAdvancedSettings.sanitized,
            previousResponseID: previousResponseID
        )
        return encoder(for: endpoint).makeBaseRequestBody(context)
    }

    private static func encoder(for endpoint: ChatAPIEndpointCandidate) -> ChatRequestBodyProviderEncoding {
        switch endpoint.style {
        case .openAIResponses, .openAIChatCompletions:
            return OpenAICompatibleRequestBodyEncoder()
        case .lmStudioRESTV1:
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
        if context.endpoint.style == .openAIResponses {
            let host = (context.endpoint.chatURL.host ?? "").lowercased()
            let requiresStructuredAssistantHistory = ChatEndpointBaseURL.hostMatchesOfficialDomain(
                host,
                domain: "openrouter.ai"
            )
            let input = ChatRequestBodyProviderEncoder.isPreviousResponseContinuation(
                previousResponseID: context.previousResponseID,
                endpoint: context.endpoint
            )
            ? ChatProviderMessagePayloadEncoder.openAIResponsesLatestUserInput(from: context.messagePayload)
            : ChatProviderMessagePayloadEncoder.openAIResponsesInput(
                from: context.messagePayload,
                includeInstructionMessages: false,
                requiresStructuredAssistantHistory: requiresStructuredAssistantHistory
            )
            var requestBody: [String: Any] = [
                "model": context.model,
                "stream": true,
                "input": input
            ]
            if let instructions = ChatProviderMessagePayloadEncoder.openAIInstructions(
                from: context.messagePayload,
                developerPrompt: context.developerPrompt
            ) {
                requestBody["instructions"] = instructions
            }
            return requestBody
        }

        return [
            "model": context.model,
            "stream": true,
            "messages": ChatProviderMessagePayloadEncoder.openAIChatCompletionsMessages(
                from: context.messagePayload,
                developerPrompt: context.developerPrompt
            )
        ]
    }
}

private struct LMStudioRESTRequestBodyEncoder: ChatRequestBodyProviderEncoding {
    func makeBaseRequestBody(_ context: ChatRequestBodyEncodingContext) -> [String: Any] {
        let previousResponseID = context.previousResponseID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPreviousResponseContinuation = ChatRequestBodyProviderEncoder.isPreviousResponseContinuation(
            previousResponseID: previousResponseID,
            endpoint: context.endpoint
        )
        let lmStudioInput: Any
        if isPreviousResponseContinuation {
            lmStudioInput = ChatProviderMessagePayloadEncoder.lmStudioRESTLatestUserInput(
                from: context.messagePayload
            )
        } else {
            lmStudioInput = ChatProviderMessagePayloadEncoder.lmStudioRESTInput(
                from: context.messagePayload
            )
        }
        var requestBody: [String: Any] = [
            "model": context.model,
            "stream": true,
            "input": lmStudioInput,
            "store": true
        ]
        if isPreviousResponseContinuation, let previousResponseID {
            requestBody["previous_response_id"] = previousResponseID
        }
        if !isPreviousResponseContinuation,
           let prompt = context.developerPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
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
    static func openAIInstructions(
        from messagePayload: [[String: Any]],
        developerPrompt: String?
    ) -> String? {
        var prompts: [String] = []
        appendPrompt(developerPrompt, to: &prompts)
        for item in messagePayload {
            let role = ((item["role"] as? String) ?? "").lowercased()
            guard role == "developer" || role == "system" else { continue }
            appendPrompt(textContent(from: item), to: &prompts)
        }
        return prompts.isEmpty ? nil : prompts.joined(separator: "\n\n")
    }

    static func openAIChatCompletionsMessages(
        from messagePayload: [[String: Any]],
        developerPrompt: String?
    ) -> [[String: Any]] {
        var output: [[String: Any]] = []
        var systemPrompts: [String] = []
        appendPrompt(developerPrompt, to: &systemPrompts)

        for item in messagePayload {
            let rawRole = ((item["role"] as? String) ?? "user").lowercased()
            if rawRole == "developer" || rawRole == "system" {
                appendPrompt(textContent(from: item), to: &systemPrompts)
                continue
            }
            var normalized = item
            normalized["role"] = rawRole.isEmpty ? "user" : rawRole
            normalized.removeValue(forKey: "id")
            normalized.removeValue(forKey: "status")
            normalized.removeValue(forKey: "type")
            output.append(normalized)
        }

        if !systemPrompts.isEmpty {
            output.insert([
                "role": "system",
                "content": systemPrompts.joined(separator: "\n\n")
            ], at: 0)
        }
        return output
    }

    static func openAIResponsesInput(
        from messagePayload: [[String: Any]],
        includeInstructionMessages: Bool = true,
        requiresStructuredAssistantHistory: Bool = false
    ) -> [[String: Any]] {
        var input: [[String: Any]] = []
        input.reserveCapacity(messagePayload.count)

        for item in messagePayload {
            let passthroughType = (item["type"] as? String)?.lowercased()
            if isOpenAIResponsesPassthroughItemType(passthroughType) {
                input.append(item)
                continue
            }

            let rawRole = ((item["role"] as? String) ?? "user").lowercased()
            if !includeInstructionMessages,
               rawRole == "developer" || rawRole == "system" {
                continue
            }
            if requiresStructuredAssistantHistory, rawRole == "assistant" {
                guard let text = textContent(from: item), !text.isEmpty else { continue }
                let existingID = (item["id"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let itemID: String
                if let existingID, !existingID.isEmpty {
                    itemID = existingID
                } else {
                    itemID = "msg_voice_chat_\(input.count)"
                }
                input.append([
                    "type": "message",
                    "role": "assistant",
                    "id": itemID,
                    "status": "completed",
                    "content": [[
                        "type": "output_text",
                        "text": text,
                        "annotations": []
                    ]]
                ])
                continue
            }
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

    static func openAIResponsesLatestUserInput(from messagePayload: [[String: Any]]) -> [[String: Any]] {
        guard let latestUser = messagePayload.last(where: { (($0["role"] as? String) ?? "").lowercased() == "user" }) else {
            return openAIResponsesInput(from: messagePayload)
        }
        return openAIResponsesInput(from: [latestUser])
    }

    private static func isOpenAIResponsesPassthroughItemType(_ type: String?) -> Bool {
        guard let type else { return false }
        return [
            "function_call",
            "function_call_output",
            "reasoning",
            "message"
        ].contains(type)
    }

    static func lmStudioRESTInput(from messagePayload: [[String: Any]]) -> Any {
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
                "type": "text",
                "content": transcript
            ])
        }
        input.append(contentsOf: latestUserImages)
        return input
    }

    static func lmStudioRESTLatestUserInput(from messagePayload: [[String: Any]]) -> Any {
        guard let latestUserMessage = messagePayload.last(where: {
            (($0["role"] as? String) ?? "").lowercased() == "user"
        }) else {
            return ""
        }

        let extracted = textAndImages(from: latestUserMessage)
        let trimmedText = extracted.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if extracted.images.isEmpty {
            return trimmedText
        }

        var input: [[String: Any]] = []
        if !trimmedText.isEmpty {
            input.append([
                "type": "text",
                "content": trimmedText
            ])
        }
        input.append(contentsOf: extracted.images)
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
                    if ["thinking", "redacted_thinking", "tool_use", "tool_result"].contains(partType) {
                        contentParts.append(part)
                        continue
                    }
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

    private static func textAndImages(from item: [String: Any]) -> (text: String, images: [[String: Any]]) {
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

        return (collectedText, collectedImages)
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

    private static func appendPrompt(_ prompt: String?, to prompts: inout [String]) {
        let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, !prompts.contains(trimmed) else { return }
        prompts.append(trimmed)
    }

    private static func textContent(from item: [String: Any]) -> String? {
        if let text = item["content"] as? String {
            return text
        }
        if let parts = item["content"] as? [[String: Any]] {
            let text = parts.compactMap { part -> String? in
                let type = ((part["type"] as? String) ?? "").lowercased()
                if type == "text" || type == "input_text" || type == "output_text" {
                    return (part["text"] as? String) ?? (part["content"] as? String)
                }
                return nil
            }.joined()
            return text.isEmpty ? nil : text
        }
        return nil
    }
}
