//
//  ChatAPIKeyStore.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatAPIKeyStore {
    typealias Loader = (String, String) -> String?
    typealias Saver = (String, String, String) -> Bool
    typealias Deleter = (String, String) -> Bool

    enum WriteResult: Equatable {
        case unchanged
        case updated
        case failed
    }

    private static let accountPrefix = "chat_server_preset_api_key."

    private let service: String
    private let loadString: Loader
    private let saveString: Saver
    private let deleteString: Deleter

    init(
        service: String = Bundle.main.bundleIdentifier ?? "VoiceChat",
        loadString: @escaping Loader = { service, account in
            return KeychainStore.loadString(service: service, account: account)
        },
        saveString: @escaping Saver = { value, service, account in
            KeychainStore.saveString(value, service: service, account: account)
        },
        deleteString: @escaping Deleter = { service, account in
            KeychainStore.delete(service: service, account: account)
        }
    ) {
        self.service = service
        self.loadString = loadString
        self.saveString = saveString
        self.deleteString = deleteString
    }

    func account(forChatServerPresetID id: UUID) -> String {
        "\(Self.accountPrefix)\(id.uuidString)"
    }

    func load(for presetID: UUID?) -> String {
        guard let presetID else { return "" }
        return (loadString(service, account(forChatServerPresetID: presetID)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func save(_ apiKey: String, for presetID: UUID?) -> Bool {
        write(apiKey, for: presetID) == .updated
    }

    func write(_ apiKey: String, for presetID: UUID?) -> WriteResult {
        guard let presetID else { return .failed }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = account(forChatServerPresetID: presetID)

        // Always issue a delete for an empty target. A failed Keychain read is
        // indistinguishable from a missing item, while SecItemDelete already
        // treats item-not-found as success.
        if trimmed.isEmpty {
            return deleteString(service, account) ? .updated : .failed
        }

        let current = (loadString(service, account) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard current != trimmed else { return .unchanged }

        return saveString(trimmed, service, account) ? .updated : .failed
    }

    @discardableResult
    func delete(for presetID: UUID) -> Bool {
        deleteString(service, account(forChatServerPresetID: presetID))
    }
}
