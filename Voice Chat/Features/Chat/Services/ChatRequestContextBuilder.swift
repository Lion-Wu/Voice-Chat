//
//  ChatRequestContextBuilder.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.24.
//

import CryptoKit
import Foundation

struct ChatRequestContextState: Equatable, Sendable {
    let fingerprint: String
    let snapshot: ChatRequestContextSnapshot
}

struct ChatRequestContextSnapshot: Equatable, Sendable {
    let fingerprint: String
    let version: Int
    let modelIdentifier: String
    let endpointURLHash: String
    let providerRawValue: String
    let requestStyleRawValue: String
    let developerPromptHash: String
    let developerPromptCharacterCount: Int
    let thinkingOptionRawValue: String?
    let toolUseEnabled: Bool
    let enabledToolIDsJSON: String
    let toolSchemaDigest: String
    let toolSchemaSummaryJSON: String
    let toolAuthorizationModeRawValue: String
    let allowHighRiskToolAutoExecution: Bool
    let useProviderContinuationIDs: Bool
}

enum ChatRequestContextBuilder {
    static let version = 1

    static func make(
        model: String,
        endpoint: ChatAPIEndpointCandidate,
        developerPrompt: String?,
        toolUseSettings: ToolUseSettings,
        apiAdvancedSettings: APIAdvancedSettings = .defaults,
        thinkingOption: ModelThinkingOption?,
        sourceMessages: [ChatRequestSourceMessage] = [],
        includeImagesInUserContent: Bool = false
    ) -> ChatRequestContextState {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt = developerPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let developerPromptFingerprintValue = ChatRequestBodyProviderEncoder.previousResponseCarriesInstructions(endpoint)
            ? normalizedPrompt
            : ""
        let enabledIDs = toolUseSettings.isEnabled
            ? toolUseSettings.enabledToolIDs
            : Set<ChatToolID>()
        let definitions = ChatToolDefinitions.definitions(enabledIDs: enabledIDs)
        let enabledToolIDs = definitions.map { $0.id.rawValue }
        let toolMetadata = definitions.map { definition in
            [
                "name": definition.id.rawValue,
                "description": definition.description,
                "parameters": definition.parametersSchema.jsonObject
            ] as [String: Any]
        }
        let imageInputSummary = makeImageInputSummary(
            sourceMessages: sourceMessages,
            includeImagesInUserContent: includeImagesInUserContent
        )
        let advancedSettingsSummary = makeAdvancedSettingsSummary(apiAdvancedSettings)
        let effectiveUseProviderContinuationIDs = toolUseSettings.useProviderContinuationIDs(for: endpoint)
        let canonicalPayload: [String: Any] = [
            "version": version,
            "model": normalizedModel,
            "provider": endpoint.provider.rawValue,
            "style": endpoint.style.rawValue,
            "chatURL": endpoint.chatURL.absoluteString,
            "developerPrompt": developerPromptFingerprintValue,
            "thinkingOption": thinkingOption?.rawValue ?? "",
            "imageInput": imageInputSummary,
            "advancedSettings": advancedSettingsSummary,
            "providerContinuation": [
                "useProviderContinuationIDs": effectiveUseProviderContinuationIDs
            ],
            "tools": toolMetadata
        ]
        let toolSchemaSummary: [String: Any] = [
            "enabledToolIDs": enabledToolIDs,
            "tools": toolMetadata
        ]
        let toolSchemaSummaryJSON = compactJSONString(from: toolSchemaSummary)
        let fingerprint = digestString(for: canonicalPayload)
        let snapshot = ChatRequestContextSnapshot(
            fingerprint: fingerprint,
            version: version,
            modelIdentifier: normalizedModel,
            endpointURLHash: digestString(for: endpoint.chatURL.absoluteString),
            providerRawValue: endpoint.provider.rawValue,
            requestStyleRawValue: endpoint.style.rawValue,
            developerPromptHash: digestString(for: normalizedPrompt),
            developerPromptCharacterCount: normalizedPrompt.count,
            thinkingOptionRawValue: thinkingOption?.rawValue,
            toolUseEnabled: toolUseSettings.isEnabled,
            enabledToolIDsJSON: compactJSONString(from: enabledToolIDs),
            toolSchemaDigest: digestString(for: toolSchemaSummaryJSON),
            toolSchemaSummaryJSON: toolSchemaSummaryJSON,
            toolAuthorizationModeRawValue: toolUseSettings.authorizationMode.rawValue,
            allowHighRiskToolAutoExecution: toolUseSettings.allowHighRiskToolAutoExecution,
            useProviderContinuationIDs: effectiveUseProviderContinuationIDs
        )
        return ChatRequestContextState(fingerprint: fingerprint, snapshot: snapshot)
    }

    private static func compactJSONString(from value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func digestString(for value: Any) -> String {
        let data: Data
        if let string = value as? String {
            data = Data(string.utf8)
        } else if let value = value as? Data {
            data = value
        } else if JSONSerialization.isValidJSONObject(value),
                  let encoded = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            data = encoded
        } else {
            data = Data()
        }
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func makeImageInputSummary(
        sourceMessages: [ChatRequestSourceMessage],
        includeImagesInUserContent: Bool
    ) -> [String: Any] {
        guard includeImagesInUserContent else {
            return [
                "includeImagesInUserContent": false,
                "attachments": []
            ]
        }

        let attachments = sourceMessages.enumerated().flatMap { messageIndex, message -> [[String: Any]] in
            guard message.isUser, !message.content.hasPrefix("!error:") else { return [] }
            return message.imageAttachments.enumerated().compactMap { attachmentIndex, attachment in
                guard !attachment.data.isEmpty else { return nil }
                return [
                    "messageIndex": messageIndex,
                    "attachmentIndex": attachmentIndex,
                    "mimeType": attachment.mimeType,
                    "byteCount": attachment.data.count,
                    "dataHash": digestString(for: attachment.data)
                ] as [String: Any]
            }
        }

        return [
            "includeImagesInUserContent": true,
            "attachments": attachments
        ]
    }

    private static func makeAdvancedSettingsSummary(_ settings: APIAdvancedSettings) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(settings.sanitized),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }
}
