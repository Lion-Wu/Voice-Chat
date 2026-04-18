//
//  AppLocalization.swift
//  Voice Chat
//
//  Created by Lion Wu on 2023/12/25.
//

import Foundation

enum AppLocalization {
    static var supportedLocalizationIdentifiers: [String] {
        Bundle.main.localizations.filter { $0 != "Base" }
    }

    static func localizedPlaceholderTitles() -> Set<String> {
        var identifiers = Set(supportedLocalizationIdentifiers)
        identifiers.insert("en")
        identifiers.insert(Locale.current.identifier)

        return Set(
            identifiers.map { identifier in
                String(localized: "New Chat", locale: Locale(identifier: identifier))
            }
        )
    }
}
