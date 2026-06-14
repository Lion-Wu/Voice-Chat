import SwiftUI

enum SidebarTimeSection: Int, CaseIterable, Identifiable {
    case today
    case yesterday
    case last7Days
    case last30Days
    case pastYear
    case older

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .today:
            return "Today"
        case .yesterday:
            return "Yesterday"
        case .last7Days:
            return "Last 7 Days"
        case .last30Days:
            return "Last 30 Days"
        case .pastYear:
            return "Past Year"
        case .older:
            return "Older"
        }
    }

    static func from(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> SidebarTimeSection {
        if calendar.isDateInToday(date) {
            return .today
        }
        if calendar.isDateInYesterday(date) {
            return .yesterday
        }

        let startOfToday = calendar.startOfDay(for: Date())
        if let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday),
           date >= sevenDaysAgo {
            return .last7Days
        }
        if let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday),
           date >= thirtyDaysAgo {
            return .last30Days
        }
        if let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: startOfToday),
           date >= oneYearAgo {
            return .pastYear
        }
        return .older
    }
}

struct SidebarSessionGroup: Identifiable {
    let section: SidebarTimeSection
    let sessions: [ChatSession]

    var id: SidebarTimeSection { section }
}

enum SidebarSessionGrouping {
    static func groupedSessions(_ sessions: [ChatSession]) -> [SidebarSessionGroup] {
        let calendar = Calendar.autoupdatingCurrent
        var grouped: [SidebarTimeSection: [ChatSession]] = [:]

        for session in sessions {
            let section = SidebarTimeSection.from(session.lastActivityAt, calendar: calendar)
            grouped[section, default: []].append(session)
        }

        return SidebarTimeSection.allCases.compactMap { section in
            guard let sessions = grouped[section], !sessions.isEmpty else { return nil }
            return SidebarSessionGroup(section: section, sessions: sessions)
        }
    }
}
