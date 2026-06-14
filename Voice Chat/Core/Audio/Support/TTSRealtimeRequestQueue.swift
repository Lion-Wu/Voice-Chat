//
//  TTSRealtimeRequestQueue.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import Foundation

struct TTSRealtimeRequestQueue: Equatable, Sendable {
    private(set) var pendingIndexes: [Int]

    init(pendingIndexes: [Int] = []) {
        self.pendingIndexes = pendingIndexes
    }

    var isEmpty: Bool {
        pendingIndexes.isEmpty
    }

    mutating func removeAll() {
        pendingIndexes.removeAll()
    }

    @discardableResult
    mutating func queue(
        index: Int,
        segmentCount: Int,
        loadedIndexes: Set<Int>,
        skippedIndexes: Set<Int>,
        atFront: Bool = false
    ) -> Bool {
        guard index >= 0, index < segmentCount else { return false }
        guard !loadedIndexes.contains(index) else { return false }
        guard !skippedIndexes.contains(index) else { return false }

        if let existing = pendingIndexes.firstIndex(of: index) {
            if atFront && existing != pendingIndexes.startIndex {
                pendingIndexes.remove(at: existing)
                pendingIndexes.insert(index, at: pendingIndexes.startIndex)
                return true
            }
            return false
        }

        if atFront {
            pendingIndexes.insert(index, at: pendingIndexes.startIndex)
        } else {
            pendingIndexes.append(index)
        }
        return true
    }

    mutating func dequeueNextValidIndex(segmentCount: Int) -> Int? {
        while !pendingIndexes.isEmpty {
            let next = pendingIndexes.removeFirst()
            if next >= 0 && next < segmentCount {
                return next
            }
        }
        return nil
    }
}
