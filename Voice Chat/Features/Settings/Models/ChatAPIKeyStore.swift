//
//  ChatAPIKeyStore.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatAPIKeyStore {
    typealias Loader = (String, String) -> String?
    typealias Saver = (String, String, String) -> Void
    typealias Deleter = (String, String) -> Void

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
            _ = KeychainStore.saveString(value, service: service, account: account)
        },
        deleteString: @escaping Deleter = { service, account in
            _ = KeychainStore.delete(service: service, account: account)
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

    func save(_ apiKey: String, for presetID: UUID?) {
        guard let presetID else { return }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = account(forChatServerPresetID: presetID)

        if trimmed.isEmpty {
            deleteString(service, account)
        } else {
            saveString(trimmed, service, account)
        }
    }

    func delete(for presetID: UUID) {
        deleteString(service, account(forChatServerPresetID: presetID))
    }
}
