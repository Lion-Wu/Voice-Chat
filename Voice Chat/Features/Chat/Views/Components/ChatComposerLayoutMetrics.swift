//
//  ChatComposerLayoutMetrics.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

struct ChatComposerLayoutMetrics: Equatable {
    let textFieldHeight: CGFloat
    let editingBannerHeight: CGFloat
    let pendingAttachmentCount: Int
    let queuedDraftCount: Int
    let hasQueuedDrafts: Bool
    let isEditingComposerDraft: Bool
    let hasConfigurableThinking: Bool

    var messageListHorizontalPadding: CGFloat {
        #if os(macOS)
        return 16
        #elseif os(visionOS)
        return 20
        #else
        return 8
        #endif
    }

    var messageListTopPadding: CGFloat {
        #if os(visionOS)
        return 18
        #else
        return 12
        #endif
    }

    var floatingInputButtonHeight: CGFloat {
        textFieldHeight + InputMetrics.composerOuterV * 2
    }

    var composerDefaultTrailingButtonTrackHeight: CGFloat {
        InputMetrics.defaultHeight + InputMetrics.composerOuterV * 2
    }

    var composerDefaultMainBarHeight: CGFloat {
        InputMetrics.defaultHeight + InputMetrics.composerOuterV * 2 + composerOuterVerticalPadding * 2
    }

    var composerMainBarHeight: CGFloat {
        floatingInputButtonHeight + composerOuterVerticalPadding * 2
    }

    var pendingAttachmentStripHeight: CGFloat {
        pendingAttachmentCount > 0 ? 88 : 0
    }

    var thinkingControlHeight: CGFloat {
        hasConfigurableThinking ? 34 : 0
    }

    var queuedDraftRowHeight: CGFloat {
        32
    }

    var queuedDraftHeight: CGFloat {
        hasQueuedDrafts ? CGFloat(queuedDraftCount) * queuedDraftRowHeight + 2 : 0
    }

    var estimatedFloatingInputPanelHeight: CGFloat {
        composerMainBarHeight + composerSupportingContentEstimatedHeight
    }

    var composerBottomPadding: CGFloat {
        #if os(iOS) || os(tvOS)
        return 8
        #elseif os(visionOS)
        return 24
        #else
        return 14
        #endif
    }

    var composerOuterVerticalPadding: CGFloat {
        #if os(iOS) || os(tvOS)
        return 4
        #elseif os(visionOS)
        return 6
        #else
        return 2
        #endif
    }

    var composerPanelHorizontalPadding: CGFloat {
        #if os(visionOS)
        return 16
        #else
        return 12
        #endif
    }

    var composerBarCornerRadius: CGFloat {
        #if os(visionOS)
        return 28
        #else
        return 24
        #endif
    }

    var composerSupportSectionSpacing: CGFloat {
        #if os(visionOS)
        return 10
        #else
        return 8
        #endif
    }

    var composerSupportTopPadding: CGFloat {
        #if os(visionOS)
        return 12
        #else
        return 8
        #endif
    }

    var composerSupportBottomPadding: CGFloat {
        #if os(visionOS)
        return 10
        #else
        return 6
        #endif
    }

    var composerSupportHorizontalPadding: CGFloat {
        #if os(visionOS)
        return 14
        #else
        return 10
        #endif
    }

    var composerAccessoryTapSize: CGFloat {
        #if os(iOS) || os(tvOS)
        return 32
        #else
        return 28
        #endif
    }

    var composerAttachmentButtonDiameter: CGFloat {
        composerDefaultMainBarHeight
    }

    var composerAttachmentGlyphSize: CGFloat {
        17
    }

    var editingBannerEstimatedHeight: CGFloat {
        #if os(iOS) || os(tvOS)
        return 40
        #else
        return 38
        #endif
    }

    var hasComposerSupportingContent: Bool {
        isEditingComposerDraft
            || hasQueuedDrafts
            || hasConfigurableThinking
            || pendingAttachmentCount > 0
    }

    var composerSupportingContentEstimatedHeight: CGFloat {
        guard hasComposerSupportingContent else { return 0 }

        var height: CGFloat = 0
        if isEditingComposerDraft {
            height += max(editingBannerHeight, editingBannerEstimatedHeight)
        }
        if hasQueuedDrafts {
            height += (height > 0 ? 8 : 0) + queuedDraftHeight
        }
        if hasConfigurableThinking {
            height += (height > 0 ? composerSupportSectionSpacing : 0) + thinkingControlHeight
        }
        if pendingAttachmentCount > 0 {
            height += (height > 0 ? composerSupportSectionSpacing : 0) + pendingAttachmentStripHeight
        }

        return height + composerSupportTopPadding + composerSupportBottomPadding + 1
    }

    var messageListBottomInset: CGFloat {
        #if os(iOS) || os(tvOS)
        return 14
        #elseif os(visionOS)
        return 18
        #else
        return 12
        #endif
    }

    var scrollButtonSize: CGFloat {
        #if os(iOS) || os(tvOS)
        return 40
        #else
        return 34
        #endif
    }

    var floatingPanelHorizontalInset: CGFloat {
        #if os(visionOS)
        return 24
        #else
        return 16
        #endif
    }
}
