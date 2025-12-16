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
        guard self.contains("<think>") else {
            return ThinkParts(think: nil, isClosed: true, body: self)
        }

        let lines = self.components(separatedBy: .newlines)
        guard let startIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "<think>" }) else {
            return ThinkParts(think: nil, isClosed: true, body: self)
        }

        let afterStart = lines.index(after: startIdx)
        let endIdx = lines[afterStart...].firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "</think>" })

        let thinkLines: ArraySlice<String>
        let bodyLines: ArraySlice<String>
        let isClosed: Bool

        if let endIdx {
            thinkLines = lines[afterStart..<endIdx]
            bodyLines = lines.suffix(from: lines.index(after: endIdx))
            isClosed = true
        } else {
            thinkLines = lines[afterStart...]
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
