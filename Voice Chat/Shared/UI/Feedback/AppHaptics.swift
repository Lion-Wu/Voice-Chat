//
//  AppHaptics.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2026/06/13.
//

import SwiftUI

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import UIKit
#endif

enum AppHapticEvent: Hashable {
    case selection
    case lightTap
    case success
    case successStrong
    case warning
    case error
}

@MainActor
protocol HapticFeedbackPolicy: AnyObject {
    var isHapticFeedbackEnabled: Bool { get }
}

@MainActor
final class StaticHapticFeedbackPolicy: HapticFeedbackPolicy {
    static let enabled = StaticHapticFeedbackPolicy(isEnabled: true)
    static let disabled = StaticHapticFeedbackPolicy(isEnabled: false)

    private let isEnabled: Bool

    private init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    var isHapticFeedbackEnabled: Bool {
        isEnabled
    }
}

@MainActor
enum AppHaptics {
    private static var feedbackPolicy: HapticFeedbackPolicy = StaticHapticFeedbackPolicy.enabled

#if os(iOS)
    private static let minimumGlobalInterval: TimeInterval = 0.05
    private static var lastTriggerAt: TimeInterval = 0
    private static var lastEvent: AppHapticEvent?

    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let tapGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let completionImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let completionTailGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
#endif

    static func configure(feedbackPolicy: HapticFeedbackPolicy) {
        self.feedbackPolicy = feedbackPolicy
    }

    static func resetFeedbackPolicy() {
        feedbackPolicy = StaticHapticFeedbackPolicy.enabled
    }

    static func trigger(_ event: AppHapticEvent) {
#if os(iOS)
        guard feedbackPolicy.isHapticFeedbackEnabled else { return }
        guard shouldTrigger(event: event) else { return }

        switch event {
        case .selection:
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        case .lightTap:
            tapGenerator.impactOccurred(intensity: 0.62)
            tapGenerator.prepare()
        case .success:
            notificationGenerator.notificationOccurred(.success)
            notificationGenerator.prepare()
        case .successStrong:
            triggerStrongSuccess()
        case .warning:
            notificationGenerator.notificationOccurred(.warning)
            notificationGenerator.prepare()
        case .error:
            notificationGenerator.notificationOccurred(.error)
            notificationGenerator.prepare()
        }
#else
        _ = event
#endif
    }

#if os(iOS)
    private static func shouldTrigger(event: AppHapticEvent) -> Bool {
        let now = Date().timeIntervalSinceReferenceDate
        let globalDelta = now - lastTriggerAt
        if globalDelta < minimumGlobalInterval {
            return false
        }
        if lastEvent == event, globalDelta < minimumInterval(for: event) {
            return false
        }
        lastTriggerAt = now
        lastEvent = event
        return true
    }

    private static func minimumInterval(for event: AppHapticEvent) -> TimeInterval {
        switch event {
        case .selection:
            return 0.08
        case .lightTap:
            return 0.14
        case .success:
            return 0.22
        case .successStrong:
            return 0.45
        case .warning, .error:
            return 0.24
        }
    }

    private static func triggerStrongSuccess() {
        completionImpactGenerator.impactOccurred(intensity: 0.92)
        completionImpactGenerator.prepare()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 115_000_000)
            guard feedbackPolicy.isHapticFeedbackEnabled else { return }
            completionTailGenerator.impactOccurred(intensity: 0.58)
            completionTailGenerator.prepare()
        }
    }
#endif
}
