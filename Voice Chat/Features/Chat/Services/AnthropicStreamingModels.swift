//
//  AnthropicStreamingModels.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

/// Anthropic SSE event model (`/v1/messages`).
struct AnthropicStreamEvent: Decodable {
    let type: String?
    let delta: AnthropicStreamDelta?
    let content_block: AnthropicStreamContentBlock?
    let message: AnthropicStreamMessage?
    let usage: AnthropicStreamUsage?
    let error: AnthropicStreamErrorPayload?
}

struct AnthropicStreamDelta: Decodable {
    let type: String?
    let text: String?
    let thinking: String?
    let stop_reason: String?
}

struct AnthropicStreamContentBlock: Decodable {
    let type: String?
    let text: String?
    let thinking: String?
}

struct AnthropicStreamErrorPayload: Decodable {
    let type: String?
    let message: String?
}

struct AnthropicStreamUsage: Decodable {
    let output_tokens: Int?
}

struct AnthropicStreamMessage: Decodable {
    let id: String?
    let stop_reason: String?
    let usage: AnthropicStreamUsage?
}
