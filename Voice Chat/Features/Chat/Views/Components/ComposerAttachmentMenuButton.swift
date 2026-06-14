//
//  ComposerAttachmentMenuButton.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.13.
//

import SwiftUI

#if os(iOS)
import UIKit

@MainActor
@available(iOS 26.0, *)
struct ComposerAttachmentMenuButton: UIViewRepresentable {
    let tintColor: UIColor
    let buttonSize: CGFloat
    let glyphPointSize: CGFloat
    let onTakePhoto: @MainActor () -> Void
    let onChoosePhotos: @MainActor () -> Void
    let onChooseFiles: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = AttachmentMenuUIButton(type: .system)
        button.buttonSize = buttonSize
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = false
        button.accessibilityLabel = NSLocalizedString("Add image", comment: "Composer attachment button")
        applyButtonAppearance(to: button)
        button.menu = context.coordinator.makeMenu()
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        if let attachmentButton = button as? AttachmentMenuUIButton {
            attachmentButton.buttonSize = buttonSize
        }
        applyButtonAppearance(to: button)
        button.menu = context.coordinator.makeMenu()
    }

    private func applyButtonAppearance(to button: UIButton) {
        let glassTint = tintColor.withAlphaComponent(0.18)
        let baseConfiguration: UIButton.Configuration
        #if os(visionOS)
        baseConfiguration = .plain()
        #else
        baseConfiguration = .glass()
        #endif
        var configuration = baseConfiguration
        configuration.buttonSize = .small
        configuration.cornerStyle = .capsule
        configuration.image = UIImage(systemName: "plus")
        configuration.baseForegroundColor = tintColor
        configuration.baseBackgroundColor = glassTint
        configuration.background.backgroundColor = glassTint
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: glyphPointSize,
            weight: .semibold
        )
        configuration.contentInsets = .zero
        button.configuration = configuration
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.tintColor = tintColor
    }

    final class AttachmentMenuUIButton: UIButton {
        var buttonSize: CGFloat = 0 {
            didSet { invalidateIntrinsicContentSize() }
        }

        override var intrinsicContentSize: CGSize {
            CGSize(width: buttonSize, height: buttonSize)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            layer.cornerRadius = min(bounds.width, bounds.height) * 0.5
        }

        override func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            menuTargetedPreview()
        }

        override func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            menuTargetedPreview()
        }

        private func menuTargetedPreview() -> UITargetedPreview? {
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.visiblePath = UIBezierPath(ovalIn: bounds)
            let target = UIPreviewTarget(container: self, center: CGPoint(x: bounds.midX, y: bounds.midY))
            return UITargetedPreview(view: self, parameters: parameters, target: target)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ComposerAttachmentMenuButton

        init(parent: ComposerAttachmentMenuButton) {
            self.parent = parent
        }

        func makeMenu() -> UIMenu {
            UIMenu(children: [
                UIAction(
                    title: String(localized: "Take Photo", comment: "Attachment menu action"),
                    image: UIImage(systemName: "camera")
                ) { [weak self] _ in
                    self?.parent.onTakePhoto()
                },
                UIAction(
                    title: String(localized: "Choose Photos", comment: "Attachment menu action"),
                    image: UIImage(systemName: "photo.on.rectangle.angled")
                ) { [weak self] _ in
                    self?.parent.onChoosePhotos()
                },
                UIAction(
                    title: String(localized: "Choose Files", comment: "Attachment menu action"),
                    image: UIImage(systemName: "folder")
                ) { [weak self] _ in
                    self?.parent.onChooseFiles()
                }
            ])
        }
    }
}
#endif

#if os(macOS)
import AppKit

@MainActor
@available(macOS 26.0, *)
struct ComposerAttachmentMenuButton: NSViewRepresentable {
    let tintColor: NSColor
    let buttonSize: CGFloat
    let glyphPointSize: CGFloat
    let onTakePhoto: @MainActor () -> Void
    let onChoosePhotos: @MainActor () -> Void
    let onChooseFiles: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> AttachmentMenuButtonHostView {
        let hostView = AttachmentMenuButtonHostView()
        hostView.button.target = context.coordinator
        hostView.button.action = #selector(Coordinator.showMenu(_:))
        hostView.button.setAccessibilityLabel(NSLocalizedString("Add image", comment: "Composer attachment button"))
        context.coordinator.button = hostView.button
        applyAppearance(to: hostView)
        return hostView
    }

    func updateNSView(_ hostView: AttachmentMenuButtonHostView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.button = hostView.button
        applyAppearance(to: hostView)
    }

    private func applyAppearance(to hostView: AttachmentMenuButtonHostView) {
        let image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .semibold))
        hostView.button.image = image
        hostView.button.imagePosition = .imageOnly
        hostView.button.imageScaling = .scaleProportionallyDown
        hostView.button.contentTintColor = tintColor
        hostView.button.isBordered = false
        hostView.button.setButtonType(.momentaryPushIn)
        hostView.button.frame = NSRect(origin: .zero, size: NSSize(width: buttonSize, height: buttonSize))

        hostView.glassView.cornerRadius = buttonSize * 0.5
        hostView.glassView.style = .regular
        hostView.glassView.tintColor = tintColor.withAlphaComponent(0.12)
        hostView.buttonSize = buttonSize
        hostView.needsLayout = true
        hostView.layoutSubtreeIfNeeded()
    }

    final class AttachmentMenuButtonHostView: NSView {
        let glassView = NSGlassEffectView(frame: .zero)
        let button = NSButton(frame: .zero)
        var buttonSize: CGFloat = 0 {
            didSet {
                invalidateIntrinsicContentSize()
            }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            glassView.translatesAutoresizingMaskIntoConstraints = true
            button.translatesAutoresizingMaskIntoConstraints = true
            glassView.contentView = button
            addSubview(glassView)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: buttonSize, height: buttonSize)
        }

        override func layout() {
            super.layout()
            let size = NSSize(width: buttonSize, height: buttonSize)
            frame.size = size
            glassView.frame = bounds
            button.frame = glassView.bounds
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ComposerAttachmentMenuButton
        weak var button: NSButton?

        init(parent: ComposerAttachmentMenuButton) {
            self.parent = parent
        }

        @objc
        func showMenu(_ sender: NSButton) {
            let menu = NSMenu()

            let takePhotoItem = NSMenuItem(
                title: String(localized: "Take Photo", comment: "Attachment menu action"),
                action: #selector(handleTakePhoto),
                keyEquivalent: ""
            )
            takePhotoItem.target = self
            takePhotoItem.image = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)
            menu.addItem(takePhotoItem)

            let choosePhotosItem = NSMenuItem(
                title: String(localized: "Choose Photos", comment: "Attachment menu action"),
                action: #selector(handleChoosePhotos),
                keyEquivalent: ""
            )
            choosePhotosItem.target = self
            choosePhotosItem.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)
            menu.addItem(choosePhotosItem)

            let chooseFilesItem = NSMenuItem(
                title: String(localized: "Choose Files", comment: "Attachment menu action"),
                action: #selector(handleChooseFiles),
                keyEquivalent: ""
            )
            chooseFilesItem.target = self
            chooseFilesItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            menu.addItem(chooseFilesItem)

            NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent ?? NSEvent(), for: sender)
        }

        @objc
        func handleTakePhoto() {
            parent.onTakePhoto()
        }

        @objc
        func handleChoosePhotos() {
            parent.onChoosePhotos()
        }

        @objc
        func handleChooseFiles() {
            parent.onChooseFiles()
        }
    }
}
#endif
