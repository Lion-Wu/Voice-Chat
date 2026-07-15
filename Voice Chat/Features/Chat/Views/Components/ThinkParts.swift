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
        let closeRange = self[afterOpen...].range(of: closeMarker)
        let thinkContent: String
        let bodyContent: String
        let isClosed: Bool

        if let closeRange {
            thinkContent = String(self[afterOpen..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            bodyContent = String(self[closeRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            isClosed = true
        } else {
            thinkContent = String(self[afterOpen...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            bodyContent = ""
            isClosed = false
        }

        let thinkValue = thinkContent.isEmpty ? nil : thinkContent
        return ThinkParts(think: thinkValue, isClosed: isClosed, body: bodyContent)
    }
}
