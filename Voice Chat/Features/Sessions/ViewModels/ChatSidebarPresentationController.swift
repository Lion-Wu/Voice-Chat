//
//  ChatSidebarPresentationController.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct SidebarSessionPreview: Equatable {
    let text: String
    let emphasizedRanges: [NSRange]

    static func plain(_ text: String) -> SidebarSessionPreview {
        SidebarSessionPreview(text: text, emphasizedRanges: [])
    }
}

struct ChatSidebarBodySearchMatch {
    let messageID: UUID
    let bodyText: String
    let foundRange: NSRange?
    let anchorY: Double
}

struct ChatSidebarPresentationController {
    private struct CacheEntry {
        let title: String
        let messageCount: Int
        let lastMessageAt: Date?
        let lastMessageID: UUID?
        let lastMessageContent: String?
        let subtitle: String
        let searchCorpus: String?
    }

    private var cache: [UUID: CacheEntry] = [:]

    mutating func invalidate(for sessionID: UUID) {
        cache.removeValue(forKey: sessionID)
    }

    mutating func prune(keeping validSessionIDs: Set<UUID>) {
        let staleKeys = cache.keys.filter { !validSessionIDs.contains($0) }
        for key in staleKeys {
            cache.removeValue(forKey: key)
        }
    }

    func normalizedQuery(_ rawQuery: String) -> String {
        normalizedSearchText(rawQuery.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    mutating func sessions(
        matching rawQuery: String,
        in candidateSessions: [ChatSession]
    ) -> [ChatSession] {
        sessions(candidateSessions, matchingNormalizedQuery: normalizedQuery(rawQuery))
    }

    mutating func sessions(
        _ candidateSessions: [ChatSession],
        matchingNormalizedQuery normalizedQuery: String
    ) -> [ChatSession] {
        guard !normalizedQuery.isEmpty else { return candidateSessions }

        var matches: [ChatSession] = []
        matches.reserveCapacity(candidateSessions.count)
        for session in candidateSessions where searchCorpus(for: session).contains(normalizedQuery) {
            matches.append(session)
        }
        return matches
    }

    mutating func subtitle(for session: ChatSession) -> String {
        presentation(for: session).subtitle
    }

    mutating func preview(for session: ChatSession, matchingSearchQuery rawQuery: String) -> SidebarSessionPreview {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = normalizedQuery(query)
        guard !normalizedQuery.isEmpty,
              let match = bodySearchMatch(
                  in: session,
                  rawQuery: query,
                  matchingNormalizedQuery: normalizedQuery
              ),
              let preview = searchContextPreview(
                  in: match.bodyText,
                  query: query,
                  foundRange: match.foundRange
              ) else {
            return .plain(subtitle(for: session))
        }

        return preview
    }

    mutating func bodySearchMatch(
        in session: ChatSession,
        rawQuery: String,
        matchingNormalizedQuery normalizedQuery: String
    ) -> ChatSidebarBodySearchMatch? {
        guard !normalizedQuery.isEmpty else { return nil }

        for message in searchMessages(in: session) {
            let body = searchText(for: message)
            let normalizedBody = normalizedSearchText(body)
            if normalizedBody.contains(normalizedQuery) {
                let foundRange = searchRange(in: body, query: rawQuery)
                return ChatSidebarBodySearchMatch(
                    messageID: message.id,
                    bodyText: body,
                    foundRange: foundRange,
                    anchorY: searchAnchorY(in: body, foundRange: foundRange)
                )
            }
        }

        return nil
    }

    private mutating func presentation(for session: ChatSession) -> CacheEntry {
        let lastMessage = latestMessage(in: session)
        let lastMessageContent = lastMessage?.content

        if let cached = cache[session.id],
           cached.title == session.title,
           cached.messageCount == session.messages.count,
           cached.lastMessageID == lastMessage?.id,
           cached.lastMessageContent == lastMessageContent,
           cached.lastMessageAt == session.lastMessageAt {
            return cached
        }

        let bodyText = lastMessageContent?
            .extractThinkParts()
            .body
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let subtitle: String
        if lastMessage == nil {
            subtitle = String(localized: "Fresh conversation")
        } else if bodyText.isEmpty {
            subtitle = String(localized: "No recent replies")
        } else {
            let snippet = bodyText.prefix(60)
            subtitle = bodyText.count > 60 ? "\(snippet)…" : String(snippet)
        }

        let entry = CacheEntry(
            title: session.title,
            messageCount: session.messages.count,
            lastMessageAt: session.lastMessageAt,
            lastMessageID: lastMessage?.id,
            lastMessageContent: lastMessageContent,
            subtitle: subtitle,
            searchCorpus: nil
        )
        cache[session.id] = entry
        return entry
    }

    private mutating func searchCorpus(for session: ChatSession) -> String {
        let presentation = presentation(for: session)
        if let cachedCorpus = presentation.searchCorpus {
            return cachedCorpus
        }

        let messageSearchText = searchMessages(in: session).map { searchText(for: $0) }
        let searchCorpus = normalizedSearchText(
            ([session.title] + messageSearchText).joined(separator: "\n")
        )

        let updatedEntry = CacheEntry(
            title: presentation.title,
            messageCount: presentation.messageCount,
            lastMessageAt: presentation.lastMessageAt,
            lastMessageID: presentation.lastMessageID,
            lastMessageContent: presentation.lastMessageContent,
            subtitle: presentation.subtitle,
            searchCorpus: searchCorpus
        )
        cache[session.id] = updatedEntry
        return searchCorpus
    }

    private func latestMessage(in session: ChatSession) -> ChatMessage? {
        if let lastMessageAt = session.lastMessageAt,
           let message = session.messages.first(where: { $0.createdAt == lastMessageAt }) {
            return message
        }
        return session.messages.max(by: { $0.createdAt < $1.createdAt })
    }

    private func searchText(for message: ChatMessage) -> String {
        message.content.extractThinkParts().body
    }

    private func searchMessages(in session: ChatSession) -> [ChatMessage] {
        ChatMessageBranchResolver.activeBranchMessages(in: session).messages
    }

    private func normalizedSearchText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func searchRange(in text: String, query: String) -> NSRange? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }

        let foundRange = nsText.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: NSRange(location: 0, length: nsText.length)
        )
        guard foundRange.location != NSNotFound, foundRange.length > 0 else { return nil }
        return foundRange
    }

    private func searchAnchorY(in text: String, foundRange: NSRange?) -> Double {
        let nsText = text as NSString
        guard nsText.length > 0,
              let foundRange,
              foundRange.location != NSNotFound,
              foundRange.length > 0 else {
            return 0.5
        }

        let midpoint = Double(foundRange.location) + Double(foundRange.length) / 2
        if let lineAnchor = searchLineAnchorY(in: text, foundRange: foundRange) {
            return lineAnchor
        }
        return clampedSearchAnchorY(midpoint / Double(nsText.length))
    }

    private func searchLineAnchorY(in text: String, foundRange: NSRange) -> Double? {
        guard text.contains(where: \.isNewline),
              let range = Range(foundRange, in: text) else {
            return nil
        }

        let lineIndex = text[..<range.lowerBound].reduce(0) { partial, character in
            partial + (character.isNewline ? 1 : 0)
        }
        let lineCount = text.reduce(1) { partial, character in
            partial + (character.isNewline ? 1 : 0)
        }
        guard lineCount > 1 else { return nil }
        return clampedSearchAnchorY((Double(lineIndex) + 0.5) / Double(lineCount))
    }

    private func clampedSearchAnchorY(_ anchorY: Double) -> Double {
        min(0.95, max(0.05, anchorY))
    }

    private func searchContextPreview(
        in text: String,
        query: String,
        foundRange: NSRange?
    ) -> SidebarSessionPreview? {
        guard let foundRange,
              let range = Range(foundRange, in: text) else {
            return nil
        }

        let leadingContextLength = 8
        let trailingContextLength = 64
        let contextStart = text.index(
            range.lowerBound,
            offsetBy: -leadingContextLength,
            limitedBy: text.startIndex
        ) ?? text.startIndex
        let contextEnd = text.index(
            range.upperBound,
            offsetBy: trailingContextLength,
            limitedBy: text.endIndex
        ) ?? text.endIndex

        var snippet = String(text[contextStart..<contextEnd])
        snippet = singleLineSnippet(snippet).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snippet.isEmpty else { return nil }

        if contextStart > text.startIndex {
            snippet = "…" + snippet
        }
        if contextEnd < text.endIndex {
            snippet += "…"
        }

        let emphasizedRanges = searchRanges(in: snippet, query: query)
        return SidebarSessionPreview(text: snippet, emphasizedRanges: emphasizedRanges)
    }

    private func singleLineSnippet(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func searchRanges(in text: String, query: String) -> [NSRange] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.location < nsText.length {
            let foundRange = nsText.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )
            guard foundRange.location != NSNotFound, foundRange.length > 0 else { break }

            ranges.append(foundRange)
            let nextLocation = foundRange.location + foundRange.length
            searchRange = NSRange(location: nextLocation, length: max(0, nsText.length - nextLocation))
        }
        return ranges
    }
}
