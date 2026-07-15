//
//  ChatToolTimeFormatter.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.24.
//

import Foundation

enum ChatToolTimeFormatter {
    static func localISO8601String(
        from date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    static func utcISO8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    static func timeZoneOffsetString(
        for date: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds >= 0 ? "+" : "-"
        let absolute = abs(seconds)
        return String(format: "%@%02d:%02d", sign, absolute / 3_600, (absolute % 3_600) / 60)
    }

    static func localDateString(
        from date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func localClockString(
        from date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(
            format: "%02d:%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    static func timeZonePayloadFields(
        for date: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> [String: JSONValue] {
        [
            "timezone": .string(timeZone.identifier),
            "timezone_offset": .string(timeZoneOffsetString(for: date, timeZone: timeZone))
        ]
    }
}
