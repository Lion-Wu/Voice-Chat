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
        guard let start = range(of: "<think>") else { return ThinkParts(think: nil, isClosed: true, body: self) }
        let afterStart = self[start.upperBound...]
        if let end = afterStart.range(of: "</think>") {
            let thinkContent = String(afterStart[..<end.lowerBound])
            let bodyContent  = String(afterStart[end.upperBound...])
            return ThinkParts(think: thinkContent, isClosed: true, body: bodyContent)
        } else {
            return ThinkParts(think: String(afterStart), isClosed: false, body: "")
        }
    }
}
