//
//  SystemPromptPreset.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation
import SwiftData

@Model
final class SystemPromptPreset {
    var id: UUID
    var name: String

    /// Which mode this preset belongs to ("normal" / "voice").
    /// Nil means the preset was created before mode separation was introduced.
    var mode: String?

    /// Prompt used for normal (text) chat requests.
    var normalPrompt: String
    /// Prompt used for voice (realtime) chat requests.
    var voicePrompt: String

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        mode: String? = nil,
        normalPrompt: String = "",
        voicePrompt: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.mode = mode
        self.normalPrompt = normalPrompt
        self.voicePrompt = voicePrompt
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
