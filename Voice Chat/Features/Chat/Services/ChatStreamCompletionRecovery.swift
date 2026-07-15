//
//  ChatStreamCompletionRecovery.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import Foundation

enum ChatStreamCompletionRecovery {
    enum Outcome {
        case ignore
        case continueWithPendingTools
        case finish
        case recoveredText(String)
        case serverError(statusCode: Int?, message: String)
        case networkError(Error)
        case emptyResponse
    }

    struct Decision {
        var metadata: ChatResponseMetadata?
        var outcome: Outcome
    }

    static func decide(
        isCancelled: Bool,
        httpStatusCode: Int?,
        error: Error?,
        errorResponseData: Data,
        successResponseData: Data,
        sawAnyPrimaryAssistantToken: Bool,
        hasPendingToolCalls: Bool,
        activeStyle: ChatRequestStyle,
        pendingLMStudioStreamErrorMessage: String?,
        bufferedResponseParser: ChatBufferedResponseParsing,
        streamPayloadExtractor: ChatStreamPayloadExtracting
    ) -> Decision {
        if isCancelled {
            return Decision(metadata: nil, outcome: .ignore)
        }

        if let status = httpStatusCode, !(200...299).contains(status) {
            return Decision(
                metadata: nil,
                outcome: .serverError(
                    statusCode: status,
                    message: httpErrorMessage(status: status, bodyData: errorResponseData)
                )
            )
        }

        if let nsError = error as NSError?,
           nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            return Decision(metadata: nil, outcome: .ignore)
        }

        if let error {
            return Decision(metadata: nil, outcome: .networkError(error))
        }

        if hasPendingToolCalls {
            return Decision(metadata: nil, outcome: .continueWithPendingTools)
        }

        if sawAnyPrimaryAssistantToken {
            return Decision(metadata: nil, outcome: .finish)
        }

        let parsedBufferedResponse = bufferedResponseParser.parse(successResponseData, style: activeStyle)
        let metadata = parsedBufferedResponse.metadata.hasAnyValue ? parsedBufferedResponse.metadata : nil

        if let recoveredText = nonEmpty(parsedBufferedResponse.text) {
            return Decision(metadata: metadata, outcome: .recoveredText(recoveredText))
        }

        if let recoveredError = nonEmpty(parsedBufferedResponse.errorMessage) {
            return Decision(
                metadata: metadata,
                outcome: .serverError(statusCode: httpStatusCode, message: recoveredError)
            )
        }

        if let recoveredSSEError = nonEmpty(
            streamPayloadExtractor.sseStreamErrorMessage(from: successResponseData)
        ) {
            return Decision(
                metadata: metadata,
                outcome: .serverError(statusCode: httpStatusCode, message: recoveredSSEError)
            )
        }

        if let pendingError = nonEmpty(pendingLMStudioStreamErrorMessage) {
            return Decision(
                metadata: metadata,
                outcome: .serverError(statusCode: httpStatusCode, message: pendingError)
            )
        }

        return Decision(metadata: metadata, outcome: .emptyResponse)
    }

    private static func httpErrorMessage(status: Int, bodyData: Data) -> String {
        let preview = String(data: bodyData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !preview.isEmpty else {
            return "HTTP \(status)"
        }
        return "HTTP \(status): \(preview.prefix(400))"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : value
    }
}
