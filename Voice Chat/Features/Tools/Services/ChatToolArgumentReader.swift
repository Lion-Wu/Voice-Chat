//
//  ChatToolArgumentReader.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation

struct ChatToolArgumentReader {
    private let values: [String: Any]

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

    func int(_ key: String, default defaultValue: Int, range: ClosedRange<Int>) -> Int {
        let raw: Int?
        if let value = values[key] as? Int {
            raw = value
        } else if let number = values[key] as? NSNumber {
            raw = number.intValue
        } else {
            raw = nil
        }
        return min(max(raw ?? defaultValue, range.lowerBound), range.upperBound)
    }

    func double(_ key: String, default defaultValue: Double, range: ClosedRange<Double>) -> Double {
        let raw: Double?
        if let value = values[key] as? Double {
            raw = value
        } else if let number = values[key] as? NSNumber {
            raw = number.doubleValue
        } else {
            raw = nil
        }
        return min(max(raw ?? defaultValue, range.lowerBound), range.upperBound)
    }

    func localDate(_ key: String, calendar: Calendar = .autoupdatingCurrent) throws -> Date? {
        guard let value = string(key) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else {
            throw ChatToolError.invalidArguments(
                String(format: NSLocalizedString("%@ must use YYYY-MM-DD format.", comment: "Tool-use error"), key)
            )
        }
        return calendar.startOfDay(for: date)
    }
}
