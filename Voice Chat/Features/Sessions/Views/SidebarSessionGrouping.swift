import SwiftUI

struct SidebarDaySection: Identifiable, Hashable {
    let startDate: Date

    var id: Date { startDate }

    var title: Text {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(startDate) {
            return Text("Today")
        }
        if calendar.isDateInYesterday(startDate) {
            return Text("Yesterday")
        }
        return Text(startDate, format: Self.dateFormatStyle(calendar: calendar))
    }

    static func dateFormatStyle(calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(
            date: .omitted,
            time: .omitted,
            calendar: calendar
        )
        .year()
        .month()
        .day()
    }
}

struct SidebarSessionGroup: Identifiable {
    let section: SidebarDaySection
    let sessions: [ChatSession]

    var id: SidebarDaySection { section }
}

enum SidebarSessionListLoadState: Equatable {
    case loading
    case ready

    static func resolve(
        isPersistentStoreAttached: Bool,
        hasSessions: Bool,
        hasPublishedGroups: Bool,
        visibleSearchKeyword: String
    ) -> Self {
        guard isPersistentStoreAttached else { return .loading }
        if visibleSearchKeyword.isEmpty, hasSessions, !hasPublishedGroups {
            return .loading
        }
        return .ready
    }
}

enum SidebarSessionGrouping {
    static func groupedSessions(
        _ sessions: [ChatSession],
        calendar: Calendar = .autoupdatingCurrent
    ) -> [SidebarSessionGroup] {
        var grouped: [Date: [ChatSession]] = [:]

        for session in sessions {
            let startDate = calendar.startOfDay(for: session.lastActivityAt)
            grouped[startDate, default: []].append(session)
        }

        return grouped.keys.sorted(by: >).compactMap { startDate in
            guard let sessions = grouped[startDate], !sessions.isEmpty else { return nil }
            return SidebarSessionGroup(
                section: SidebarDaySection(startDate: startDate),
                sessions: sessions
            )
        }
    }

    static func hasSameLayout(
        _ current: [SidebarSessionGroup],
        as proposed: [SidebarSessionGroup]
    ) -> Bool {
        guard current.count == proposed.count else { return false }
        return zip(current, proposed).allSatisfy { currentGroup, proposedGroup in
            guard currentGroup.section == proposedGroup.section,
                  currentGroup.sessions.count == proposedGroup.sessions.count else {
                return false
            }
            return zip(currentGroup.sessions, proposedGroup.sessions).allSatisfy {
                $0.id == $1.id && $0 === $1
            }
        }
    }
}
