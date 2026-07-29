//
//  ServerReachabilitySnapshot.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

struct ServerReachabilitySnapshot: Equatable, Sendable {
    var chatBaseURL: String
    var ttsBaseURL: String
    var requiresTTSNetworkService: Bool
}
