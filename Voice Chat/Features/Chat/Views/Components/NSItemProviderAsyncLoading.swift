//
//  NSItemProviderAsyncLoading.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation
import UniformTypeIdentifiers

@MainActor
extension NSItemProvider {
    func loadDataRepresentationAsync(forTypeIdentifier typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    func loadFileURLAsync() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let text = item as? String,
                          let url = URL(string: text) {
                    continuation.resume(returning: url)
                } else if let text = item as? NSString,
                          let url = URL(string: text as String) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }
}
