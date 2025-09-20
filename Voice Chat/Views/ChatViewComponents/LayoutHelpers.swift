//
//  LayoutHelpers.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif

@MainActor
func contentMaxWidthForAssistant() -> CGFloat {
    #if os(iOS) || os(tvOS) || os(watchOS)
    return min(UIScreen.main.bounds.width - 16, 680)
    #elseif os(macOS)
    return min((NSScreen.main?.frame.width ?? 1200) - 80, 900)
    #else
    return 680
    #endif
}

@MainActor
func contentMaxWidthForUser() -> CGFloat {
    #if os(iOS) || os(tvOS) || os(watchOS)
    return min(UIScreen.main.bounds.width - 16, 680)
    #elseif os(macOS)
    return min((NSScreen.main?.frame.width ?? 1200) - 80, 900)
    #else
    return 680
    #endif
}

@MainActor
func contentColumnMaxWidth() -> CGFloat {
    return max(contentMaxWidthForAssistant(), contentMaxWidthForUser())
}

@MainActor
func platformMaxLines() -> Int {
    #if os(macOS)
    return 10
    #else
    return 6
    #endif
}

#if os(iOS) || os(tvOS)
@MainActor
func isPhone() -> Bool {
    return UIDevice.current.userInterfaceIdiom == .phone
}
#endif
