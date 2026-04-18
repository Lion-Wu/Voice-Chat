//
//  ContentFingerprint.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2025/03/28.
//

import Foundation

/// Lightweight fingerprint used to compare message content efficiently.
struct ContentFingerprint: Equatable, Sendable {
    let utf16Count: Int
    let hash: UInt64

    private static let fnvOffsetBasis: UInt64 = 0xcbf29ce484222325
    private static let fnvPrime: UInt64 = 0x100000001b3

    static func make(_ s: String) -> ContentFingerprint {
        let (hash, count) = fnv1aHashUTF16(s, startingWith: fnvOffsetBasis)
        return .init(utf16Count: count, hash: hash)
    }

    func appending(_ delta: String) -> ContentFingerprint {
        let (hash, addedCount) = Self.fnv1aHashUTF16(delta, startingWith: hash)
        return .init(utf16Count: utf16Count + addedCount, hash: hash)
    }

    private static func fnv1aHashUTF16(_ s: String, startingWith seed: UInt64) -> (UInt64, Int) {
        var h = seed
        var count = 0
        for unit in s.utf16 {
            count += 1
            let low = UInt8(truncatingIfNeeded: unit)
            let high = UInt8(truncatingIfNeeded: unit >> 8)
            h ^= UInt64(low)
            h &*= fnvPrime
            h ^= UInt64(high)
            h &*= fnvPrime
        }
        return (h, count)
    }
}
