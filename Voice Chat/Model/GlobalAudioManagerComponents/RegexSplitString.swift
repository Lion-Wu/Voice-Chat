//
//  RegexSplitString.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation

extension String {
    /// Split by regex separators and keep content pieces (separators dropped).
    func split(usingRegex pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [self] }
        let ns = self as NSString
        var last = 0
        var parts: [String] = []
        for m in regex.matches(in: self, options: [], range: NSRange(location: 0, length: ns.length)) {
            let r = NSRange(location: last, length: m.range.location - last)
            if r.length > 0 {
                let sub = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sub.isEmpty { parts.append(sub) }
            }
            last = m.range.location + m.range.length
        }
        let tail = NSRange(location: last, length: ns.length - last)
        if tail.length > 0 {
            let sub = ns.substring(with: tail).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sub.isEmpty { parts.append(sub) }
        }
        return parts
    }
}
