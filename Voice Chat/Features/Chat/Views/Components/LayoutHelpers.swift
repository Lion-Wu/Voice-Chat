//
//  LayoutHelpers.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI

@MainActor
func contentMaxWidthForAssistant(availableWidth: CGFloat? = nil) -> CGFloat {
    #if os(macOS)
    let maximumWidth: CGFloat = 900
    let horizontalInset: CGFloat = 80
    #elseif os(visionOS)
    let maximumWidth: CGFloat = 760
    let horizontalInset: CGFloat = 40
    #else
    let maximumWidth: CGFloat = 680
    let horizontalInset: CGFloat = 16
    #endif

    guard let availableWidth else { return maximumWidth }
    return min(max(availableWidth - horizontalInset, 0), maximumWidth)
}

@MainActor
func contentMaxWidthForUser(availableWidth: CGFloat? = nil) -> CGFloat {
    contentMaxWidthForAssistant(availableWidth: availableWidth)
}

@MainActor
func contentColumnMaxWidth(availableWidth: CGFloat? = nil) -> CGFloat {
    max(
        contentMaxWidthForAssistant(availableWidth: availableWidth),
        contentMaxWidthForUser(availableWidth: availableWidth)
    )
}

@MainActor
func composerPanelMaxWidth(availableWidth: CGFloat? = nil) -> CGFloat {
    #if os(macOS)
    let additionalWidth: CGFloat = 64
    #elseif os(visionOS)
    let additionalWidth: CGFloat = 88
    #else
    let additionalWidth: CGFloat = isPhone() ? 24 : 48
    #endif

    let expandedWidth = contentColumnMaxWidth(availableWidth: availableWidth) + additionalWidth
    guard let availableWidth else { return expandedWidth }
    return min(availableWidth, expandedWidth)
}

@MainActor
func platformMaxLines() -> Int {
    #if os(macOS)
    return 10
    #else
    return 6
    #endif
}

#if os(iOS) || os(tvOS) || os(visionOS)
@MainActor
func isPhone() -> Bool {
    return UIDevice.current.userInterfaceIdiom == .phone
}
#endif
