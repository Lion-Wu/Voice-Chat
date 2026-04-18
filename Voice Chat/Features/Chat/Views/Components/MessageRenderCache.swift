//
//  MessageRenderCache.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2025/03/28.
//

import Foundation

/// Caches expensive per-message derived values (e.g., think-part parsing) to avoid recomputation.
final class MessageRenderCache: @unchecked Sendable {
    static let shared = MessageRenderCache()

    private struct ThinkEntry {
        let fingerprint: ContentFingerprint
        let parts: ThinkParts
    }

    private let lock = NSLock()
    private var thinkPartsCache: [UUID: ThinkEntry] = [:]

    private init() {}

    func thinkParts(for messageID: UUID, content: String) -> ThinkParts {
        thinkParts(for: messageID, content: content, fingerprint: ContentFingerprint.make(content))
    }

    func thinkParts(for messageID: UUID, content: String, fingerprint: ContentFingerprint) -> ThinkParts {
        let fp = fingerprint

        lock.lock()
        if let cached = thinkPartsCache[messageID], cached.fingerprint == fp {
            lock.unlock()
            return cached.parts
        }
        lock.unlock()

        let parts = content.extractThinkParts()

        lock.lock()
        thinkPartsCache[messageID] = ThinkEntry(fingerprint: fp, parts: parts)
        lock.unlock()

        return parts
    }

    /// Precomputes think-part parsing for a batch to reduce perceived loading time on long sessions.
    func prewarmThinkParts(_ snapshots: [(UUID, String, ContentFingerprint)]) {
        for entry in snapshots {
            _ = thinkParts(for: entry.0, content: entry.1, fingerprint: entry.2)
        }
    }

    func clear() {
        lock.lock()
        thinkPartsCache.removeAll()
        lock.unlock()
    }
}
