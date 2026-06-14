import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

extension JSONValue {
    var prettyPrintedJSONString: String {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let output = String(data: prettyData, encoding: .utf8) else {
            return String(describing: self)
        }
        return output
    }

    func debugPreviewJSONString(
        maxCharacters: Int = 12_000,
        maxDepth: Int = 8,
        maxCollectionItems: Int = 80
    ) -> String {
        var renderer = JSONValuePreviewRenderer(
            maxCharacters: maxCharacters,
            maxDepth: maxDepth,
            maxCollectionItems: maxCollectionItems
        )
        renderer.append(self, depth: 0, indent: 0)
        if renderer.truncated, !renderer.output.hasSuffix("\n...") {
            renderer.appendTruncationMarker()
        }
        return renderer.output
    }
}

private struct JSONValuePreviewRenderer {
    private(set) var output = ""
    private let maxCharacters: Int
    private let maxDepth: Int
    private let maxCollectionItems: Int
    private(set) var truncated = false

    init(maxCharacters: Int, maxDepth: Int, maxCollectionItems: Int) {
        self.maxCharacters = max(256, maxCharacters)
        self.maxDepth = max(1, maxDepth)
        self.maxCollectionItems = max(1, maxCollectionItems)
    }

    mutating func append(_ value: JSONValue, depth: Int, indent: Int) {
        guard !truncated else { return }
        guard depth <= maxDepth else {
            append("\"...\"")
            truncated = true
            return
        }

        switch value {
        case let .string(value):
            append(quoted(value))
        case let .number(value):
            append(String(value))
        case let .bool(value):
            append(value ? "true" : "false")
        case .null:
            append("null")
        case let .array(values):
            appendArray(values, depth: depth, indent: indent)
        case let .object(values):
            appendObject(values, depth: depth, indent: indent)
        }
    }

    mutating func appendTruncationMarker() {
        output += "\n..."
    }

    private mutating func appendArray(_ values: [JSONValue], depth: Int, indent: Int) {
        guard !values.isEmpty else {
            append("[]")
            return
        }

        append("[\n")
        let visibleValues = values.prefix(maxCollectionItems)
        for (index, value) in visibleValues.enumerated() {
            appendIndent(indent + 1)
            append(value, depth: depth + 1, indent: indent + 1)
            if index < visibleValues.count - 1 || values.count > maxCollectionItems {
                append(",")
            }
            append("\n")
        }
        if values.count > maxCollectionItems {
            appendIndent(indent + 1)
            append("\"...\"")
            append("\n")
            truncated = true
        }
        appendIndent(indent)
        append("]")
    }

    private mutating func appendObject(_ values: [String: JSONValue], depth: Int, indent: Int) {
        guard !values.isEmpty else {
            append("{}")
            return
        }

        append("{\n")
        let entries = values.sorted { $0.key < $1.key }
        let visibleEntries = entries.prefix(maxCollectionItems)
        for (index, entry) in visibleEntries.enumerated() {
            appendIndent(indent + 1)
            append(quoted(entry.key))
            append(": ")
            append(entry.value, depth: depth + 1, indent: indent + 1)
            if index < visibleEntries.count - 1 || entries.count > maxCollectionItems {
                append(",")
            }
            append("\n")
        }
        if entries.count > maxCollectionItems {
            appendIndent(indent + 1)
            append(quoted("..."))
            append(": ")
            append(quoted("..."))
            append("\n")
            truncated = true
        }
        appendIndent(indent)
        append("}")
    }

    private mutating func appendIndent(_ level: Int) {
        append(String(repeating: "  ", count: level))
    }

    private mutating func append(_ text: String) {
        guard !truncated else { return }
        let remaining = maxCharacters - output.count
        guard remaining > 0 else {
            truncated = true
            return
        }

        if text.count <= remaining {
            output += text
        } else {
            output += String(text.prefix(remaining))
            truncated = true
        }
    }

    private func quoted(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                result += "\\\""
            case "\\":
                result += "\\\\"
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        result += "\""
        return result
    }
}
