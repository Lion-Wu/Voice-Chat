//
//  ChatMessageBranchResolver.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatMessageBranchResolution {
    let messages: [ChatMessage]
    let didMutate: Bool
    let didMutateBranch: Bool
}

struct ChatMessageTreeRepairResult {
    var didMutate = false
    var didMutateBranch = false
}

enum ChatMessageBranchResolver {
    static func stableMessageOrder(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.createdAt < rhs.createdAt
    }

    static func messageLookup(in session: ChatSession) -> [UUID: ChatMessage] {
        var lookup: [UUID: ChatMessage] = [:]
        lookup.reserveCapacity(session.messages.count)
        for message in session.messages {
            lookup[message.id] = message
        }
        return lookup
    }

    static func messagesThrough(
        _ target: ChatMessage,
        in session: ChatSession
    ) -> [ChatMessage]? {
        let lookup = messageLookup(in: session)
        guard let storedTarget = lookup[target.id] else { return nil }

        var reversed: [ChatMessage] = []
        reversed.reserveCapacity(min(64, session.messages.count))
        var visited = Set<UUID>()
        var current = storedTarget

        while true {
            guard visited.insert(current.id).inserted else { return nil }
            reversed.append(current)

            guard let parent = current.parentMessage else {
                return Array(reversed.reversed())
            }
            guard let storedParent = lookup[parent.id] else { return nil }
            current = storedParent
        }
    }

    static func activeBranchMessages(
        in session: ChatSession,
        repairRootSelection: Bool = false
    ) -> ChatMessageBranchResolution {
        let lookup = messageLookup(in: session)
        var didMutate = false
        var didMutateBranch = false

        guard let root = activeRootMessage(
            in: session,
            lookup: lookup,
            repairRootSelection: repairRootSelection,
            didMutate: &didMutate,
            didMutateBranch: &didMutateBranch
        ) else {
            return ChatMessageBranchResolution(
                messages: [],
                didMutate: didMutate,
                didMutateBranch: didMutateBranch
            )
        }

        let childrenByParent = childrenByParent(in: session.messages, lookup: lookup)
        var out: [ChatMessage] = []
        out.reserveCapacity(min(64, session.messages.count))

        var visited = Set<UUID>()
        var current: ChatMessage? = root
        while let message = current, visited.insert(message.id).inserted {
            out.append(message)
            current = activeChild(
                for: message,
                lookup: lookup,
                childrenByParent: childrenByParent
            )
        }

        return ChatMessageBranchResolution(
            messages: out,
            didMutate: didMutate,
            didMutateBranch: didMutateBranch
        )
    }

    static func repairMessageTree(in session: ChatSession) -> ChatMessageTreeRepairResult {
        guard !session.messages.isEmpty else { return ChatMessageTreeRepairResult() }

        var result = ChatMessageTreeRepairResult()

        for message in session.messages {
            if message.session?.id != session.id {
                message.session = session
                result.didMutate = true
            }
        }

        let messages = session.messages
        let lookup = messageLookup(in: session)

        for message in messages {
            guard let parent = message.parentMessage else { continue }
            if parent.id == message.id || lookup[parent.id] == nil {
                message.parentMessage = nil
                result.didMutate = true
                result.didMutateBranch = true
            }
        }

        for message in messages {
            var visited = Set<UUID>()
            var current: ChatMessage? = message
            while let cursor = current {
                if !visited.insert(cursor.id).inserted {
                    if cursor.parentMessage != nil {
                        cursor.parentMessage = nil
                        result.didMutate = true
                        result.didMutateBranch = true
                    }
                    break
                }

                guard let parent = cursor.parentMessage else { break }
                if lookup[parent.id] == nil {
                    cursor.parentMessage = nil
                    result.didMutate = true
                    result.didMutateBranch = true
                    break
                }
                current = parent
            }
        }

        var roots = rootCandidatesSorted(in: messages)
        if roots.isEmpty, let fallback = messages.sorted(by: stableMessageOrder).first {
            fallback.parentMessage = nil
            roots = [fallback]
            result.didMutate = true
            result.didMutateBranch = true
        }

        if let activeID = session.activeRootMessageID,
           let active = lookup[activeID] {
            let root = rootMessage(for: active, lookup: lookup)
            if session.activeRootMessageID != root.id {
                session.activeRootMessageID = root.id
                result.didMutate = true
                result.didMutateBranch = true
            }
        } else if let fallback = roots.first {
            session.activeRootMessageID = fallback.id
            result.didMutate = true
            result.didMutateBranch = true
        }

        let repairedChildrenByParent = childrenByParent(in: messages, lookup: lookup)
        for parent in messages {
            let children = repairedChildrenByParent[parent.id, default: []].sorted(by: stableMessageOrder)
            guard !children.isEmpty else {
                if parent.activeChildMessageID != nil {
                    parent.activeChildMessageID = nil
                    result.didMutate = true
                    result.didMutateBranch = true
                }
                continue
            }

            if let activeChildID = parent.activeChildMessageID,
               children.contains(where: { $0.id == activeChildID }) {
                continue
            }

            if let fallback = children.last, parent.activeChildMessageID != fallback.id {
                parent.activeChildMessageID = fallback.id
                result.didMutate = true
                result.didMutateBranch = true
            }
        }

        return result
    }

    private static func activeRootMessage(
        in session: ChatSession,
        lookup: [UUID: ChatMessage],
        repairRootSelection: Bool,
        didMutate: inout Bool,
        didMutateBranch: inout Bool
    ) -> ChatMessage? {
        if let activeID = session.activeRootMessageID,
           let active = lookup[activeID] {
            let root = rootMessage(for: active, lookup: lookup)
            if repairRootSelection, session.activeRootMessageID != root.id {
                session.activeRootMessageID = root.id
                didMutate = true
                didMutateBranch = true
            }
            return root
        }

        if let fallback = rootCandidatesSorted(in: session.messages).first {
            if repairRootSelection {
                session.activeRootMessageID = fallback.id
                didMutate = true
                didMutateBranch = true
            }
            return fallback
        }

        guard let fallback = session.messages.sorted(by: stableMessageOrder).first else {
            return nil
        }
        if repairRootSelection {
            if fallback.parentMessage != nil {
                fallback.parentMessage = nil
            }
            session.activeRootMessageID = fallback.id
            didMutate = true
            didMutateBranch = true
        }
        return fallback
    }

    private static func rootCandidatesSorted(in messages: [ChatMessage]) -> [ChatMessage] {
        messages
            .filter { $0.parentMessage == nil }
            .sorted(by: stableMessageOrder)
    }

    private static func childrenByParent(
        in messages: [ChatMessage],
        lookup: [UUID: ChatMessage]
    ) -> [UUID: [ChatMessage]] {
        var childrenByParent: [UUID: [ChatMessage]] = [:]
        childrenByParent.reserveCapacity(messages.count)
        for message in messages {
            guard let parent = message.parentMessage,
                  lookup[parent.id] != nil,
                  parent.id != message.id else {
                continue
            }
            childrenByParent[parent.id, default: []].append(message)
        }
        return childrenByParent
    }

    private static func activeChild(
        for message: ChatMessage,
        lookup: [UUID: ChatMessage],
        childrenByParent: [UUID: [ChatMessage]]
    ) -> ChatMessage? {
        let children = childrenByParent[message.id, default: []].sorted(by: stableMessageOrder)
        guard !children.isEmpty else { return nil }

        if let activeChildID = message.activeChildMessageID,
           let activeChild = lookup[activeChildID],
           activeChild.parentMessage?.id == message.id {
            return activeChild
        }

        return children.last
    }

    private static func rootMessage(
        for message: ChatMessage,
        lookup: [UUID: ChatMessage]
    ) -> ChatMessage {
        var cursor = message
        var visited = Set<UUID>()
        while let parent = cursor.parentMessage,
              lookup[parent.id] != nil,
              visited.insert(cursor.id).inserted {
            cursor = parent
        }
        return cursor
    }
}
