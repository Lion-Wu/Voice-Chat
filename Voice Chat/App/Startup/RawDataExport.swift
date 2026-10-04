import Foundation
import Security

nonisolated struct RawDataExport {
    let url: URL

    /// Copies owned data without opening or interpreting a possibly damaged store.
    static func prepare(
        sources: [String: URL], keychain: Data,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> RawDataExport {
        let manager = FileManager.default
        let directory = temporaryDirectory.appendingPathComponent("DataExport-" + UUID().uuidString)
        let contents = directory.appendingPathComponent("Voice Chat Data", isDirectory: true)
        try manager.createDirectory(at: contents, withIntermediateDirectories: true)
        var keepArchive = false
        defer {
            if !keepArchive { remove(directory) }
        }
        for (name, source) in sources.sorted(by: { $0.key < $1.key }) {
            if manager.fileExists(atPath: source.path) {
                let destination = contents.appendingPathComponent(name)
                try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try copyStoredFiles(from: source, to: destination)
            }
        }
        let manifest: [String: Any] = [
            "formatVersion": 1,
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "VoiceChat",
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "appBuild": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: contents.appendingPathComponent("Manifest.json"))
        try keychain.write(to: contents.appendingPathComponent("Keychain.plist"))
        let archive = directory.appendingPathComponent("Voice Chat Data.zip")
        var coordinationError: NSError?
        var copyResult: Result<Void, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: contents, options: .forUploading, error: &coordinationError) { snapshot in
            copyResult = Result { try manager.copyItem(at: snapshot, to: archive) }
        }
        if let coordinationError { throw coordinationError }
        try copyResult.get()
        try manager.removeItem(at: contents)
        keepArchive = true
        return RawDataExport(url: archive)
    }

    static func applicationSnapshot() throws -> RawDataExport {
        let manager = FileManager.default
        let identifier = Bundle.main.bundleIdentifier ?? "VoiceChat"
        #if os(macOS)
        // Never archive shared home directories from an unsigned, unsandboxed build.
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard home.lastPathComponent == "Data", home.deletingLastPathComponent().lastPathComponent == identifier else {
            throw CocoaError(.fileReadNoPermission)
        }
        #endif
        var sources = StartupPersistentStore.exportSources()
        sources["Documents"] = try manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let keychain = try keychainSnapshot(service: identifier)
        return try prepare(sources: sources, keychain: keychain)
    }

    static func keychainSnapshot(service: String) throws -> Data {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
            kSecReturnPersistentRef: true
        ] as CFDictionary, &result)
        if status == errSecItemNotFound {
            return try PropertyListSerialization.data(fromPropertyList: [], format: .xml, options: 0)
        }
        guard status == errSecSuccess else { throw KeychainStoreError(status: status) }
        guard let items = result as? [[String: Any]] else { throw KeychainStoreError(status: errSecDecode) }
        // macOS password queries cannot combine all matches with returned data.
        // Persistent references identify exact records during this read only.
        let records: [[String: Any]] = try items.map { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  let reference = item[kSecValuePersistentRef as String] as? Data else {
                throw KeychainStoreError(status: errSecDecode)
            }
            var value: CFTypeRef?
            let readStatus = SecItemCopyMatching([
                kSecValuePersistentRef: reference,
                kSecMatchLimit: kSecMatchLimitOne,
                kSecReturnData: true
            ] as CFDictionary, &value)
            guard readStatus == errSecSuccess else { throw KeychainStoreError(status: readStatus) }
            guard let data = value as? Data else { throw KeychainStoreError(status: errSecDecode) }
            return [
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data
            ]
        }
        return try PropertyListSerialization.data(fromPropertyList: records, format: .xml, options: 0)
    }

    func discard() { Self.remove(url.deletingLastPathComponent()) }

    private static func copyStoredFiles(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        // Sandbox Library links point to system-managed locations outside the
        // app's stored data. Never follow them into the export.
        guard values.isSymbolicLink != true else { return }
        if values.isDirectory == true {
            try manager.createDirectory(at: destination, withIntermediateDirectories: true)
            for child in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey]) {
                try copyStoredFiles(from: child, to: destination.appendingPathComponent(child.lastPathComponent))
            }
        } else {
            try manager.copyItem(at: source, to: destination)
        }
    }

    private static func remove(_ directory: URL) {
        do { try FileManager.default.removeItem(at: directory) }
        catch { print("Could not remove data export: \(error)") }
    }
}
