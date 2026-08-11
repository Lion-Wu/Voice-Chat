//
//  JavaScriptRuntimeTool.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.24.
//

import Foundation

protocol JavaScriptRuntimeToolServing: Sendable {
    func run(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload
}

struct SandboxedJavaScriptRuntimeTool: JavaScriptRuntimeToolServing {
    func run(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        let code = try arguments.requiredString("code")
        let input = try arguments.jsonObject("input") ?? [:]
        let result = try await JavaScriptRuntime.evaluate(code: code, input: input)
        var payload: [String: JSONValue] = [
            "result_type": .string(result.resultType),
            "output": .string(result.output),
            "truncated": .bool(result.truncated)
        ]
        if let value = result.value {
            payload["result"] = value.jsonValue
        }
        if let resultDisplay = result.resultDisplay {
            payload["result_display"] = .string(resultDisplay)
        }
        return ChatToolExecutionPayload(
            payload: payload,
            summary: NSLocalizedString("JavaScript code was evaluated.", comment: "Tool summary")
        )
    }
}
