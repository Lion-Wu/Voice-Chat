//
//  ChatSSEStreamParser.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct ChatSSEStreamFrame: Equatable {
    let payload: String
    let eventType: String?

    var isDone: Bool {
        payload == "[DONE]"
    }

    var jsonData: Data? {
        payload.data(using: .utf8)
    }
}

enum ChatSSEStreamParserAppendResult: Equatable {
    case frames([ChatSSEStreamFrame])
    case exceededBufferLimit
}

struct ChatSSEStreamParser {
    private var partialLine: String = ""
    private var pendingEventType: String?
    private let maxBufferedBytes: Int

    init(maxBufferedBytes: Int = 512 * 1024) {
        self.maxBufferedBytes = maxBufferedBytes
    }

    mutating func reset() {
        partialLine = ""
        pendingEventType = nil
    }

    mutating func clearPendingEventType() {
        pendingEventType = nil
    }

    mutating func append(_ data: Data) -> ChatSSEStreamParserAppendResult {
        append(String(decoding: data, as: UTF8.self))
    }

    mutating func append(_ chunk: String) -> ChatSSEStreamParserAppendResult {
        partialLine += chunk

        guard partialLine.utf8.count <= maxBufferedBytes else {
            return .exceededBufferLimit
        }

        let lines = partialLine.split(
            maxSplits: Int.max,
            omittingEmptySubsequences: false,
            whereSeparator: { $0.isNewline }
        )

        var processCount = lines.count
        if let last = partialLine.last, last != "\n" && last != "\r" {
            processCount -= 1
        }

        var frames: [ChatSSEStreamFrame] = []
        for index in 0..<max(0, processCount) {
            let line = String(lines[index]).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                pendingEventType = nil
                continue
            }
            if line.hasPrefix("event:") {
                let eventType = String(line.dropFirst("event:".count))
                    .trimmingCharacters(in: .whitespaces)
                pendingEventType = eventType.isEmpty ? nil : eventType
                continue
            }
            guard line.hasPrefix("data:") else { continue }

            let payload = String(line.dropFirst("data:".count))
                .trimmingCharacters(in: .whitespaces)
            frames.append(ChatSSEStreamFrame(payload: payload, eventType: pendingEventType))
        }

        let remainder = lines.suffix(from: max(0, processCount)).joined(separator: "\n")
        partialLine = remainder
        return .frames(frames)
    }
}
