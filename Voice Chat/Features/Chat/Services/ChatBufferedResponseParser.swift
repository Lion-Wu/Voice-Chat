//
//  ChatBufferedResponseParser.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

struct ChatBufferedResponseParseResult {
    let text: String?
    let errorMessage: String?
    let metadata: ChatResponseMetadata
}

protocol ChatBufferedResponseParsing {
    func parse(_ data: Data, style: ChatRequestStyle) -> ChatBufferedResponseParseResult
}

struct ChatBufferedResponseParser: ChatBufferedResponseParsing {
    private let metadataExtractor: ChatResponseMetadataExtracting
    private let textExtractor: ChatResponseTextExtracting

    init(
        metadataExtractor: ChatResponseMetadataExtracting = ChatResponseMetadataExtractor(),
        textExtractor: ChatResponseTextExtracting = ChatResponseTextExtractor()
    ) {
        self.metadataExtractor = metadataExtractor
        self.textExtractor = textExtractor
    }

    func parse(_ data: Data, style: ChatRequestStyle) -> ChatBufferedResponseParseResult {
        guard !data.isEmpty else { return .empty }
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty else {
            return .empty
        }
        guard let first = raw.first, first == "{" || first == "[" else {
            // Likely SSE frames (`event:` / `data:`), not a plain JSON response body.
            return .empty
        }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any] else {
            return .empty
        }
        let metadata = metadataExtractor.extractResponseMetadata(from: dictionary, style: style)

        if let errorObject = dictionary["error"] as? [String: Any],
           let message = errorObject["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return ChatBufferedResponseParseResult(text: nil, errorMessage: trimmed, metadata: metadata)
            }
        }
        if let directMessage = dictionary["message"] as? String {
            let trimmed = directMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, dictionary["output"] == nil, dictionary["choices"] == nil {
                return ChatBufferedResponseParseResult(text: nil, errorMessage: trimmed, metadata: metadata)
            }
        }

        let recoveredText: String?
        switch style {
        case .lmStudioRESTV1:
            recoveredText = textExtractor.extractLMStudioAssistantText(from: dictionary)
        case .openAIResponses, .openAIChatCompletions:
            recoveredText = textExtractor.extractOpenAIAssistantText(from: dictionary)
        case .anthropicMessages:
            recoveredText = textExtractor.extractAnthropicAssistantText(from: dictionary)
        }

        if let text = recoveredText {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return ChatBufferedResponseParseResult(text: trimmed, errorMessage: nil, metadata: metadata)
            }
        }

        return ChatBufferedResponseParseResult(text: nil, errorMessage: nil, metadata: metadata)
    }
}

private extension ChatBufferedResponseParseResult {
    static var empty: ChatBufferedResponseParseResult {
        ChatBufferedResponseParseResult(text: nil, errorMessage: nil, metadata: .empty)
    }
}
