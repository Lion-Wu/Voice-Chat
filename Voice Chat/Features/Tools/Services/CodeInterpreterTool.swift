//
//  CodeInterpreterTool.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.24.
//

import Foundation

protocol CodeInterpreterToolServing: Sendable {
    func run(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload
}

struct SandboxedCodeInterpreterTool: CodeInterpreterToolServing {
    func run(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        let code = try arguments.requiredString("code")
        let input = try arguments.jsonObject("input") ?? [:]
        let result = try await CodeInterpreterRuntime.evaluate(code: code, input: input)
        return ChatToolExecutionPayload(
            payload: [
                "result": result.value.jsonValue,
                "result_type": .string(result.value.typeName),
                "truncated": .bool(result.truncated)
            ],
            summary: NSLocalizedString("JavaScript code was evaluated.", comment: "Tool summary")
        )
    }
}
