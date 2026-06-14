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
            },
            deleteString: { _, _ in }
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
            loadString: { _, _ in nil },
            saveString: { _, _, _ in XCTFail("empty API keys should delete instead of save") },
            deleteString: { service, account in
                deleted.append((service, account))
            }
        )

        store.save("   ", for: presetID)

        let deletion = try XCTUnwrap(deleted.first)
        XCTAssertEqual(deletion.service, "test.service")
        XCTAssertEqual(deletion.account, store.account(forChatServerPresetID: presetID))
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
            saveString: { _, _, _ in },
            deleteString: { _, _ in }
        )

        XCTAssertEqual(store.load(for: presetID), "loaded-token")
        XCTAssertEqual(requestedAccounts, [store.account(forChatServerPresetID: presetID)])
        XCTAssertEqual(store.load(for: nil), "")
    }
}
