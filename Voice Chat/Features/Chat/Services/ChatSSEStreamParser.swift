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
    private var bufferedData = Data()
    private var pendingEventType: String?
    private let maxBufferedBytes: Int

    init(maxBufferedBytes: Int = 512 * 1024) {
        self.maxBufferedBytes = maxBufferedBytes
    }

    mutating func reset() {
        bufferedData.removeAll(keepingCapacity: true)
        pendingEventType = nil
    }

    mutating func clearPendingEventType() {
        pendingEventType = nil
    }

    mutating func append(_ data: Data) -> ChatSSEStreamParserAppendResult {
        bufferedData.append(data)
        guard bufferedData.count <= maxBufferedBytes else {
            return .exceededBufferLimit
        }

        var frames: [ChatSSEStreamFrame] = []
        var lineStart = bufferedData.startIndex
        var index = lineStart
        while index < bufferedData.endIndex {
            let byte = bufferedData[index]
            let terminatorLength: Int
            if byte == 0x0A {
                terminatorLength = 1
            } else if byte == 0x0D {
                let nextIndex = bufferedData.index(after: index)
                guard nextIndex < bufferedData.endIndex else { break }
                terminatorLength = bufferedData[nextIndex] == 0x0A ? 2 : 1
            } else {
                index = bufferedData.index(after: index)
                continue
            }

            let lineData = bufferedData[lineStart..<index]
            processLine(String(decoding: lineData, as: UTF8.self), frames: &frames)
            index = bufferedData.index(index, offsetBy: terminatorLength)
            lineStart = index
        }

        if lineStart > bufferedData.startIndex {
            bufferedData.removeSubrange(bufferedData.startIndex..<lineStart)
        }
        return .frames(frames)
    }

    mutating func append(_ chunk: String) -> ChatSSEStreamParserAppendResult {
        append(Data(chunk.utf8))
    }

    private mutating func processLine(
        _ rawLine: String,
        frames: inout [ChatSSEStreamFrame]
    ) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty {
            pendingEventType = nil
            return
        }
        if line.hasPrefix("event:") {
            let eventType = String(line.dropFirst("event:".count))
                .trimmingCharacters(in: .whitespaces)
            pendingEventType = eventType.isEmpty ? nil : eventType
            return
        }
        guard line.hasPrefix("data:") else { return }

        let payload = String(line.dropFirst("data:".count))
            .trimmingCharacters(in: .whitespaces)
        frames.append(ChatSSEStreamFrame(payload: payload, eventType: pendingEventType))
    }
}
