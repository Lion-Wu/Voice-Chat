import XCTest
@testable import Voice_Chat

final class ChatAPIKeyStoreTests: XCTestCase {
    func testStoresTrimmedKeyUsingPresetScopedAccount() throws {
        let presetID = UUID()
        var saved: [(value: String, service: String, account: String)] = []
        let store = ChatAPIKeyStore(
            service: "test.service",
            loadString: { _, _ in nil },
            saveString: { value, service, account in
                saved.append((value, service, account))
                return .success(())
            },
            deleteString: { _, _ in .success(()) }
        )

        store.save("  secret-token  ", for: presetID)

        let write = try XCTUnwrap(saved.first)
        XCTAssertEqual(write.value, "secret-token")
        XCTAssertEqual(write.service, "test.service")
        XCTAssertEqual(write.account, store.account(forChatServerPresetID: presetID))
    }

    func testEmptyKeyDeletesExistingPresetAccount() throws {
        let presetID = UUID()
        var deleted: [(service: String, account: String)] = []
        let store = ChatAPIKeyStore(
            service: "test.service",
            loadString: { _, _ in "existing-token" },
            saveString: { _, _, _ in
                XCTFail("empty API keys should delete instead of save")
                return .failure(KeychainStoreError(status: -1))
            },
            deleteString: { service, account in
                deleted.append((service, account))
                return .success(())
            }
        )

        store.save("   ", for: presetID)

        let deletion = try XCTUnwrap(deleted.first)
        XCTAssertEqual(deletion.service, "test.service")
        XCTAssertEqual(deletion.account, store.account(forChatServerPresetID: presetID))
    }

    func testIdenticalCanonicalKeyDoesNotWriteOrDelete() {
        let presetID = UUID()
        var saveCount = 0
        var deleteCount = 0
        let store = ChatAPIKeyStore(
            service: "test.service",
            loadString: { _, _ in "  unchanged-token\n" },
            saveString: { _, _, _ in saveCount += 1; return .success(()) },
            deleteString: { _, _ in deleteCount += 1; return .success(()) }
        )

        XCTAssertFalse(store.save("unchanged-token", for: presetID))
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(deleteCount, 0)
    }

    func testEmptyKeyAlwaysIssuesVerifiedDelete() {
        let presetID = UUID()
        var deleteCount = 0
        let store = ChatAPIKeyStore(
            service: "test.service",
            loadString: { _, _ in nil },
            saveString: { _, _, _ in
                XCTFail("empty API key must not be saved")
                return .failure(KeychainStoreError(status: -1))
            },
            deleteString: { _, _ in deleteCount += 1; return .success(()) }
        )

        XCTAssertTrue(store.save("   ", for: presetID))
        XCTAssertEqual(deleteCount, 1)
    }

    func testLoadsTrimmedKeyAndIgnoresMissingSelection() {
        let presetID = UUID()
        var requestedAccounts: [String] = []
        let store = ChatAPIKeyStore(
            service: "test.service",
            loadString: { _, account in
                requestedAccounts.append(account)
                return "  loaded-token\n"
            },
            saveString: { _, _, _ in .success(()) },
            deleteString: { _, _ in .success(()) }
        )

        XCTAssertEqual(store.load(for: presetID), "loaded-token")
        XCTAssertEqual(requestedAccounts, [store.account(forChatServerPresetID: presetID)])
        XCTAssertEqual(store.load(for: nil), "")
    }

    func testWriteReportsKeychainFailure() {
        let presetID = UUID()
        let store = ChatAPIKeyStore(
            service: "test.service",
            loadString: { _, _ in nil },
            saveString: { _, _, _ in .failure(KeychainStoreError(status: -50)) },
            deleteString: { _, _ in .failure(KeychainStoreError(status: -50)) }
        )

        guard case .failed(let failure) = store.write("new-token", for: presetID) else {
            return XCTFail("Expected a Keychain write failure")
        }
        XCTAssertTrue(
            failure.localizedDescription.hasPrefix(
                String(localized: "The API key could not be saved.")
            )
        )
        XCTAssertEqual(
            failure.reason,
            KeychainStoreError(status: -50).localizedDescription
        )
    }
}
