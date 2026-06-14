//
//  ChatEndpointBaseURL.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import Foundation

enum ChatEndpointBaseURL {
    static func normalizedComponents(from base: String) -> URLComponents? {
        var sanitized = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return nil }

        if !sanitized.contains("://") {
            sanitized = "http://\(sanitized)"
        }
        while sanitized.hasSuffix("/") {
            sanitized.removeLast()
        }
        return URLComponents(string: sanitized)
    }

    static func normalizedAPIBaseKey(_ base: String) -> String? {
        guard var comps = normalizedComponents(from: base) else { return nil }
        comps.path = canonicalPath(comps.path)
        return comps.url?.absoluteString.lowercased()
    }

    static func canonicalPath(_ path: String) -> String {
        var value = path
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if value == "/" {
            return ""
        }
        return value
    }

    static func joinPath(_ base: String, _ suffix: String) -> String {
        let normalizedBase = canonicalPath(base)
        if normalizedBase.isEmpty {
            return suffix.hasPrefix("/") ? suffix : "/\(suffix)"
        }
        if suffix.hasPrefix("/") {
            return normalizedBase + suffix
        }
        return normalizedBase + "/" + suffix
    }

    static func isLocalHost(_ host: String) -> Bool {
        let normalized = host
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1" {
            return true
        }
        if normalized.hasSuffix(".local") {
            return true
        }
        if isPrivateIPv4Host(normalized) || isPrivateIPv6Host(normalized) {
            return true
        }
        return false
    }

    static func hostMatchesOfficialDomain(_ host: String, domain: String) -> Bool {
        if host == domain {
            return true
        }
        return host.hasSuffix(".\(domain)")
    }

    private static func isPrivateIPv4Host(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }

        switch (octets[0], octets[1]) {
        case (10, _):
            return true
        case (172, 16...31):
            return true
        case (192, 168):
            return true
        case (169, 254):
            return true
        case (127, _):
            return true
        default:
            return false
        }
    }

    private static func isPrivateIPv6Host(_ host: String) -> Bool {
        guard host.contains(":") else { return false }
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if normalized == "::1" { return true }
        if normalized.hasPrefix("fc") || normalized.hasPrefix("fd") {
            return true
        }
        if normalized.hasPrefix("fe80:") {
            return true
        }
        return false
    }
}
