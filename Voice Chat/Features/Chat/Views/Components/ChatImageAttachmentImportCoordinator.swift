//
//  ChatImageAttachmentImportCoordinator.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

#if os(iOS) || os(macOS) || os(visionOS)
enum ChatImageAttachmentImportSource {
    case photoPicker
    case other
}

enum ChatImageAttachmentLimitDecision: Equatable {
    case rejected
    case accepted(limit: Int, didOverflow: Bool)
}

enum ChatImageAttachmentImportCompletion: Equatable {
    case apply(clearPhotoSelection: Bool)
    case stale
}

struct ChatImageAttachmentImportCoordinator {
    static let maximumAttachmentCount = ChatImageAttachmentLimits.maximumAttachmentCount

    private(set) var tasks: [UUID: Task<Void, Never>] = [:]
    private(set) var activePhotoImportID: UUID?

    static func remainingSlots(
        currentCount: Int,
        maximumAttachmentCount: Int = Self.maximumAttachmentCount
    ) -> Int {
        max(0, maximumAttachmentCount - currentCount)
    }

    static func limitDecision(
        requestedCount: Int,
        currentCount: Int,
        maximumAttachmentCount: Int = Self.maximumAttachmentCount
    ) -> ChatImageAttachmentLimitDecision {
        let remainingSlots = remainingSlots(
            currentCount: currentCount,
            maximumAttachmentCount: maximumAttachmentCount
        )
        guard remainingSlots > 0 else { return .rejected }
        return .accepted(
            limit: min(max(0, requestedCount), remainingSlots),
            didOverflow: requestedCount > remainingSlots
        )
    }

    mutating func beginImport(
        source: ChatImageAttachmentImportSource,
        cancelsEarlierPhotoImports: Bool,
        makeID: () -> UUID = UUID.init
    ) -> UUID {
        let importID = makeID()
        if cancelsEarlierPhotoImports, let activePhotoImportID {
            tasks[activePhotoImportID]?.cancel()
            tasks[activePhotoImportID] = nil
        }
        if source == .photoPicker {
            activePhotoImportID = importID
        }
        return importID
    }

    mutating func registerTask(_ task: Task<Void, Never>, id: UUID) {
        tasks[id] = task
    }

    mutating func finishCancelledImport(id: UUID) {
        if activePhotoImportID == id {
            activePhotoImportID = nil
        }
        tasks[id] = nil
    }

    mutating func clearActivePhotoImport() {
        activePhotoImportID = nil
    }

    mutating func completeImport(
        id: UUID,
        source: ChatImageAttachmentImportSource
    ) -> ChatImageAttachmentImportCompletion {
        defer { tasks[id] = nil }

        if source == .photoPicker {
            guard activePhotoImportID == id else { return .stale }
            activePhotoImportID = nil
            return .apply(clearPhotoSelection: true)
        }

        return .apply(clearPhotoSelection: false)
    }

    mutating func cancelAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
        activePhotoImportID = nil
    }
}
#endif
