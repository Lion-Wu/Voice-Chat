//
//  VoiceServerPreset.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation
import SwiftData

@Model
final class VoiceServerPreset {
    var id: UUID
    var name: String

    var serverAddress: String

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        serverAddress: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.serverAddress = serverAddress
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
