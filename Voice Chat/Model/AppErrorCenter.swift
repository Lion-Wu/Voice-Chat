//
//  AppErrorCenter.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2025/03/10.
//

import Foundation
import SwiftUI

/// Lightweight value used by the UI to render error notices without blocking the user.
struct AppErrorNotice: Identifiable, Equatable {
    enum Category: String {
        case textModel
        case tts
        case realtimeVoice
    }

    enum Severity {
        case banner
        case critical
    }

    let id: UUID
    let title: String
    let message: String
    let category: Category
    let timestamp: Date
    let severity: Severity

    var iconName: String {
        switch category {
        case .textModel: return "network.slash"
        case .tts: return "waveform.badge.exclamationmark"
        case .realtimeVoice: return "mic.slash"
        }
    }

    var tint: Color {
        switch category {
        case .textModel: return .orange
        case .tts: return .red
        case .realtimeVoice: return .pink
        }
    }
}

@MainActor
final class AppErrorCenter: ObservableObject {
    static let shared = AppErrorCenter()

    @Published private(set) var notices: [AppErrorNotice] = []
    @Published private(set) var dismissedCategories: Set<AppErrorNotice.Category> = []

    private var dismissTasks: [UUID: Task<Void, Never>] = [:]
    private let maxItems: Int = 4
    private let noticeAnimation = Animation.spring(response: 0.35, dampingFraction: 0.9)

    private init() {}

    /// Pushes a new notice to the stack (replaces existing notice of the same category).
    func publish(title: String,
                 message: String,
                 category: AppErrorNotice.Category,
                 severity: AppErrorNotice.Severity = .banner,
                 autoDismiss: TimeInterval = 8) {
        guard !dismissedCategories.contains(category) else { return }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = finalTitle.isEmpty ? defaultTitle(for: category) : finalTitle
        let notice: AppErrorNotice

        if let idx = notices.firstIndex(where: { $0.category == category }) {
            let existing = notices[idx]
            notice = AppErrorNotice(
                id: existing.id,
                title: resolvedTitle,
                message: trimmedMessage,
                category: category,
                timestamp: Date(),
                severity: severity
            )
            withAnimation(noticeAnimation) {
                notices[idx] = notice
            }
        } else {
            notice = AppErrorNotice(
                id: UUID(),
                title: resolvedTitle,
                message: trimmedMessage,
                category: category,
                timestamp: Date(),
                severity: severity
            )
            withAnimation(noticeAnimation) {
                notices.insert(notice, at: 0)
            }
            pruneIfNeeded()
        }

        scheduleAutoDismiss(for: notice.id, after: autoDismiss)
    }

    func dismiss(_ notice: AppErrorNotice) {
        dismiss(byID: notice.id)
        dismissedCategories.insert(notice.category)
    }

    func clear(category: AppErrorNotice.Category? = nil) {
        let removedIDs: [UUID]
        if let category {
            removedIDs = notices
                .filter { $0.category == category }
                .map(\.id)
            withAnimation(noticeAnimation) {
                notices.removeAll { $0.category == category }
            }
            dismissedCategories.remove(category)
        } else {
            removedIDs = notices.map(\.id)
            withAnimation(noticeAnimation) {
                notices.removeAll()
            }
            dismissedCategories.removeAll()
        }
        for id in removedIDs {
            dismissTasks[id]?.cancel()
            dismissTasks[id] = nil
        }
    }

    private func scheduleAutoDismiss(for id: UUID, after interval: TimeInterval) {
        guard interval > 0 else { return }
        dismissTasks[id]?.cancel()
        dismissTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            await MainActor.run {
                self?.dismiss(byID: id)
            }
        }
    }

    private func dismiss(byID id: UUID) {
        withAnimation(noticeAnimation) {
            notices.removeAll { $0.id == id }
        }
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
    }

    private func pruneIfNeeded() {
        if notices.count > maxItems {
            let overflow = notices.suffix(from: maxItems)
            for item in overflow {
                dismissTasks[item.id]?.cancel()
            }
            withAnimation(noticeAnimation) {
                notices = Array(notices.prefix(maxItems))
            }
        }
    }

    private func defaultTitle(for category: AppErrorNotice.Category) -> String {
        switch category {
        case .textModel:
            return NSLocalizedString("Text Generation Issue", comment: "Fallback title when the LLM/text server is unavailable")
        case .tts:
            return NSLocalizedString("Voice Playback Issue", comment: "Fallback title when TTS or audio playback fails")
        case .realtimeVoice:
            return NSLocalizedString("Realtime Voice Issue", comment: "Fallback title when realtime voice mode fails")
        }
    }

    func isDismissed(for category: AppErrorNotice.Category) -> Bool {
        dismissedCategories.contains(category)
    }

    func publishCritical(title: String, message: String, category: AppErrorNotice.Category) {
        publish(title: title, message: message, category: category, severity: .critical, autoDismiss: 0)
    }
}
