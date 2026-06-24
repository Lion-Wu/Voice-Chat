//
//  MCPClientTypes.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation

struct MCPServerConfiguration: Identifiable, Codable, Equatable, Sendable {
    enum Transport: String, Codable, Sendable {
        case streamableHTTP = "streamable_http"
        case stdio
    }

    var id: UUID
    var name: String
    var transport: Transport
    var endpointURL: URL?
    var command: String?
    var arguments: [String]
    var enabledToolNames: Set<String>?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        transport: Transport,
        endpointURL: URL? = nil,
        command: String? = nil,
        arguments: [String] = [],
        enabledToolNames: Set<String>? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.endpointURL = endpointURL
        self.command = command
        self.arguments = arguments
        self.enabledToolNames = enabledToolNames
        self.isEnabled = isEnabled
    }
}

struct MCPToolDescriptor: Equatable, Sendable {
    let serverID: UUID
    let name: String
    let description: String?
    let inputSchema: JSONValue
}

struct MCPToolInvocation: Equatable, Sendable {
    let serverID: UUID
    let toolName: String
    let arguments: [String: JSONValue]
}

struct MCPToolInvocationResult: Equatable, Sendable {
    let content: [JSONValue]
    let isError: Bool
}

protocol MCPClientServing: Sendable {
    func listTools(for server: MCPServerConfiguration) async throws -> [MCPToolDescriptor]
    func callTool(_ invocation: MCPToolInvocation, on server: MCPServerConfiguration) async throws -> MCPToolInvocationResult
}

enum MCPClientError: LocalizedError, Equatable {
    case disabled
    case unsupportedTransport(String)
    case invalidConfiguration(String)
    case connectionFailed(String)
    case protocolFailure(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return NSLocalizedString("MCP server is disabled.", comment: "MCP client error")
        case let .unsupportedTransport(transport):
            return String(format: NSLocalizedString("Unsupported MCP transport: %@", comment: "MCP client error"), transport)
        case let .invalidConfiguration(message),
             let .connectionFailed(message),
             let .protocolFailure(message):
            return message
        }
    }
}
