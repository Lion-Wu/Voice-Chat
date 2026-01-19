//
//  KeychainStore.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2026/01/19.
//

import Foundation
import Security

enum KeychainStore {
    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func loadString(service: String, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = kCFBooleanTrue

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            return nil
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func saveString(_ value: String, service: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        var addQuery = baseQuery(service: service, account: account)
        addQuery[kSecValueData as String] = data
#if os(iOS)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
#endif

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            return true
        }
        if status != errSecDuplicateItem {
            return false
        }

        let updateQuery = baseQuery(service: service, account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        return SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary) == errSecSuccess
    }

    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let query = baseQuery(service: service, account: account)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

