//
//  ChatToolArgumentReader.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation

struct ChatToolArgumentReader {
    private let values: [String: Any]

    var argumentsValue: JSONValue {
        .object(values.mapValues(JSONValue.normalized))
    }

    init(argumentsJSON: String) throws {
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            values = [:]
            return
        }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            throw ChatToolError.invalidArguments(NSLocalizedString("Tool arguments were not valid JSON.", comment: "Tool-use error"))
        }
        values = dictionary
    }

    func string(_ key: String) -> String? {
        guard let value = values[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func requiredString(_ key: String) throws -> String {
        guard let value = string(key) else {
            throw ChatToolError.invalidArguments(
                String(format: NSLocalizedString("%@ is required.", comment: "Tool-use error"), key)
            )
        }
        return value
    }

    func requiredRawString(_ key: String) throws -> String {
        guard let value = values[key] as? String, !value.isEmpty else {
            throw ChatToolError.invalidArguments(
                String(format: NSLocalizedString("%@ is required.", comment: "Tool-use error"), key)
            )
        }
        return value
    }

    func bool(_ key: String, default defaultValue: Bool = false) throws -> Bool {
        guard let raw = values[key] else { return defaultValue }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw invalidValue(key, requirement: "a boolean")
        }
        return number.boolValue
    }

    func jsonObject(_ key: String) throws -> [String: Any]? {
        guard let raw = values[key] else { return nil }
        guard let value = raw as? [String: Any] else {
            throw invalidValue(key, requirement: "a JSON object")
        }
        return value
    }

    func stringArray(_ key: String) throws -> [String] {
        guard let raw = values[key] else { return [] }
        guard let values = raw as? [String] else {
            throw invalidValue(key, requirement: "an array of strings")
        }
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func int(_ key: String, default defaultValue: Int, range: ClosedRange<Int>) throws -> Int {
        guard let raw = values[key] else { return defaultValue }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw invalidValue(key, requirement: "an integer")
        }
        let value = number.doubleValue
        guard value.isFinite, value.rounded(.towardZero) == value else {
            throw invalidValue(key, requirement: "an integer")
        }
        guard value >= Double(range.lowerBound), value <= Double(range.upperBound) else {
            throw invalidValue(key, requirement: "an integer from \(range.lowerBound) to \(range.upperBound)")
        }
        return Int(value)
    }

    func double(_ key: String, default defaultValue: Double, range: ClosedRange<Double>) throws -> Double {
        guard let raw = values[key] else { return defaultValue }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw invalidValue(key, requirement: "a number")
        }
        let value = number.doubleValue
        guard value.isFinite, range.contains(value) else {
            throw invalidValue(key, requirement: "a number from \(range.lowerBound) to \(range.upperBound)")
        }
        return value
    }

    func temporalDate(_ key: String, calendar: Calendar = .autoupdatingCurrent) throws -> Date? {
        try ChatToolTemporalResolver.date(from: string(key), calendar: calendar)
    }

    func temporalTimePoint(
        _ key: String,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> ChatToolResolvedTimePoint? {
        try ChatToolTemporalResolver.timePoint(from: string(key), calendar: calendar)
    }

    func requiredTemporalDate(_ key: String, calendar: Calendar = .autoupdatingCurrent) throws -> Date {
        guard let date = try temporalDate(key, calendar: calendar) else {
            throw ChatToolError.invalidArguments(
                String(format: NSLocalizedString("%@ is required.", comment: "Tool-use error"), key)
            )
        }
        return date
    }

    func temporalRange(
        startKey: String = "start",
        endKey: String = "end",
        defaultRange: ChatToolTemporalResolver.DefaultRange?,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> ChatToolTimeRange? {
        try ChatToolTemporalResolver.range(
            start: string(startKey),
            end: string(endKey),
            defaultRange: defaultRange,
            calendar: calendar
        )
    }

    private func invalidValue(_ key: String, requirement: String) -> ChatToolError {
        ChatToolError.invalidArguments("\(key) must be \(requirement).")
    }

}
