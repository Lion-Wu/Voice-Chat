//
//  ChatAPIKeyStore.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatAPIKeyStore {
    typealias Loader = (String, String) -> String?
    typealias Saver = (String, String, String) -> Result<Void, KeychainStoreError>
    typealias Deleter = (String, String) -> Result<Void, KeychainStoreError>

    struct WriteFailure: LocalizedError, Equatable {
        let reason: String?

        var errorDescription: String? {
            let base = String(localized: "The API key could not be saved.")
            guard let reason, !reason.isEmpty else { return base }
            return "\(base)\n\(reason)"
        }
    }

    enum WriteResult: Equatable {
        case unchanged
        case updated
        case failed(WriteFailure)

        var didUpdate: Bool {
            self == .updated
        }

        var failure: WriteFailure? {
            guard case .failed(let failure) = self else { return nil }
            return failure
        }
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
        guard let presetID else { return .failed(WriteFailure(reason: nil)) }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = account(forChatServerPresetID: presetID)

        // Always issue a delete for an empty target. A failed Keychain read is
        // indistinguishable from a missing item, while SecItemDelete already
        // treats item-not-found as success.
        if trimmed.isEmpty {
            switch deleteString(service, account) {
            case .success:
                return .updated
            case .failure(let error):
                return .failed(WriteFailure(reason: error.localizedDescription))
            }
        }

        let current = (loadString(service, account) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard current != trimmed else { return .unchanged }

        switch saveString(trimmed, service, account) {
        case .success:
            return .updated
        case .failure(let error):
            return .failed(WriteFailure(reason: error.localizedDescription))
        }
    }

    @discardableResult
    func delete(for presetID: UUID) -> Bool {
        switch deleteString(service, account(forChatServerPresetID: presetID)) {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}
