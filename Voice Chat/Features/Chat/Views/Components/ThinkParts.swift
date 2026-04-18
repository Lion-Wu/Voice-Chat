//
//  ThinkParts.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation

struct ThinkParts {
    let think: String?
    let isClosed: Bool
    let body: String
}

extension String {
    func extractThinkParts() -> ThinkParts {
        let openMarker = "<think>"
        let closeMarker = "</think>"

        guard self.contains(openMarker) else {
            return ThinkParts(think: nil, isClosed: true, body: self)
        }

        // Opening marker must be the first token in the content,
        // but no longer needs to be on a standalone line.
        guard self.hasPrefix(openMarker) else {
            return ThinkParts(think: nil, isClosed: true, body: self)
        }

        let afterOpen = self.index(self.startIndex, offsetBy: openMarker.count)
        let contentAfterOpen = String(self[afterOpen...])
        let lines = contentAfterOpen.components(separatedBy: .newlines)
        let endIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == closeMarker })

        let thinkLines: ArraySlice<String>
        let bodyLines: ArraySlice<String>
        let isClosed: Bool

        if let endIdx {
            thinkLines = lines[..<endIdx]
            bodyLines = lines.suffix(from: lines.index(after: endIdx))
            isClosed = true
        } else {
            thinkLines = lines[...]
            bodyLines = []
            isClosed = false
        }

        let thinkContent = thinkLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyContent = bodyLines
            .drop(while: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            .joined(separator: "\n")

        let thinkValue = thinkContent.isEmpty ? nil : thinkContent
        return ThinkParts(think: thinkValue, isClosed: isClosed, body: bodyContent)
    }
}
