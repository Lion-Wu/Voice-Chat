//
//  ChatRequestContextMetadata.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.24.
//

import Foundation
import SwiftData

@Model
final class ChatRequestContextMetadata {
    @Attribute(.unique) var fingerprint: String
    var version: Int
    var createdAt: Date
    var lastSeenAt: Date
    var referenceCount: Int
    var modelIdentifier: String
    var endpointURLHash: String
    var providerRawValue: String
    var requestStyleRawValue: String
    var developerPromptHash: String
    var developerPromptCharacterCount: Int
    var thinkingOptionRawValue: String?
    var toolUseEnabled: Bool
    var enabledToolIDsJSON: String
    var toolSchemaDigest: String
    var toolSchemaSummaryJSON: String
    var toolAuthorizationModeRawValue: String
    var allowHighRiskToolAutoExecution: Bool?
    var useProviderContinuationIDs: Bool?

    init(snapshot: ChatRequestContextSnapshot, now: Date = Date()) {
        self.fingerprint = snapshot.fingerprint
        self.version = snapshot.version
        self.createdAt = now
        self.lastSeenAt = now
        self.referenceCount = 1
        self.modelIdentifier = snapshot.modelIdentifier
        self.endpointURLHash = snapshot.endpointURLHash
        self.providerRawValue = snapshot.providerRawValue
        self.requestStyleRawValue = snapshot.requestStyleRawValue
        self.developerPromptHash = snapshot.developerPromptHash
        self.developerPromptCharacterCount = snapshot.developerPromptCharacterCount
        self.thinkingOptionRawValue = snapshot.thinkingOptionRawValue
        self.toolUseEnabled = snapshot.toolUseEnabled
        self.enabledToolIDsJSON = snapshot.enabledToolIDsJSON
        self.toolSchemaDigest = snapshot.toolSchemaDigest
        self.toolSchemaSummaryJSON = snapshot.toolSchemaSummaryJSON
        self.toolAuthorizationModeRawValue = snapshot.toolAuthorizationModeRawValue
        self.allowHighRiskToolAutoExecution = snapshot.allowHighRiskToolAutoExecution
        self.useProviderContinuationIDs = snapshot.useProviderContinuationIDs
    }

    func markSeen(with snapshot: ChatRequestContextSnapshot, now: Date = Date()) {
        version = snapshot.version
        lastSeenAt = now
        referenceCount += 1
        modelIdentifier = snapshot.modelIdentifier
        endpointURLHash = snapshot.endpointURLHash
        providerRawValue = snapshot.providerRawValue
        requestStyleRawValue = snapshot.requestStyleRawValue
        developerPromptHash = snapshot.developerPromptHash
        developerPromptCharacterCount = snapshot.developerPromptCharacterCount
        thinkingOptionRawValue = snapshot.thinkingOptionRawValue
        toolUseEnabled = snapshot.toolUseEnabled
        enabledToolIDsJSON = snapshot.enabledToolIDsJSON
        toolSchemaDigest = snapshot.toolSchemaDigest
        toolSchemaSummaryJSON = snapshot.toolSchemaSummaryJSON
        toolAuthorizationModeRawValue = snapshot.toolAuthorizationModeRawValue
        allowHighRiskToolAutoExecution = snapshot.allowHighRiskToolAutoExecution
        useProviderContinuationIDs = snapshot.useProviderContinuationIDs
    }

    var enabledToolIDs: [String] {
        Self.decodeStringArray(enabledToolIDsJSON)
    }

    private static func decodeStringArray(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }
}

enum ChatRequestContextMetadataStore {
    @MainActor
    static func record(_ snapshot: ChatRequestContextSnapshot, in context: ModelContext?) {
        guard let context else { return }
        if let existing = fetch(fingerprint: snapshot.fingerprint, in: context) {
            existing.markSeen(with: snapshot)
        } else {
            context.insert(ChatRequestContextMetadata(snapshot: snapshot))
        }
        do {
            try context.save()
        } catch {
            print("Save request context metadata error: \(error)")
        }
    }

    @MainActor
    static func fetch(fingerprint: String?, in context: ModelContext?) -> ChatRequestContextMetadata? {
        guard let context,
              let fingerprint = fingerprint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !fingerprint.isEmpty else {
            return nil
        }
        var descriptor = FetchDescriptor<ChatRequestContextMetadata>(
            predicate: #Predicate { $0.fingerprint == fingerprint }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
