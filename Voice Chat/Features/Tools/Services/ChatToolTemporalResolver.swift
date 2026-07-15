//
//  ChatToolTemporalResolver.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.28.
//

import Foundation

struct ChatToolTimeRange: Equatable, Sendable {
    let start: Date
    let end: Date
    let originalStart: String?
    let originalEnd: String?
    let usedDefaultRange: Bool
    let isDateOnlyRange: Bool

    var isValid: Bool {
        end > start
    }
}

struct ChatToolResolvedTimePoint: Equatable, Sendable {
    let date: Date
    let isDateOnly: Bool
}

enum ChatToolTemporalResolver {
    static let absoluteValueSyntax =
        "Accepted formats: an ISO 8601 date-time with timezone; a device-local date-time in YYYY-MM-DDTHH:mm[:ss[.SSS]] or YYYY-MM-DD HH:mm[:ss]; or a device-local date in YYYY-MM-DD."
    static let relativeTimePointExpressionSyntax = RelativeExpressionSyntax.description(
        includesWeekRanges: false
    )
    static let relativeRangeExpressionSyntax = RelativeExpressionSyntax.description(
        includesWeekRanges: true
    )
    static let timePointValueSyntax = "\(absoluteValueSyntax) \(relativeTimePointExpressionSyntax)"
    static let rangeValueSyntax = "\(absoluteValueSyntax) \(relativeRangeExpressionSyntax)"
    static let generalToolRuleReference = "Format this value using the general date/time rules."
    static let namedWeekRangeRuleReference = "This value also accepts named week ranges."

    static func generalToolValueSyntax(canReadCurrentTime: Bool) -> String {
        let currentTimeRule = canReadCurrentTime
            ? "When a request depends on the actual current date or time, call system_get_time immediately before the time-dependent tool unless a documented relative expression represents the requested time exactly. Never invent the current date or time, and refresh system_get_time in a later user turn instead of reusing an older result."
            : "Never invent the current date or time. Use a documented relative expression when it represents the request exactly; otherwise explain that exact current time is unavailable."
        return """
        General date/time rules:
        - Apply these rules only to tool arguments whose schema description includes "\(generalToolRuleReference)"
        - \(absoluteValueSyntax)
        \(relativeRangeExpressionSyntax)
        - Arguments whose schema description also includes "\(namedWeekRangeRuleReference)" may use "this week", "next week", and "last week". Every other documented expression is valid for every argument that uses the general date/time rules.
        \(currentTimeRule)
        """
    }

    static func range(
        start startRaw: String?,
        end endRaw: String?,
        defaultRange: DefaultRange?,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) throws -> ChatToolTimeRange? {
        let startComponent = try startRaw.map {
            try component(from: $0, calendar: calendar, now: now, allowsWeekRange: true)
        }
        let endComponent = try endRaw.map {
            try component(from: $0, calendar: calendar, now: now, allowsWeekRange: true)
        }

        if let startComponent {
            let endDate: Date
            let isDateOnlyRange: Bool
            if let endComponent {
                endDate = endComponent.exclusiveUpperBound(defaultingToEndOfDay: false, calendar: calendar)
                isDateOnlyRange = startComponent.isDateOnly && endComponent.isDateOnly
            } else {
                endDate = startComponent.defaultExclusiveUpperBound(calendar: calendar)
                isDateOnlyRange = startComponent.isDateOnly
            }
            return ChatToolTimeRange(
                start: startComponent.date,
                end: endDate,
                originalStart: startRaw,
                originalEnd: endRaw,
                usedDefaultRange: false,
                isDateOnlyRange: isDateOnlyRange
            )
        }

        if endComponent != nil {
            throw ChatToolError.invalidArguments(
                NSLocalizedString("start is required when end is provided.", comment: "Tool-use error")
            )
        }

        guard let defaultRange else { return nil }
        let defaultBounds = defaultRange.bounds(calendar: calendar, now: now)
        return ChatToolTimeRange(
            start: defaultBounds.start,
            end: defaultBounds.end,
            originalStart: nil,
            originalEnd: nil,
            usedDefaultRange: true,
            isDateOnlyRange: defaultRange == .today
        )
    }

    static func date(
        from raw: String?,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) throws -> Date? {
        try timePoint(from: raw, calendar: calendar, now: now)?.date
    }

    static func timePoint(
        from raw: String?,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) throws -> ChatToolResolvedTimePoint? {
        guard let raw else { return nil }
        let component = try component(from: raw, calendar: calendar, now: now, allowsWeekRange: false)
        return ChatToolResolvedTimePoint(date: component.date, isDateOnly: component.isDateOnly)
    }

    static func parseDateTime(_ raw: String, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        let fractionalSecondsFormatter = ISO8601DateFormatter()
        fractionalSecondsFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601Formatter.date(from: value) ??
            fractionalSecondsFormatter.date(from: value) {
            return date
        }

        for format in dateTimeFormats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: value), formatter.string(from: date) == value {
                return date
            }
        }
        return nil
    }

    static func parseDateOnly(_ raw: String, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        var gregorianCalendar = Calendar(identifier: .gregorian)
        gregorianCalendar.timeZone = calendar.timeZone
        let formatter = DateFormatter()
        formatter.calendar = gregorianCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return gregorianCalendar.startOfDay(for: date)
    }

    enum DefaultRange: Equatable, Sendable {
        case today

        func bounds(calendar: Calendar, now: Date) -> (start: Date, end: Date) {
            switch self {
            case .today:
                let start = calendar.startOfDay(for: now)
                return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? now)
            }
        }
    }

    private struct Component {
        let date: Date
        let isDateOnly: Bool
        let defaultEnd: Date?

        init(date: Date, isDateOnly: Bool, defaultEnd: Date? = nil) {
            self.date = date
            self.isDateOnly = isDateOnly
            self.defaultEnd = defaultEnd
        }

        func defaultExclusiveUpperBound(calendar: Calendar) -> Date {
            if let defaultEnd {
                return defaultEnd
            }
            if isDateOnly {
                return calendar.date(byAdding: .day, value: 1, to: date) ?? date
            }
            return date
        }

        func exclusiveUpperBound(defaultingToEndOfDay: Bool, calendar: Calendar) -> Date {
            if let defaultEnd {
                return defaultEnd
            }
            if isDateOnly || defaultingToEndOfDay {
                return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
            }
            return date
        }
    }

    private enum RelativeExpressionSyntax {
        private struct NamedOffset: Sendable {
            let phrase: String
            let offset: Int
        }

        private struct OffsetUnit: Sendable {
            let singular: String
            let component: Calendar.Component
        }

        private static let dayExpressions = [
            NamedOffset(phrase: "today", offset: 0),
            NamedOffset(phrase: "tomorrow", offset: 1),
            NamedOffset(phrase: "yesterday", offset: -1),
            NamedOffset(phrase: "day after tomorrow", offset: 2),
            NamedOffset(phrase: "day before yesterday", offset: -2)
        ]
        private static let weekExpressions = [
            NamedOffset(phrase: "this week", offset: 0),
            NamedOffset(phrase: "next week", offset: 1),
            NamedOffset(phrase: "last week", offset: -1)
        ]
        private static let weekdayScopes = [
            NamedOffset(phrase: "this", offset: 0),
            NamedOffset(phrase: "next", offset: 1),
            NamedOffset(phrase: "last", offset: -1)
        ]
        private static let weekdayNames = [
            "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
        ]
        private static let offsetUnits = [
            OffsetUnit(singular: "second", component: .second),
            OffsetUnit(singular: "minute", component: .minute),
            OffsetUnit(singular: "hour", component: .hour),
            OffsetUnit(singular: "day", component: .day),
            OffsetUnit(singular: "week", component: .weekOfYear),
            OffsetUnit(singular: "month", component: .month),
            OffsetUnit(singular: "year", component: .year)
        ]

        static func description(includesWeekRanges: Bool) -> String {
            var namedExpressions = ["now"] + dayExpressions.map(\.phrase)
            if includesWeekRanges {
                namedExpressions += weekExpressions.map(\.phrase)
            }
            let named = namedExpressions.map { "\"\($0)\"" }.joined(separator: " / ")
            let scopes = weekdayScopes.map(\.phrase).map { "\"\($0)\"" }.joined(separator: " / ")
            let weekdays = weekdayNames.map { "\"\($0.lowercased())\"" }.joined(separator: " / ")
            let units = offsetUnits.map { "\"\($0.singular)\"" }.joined(separator: " / ")
            let resolution = includesWeekRanges
                ? "Named days and weekdays resolve to local dates, named weeks resolve to full local weeks, and numeric offsets resolve to exact instants."
                : "Named days and weekdays resolve to local dates, and numeric offsets resolve to exact instants."
            return """
            Accepted relative date/time expressions use this ABNF (quoted literals are case-insensitive):
              relative = named / weekday-relative / offset-relative
              named = \(named)
              weekday-relative = scope SP weekday
              scope = \(scopes)
              weekday = \(weekdays)
              offset-relative = integer SP unit SP ("ago" / ("from" SP "now"))
              integer = 1*5DIGIT ; numeric value must be 1 through 10000
              unit = (\(units)) ["s"]
            Emit the canonical phrases with one space between words. The weekday scopes mean the current, next, or previous local calendar week, respectively. \(resolution) Values are resolved against the device calendar, time zone, and current time when the tool executes. No other natural-language forms are accepted.
            """
        }

        static func dayOffset(for phrase: String) -> Int? {
            dayExpressions.first { $0.phrase == phrase }?.offset
        }

        static func weekOffset(for phrase: String) -> Int? {
            weekExpressions.first { $0.phrase == phrase }?.offset
        }

        static func weekOffset(forWeekdayScope phrase: String) -> Int? {
            weekdayScopes.first { $0.phrase == phrase }?.offset
        }

        static func weekdayNumber(for name: String) -> Int? {
            guard let index = weekdayNames.firstIndex(where: { $0.lowercased() == name }) else {
                return nil
            }
            return index + 1
        }

        static func calendarComponent(forUnit name: String) -> Calendar.Component? {
            let singular = name.hasSuffix("s") ? String(name.dropLast()) : name
            return offsetUnits.first { $0.singular == singular }?.component
        }
    }

    private static func component(
        from raw: String,
        calendar: Calendar,
        now: Date,
        allowsWeekRange: Bool
    ) throws -> Component {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw ChatToolError.invalidArguments(NSLocalizedString("Time value cannot be empty.", comment: "Tool-use error"))
        }
        if let date = parseDateTime(value, calendar: calendar) {
            return Component(date: date, isDateOnly: false)
        }
        if let date = parseDateOnly(value, calendar: calendar) {
            return Component(date: date, isDateOnly: true)
        }
        if let component = relativeComponent(
            from: value,
            calendar: calendar,
            now: now,
            allowsWeekRange: allowsWeekRange
        ) {
            return component
        }
        throw ChatToolError.invalidArguments(
            "\(raw) is not a valid date/time value. " + (allowsWeekRange
                ? rangeValueSyntax
                : timePointValueSyntax)
        )
    }

    private static func relativeComponent(
        from raw: String,
        calendar: Calendar,
        now: Date,
        allowsWeekRange: Bool
    ) -> Component? {
        let value = normalized(raw)
        if value == "now" {
            return Component(date: now, isDateOnly: false)
        }
        if let offset = RelativeExpressionSyntax.dayOffset(for: value) {
            return dayOffset(offset, calendar: calendar, now: now)
        }
        if allowsWeekRange,
           let offset = RelativeExpressionSyntax.weekOffset(for: value) {
            return weekRange(offset: offset, calendar: calendar, now: now)
        }

        if let component = weekdayComponent(from: value, calendar: calendar, now: now) {
            return component
        }
        if let component = relativeOffsetComponent(from: value, calendar: calendar, now: now) {
            return component
        }
        return nil
    }

    private static func dayOffset(_ offset: Int, calendar: Calendar, now: Date) -> Component? {
        let start = calendar.startOfDay(for: now)
        guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
        return Component(
            date: date,
            isDateOnly: true
        )
    }

    private static func weekRange(offset: Int, calendar: Calendar, now: Date) -> Component? {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
        let start = calendar.date(byAdding: .weekOfYear, value: offset, to: interval.start) ?? interval.start
        let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)
        return Component(date: start, isDateOnly: true, defaultEnd: end)
    }

    private static func weekdayComponent(from value: String, calendar: Calendar, now: Date) -> Component? {
        let parts = value.split(separator: " ").map(String.init)
        guard parts.count == 2,
              let weekOffset = RelativeExpressionSyntax.weekOffset(forWeekdayScope: parts[0]),
              let targetWeekday = RelativeExpressionSyntax.weekdayNumber(for: parts[1]) else {
            return nil
        }
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now),
              let targetWeekStart = calendar.date(
                byAdding: .weekOfYear,
                value: weekOffset,
                to: currentWeek.start
              ),
              let targetWeekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: targetWeekStart) else {
            return nil
        }
        var components = DateComponents()
        components.weekday = targetWeekday
        guard let date = calendar.nextDate(
            after: targetWeekStart.addingTimeInterval(-1),
            matching: components,
            matchingPolicy: .nextTime,
            direction: .forward
        ), date < targetWeekEnd else {
            return nil
        }
        return Component(date: calendar.startOfDay(for: date), isDateOnly: true)
    }

    private static func relativeOffsetComponent(from value: String, calendar: Calendar, now: Date) -> Component? {
        let parts = value.split(separator: " ").map(String.init)
        let sign: Int
        if parts.count == 3, parts[2] == "ago" {
            sign = -1
        } else if parts.count == 4, parts[2] == "from", parts[3] == "now" {
            sign = 1
        } else {
            return nil
        }
        guard parts[0].utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let amount = Int(parts[0]),
              (1...10_000).contains(amount),
              let component = RelativeExpressionSyntax.calendarComponent(forUnit: parts[1]) else {
            return nil
        }
        guard let date = calendar.date(byAdding: component, value: amount * sign, to: now) else {
            return nil
        }
        return Component(date: date, isDateOnly: false)
    }

    private static func normalized(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static let dateTimeFormats = [
        "yyyy-MM-dd'T'HH:mmXXXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd HH:mmXXXXX",
        "yyyy-MM-dd HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd HH:mm:ss"
    ]
}
