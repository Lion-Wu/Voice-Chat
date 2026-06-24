//
//  CoreMotionTool.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation
#if canImport(CoreMotion)
import CoreMotion
#endif

protocol MotionToolServing: Sendable {
    func deviceMotion(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload
}

struct CoreMotionTool: MotionToolServing {
    func deviceMotion(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        #if canImport(CoreMotion) && (os(iOS) || os(visionOS))
        let duration = arguments.double("duration_seconds", default: 1.0, range: 0.2...3.0)
        let manager = CMMotionManager()
        guard manager.isDeviceMotionAvailable else {
            throw ChatToolError.unsupported(NSLocalizedString("Device motion is not available on this platform.", comment: "Tool-use error"))
        }
        manager.deviceMotionUpdateInterval = 0.1
        manager.startDeviceMotionUpdates()
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        let motion = manager.deviceMotion
        manager.stopDeviceMotionUpdates()

        guard let motion else {
            throw ChatToolError.failed(NSLocalizedString("No device motion sample was received.", comment: "Tool-use error"))
        }
        return ChatToolExecutionPayload(
            payload: [
                "attitude": .object([
                    "roll": .number(motion.attitude.roll),
                    "pitch": .number(motion.attitude.pitch),
                    "yaw": .number(motion.attitude.yaw)
                ]),
                "rotation_rate": .object([
                    "x": .number(motion.rotationRate.x),
                    "y": .number(motion.rotationRate.y),
                    "z": .number(motion.rotationRate.z)
                ]),
                "gravity": .object([
                    "x": .number(motion.gravity.x),
                    "y": .number(motion.gravity.y),
                    "z": .number(motion.gravity.z)
                ]),
                "duration_seconds": .number(duration)
            ],
            summary: NSLocalizedString("Device motion snapshot was read.", comment: "Tool summary")
        )
        #else
        throw ChatToolError.unsupported(NSLocalizedString("Device motion is not available on this platform.", comment: "Tool-use error"))
        #endif
    }
}
