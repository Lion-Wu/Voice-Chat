//
//  ChatServerPreset.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation
import SwiftData

@Model
final class ChatServerPreset {
    var id: UUID
    var name: String

    var apiURL: String
    var selectedModel: String
    var apiFormatPreferenceRaw: String?

    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        apiURL: String = "",
        selectedModel: String = "",
        apiFormatPreferenceRaw: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.apiURL = apiURL
        self.selectedModel = selectedModel
        self.apiFormatPreferenceRaw = apiFormatPreferenceRaw
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
