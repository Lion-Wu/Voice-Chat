//
//  ChatComposerAttachmentButton.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.14.
//

import SwiftUI

#if os(iOS) || os(macOS) || os(visionOS)
#if os(iOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ChatComposerAttachmentButton: View {
    let supportsImageInput: Bool
    let buttonDiameter: CGFloat
    let glyphSize: CGFloat
    let defaultMainBarHeight: CGFloat
    let remainingSlots: Int
    let onLimitReached: @MainActor () -> Void
    let onTakePhoto: @MainActor () -> Void
    let onChoosePhotos: @MainActor () -> Void
    let onChooseFiles: @MainActor () -> Void

    var body: some View {
        #if os(iOS) || os(macOS) || os(visionOS)
        if supportsImageInput {
            platformAttachmentButton
        }
        #endif
    }

    @ViewBuilder
    private var platformAttachmentButton: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            ComposerAttachmentMenuButton(
                tintColor: UIColor(ChatTheme.accent),
                buttonSize: buttonDiameter,
                glyphPointSize: glyphSize,
                onTakePhoto: { performIfCapacityAvailable(onTakePhoto) },
                onChoosePhotos: { performIfCapacityAvailable(onChoosePhotos) },
                onChooseFiles: { performIfCapacityAvailable(onChooseFiles) }
            )
            .frame(width: buttonDiameter, height: buttonDiameter)
        } else {
            fallbackAttachmentMenu
                .frame(height: defaultMainBarHeight, alignment: .center)
        }
        #elseif os(visionOS)
        fallbackAttachmentMenu
            .frame(height: defaultMainBarHeight, alignment: .center)
        #elseif os(macOS)
        if #available(macOS 26.0, *) {
            Menu {
                attachmentMenuActions
            } label: {
                ZStack {
                    Circle()
                        .fill(.clear)

                    Image(systemName: "plus")
                        .font(.system(size: glyphSize, weight: .semibold))
                        .foregroundStyle(ChatTheme.accent)
                }
                .frame(width: buttonDiameter, height: buttonDiameter)
                .contentShape(Circle())
            }
            .frame(width: buttonDiameter, height: buttonDiameter)
            .glassEffect(
                .regular.tint(ChatTheme.accent.opacity(0.12)).interactive(),
                in: .circle
            )
            .contentShape(Circle())
            .buttonStyle(.plain)
        } else {
            fallbackAttachmentMenu
        }
        #endif
    }

    private var fallbackAttachmentMenu: some View {
        Menu {
            attachmentMenuActions
        } label: {
            Label("Add image", systemImage: "plus.circle.fill")
                .labelStyle(.iconOnly)
                .font(.system(size: 26, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ChatTheme.accent)
                .frame(width: 30, height: 30)
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var attachmentMenuActions: some View {
        #if !os(visionOS)
        Button("Take Photo", systemImage: "camera") {
            performIfCapacityAvailable(onTakePhoto)
        }

        Divider()
        #endif

        Button("Choose Photos", systemImage: "photo.on.rectangle.angled") {
            performIfCapacityAvailable(onChoosePhotos)
        }

        Button("Choose Files", systemImage: "folder") {
            performIfCapacityAvailable(onChooseFiles)
        }
    }

    @MainActor
    private func performIfCapacityAvailable(_ action: @MainActor () -> Void) {
        guard remainingSlots > 0 else {
            onLimitReached()
            return
        }
        action()
    }
}
#endif
