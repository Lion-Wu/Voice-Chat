import XCTest
import SwiftData
import SQLite3
import Security
@testable import Voice_Chat

@MainActor
final class StartupDataRecoveryTests: XCTestCase {
    func testHealthyStoreRoundTripsEveryEntityAndAcceptsNewWrites() throws {
        try withFixture { fixture in
            let attachment = XCTAttachment(contentsOfFile: fixture.source)
            attachment.name = "healthy-recovery-fixture.store"
            attachment.lifetime = .keepAlways
            add(attachment)
            let plan = try fixture.prepare()
            XCTAssertEqual(plan.categories.count, 8)
            XCTAssertTrue(plan.categories.allSatisfy { $0.recovered > 0 && $0.skipped == 0 && !$0.hasUnknownLoss && !$0.hasPartialLoss })
            try inspect(plan) { context in
                let messages = try context.fetch(FetchDescriptor<ChatMessage>())
                XCTAssertEqual(messages.count, 3)
                let answer = try XCTUnwrap(messages.first { !$0.isUser })
                XCTAssertEqual(answer.assistantText, "Readable answer")
                XCTAssertEqual(answer.imageAttachments.first?.data, Fixture.image)
                XCTAssertEqual(answer.toolActivityPlacements.first?.activity.title, "Readable tool")
                XCTAssertEqual(answer.parentMessage?.content, "First question")
                XCTAssertEqual(try context.fetch(FetchDescriptor<VoicePreset>()).first?.promptText, "Voice reference")
                XCTAssertEqual(try context.fetch(FetchDescriptor<VoiceServerPreset>()).first?.serverAddress, "https://voice.example.test")
                XCTAssertEqual(try context.fetch(FetchDescriptor<ChatServerPreset>()).first?.selectedModel, "fixture-model")
                XCTAssertEqual(try context.fetch(FetchDescriptor<ChatRequestContextMetadata>()).first?.enabledToolIDs, ["calendar"])
                let settings = try XCTUnwrap(context.fetch(FetchDescriptor<AppSettings>()).first)
                XCTAssertEqual(settings.selectedModel, "fixture-model")
                XCTAssertEqual(ChatModelCapabilityStore.restoringPreferences(from: settings).thinkingPreferences["https://chat.example.test|fixture-model"], .high)
                settings.selectedModel = "updated-after-recovery"
                let message = ChatMessage(content: "New message after recovery", isUser: true, session: answer.session)
                context.insert(message)
                try context.save()
            }
            try inspect(plan) { context in
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<ChatMessage>()), 4)
                XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).first?.selectedModel, "updated-after-recovery")
            }
        }
    }

    func testDamagedScalarMetadataKeepsReadableMessageAndDefaults() throws {
        try withFixture { fixture in
            try fixture.sql("UPDATE ZCHATMESSAGE SET ZTOKENCOUNT='obsolete', ZOUTPUTTOKENCOUNT='bad' WHERE ZISUSER=0")
            let plan = try fixture.prepare()
            try inspect(plan) { context in
                let answer = try XCTUnwrap(context.fetch(FetchDescriptor<ChatMessage>()).first { !$0.isUser })
                XCTAssertEqual(answer.content, "Readable answer")
                XCTAssertEqual(answer.assistantText, "Readable answer")
                XCTAssertEqual(answer.tokenCount, 0)
                XCTAssertNil(answer.outputTokenCount)
                XCTAssertEqual(answer.modelIdentifier, "fixture-model")
            }
            let category = try category("ChatMessage", in: plan)
            XCTAssertEqual(category.recovered, 3)
            XCTAssertEqual(category.skipped, 0)
        }
    }

    func testDamagedStructuredDataIsOmittedWithoutRewritingReadableBody() throws {
        try withFixture { fixture in
            try fixture.sql("UPDATE ZCHATMESSAGE SET ZASSISTANTSEGMENTSDATA=CAST('[{\"kind\":\"text\",\"itemID\":\"kept-id\",\"text\":17}]' AS BLOB) WHERE ZISUSER=0")
            try fixture.sql("UPDATE ZAPPSETTINGS SET ZAPIADVANCEDSETTINGSJSON='{\"openAIChatMaxCompletionTokens\":1234,\"openAIChatSampling\":{\"temperature\":\"broken\",\"topP\":0.7}}'")
            let plan = try fixture.prepare()
            try inspect(plan) { context in
                let answer = try XCTUnwrap(context.fetch(FetchDescriptor<ChatMessage>()).first { !$0.isUser })
                XCTAssertEqual(answer.assistantText, "Readable answer")
                XCTAssertTrue(answer.assistantSegments.isEmpty)
                XCTAssertTrue(answer.toolActivityPlacements.isEmpty)
                let settings = try XCTUnwrap(context.fetch(FetchDescriptor<AppSettings>()).first)
                let advanced = try JSONDecoder().decode(APIAdvancedSettings.self, from: Data(try XCTUnwrap(settings.apiAdvancedSettingsJSON).utf8))
                XCTAssertEqual(advanced.openAIChatMaxCompletionTokens, SettingsDefaults.apiAdvancedSettings.openAIChatMaxCompletionTokens)
                XCTAssertEqual(advanced.openAIChatSampling.topP, SettingsDefaults.apiAdvancedSettings.openAIChatSampling.topP)
                XCTAssertEqual(advanced.openAIChatSampling.temperature, SettingsDefaults.apiAdvancedSettings.openAIChatSampling.temperature)
            }
        }
    }

    func testBrokenRelationshipsAreSkippedWithoutCreatingChatsOrReparenting() throws {
        try withFixture { fixture in
            try fixture.sql("UPDATE ZCHATMESSAGE SET ZSESSION=999999 WHERE ZCONTENT='Second question'")
            try fixture.sql("UPDATE ZCHATMESSAGE SET ZPARENTMESSAGE=Z_PK WHERE ZISUSER=0")
            let plan = try fixture.prepare()
            try inspect(plan) { context in
                let sessions = try context.fetch(FetchDescriptor<ChatSession>())
                XCTAssertEqual(sessions.count, 1)
                XCTAssertEqual(sessions.first?.messages.map(\.content), ["First question"])
            }
            XCTAssertEqual(try category("ChatMessage", in: plan).recovered, 1)
            XCTAssertEqual(try category("ChatMessage", in: plan).skipped, 2)
        }
    }

    func testDamagedAttachmentAndToolEntriesAreNotInvented() throws {
        try withFixture { fixture in
            try fixture.sql("UPDATE ZCHATMESSAGE SET ZIMAGEATTACHMENTSDATA=CAST(json_set(CAST(ZIMAGEATTACHMENTSDATA AS TEXT), '$[0].id', 'broken') AS BLOB), ZTOOLACTIVITYPLACEMENTSDATA=CAST(json_set(CAST(ZTOOLACTIVITYPLACEMENTSDATA AS TEXT), '$[0].activity.phase', 'removed-phase') AS BLOB) WHERE ZISUSER=0")
            try fixture.sql("UPDATE ZCHATREQUESTCONTEXTMETADATA SET ZREFERENCECOUNT='broken'")
            let plan = try fixture.prepare()
            try inspect(plan) { context in
                let answer = try XCTUnwrap(context.fetch(FetchDescriptor<ChatMessage>()).first { !$0.isUser })
                XCTAssertTrue(answer.imageAttachments.isEmpty)
                XCTAssertTrue(answer.toolActivityPlacements.isEmpty)
                XCTAssertEqual(try context.fetch(FetchDescriptor<ChatRequestContextMetadata>()).first?.enabledToolIDs, ["calendar"])
            }
            XCTAssertEqual(try category("ChatMessage", in: plan).skipped, 0)
            XCTAssertTrue(try category("ChatMessage", in: plan).hasPartialLoss)
        }
    }

    func testDuplicateIdentifiersAndTheirDependentMessagesAreSkipped() throws {
        try withFixture { fixture in
            try fixture.sql("UPDATE ZCHATMESSAGE SET ZID=(SELECT ZID FROM ZCHATMESSAGE WHERE ZCONTENT='First question') WHERE ZCONTENT='Second question'")
            let plan = try fixture.prepare()
            try inspect(plan) { context in
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<ChatMessage>()), 0)
            }
            XCTAssertEqual(try category("ChatMessage", in: plan).skipped, 3)
        }
    }

    func testInvalidPromptModeOrContentIsSkippedWithoutCreatingPresets() throws {
        for damage in ["ZMODE='removed-mode'", "ZNORMALPROMPT=X'00'"] {
            try withFixture { fixture in
                try fixture.sql("UPDATE ZSYSTEMPROMPTPRESET SET \(damage) WHERE ZNAME='Recovery prompt'")
                let plan = try fixture.prepare()
                try inspect(plan) { context in
                    let presets = try context.fetch(FetchDescriptor<SystemPromptPreset>())
                    XCTAssertEqual(presets.map(\.name), ["Voice prompt fixture"])
                    XCTAssertEqual(presets.first?.voicePrompt, "Selected voice prompt")
                }
                XCTAssertEqual(try category("SystemPromptPreset", in: plan).skipped, 1)
            }
        }
    }

    func testMissingEssentialMessageFieldsAreSkippedWithTheirDescendants() throws {
        for column in ["ZID", "ZISUSER", "ZCONTENT", "ZCREATEDAT", "ZPARENTMESSAGE"] {
            try withFixture { fixture in
                try fixture.sql("UPDATE ZCHATMESSAGE SET \(column)=X'00' WHERE ZISUSER=0")
                let plan = try fixture.prepare()
                try inspect(plan) { context in
                    XCTAssertEqual(try context.fetch(FetchDescriptor<ChatMessage>()).map(\.content), ["First question"])
                }
                XCTAssertEqual(try category("ChatMessage", in: plan).skipped, 2)
            }
        }
    }

    func testRawExportIncludesUnreadableBytesSidecarsAndKeychain() throws {
        try withFixture { fixture in
            let source = fixture.root.appendingPathComponent("raw", isDirectory: true)
            try FileManager.default.createDirectory(at: source.appendingPathComponent("DataRecovery"), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: source.appendingPathComponent("DataRecovery/system-link"),
                withDestinationURL: fixture.root.appendingPathComponent("missing-system-directory")
            )
            let files = ["broken.store": Data([0, 255, 1]), "broken.store-wal": Data([7, 8]), "broken.store-shm": Data([9])]
            for (name, bytes) in files { try bytes.write(to: source.appendingPathComponent(name)) }
            let keychain = try PropertyListSerialization.data(fromPropertyList: [["acct": "synthetic-key", "v_Data": Data("synthetic-secret".utf8)]], format: .xml, options: 0)
            let crashReports = source.appendingPathComponent("CrashReporter")
            try FileManager.default.createDirectory(at: crashReports, withIntermediateDirectories: true)
            try Data("unrelated report".utf8).write(to: crashReports.appendingPathComponent("report.plist"))
            let recovery = source.appendingPathComponent("DataRecovery/damaged-candidate")
            try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
            try Data([0, 255]).write(to: recovery.appendingPathComponent("recovered.store"))
            try Data("unreadable selection".utf8).write(to: source.appendingPathComponent("recovered-store.json"))
            let sources = StartupPersistentStore.exportSources(defaultStoreURL: source.appendingPathComponent("broken.store"))
            XCTAssertEqual(Set(sources.keys), Set([
                "Stores/broken.store", "Stores/broken.store-wal", "Stores/broken.store-shm",
                "Stores/DataRecovery", "Stores/recovered-store.json"
            ]))
            let archive = try RawDataExport.prepare(sources: sources, keychain: keychain, temporaryDirectory: fixture.root)
            XCTAssertGreaterThan(try Data(contentsOf: archive.url).count, 0)
            #if os(macOS)
            let unpacked = fixture.root.appendingPathComponent("unpacked")
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", archive.url.path, unpacked.path]
            try unzip.run()
            unzip.waitUntilExit()
            XCTAssertEqual(unzip.terminationStatus, 0)
            let contents = unpacked.appendingPathComponent("Voice Chat Data")
            var expected = Dictionary(uniqueKeysWithValues: files.map { ("Stores/" + $0.key, $0.value) })
            expected["Stores/DataRecovery/damaged-candidate/recovered.store"] = Data([0, 255])
            expected["Stores/recovered-store.json"] = Data("unreadable selection".utf8)
            expected["Keychain.plist"] = keychain
            for (name, bytes) in expected { XCTAssertEqual(try Data(contentsOf: contents.appendingPathComponent(name)), bytes) }
            let entries = try XCTUnwrap(FileManager.default.enumerator(at: unpacked, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL])
            let names = try entries.filter { try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true }
                .map { String($0.path.dropFirst(unpacked.path.count + 1)) }
            let expectedNames = Set(expected.keys.map { "Voice Chat Data/" + $0 }).union(["Voice Chat Data/Manifest.json"])
            XCTAssertEqual(Set(names), expectedNames)
            #endif
            let attachment = XCTAttachment(contentsOfFile: archive.url)
            attachment.name = "raw-export-validation.zip"
            attachment.lifetime = .keepAlways
            add(attachment)
            for (name, bytes) in files { XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent(name)), bytes) }
            archive.discard()
            XCTAssertFalse(FileManager.default.fileExists(atPath: archive.url.deletingLastPathComponent().path))
        }
    }

    func testRawExportReadsAllRealKeychainItems() throws {
        let service = "ExportValidation-" + UUID().uuidString
        let credentials = ["first": "synthetic-secret-1", "second": "synthetic-secret-2"]
        defer {
            for account in credentials.keys {
                XCTAssertNoThrow(try KeychainStore.delete(service: service, account: account).get())
            }
        }
        let empty = try RawDataExport.keychainSnapshot(service: service)
        XCTAssertEqual(try PropertyListSerialization.propertyList(from: empty, format: nil) as? [String], [])
        for (account, value) in credentials {
            try KeychainStore.saveString(value, service: service, account: account).get()
        }
        let snapshot = try RawDataExport.keychainSnapshot(service: service)
        let decoded = try XCTUnwrap(PropertyListSerialization.propertyList(from: snapshot, format: nil) as? [[String: Any]])
        XCTAssertEqual(decoded.count, credentials.count)
        for item in decoded {
            XCTAssertEqual(Set(item.keys), Set([kSecAttrService as String, kSecAttrAccount as String, kSecValueData as String]))
            XCTAssertEqual(item[kSecAttrService as String] as? String, service)
            let account = try XCTUnwrap(item[kSecAttrAccount as String] as? String)
            let expected = try XCTUnwrap(credentials[account])
            XCTAssertEqual(item[kSecValueData as String] as? Data, Data(expected.utf8))
        }
    }

    func testResetRemovesDamagedSelectionAndAllStoresWithoutReadingThem() throws {
        try withFixture { fixture in
            let manager = FileManager.default
            let selection = fixture.root.appendingPathComponent("recovered-store.json")
            let recovery = fixture.root.appendingPathComponent("DataRecovery")
            let previous = recovery.appendingPathComponent(UUID().uuidString)
            try manager.createDirectory(at: previous, withIntermediateDirectories: true)
            try Data("damaged selection".utf8).write(to: selection)
            try Data([0, 255]).write(to: previous.appendingPathComponent("recovered.store"))
            for suffix in ["-wal", "-shm"] {
                try Data([0, 255]).write(to: URL(fileURLWithPath: fixture.source.path + suffix))
            }
            let unrelated = fixture.root.appendingPathComponent("unrelated.txt")
            try Data("keep".utf8).write(to: unrelated)

            try StartupPersistentStore.reset(defaultStoreURL: fixture.source)

            for url in [fixture.source, selection, recovery] {
                XCTAssertFalse(manager.fileExists(atPath: url.path))
            }
            for suffix in ["-wal", "-shm"] {
                XCTAssertFalse(manager.fileExists(atPath: fixture.source.path + suffix))
            }
            XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
            let container = try StartupPersistentStore.open(at: fixture.source)
            let context = ModelContext(container)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ChatMessage>()), 0)
            context.insert(ChatSession(title: "After reset"))
            try context.save()
            try container.erase()
        }
    }

    func testMissingLegacyColumnsUseDefaultsWithoutLosingRecords() throws {
        try withFixture { fixture in
            try fixture.sql("ALTER TABLE ZAPPSETTINGS DROP COLUMN ZMODELTHINKINGPREFERENCESJSON")
            try fixture.sql("ALTER TABLE ZAPPSETTINGS DROP COLUMN ZDETECTEDAPIFORMATSJSON")
            try fixture.sql("ALTER TABLE ZCHATMESSAGE DROP COLUMN ZOUTPUTTOKENCOUNT")
            try fixture.sql("ALTER TABLE ZCHATMESSAGE DROP COLUMN ZREASONINGOUTPUTTOKENCOUNT")
            let plan = try fixture.prepare()
            XCTAssertEqual(try category("ChatMessage", in: plan).recovered, 3)
            try inspect(plan) { context in
                let answer = try XCTUnwrap(context.fetch(FetchDescriptor<ChatMessage>()).first { !$0.isUser })
                XCTAssertEqual(answer.assistantText, "Readable answer")
                XCTAssertNil(answer.outputTokenCount)
            }
        }
    }

    func testCorruptedSQLitePageSalvagesRowsOnBothSides() throws {
        try withFixture(extraMessages: 240) { fixture in
            let pageSize = try fixture.integer("PRAGMA page_size")
            let rootPage = try fixture.integer("SELECT rootpage FROM sqlite_master WHERE name='ZCHATMESSAGE'")
            // SwiftData assigns primary keys at save time, not insertion order.
            let firstContent = try fixture.text("SELECT ZCONTENT FROM ZCHATMESSAGE WHERE ZCONTENT LIKE 'Bulk %' ORDER BY Z_PK LIMIT 1")
            let lastContent = try fixture.text("SELECT ZCONTENT FROM ZCHATMESSAGE WHERE ZCONTENT LIKE 'Bulk %' ORDER BY Z_PK DESC LIMIT 1")
            var bytes = try Data(contentsOf: fixture.source)
            let leaves = tableLeaves(in: bytes, page: rootPage, pageSize: pageSize)
            XCTAssertGreaterThan(leaves.count, 4)
            let damagedPage = leaves[leaves.count / 2]
            bytes[(damagedPage - 1) * pageSize] = 0
            try bytes.write(to: fixture.source)
            let plan = try fixture.prepare()
            let messages = try category("ChatMessage", in: plan)
            XCTAssertTrue(messages.hasUnknownLoss)
            XCTAssertGreaterThan(messages.recovered, 100)
            XCTAssertLessThan(messages.recovered, 243)
            XCTAssertEqual(try category("AppSettings", in: plan).recovered, 1)
            try inspect(plan) { context in
                let contents = try context.fetch(FetchDescriptor<ChatMessage>()).map(\.content)
                XCTAssertTrue(contents.contains(firstContent))
                XCTAssertTrue(contents.contains(lastContent))
            }
            print("RECOVERY_PAGE_RESULT recovered=\(messages.recovered)/243 damagedPage=\(damagedPage) leafPages=\(leaves.count)")
        }
    }

    func testCancelledPreviewDoesNotModifySourceAndCanBeRepeated() throws {
        try withFixture { fixture in
            try fixture.sql("UPDATE ZCHATMESSAGE SET ZTOKENCOUNT='bad' WHERE ZISUSER=0")
            let original = try Data(contentsOf: fixture.source)
            for _ in 0..<3 {
                let plan = try fixture.prepare()
                XCTAssertEqual(plan.recoveredCount, 11)
                plan.discard()
                XCTAssertFalse(FileManager.default.fileExists(atPath: plan.directory.path))
                XCTAssertEqual(try Data(contentsOf: fixture.source), original)
            }
        }
    }

    func testUnreadableDatabaseDoesNotOfferEmptyRecoveryAsUsableData() throws {
        try withFixture { fixture in
            let bytes = Data(repeating: 0x41, count: 4096)
            try bytes.write(to: fixture.source)
            do {
                let plan = try fixture.prepare()
                XCTAssertEqual(plan.recoveredCount, 0)
                XCTAssertTrue(plan.categories.allSatisfy(\.hasUnknownLoss))
            } catch {
                XCTAssertEqual((error as NSError).domain, "RecoverySQLite")
            }
            XCTAssertEqual(try Data(contentsOf: fixture.source), bytes)
        }
    }

    private func category(_ id: String, in plan: DataRecoveryPlan) throws -> DataRecoveryCategory {
        try XCTUnwrap(plan.categories.first { $0.id == id })
    }

    private func inspect(_ plan: DataRecoveryPlan, body: (ModelContext) throws -> Void) throws {
        try autoreleasepool {
            let context = ModelContext(plan.container)
            context.autosaveEnabled = false
            try body(context)
        }
    }

    private func withFixture(extraMessages: Int = 0, body: (Fixture) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RecoveryTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = Fixture(root: root)
        defer {
            for plan in fixture.plans where FileManager.default.fileExists(atPath: plan.directory.path) { plan.discard() }
            do { try FileManager.default.removeItem(at: root) }
            catch { XCTFail("Fixture cleanup failed: \(error)") }
        }
        try fixture.populate(extraMessages: extraMessages)
        try body(fixture)
    }

    // Table b-tree traversal follows https://sqlite.org/fileformat2.html#b_tree_pages.
    private func tableLeaves(in bytes: Data, page: Int, pageSize: Int) -> [Int] {
        let base = (page - 1) * pageSize
        let header = base + (page == 1 ? 100 : 0)
        func integer(_ offset: Int, _ count: Int) -> Int {
            bytes[offset..<(offset + count)].reduce(0) { ($0 << 8) | Int($1) }
        }
        if bytes[header] == 13 { return [page] }
        guard bytes[header] == 5 else { return [] }
        var children = (0..<integer(header + 3, 2)).map { index in
            integer(base + integer(header + 12 + index * 2, 2), 4)
        }
        children.append(integer(header + 8, 4))
        return children.flatMap { tableLeaves(in: bytes, page: $0, pageSize: pageSize) }
    }

    @MainActor
    private final class Fixture {
        let root: URL
        var plans: [DataRecoveryPlan] = []
        var source: URL { root.appendingPathComponent("source.store") }
        static let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXioAAAAASUVORK5CYII=")!

        init(root: URL) { self.root = root }

        func prepare() throws -> DataRecoveryPlan {
            let plan = try StartupDataRecovery.prepare(sourceURL: source, recoveryDirectory: root.appendingPathComponent("Recovery"))
            plans.append(plan)
            return plan
        }

        func populate(extraMessages: Int) throws {
            let working = root.appendingPathComponent("working.store")
            let container = try StartupPersistentStore.open(at: working)
            defer {
                do { try container.erase() }
                catch { XCTFail("Fixture store cleanup failed: \(error)") }
            }
            try autoreleasepool {
                let context = ModelContext(container)
                context.autosaveEnabled = false
                let session = ChatSession(title: "Recovery validation chat")
                context.insert(session)
                let question = ChatMessage(content: "First question", isUser: true, session: session)
                context.insert(question)
                let answer = ChatMessage(
                    content: "Readable answer", assistantSegments: [ChatAssistantSegment(kind: .text, text: "Readable answer")],
                    imageAttachments: [ChatImageAttachment(mimeType: "image/png", data: Self.image)],
                    isUser: false, modelIdentifier: "fixture-model", outputTokenCount: 12, tokenCount: 12,
                    toolActivityPlacements: [ChatToolActivityPlacement(
                        activity: ChatToolActivity(id: "tool-1", toolName: "calendar", title: "Readable tool", phase: .succeeded),
                        scope: .body, offset: 0, assistantSegmentAnchor: ChatAssistantSegmentAnchor(segmentIndex: 0, characterOffset: 0)
                    )], session: session, parentMessage: question
                )
                context.insert(answer)
                let followup = ChatMessage(content: "Second question", isUser: true, session: session, parentMessage: answer)
                context.insert(followup)
                session.activeRootMessageID = question.id
                question.activeChildMessageID = answer.id
                answer.activeChildMessageID = followup.id
                let preset = SystemPromptPreset(name: "Recovery prompt", mode: "normal", normalPrompt: "Normal prompt", voicePrompt: "Voice prompt")
                context.insert(preset)
                let voicePrompt = SystemPromptPreset(name: "Voice prompt fixture", mode: "voice", voicePrompt: "Selected voice prompt")
                context.insert(voicePrompt)
                let settings = AppSettings(selectedModel: "fixture-model", selectedNormalSystemPromptPresetID: preset.id, selectedVoiceSystemPromptPresetID: voicePrompt.id)
                try ChatModelCapabilityStore(thinkingPreferences: ["https://chat.example.test|fixture-model": .high]).savePreferences(to: settings)
                context.insert(settings)
                context.insert(ChatServerPreset(name: "Chat fixture", apiURL: "https://chat.example.test", selectedModel: "fixture-model"))
                context.insert(VoiceServerPreset(name: "Voice server fixture", serverAddress: "https://voice.example.test"))
                context.insert(VoicePreset(name: "Voice fixture", promptText: "Voice reference"))
                context.insert(ChatRequestContextMetadata(snapshot: ChatRequestContextSnapshot(
                    fingerprint: "fixture-context", version: 1, modelIdentifier: "fixture-model", endpointURLHash: "endpoint", providerRawValue: "openAI",
                    requestStyleRawValue: "chatCompletions", developerPromptHash: "prompt", developerPromptCharacterCount: 12,
                    thinkingOptionRawValue: nil, toolUseEnabled: true, enabledToolIDsJSON: "[\"calendar\"]", toolSchemaDigest: "schema",
                    toolSchemaSummaryJSON: "{}", toolAuthorizationModeRawValue: "readOnly", allowHighRiskToolAutoExecution: false, useProviderContinuationIDs: false
                )))
                for index in 0..<extraMessages {
                    context.insert(ChatMessage(content: String(format: "Bulk %03d ", index) + String(repeating: "x", count: 1500), isUser: true, session: session))
                }
                try context.save()
            }
            // A read-only backup does not compete with Core Data's asynchronous
            // connection cleanup for the write lock required by VACUUM INTO.
            try database(at: working) { origin in
                var destination: OpaquePointer?
                guard sqlite3_open(source.path, &destination) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
                defer { sqlite3_close(destination) }
                guard let backup = sqlite3_backup_init(destination, "main", origin, "main") else { throw CocoaError(.fileReadUnknown) }
                let status = sqlite3_backup_step(backup, -1)
                let finish = sqlite3_backup_finish(backup)
                guard status == SQLITE_DONE, finish == SQLITE_OK,
                      sqlite3_exec(destination, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
                    throw CocoaError(.fileReadUnknown)
                }
            }
        }

        func sql(_ statement: String, at url: URL? = nil) throws {
            try database(at: url ?? source) { database in
                guard sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK else {
                    throw NSError(domain: "FixtureSQLite", code: Int(sqlite3_errcode(database)), userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
                }
            }
        }

        func integer(_ statement: String) throws -> Int {
            try database(at: source) { database in
                var query: OpaquePointer?
                guard sqlite3_prepare_v2(database, statement, -1, &query, nil) == SQLITE_OK else { throw CocoaError(.fileReadCorruptFile) }
                defer { sqlite3_finalize(query) }
                guard sqlite3_step(query) == SQLITE_ROW else { throw CocoaError(.fileReadCorruptFile) }
                return Int(sqlite3_column_int64(query, 0))
            }
        }

        func text(_ statement: String) throws -> String {
            try database(at: source) { database in
                var query: OpaquePointer?
                guard sqlite3_prepare_v2(database, statement, -1, &query, nil) == SQLITE_OK else { throw CocoaError(.fileReadCorruptFile) }
                defer { sqlite3_finalize(query) }
                guard sqlite3_step(query) == SQLITE_ROW, let value = sqlite3_column_text(query, 0) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return String(cString: value)
            }
        }

        private func database<T>(at url: URL, body: (OpaquePointer) throws -> T) throws -> T {
            var handle: OpaquePointer?
            let status = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil)
            defer { if let handle { sqlite3_close(handle) } }
            guard status == SQLITE_OK, let handle else { throw CocoaError(.fileReadUnknown) }
            return try body(handle)
        }
    }
}
