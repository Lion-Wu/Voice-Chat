//
//  ChatReturnKeySendMonitor.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

#if os(macOS)
import AppKit

@MainActor
final class ChatReturnKeySendMonitor: ObservableObject {
    private var monitor: Any?

    func register(
        isInputFocused: @escaping () -> Bool,
        sendIfPossible: @escaping () -> Bool
    ) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            Self.handle(
                event,
                isInputFocused: isInputFocused,
                sendIfPossible: sendIfPossible
            )
        }
    }

    func unregister() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private static func handle(
        _ event: NSEvent,
        isInputFocused: () -> Bool,
        sendIfPossible: () -> Bool
    ) -> NSEvent? {
        let returnKeyCodes: Set<UInt16> = [36, 76]
        guard returnKeyCodes.contains(event.keyCode) else { return event }
        guard isInputFocused() else { return event }

        let modifierMask = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let blockingMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        if modifierMask.intersection(blockingMask).isEmpty {
            _ = sendIfPossible()
            return nil
        }

        return event
    }
}
#endif
