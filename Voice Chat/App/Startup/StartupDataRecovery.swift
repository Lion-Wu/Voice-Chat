import Foundation
import SwiftData

struct DataRecoveryCategory: Identifiable, Sendable {
    let id: String
    let title: String
    var recovered = 0
    var skipped = 0
    var hasUnknownLoss = false
    var hasPartialLoss = false
    var names: [String] = []
    var skippedNames: [String] = []
}

struct DataRecoveryPlan: Identifiable, Sendable {
    let id: UUID
    let storeURL: URL
    let container: ModelContainer
    let categories: [DataRecoveryCategory]
    var directory: URL { storeURL.deletingLastPathComponent() }
    var recoveredCount: Int { categories.reduce(0) { $0 + $1.recovered } }

    func discard() { StartupDataRecovery.discard(container: container, directory: directory) }
}

/// Store selection changes only after a reviewed candidate has been saved.
/// Superseded stores are removed after the app accepts the new container.
nonisolated enum StartupPersistentStore {
    static let schema = Schema([
        ChatSession.self, ChatMessage.self, ChatRequestContextMetadata.self,
        AppSettings.self, ChatServerPreset.self, VoiceServerPreset.self,
        VoicePreset.self, SystemPromptPreset.self
    ])

    static var defaultURL: URL { ModelConfiguration().url }
    private static var selectionURL: URL {
        defaultURL.deletingLastPathComponent().appendingPathComponent("recovered-store.json")
    }
    static var recoveryDirectory: URL {
        defaultURL.deletingLastPathComponent().appendingPathComponent("DataRecovery", isDirectory: true)
    }

    static func currentURL() throws -> URL {
        guard FileManager.default.fileExists(atPath: selectionURL.path) else { return defaultURL }
        let id = try JSONDecoder().decode(UUID.self, from: Data(contentsOf: selectionURL))
        let url = recoveryDirectory.appendingPathComponent(id.uuidString).appendingPathComponent("recovered.store")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    static func open(at url: URL) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    }

    static func activate(_ plan: DataRecoveryPlan) throws {
        try JSONEncoder().encode(plan.id).write(to: selectionURL, options: .atomic)
    }

    /// Keep storage ownership here rather than exporting the entire Library.
    /// Include every recovery store even when selection metadata is unreadable.
    static func exportSources(defaultStoreURL: URL = defaultURL) -> [String: URL] {
        let directory = defaultStoreURL.deletingLastPathComponent()
        let names = [defaultStoreURL.lastPathComponent, defaultStoreURL.lastPathComponent + "-wal",
                     defaultStoreURL.lastPathComponent + "-shm", "DataRecovery", "recovered-store.json"]
        return Dictionary(uniqueKeysWithValues: names.map { ("Stores/" + $0, directory.appendingPathComponent($0)) })
    }

    /// An explicitly confirmed reset removes every owned store and the selection
    /// metadata without requiring any of them to be readable.
    static func reset(defaultStoreURL: URL = defaultURL) throws {
        let manager = FileManager.default
        let directory = defaultStoreURL.deletingLastPathComponent()
        try removeStoreFiles(at: defaultStoreURL)
        for name in ["DataRecovery", "recovered-store.json"] {
            let url = directory.appendingPathComponent(name)
            if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
        }
    }

    static func removeSupersededStores(keeping storeURL: URL) throws {
        let fileManager = FileManager.default
        let directories = try fileManager.contentsOfDirectory(at: recoveryDirectory, includingPropertiesForKeys: nil)
        let activeDirectory = storeURL.deletingLastPathComponent().standardizedFileURL.path
        try removeStoreFiles(at: defaultURL)
        for directory in directories where UUID(uuidString: directory.lastPathComponent) != nil
            && directory.standardizedFileURL.path != activeDirectory {
            try fileManager.removeItem(at: directory)
        }
    }

    static func removeStoreFiles(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let relatedURLs = [storeURL, URL(fileURLWithPath: storeURL.path + "-shm"), URL(fileURLWithPath: storeURL.path + "-wal")]
        var firstError: Error?
        for url in relatedURLs where fileManager.fileExists(atPath: url.path) {
            do { try fileManager.removeItem(at: url) }
            catch { if firstError == nil { firstError = error } }
        }
        if let firstError { throw firstError }
    }
}

nonisolated enum StartupDataRecovery {
    static func prepare(sourceURL: URL, recoveryDirectory: URL) throws -> DataRecoveryPlan {
        let id = UUID()
        let directory = recoveryDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var keepCandidate = false
        var container: ModelContainer?
        defer {
            if !keepCandidate { discard(container: container, directory: directory) }
        }
        let storeURL = directory.appendingPathComponent("recovered.store")
        let candidate = try StartupPersistentStore.open(at: storeURL)
        container = candidate
        let categories = try reconstruct(sourceURL: sourceURL, container: candidate)
        try Task.checkCancellation()
        keepCandidate = true
        return DataRecoveryPlan(id: id, storeURL: storeURL, container: candidate, categories: categories)
    }

    static func discard(container: ModelContainer?, directory: URL) {
        do {
            try container?.erase()
            try FileManager.default.removeItem(at: directory)
        }
        catch { print("Could not remove recovery preview: \(error)") }
    }

    private static func reconstruct(sourceURL: URL, container: ModelContainer) throws -> [DataRecoveryCategory] {
        let source = try RecoveryStoreReader(url: sourceURL)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var categories: [DataRecoveryCategory] = []
        var sessions: [Int64: ChatSession] = [:]
        var messages: [Int64: ChatMessage] = [:]
        var parents: [Int64: Int64] = [:]

        func recover<M: PersistentModel>(
            _ entity: String, title: String,
            make: (RecoveryRow) throws -> M,
            identityField: String = "id",
            connect: (M, RecoveryRow) throws -> Void = { _, _ in }
        ) throws {
            var category = DataRecoveryCategory(id: entity, title: title)
            var rows: [RecoveryRow] = []
            do {
                category.hasUnknownLoss = try !source.scan(entity: entity) { rows.append($0) }
            } catch is CancellationError { throw CancellationError() }
            catch {
                let error = error as NSError
                guard error.domain == "RecoverySQLite", [1, 11, 26].contains(error.code) else { throw error }
                category.hasUnknownLoss = true
            }
            func identity(_ row: RecoveryRow) -> String? {
                if identityField == "id" { return (try? row.value("id", as: UUID.self))?.uuidString }
                return try? row.value(identityField, as: String.self)
            }
            let identityCounts = Dictionary(rows.compactMap { identity($0).map { ($0, 1) } }, uniquingKeysWith: +)
            // Match the settings store's existing selection; never merge unrelated records.
            let selectedSettingsID = entity == "AppSettings" ? identityCounts.keys.min() : nil
            for row in rows {
                try Task.checkCancellation()
                let name = ["title", "name", "content"].compactMap { try? row.value($0, as: String.self) }.first
                do {
                    guard let id = identity(row), !id.isEmpty, identityCounts[id] == 1,
                          selectedSettingsID == nil || selectedSettingsID == id else { throw row.invalid(identityField) }
                    let model = try make(row)
                    try connect(model, row)
                    context.insert(model)
                    category.recovered += 1
                    category.hasPartialLoss = category.hasPartialLoss || row.hasLoss
                    if let name { category.names.append(String(name.prefix(120))) }
                } catch {
                    guard (error as NSError).domain == "RecoveryRecord" else { throw error }
                    category.skipped += 1
                    if let name { category.skippedNames.append(String(name.prefix(120))) }
                }
            }
            categories.append(category)
        }

        try recover("ChatSession", title: String(localized: "Chats"), make: recoverSession) { session, row in
            sessions[try row.integer("Z_PK")] = session
        }
        try recover("ChatMessage", title: String(localized: "Messages"), make: recoverMessage) { message, row in
            let key = try row.integer("Z_PK")
            let sessionKey = try row.integer("ZSESSION")
            guard let session = sessions[sessionKey] else { throw row.invalid("session") }
            let parent = try row.optionalInteger("ZPARENTMESSAGE")
            message.session = session
            parents[key] = parent
            messages[key] = message
        }
        // Keep only original, unambiguous parent chains. Missing parents and cycles
        // invalidate their descendants; they never become new conversation roots.
        var validChains: [Int64: Bool] = [:]
        for key in messages.keys {
            var path: Set<Int64> = []
            var cursor = key
            var valid = true
            while let message = messages[cursor] {
                if let known = validChains[cursor] { valid = known; break }
                guard path.insert(cursor).inserted else { valid = false; break }
                guard let parent = parents[cursor] else { break }
                guard let parentMessage = messages[parent], parentMessage.session === message.session else {
                    valid = false
                    break
                }
                cursor = parent
            }
            for visited in path { validChains[visited] = valid }
        }
        for (key, message) in messages where validChains[key] == false {
            context.delete(message)
            categories[1].recovered -= 1
            categories[1].skipped += 1
            categories[1].skippedNames.append(String(message.content.prefix(120)))
        }
        messages = messages.filter { validChains[$0.key] == true }
        categories[1].names = messages.keys.sorted().compactMap { messages[$0].map { String($0.content.prefix(120)) } }
        for (key, message) in messages {
            message.parentMessage = parents[key].flatMap { messages[$0] }
        }
        // These are display selections and projections, not message ownership.
        let messagesBySession = Dictionary(grouping: messages.values, by: { $0.session?.id })
        for session in sessions.values {
            let surviving = messagesBySession[session.id] ?? []
            let lookup = Dictionary(uniqueKeysWithValues: surviving.map { ($0.id, $0) })
            if !surviving.contains(where: { $0.id == session.activeRootMessageID && $0.parentMessage == nil }) {
                session.activeRootMessageID = nil
            }
            for message in surviving {
                if message.activeChildMessageID.flatMap({ lookup[$0] })?.parentMessage !== message {
                    message.activeChildMessageID = nil
                }
            }
            let latest = surviving.max { $0.createdAt < $1.createdAt }
            session.lastMessageID = latest?.id
            session.lastMessageAt = latest?.createdAt
            session.sidebarPreviewText = ChatSession.sidebarPreviewText(for: latest)
        }

        try recover("AppSettings", title: String(localized: "Settings"), make: AppSettingsStore.recover)
        try recover("ChatServerPreset", title: String(localized: "Chat Server Presets"), make: recoverChatServer)
        try recover("VoiceServerPreset", title: String(localized: "Voice Server Presets"), make: recoverVoiceServer)
        try recover("VoicePreset", title: String(localized: "Voice Presets"), make: recoverVoice)
        try recover("SystemPromptPreset", title: String(localized: "System Prompt Presets"), make: recoverPrompt)
        try recover("ChatRequestContextMetadata", title: String(localized: "Request Metadata"), make: recoverMetadata, identityField: "fingerprint")
        try context.save()
        return categories
    }

}

extension StartupDataRecovery {
    private static func recoverSession(_ row: RecoveryRow) throws -> ChatSession {
        let model = ChatSession()
        model.id = try row.value("id")
        model.title = try row.value("title")
        model.createdAt = try row.value("createdAt")
        model.updatedAt = row.recover("updatedAt", defaultValue: model.updatedAt)
        // Sidebar projections are rebuilt from the recovered messages.
        model.activeRootMessageID = row.recover("activeRootMessageID", defaultValue: model.activeRootMessageID)
        return model
    }

    private static func recoverMessage(_ row: RecoveryRow) throws -> ChatMessage {
        let model = ChatMessage(content: "", isUser: false)
        model.id = try row.value("id")
        model.activeChildMessageID = row.recover("activeChildMessageID", defaultValue: model.activeChildMessageID)
        model.content = try row.value("content")
        model.requestContentSnapshot = row.recover("requestContentSnapshot", defaultValue: model.requestContentSnapshot)
        model.assistantSegmentsData = row.recover("assistantSegmentsData", defaultValue: model.assistantSegmentsData)
        model.openAIResponsesConversationItemsData = row.recover("openAIResponsesConversationItemsData", defaultValue: model.openAIResponsesConversationItemsData)
        model.imageAttachmentsData = row.recover("imageAttachmentsData", defaultValue: model.imageAttachmentsData)
        model.isUser = try row.value("isUser")
        model.isActive = row.recover("isActive", defaultValue: model.isActive)
        model.createdAt = try row.value("createdAt")
        model.modelIdentifier = row.recover("modelIdentifier", defaultValue: model.modelIdentifier)
        model.apiBaseURL = row.recover("apiBaseURL", defaultValue: model.apiBaseURL)
        model.thinkingOptionRawValue = row.recover("thinkingOptionRawValue", defaultValue: model.thinkingOptionRawValue)
        model.requestID = row.recover("requestID", defaultValue: model.requestID)
        model.providerResponseID = row.recover("providerResponseID", defaultValue: model.providerResponseID)
        model.providerResponseIDsData = row.recover("providerResponseIDsData", defaultValue: model.providerResponseIDsData)
        model.requestContextFingerprint = row.recover("requestContextFingerprint", defaultValue: model.requestContextFingerprint)
        model.requestUsedPreviousResponseID = row.recover("requestUsedPreviousResponseID", defaultValue: model.requestUsedPreviousResponseID)
        model.requestPreviousResponseID = row.recover("requestPreviousResponseID", defaultValue: model.requestPreviousResponseID)
        model.streamStartedAt = row.recover("streamStartedAt", defaultValue: model.streamStartedAt)
        model.streamFirstTokenAt = row.recover("streamFirstTokenAt", defaultValue: model.streamFirstTokenAt)
        model.streamCompletedAt = row.recover("streamCompletedAt", defaultValue: model.streamCompletedAt)
        model.timeToFirstToken = row.recover("timeToFirstToken", defaultValue: model.timeToFirstToken)
        model.streamDuration = row.recover("streamDuration", defaultValue: model.streamDuration)
        model.generationDuration = row.recover("generationDuration", defaultValue: model.generationDuration)
        model.outputTokenCount = row.recover("outputTokenCount", defaultValue: model.outputTokenCount)
        model.reasoningOutputTokenCount = row.recover("reasoningOutputTokenCount", defaultValue: model.reasoningOutputTokenCount)
        model.tokensPerSecond = row.recover("tokensPerSecond", defaultValue: model.tokensPerSecond)
        model.tokenCount = row.recover("tokenCount", defaultValue: model.tokenCount)
        model.tokenCountSource = row.recover("tokenCountSource", defaultValue: model.tokenCountSource)
        model.timeToFirstTokenSource = row.recover("timeToFirstTokenSource", defaultValue: model.timeToFirstTokenSource)
        model.tokensPerSecondSource = row.recover("tokensPerSecondSource", defaultValue: model.tokensPerSecondSource)
        model.finishReasonSource = row.recover("finishReasonSource", defaultValue: model.finishReasonSource)
        model.characterCount = row.recover("characterCount", defaultValue: model.characterCount)
        model.promptMessageCount = row.recover("promptMessageCount", defaultValue: model.promptMessageCount)
        model.promptCharacterCount = row.recover("promptCharacterCount", defaultValue: model.promptCharacterCount)
        model.finishReason = row.recover("finishReason", defaultValue: model.finishReason)
        model.errorDescription = row.recover("errorDescription", defaultValue: model.errorDescription)
        model.toolActivityPlacementsData = row.recover("toolActivityPlacementsData", defaultValue: model.toolActivityPlacementsData)
        // Keep readable payloads unchanged. Invalid structured display data is
        // omitted; the normal renderer can still display the original body.
        model.assistantSegmentsData = row.validArray(model.assistantSegmentsData, of: ChatAssistantSegment.self)
        model.openAIResponsesConversationItemsData = row.validArray(model.openAIResponsesConversationItemsData, of: JSONValue.self)
        model.imageAttachmentsData = try row.readableItems(model.imageAttachmentsData, of: ChatImageAttachment.self)
        model.providerResponseIDsData = try row.readableItems(model.providerResponseIDsData, of: String.self)
        model.toolActivityPlacementsData = row.validArray(model.toolActivityPlacementsData, of: ChatToolActivityPlacement.self)
        if model.assistantSegmentsData == nil {
            if model.toolActivityPlacements.contains(where: { $0.assistantSegmentAnchor != nil }) { row.hasLoss = true }
            model.toolActivityPlacements = model.toolActivityPlacements.filter { $0.assistantSegmentAnchor == nil }
        }
        return model
    }

    private static func recoverChatServer(_ row: RecoveryRow) throws -> ChatServerPreset {
        let model = ChatServerPreset(name: String(localized: "New Preset"))
        model.id = try row.value("id")
        model.name = try row.value("name")
        model.apiURL = try row.value("apiURL")
        model.selectedModel = try row.value("selectedModel")
        model.apiFormatPreferenceRaw = row.recover("apiFormatPreferenceRaw", defaultValue: model.apiFormatPreferenceRaw)
        model.createdAt = row.recover("createdAt", defaultValue: model.createdAt)
        model.updatedAt = row.recover("updatedAt", defaultValue: model.updatedAt)
        return model
    }

    private static func recoverVoiceServer(_ row: RecoveryRow) throws -> VoiceServerPreset {
        let model = VoiceServerPreset(name: String(localized: "New Preset"))
        model.id = try row.value("id")
        model.name = try row.value("name")
        model.serverAddress = try row.value("serverAddress")
        model.createdAt = row.recover("createdAt", defaultValue: model.createdAt)
        model.updatedAt = row.recover("updatedAt", defaultValue: model.updatedAt)
        return model
    }

    private static func recoverVoice(_ row: RecoveryRow) throws -> VoicePreset {
        let model = VoicePreset(name: String(localized: "New Preset"))
        model.id = try row.value("id")
        model.name = try row.value("name")
        model.refAudioPath = try row.value("refAudioPath")
        model.promptText = try row.value("promptText")
        model.promptLang = try row.value("promptLang")
        model.gptWeightsPath = try row.value("gptWeightsPath")
        model.sovitsWeightsPath = try row.value("sovitsWeightsPath")
        model.createdAt = row.recover("createdAt", defaultValue: model.createdAt)
        model.updatedAt = row.recover("updatedAt", defaultValue: model.updatedAt)
        return model
    }

    private static func recoverPrompt(_ row: RecoveryRow) throws -> SystemPromptPreset {
        let model = SystemPromptPreset(name: String(localized: "New Prompt Preset"))
        model.id = try row.value("id")
        model.name = try row.value("name")
        model.mode = try row.value("mode", as: String.self)
        model.normalPrompt = row.recover("normalPrompt", defaultValue: model.normalPrompt)
        model.voicePrompt = row.recover("voicePrompt", defaultValue: model.voicePrompt)
        model.createdAt = row.recover("createdAt", defaultValue: model.createdAt)
        model.updatedAt = row.recover("updatedAt", defaultValue: model.updatedAt)
        switch model.mode {
        case SystemPromptPresetStore.normalMode: model.normalPrompt = try row.value("normalPrompt")
        case SystemPromptPresetStore.voiceMode: model.voicePrompt = try row.value("voicePrompt")
        default: throw row.invalid("mode")
        }
        return model
    }

    private static func recoverMetadata(_ row: RecoveryRow) throws -> ChatRequestContextMetadata {
        let snapshot = ChatRequestContextSnapshot(
            fingerprint: try row.value("fingerprint"),
            version: ChatRequestContextBuilder.version,
            modelIdentifier: "",
            endpointURLHash: "",
            providerRawValue: "",
            requestStyleRawValue: "",
            developerPromptHash: "",
            developerPromptCharacterCount: 0,
            thinkingOptionRawValue: nil,
            toolUseEnabled: false,
            enabledToolIDsJSON: "[]",
            toolSchemaDigest: "",
            toolSchemaSummaryJSON: "{}",
            toolAuthorizationModeRawValue: ToolAuthorizationMode.readOnly.rawValue,
            allowHighRiskToolAutoExecution: false,
            useProviderContinuationIDs: false
        )
        let model = ChatRequestContextMetadata(snapshot: snapshot)
        model.version = row.recover("version", defaultValue: model.version)
        model.createdAt = row.recover("createdAt", defaultValue: model.createdAt)
        model.lastSeenAt = row.recover("lastSeenAt", defaultValue: model.lastSeenAt)
        model.referenceCount = row.recover("referenceCount", defaultValue: model.referenceCount)
        model.modelIdentifier = row.recover("modelIdentifier", defaultValue: model.modelIdentifier)
        model.endpointURLHash = row.recover("endpointURLHash", defaultValue: model.endpointURLHash)
        model.providerRawValue = row.recover("providerRawValue", defaultValue: model.providerRawValue)
        model.requestStyleRawValue = row.recover("requestStyleRawValue", defaultValue: model.requestStyleRawValue)
        model.developerPromptHash = row.recover("developerPromptHash", defaultValue: model.developerPromptHash)
        model.developerPromptCharacterCount = row.recover("developerPromptCharacterCount", defaultValue: model.developerPromptCharacterCount)
        model.thinkingOptionRawValue = row.recover("thinkingOptionRawValue", defaultValue: model.thinkingOptionRawValue)
        model.toolUseEnabled = row.recover("toolUseEnabled", defaultValue: model.toolUseEnabled)
        model.enabledToolIDsJSON = row.recover("enabledToolIDsJSON", defaultValue: model.enabledToolIDsJSON)
        model.toolSchemaDigest = row.recover("toolSchemaDigest", defaultValue: model.toolSchemaDigest)
        model.toolSchemaSummaryJSON = row.recover("toolSchemaSummaryJSON", defaultValue: model.toolSchemaSummaryJSON)
        model.toolAuthorizationModeRawValue = row.recover("toolAuthorizationModeRawValue", defaultValue: model.toolAuthorizationModeRawValue)
        model.allowHighRiskToolAutoExecution = row.recover("allowHighRiskToolAutoExecution", defaultValue: model.allowHighRiskToolAutoExecution)
        model.useProviderContinuationIDs = row.recover("useProviderContinuationIDs", defaultValue: model.useProviderContinuationIDs)
        model.enabledToolIDsJSON = try row.validJSON(model.enabledToolIDsJSON, defaultValue: [String]())
        model.toolSchemaSummaryJSON = try row.validJSON(model.toolSchemaSummaryJSON, defaultValue: JSONValue.object([:]))
        return model
    }
}
