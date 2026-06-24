//
//  DeviceContextTool.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

protocol DeviceContextToolServing: Sendable {
    func deviceContext(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload
}

struct SystemDeviceContextTool: DeviceContextToolServing {
    func deviceContext(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        var payload: [String: JSONValue] = [
            "locale": .string(Locale.autoupdatingCurrent.identifier),
            "timezone": .string(TimeZone.autoupdatingCurrent.identifier),
            "low_power_mode_enabled": .bool(ProcessInfo.processInfo.isLowPowerModeEnabled),
            "os_version": .string(ProcessInfo.processInfo.operatingSystemVersionString)
        ]

        #if os(iOS)
        payload["platform"] = .string("iOS")
        #elseif os(macOS)
        payload["platform"] = .string("macOS")
        #elseif os(visionOS)
        payload["platform"] = .string("visionOS")
        #else
        payload["platform"] = .string("unknown")
        #endif

        #if canImport(UIKit) && !os(visionOS)
        await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            if level >= 0 {
                payload["battery_level"] = .number(Double(level))
            }
            payload["device_model"] = .string(UIDevice.current.model)
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
        #endif

        return ChatToolExecutionPayload(
            payload: payload,
            summary: NSLocalizedString("Device context was read.", comment: "Tool summary")
        )
    }
}
