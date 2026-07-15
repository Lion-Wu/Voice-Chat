//
//  ChatToolPresentationView.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.25.
//

import SwiftUI

enum ChatToolPresentationStyle {
    case full
    case compactGrid
}

struct ChatToolPresentationView: View {
    let presentation: ChatToolPresentation
    var style: ChatToolPresentationStyle = .full

    var body: some View {
        switch presentation.kind ?? .generic {
        case .calendar:
            calendarView
        case .reminders:
            remindersView
        case .generic:
            genericView
        }
    }

    @ViewBuilder
    private var calendarView: some View {
        if style == .compactGrid {
            compactGrid(tint: .red) {
                ForEach(presentation.items) { item in
                    CalendarCompactPresentationRow(item: item)
                }
            }
        } else {
            fullCalendarView
        }
    }

    private var fullCalendarView: some View {
        VStack(alignment: .leading, spacing: 10) {
            presentationHeader(systemImage: "calendar", tint: .red, count: presentation.items.count)

            VStack(spacing: 0) {
                ForEach(Array(presentation.items.enumerated()), id: \.element.id) { index, item in
                    CalendarPresentationRow(item: item)
                    if index < presentation.items.count - 1 {
                        Divider()
                            .padding(.leading, 64)
                            .opacity(0.58)
                    }
                }
            }
        }
        .padding(12)
        .background(presentationBackground(tint: .red))
    }

    @ViewBuilder
    private var remindersView: some View {
        if style == .compactGrid {
            compactGrid(tint: .blue) {
                ForEach(presentation.items) { item in
                    ReminderCompactPresentationRow(item: item)
                }
            }
        } else {
            fullRemindersView
        }
    }

    private var fullRemindersView: some View {
        VStack(alignment: .leading, spacing: 10) {
            presentationHeader(systemImage: "checklist", tint: .blue, count: presentation.items.count)

            VStack(spacing: 0) {
                ForEach(Array(presentation.items.enumerated()), id: \.element.id) { index, item in
                    ReminderPresentationRow(item: item)
                    if index < presentation.items.count - 1 {
                        Divider()
                            .padding(.leading, 34)
                            .opacity(0.58)
                    }
                }
            }
        }
        .padding(12)
        .background(presentationBackground(tint: .blue))
    }

    private func compactGrid<Content: View>(
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 8, alignment: .top)
            ],
            alignment: .leading,
            spacing: 8
        ) {
            content()
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ChatTheme.systemBubbleFill.opacity(0.42))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tint.opacity(0.10))
                }
        )
    }

    private var genericView: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(presentation.items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if let detail = item.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(3)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(ChatTheme.systemBubbleFill.opacity(0.65))
                    )
                }
            }
            .padding(.top, 4)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.caption.weight(.semibold))
                if let subtitle = presentation.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
    }

    private func presentationHeader(systemImage: String, tint: Color, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(Circle().fill(tint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                if let subtitle = presentation.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Text(itemCountText(count))
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.12)))
        }
    }

    private func itemCountText(_ count: Int) -> String {
        if count == 1 {
            return NSLocalizedString("1 item", comment: "Tool presentation item count")
        }
        return String.localizedStringWithFormat(
            NSLocalizedString("%d items", comment: "Tool presentation item count"),
            count
        )
    }

    private func presentationBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(ChatTheme.systemBubbleFill.opacity(0.72))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.18))
            }
    }
}

private struct CalendarCompactPresentationRow: View {
    let item: ChatToolPresentationItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            compactDateBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    ToolPresentationChip(
                        text: timeText,
                        systemImage: item.metadata["all_day"] == "true" ? "sun.max" : "clock",
                        tint: .red
                    )
                    if let calendar = item.metadata["calendar"], !calendar.isEmpty {
                        ToolPresentationChip(text: calendar, systemImage: "calendar", tint: .secondary)
                    }
                }

                if let detail = item.detail, !detail.isEmpty {
                    Label(detail, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let notes = item.metadata["notes"], !notes.isEmpty {
                    Label(notes, systemImage: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(ChatTheme.systemBubbleFill.opacity(0.58))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.08))
                }
        )
    }

    private var dateInfo: ToolPresentationDateInterval {
        ToolPresentationDateInterval(subtitle: item.subtitle)
    }

    private var compactDateBadge: some View {
        VStack(spacing: 0) {
            Text(dateInfo.monthText ?? String(localized: "Event"))
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(dateInfo.dayText ?? "--")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .frame(width: 38)
        .frame(minHeight: 42)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.14))
                }
        )
    }

    private var timeText: String {
        if item.metadata["all_day"] == "true" {
            return String(localized: "All day")
        }
        if let range = dateInfo.timeRangeText, !range.isEmpty {
            return range
        }
        return item.subtitle ?? String(localized: "Time unavailable")
    }
}

private struct ReminderCompactPresentationRow: View {
    let item: ChatToolPresentationItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isCompleted ? .green : .blue)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .lineLimit(2)
                    .strikethrough(isCompleted, color: .secondary)

                HStack(spacing: 5) {
                    if let due = item.subtitle, !due.isEmpty {
                        ToolPresentationChip(text: dueText(due), systemImage: "clock", tint: .blue)
                    }
                    if let list = item.metadata["list"], !list.isEmpty {
                        ToolPresentationChip(text: list, systemImage: "list.bullet", tint: .secondary)
                    }
                    if priority > 0 {
                        ToolPresentationChip(text: "P\(priority)", systemImage: "flag.fill", tint: .orange)
                    }
                }

                if let notes = notesText {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(ChatTheme.systemBubbleFill.opacity(0.58))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder((isCompleted ? Color.green : Color.blue).opacity(0.08))
                }
        )
    }

    private var isCompleted: Bool {
        if let completed = item.metadata["completed"]?.lowercased() {
            return completed == "true"
        }
        return item.detail?.localizedCaseInsensitiveContains("completed") == true
    }

    private var priority: Int {
        Int(item.metadata["priority"] ?? "") ?? 0
    }

    private var notesText: String? {
        guard let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detail.isEmpty else {
            return nil
        }
        return detail
    }

    private func dueText(_ value: String) -> String {
        ToolPresentationDateFormatter.shortDateTimeText(value) ??
            String(value.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}

private struct CalendarPresentationRow: View {
    let item: ChatToolPresentationItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CalendarDateBadge(info: dateInfo)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    ToolPresentationChip(
                        text: timeText,
                        systemImage: item.metadata["all_day"] == "true" ? "sun.max" : "clock",
                        tint: .red
                    )
                    if let calendar = item.metadata["calendar"], !calendar.isEmpty {
                        ToolPresentationChip(text: calendar, systemImage: "calendar", tint: .secondary)
                    }
                }

                if let detail = item.detail, !detail.isEmpty {
                    Label(detail, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }

                if let notes = item.metadata["notes"], !notes.isEmpty {
                    Label(notes, systemImage: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateInfo: ToolPresentationDateInterval {
        ToolPresentationDateInterval(subtitle: item.subtitle)
    }

    private var timeText: String {
        if item.metadata["all_day"] == "true" {
            return String(localized: "All day")
        }
        if let range = dateInfo.timeRangeText, !range.isEmpty {
            return range
        }
        return item.subtitle ?? String(localized: "Time unavailable")
    }
}

private struct ReminderPresentationRow: View {
    let item: ChatToolPresentationItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isCompleted ? .green : .blue)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill((isCompleted ? Color.green : Color.blue).opacity(0.08))
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                        .lineLimit(2)
                        .strikethrough(isCompleted, color: .secondary)

                    Spacer(minLength: 0)

                    ToolPresentationChip(
                        text: isCompleted ? String(localized: "Done") : String(localized: "Open"),
                        systemImage: isCompleted ? "checkmark" : "circle",
                        tint: isCompleted ? .green : .blue
                    )
                }

                HStack(spacing: 5) {
                    if let due = item.subtitle, !due.isEmpty {
                        ToolPresentationChip(text: dueText(due), systemImage: "clock", tint: .blue)
                    }
                    if let list = item.metadata["list"], !list.isEmpty {
                        ToolPresentationChip(text: list, systemImage: "list.bullet", tint: .secondary)
                    }
                    if priority > 0 {
                        ToolPresentationChip(text: "P\(priority)", systemImage: "flag.fill", tint: .orange)
                    }
                }

                if let notes = notesText {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isCompleted: Bool {
        if let completed = item.metadata["completed"]?.lowercased() {
            return completed == "true"
        }
        return item.detail?.localizedCaseInsensitiveContains("completed") == true
    }

    private var priority: Int {
        Int(item.metadata["priority"] ?? "") ?? 0
    }

    private var notesText: String? {
        guard let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detail.isEmpty else {
            return nil
        }
        return detail
    }

    private func dueText(_ value: String) -> String {
        ToolPresentationDateFormatter.shortDateTimeText(value) ??
            String(value.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}

private struct CalendarDateBadge: View {
    let info: ToolPresentationDateInterval

    var body: some View {
        VStack(spacing: 1) {
            Text(info.monthText ?? String(localized: "Event"))
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(info.dayText ?? "--")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
            if let weekday = info.weekdayText {
                Text(weekday)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 48)
        .frame(minHeight: 52)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.red.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.12))
                }
        )
    }
}

private struct ToolPresentationChip: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.10)))
    }
}

private struct ToolPresentationDateInterval {
    let start: Date?
    let end: Date?
    let fallbackStartText: String?
    let fallbackEndText: String?

    init(subtitle: String?) {
        let parts = subtitle?
            .components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
        let startText = parts.first?.nilIfEmpty
        let endText = parts.dropFirst().first?.nilIfEmpty
        self.start = startText.flatMap(ToolPresentationDateFormatter.date)
        self.end = endText.flatMap(ToolPresentationDateFormatter.date)
        self.fallbackStartText = startText
        self.fallbackEndText = endText
    }

    var monthText: String? {
        start.map(ToolPresentationDateFormatter.monthText)
            ?? fallbackStartText.map { String($0.prefix(7).suffix(2)) }
    }

    var dayText: String? {
        start.map(ToolPresentationDateFormatter.dayText)
            ?? fallbackStartText.map { String($0.prefix(10).suffix(2)) }
    }

    var weekdayText: String? {
        start.map(ToolPresentationDateFormatter.weekdayText)
    }

    var timeRangeText: String? {
        if let start, let end {
            return "\(ToolPresentationDateFormatter.timeText(start)) - \(ToolPresentationDateFormatter.timeText(end))"
        }
        if let fallbackStartText, let fallbackEndText {
            let startTime = ToolPresentationDateFormatter.timeComponent(fallbackStartText)
            let endTime = ToolPresentationDateFormatter.timeComponent(fallbackEndText)
            if let startTime, let endTime {
                return "\(startTime) - \(endTime)"
            }
            return fallbackStartText
        }
        return fallbackStartText
    }
}

private enum ToolPresentationDateFormatter {
    static func date(_ value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        let fractionalISOFormatter = ISO8601DateFormatter()
        fractionalISOFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return isoFormatter.date(from: value) ?? fractionalISOFormatter.date(from: value)
    }

    static func monthText(_ date: Date) -> String {
        let monthFormatter = DateFormatter()
        monthFormatter.locale = .autoupdatingCurrent
        monthFormatter.setLocalizedDateFormatFromTemplate("MMM")
        return monthFormatter.string(from: date)
    }

    static func dayText(_ date: Date) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = .autoupdatingCurrent
        dayFormatter.setLocalizedDateFormatFromTemplate("d")
        return dayFormatter.string(from: date)
    }

    static func weekdayText(_ date: Date) -> String {
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = .autoupdatingCurrent
        weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE")
        return weekdayFormatter.string(from: date)
    }

    static func timeText(_ date: Date) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = .autoupdatingCurrent
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        return timeFormatter.string(from: date)
    }

    static func shortDateTimeText(_ value: String) -> String? {
        guard let date = date(value) else { return nil }
        let shortDateTimeFormatter = DateFormatter()
        shortDateTimeFormatter.locale = .autoupdatingCurrent
        shortDateTimeFormatter.dateStyle = .medium
        shortDateTimeFormatter.timeStyle = .short
        return shortDateTimeFormatter.string(from: date)
    }

    static func timeComponent(_ value: String) -> String? {
        let matches = value.matches(of: /\d{2}:\d{2}/).map { String($0.output) }
        return matches.first
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
