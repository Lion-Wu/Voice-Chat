//
//  AutoSizingTextEditor.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI
import UniformTypeIdentifiers

enum AutoSizingTextEditorLayout {
    static let fontSize: CGFloat = 17
    static let verticalInset: CGFloat = InputMetrics.innerVertical

    static func minHeight(for lineHeight: CGFloat) -> CGFloat {
        ceil(lineHeight + verticalInset * 2)
    }

    static func maxHeight(for lineHeight: CGFloat, maxLines: Int) -> CGFloat {
        ceil(CGFloat(maxLines) * lineHeight + verticalInset * 2)
    }

    static func measuredHeight(contentHeight: CGFloat, lineHeight: CGFloat, maxLines: Int) -> CGFloat {
        let contentBoxHeight = ceil(contentHeight + verticalInset * 2)
        return min(maxHeight(for: lineHeight, maxLines: maxLines), max(minHeight(for: lineHeight), contentBoxHeight))
    }

    static func documentHeight(contentHeight: CGFloat, lineHeight: CGFloat) -> CGFloat {
        let contentBoxHeight = ceil(contentHeight + verticalInset * 2)
        return max(minHeight(for: lineHeight), contentBoxHeight)
    }

    static func shouldOverflow(contentHeight: CGFloat, lineHeight: CGFloat, maxLines: Int) -> Bool {
        measuredHeight(contentHeight: contentHeight, lineHeight: lineHeight, maxLines: maxLines) >= maxHeight(for: lineHeight, maxLines: maxLines) - 0.5
            && contentHeight + verticalInset * 2 > maxHeight(for: lineHeight, maxLines: maxLines) - 0.5
    }
}

#if os(macOS)
import AppKit

struct AutoSizingTextEditor: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    @Binding var text: String
    @Binding var height: CGFloat
    var externalTextRevision: UInt64 = 0
    var placeholder: String = ""
    var maxLines: Int = 10
    var allowsImagePasting: Bool = true
    var maxPastedImages: Int = .max
    var onOverflowChange: (Bool) -> Void = { _ in }
    var onCommit: () -> Void = {}
    var onPasteImages: ([(data: Data, mimeType: String?)]) -> Void = { _ in }

    private func lineHeight(for textView: NSTextView) -> CGFloat {
        textView.layoutManager?.defaultLineHeight(for: textView.font ?? .systemFont(ofSize: AutoSizingTextEditorLayout.fontSize))
            ?? InputMetrics.baseLineHeight
    }

    private func layoutContentWidth(for textView: NSTextView) -> CGFloat {
        max(textView.enclosingScrollView?.contentSize.width ?? textView.bounds.width, 1)
    }

    private func scheduleStateUpdate(
        measuredHeight: CGFloat,
        overflow: Bool
    ) {
        DispatchQueue.main.async {
            if abs(height - measuredHeight) > 0.5 {
                height = measuredHeight
            }
            onOverflowChange(overflow)
        }
    }

    private func updateMacLayout(for textView: CommitTextView, maxLines: Int) -> (height: CGFloat, shouldOverflow: Bool) {
        let contentWidth = layoutContentWidth(for: textView)
        let lineFragmentPadding = textView.textContainer?.lineFragmentPadding ?? 0
        let horizontalInsets = textView.textContainerInset.width * 2 + lineFragmentPadding * 2
        let layoutWidth = max(contentWidth - horizontalInsets, 1)
        textView.textContainer?.containerSize = NSSize(width: layoutWidth, height: CGFloat.greatestFiniteMagnitude)

        guard let textContainer = textView.textContainer else {
            return (AutoSizingTextEditorLayout.minHeight(for: InputMetrics.baseLineHeight), false)
        }

        textView.layoutManager?.ensureLayout(for: textContainer)

        let used = textView.layoutManager?.usedRect(for: textContainer) ?? .zero
        let lineHeight = lineHeight(for: textView)
        let measuredHeight = AutoSizingTextEditorLayout.measuredHeight(
            contentHeight: used.height,
            lineHeight: lineHeight,
            maxLines: maxLines
        )
        let documentHeight = AutoSizingTextEditorLayout.documentHeight(
            contentHeight: used.height,
            lineHeight: lineHeight
        )
        let shouldOverflow = AutoSizingTextEditorLayout.shouldOverflow(
            contentHeight: used.height,
            lineHeight: lineHeight,
            maxLines: maxLines
        )

        let targetSize = NSSize(width: contentWidth, height: documentHeight)
        if abs(textView.frame.width - targetSize.width) > 0.5 || abs(textView.frame.height - targetSize.height) > 0.5 {
            textView.setFrameSize(targetSize)
        }

        return (measuredHeight, shouldOverflow)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = CommitTextView(frame: NSRect(x: 0, y: 0, width: 1, height: InputMetrics.defaultHeight), textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: AutoSizingTextEditorLayout.fontSize)
        textView.backgroundColor = NSColor.clear
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.focusRingType = .none
        textView.placeholder = placeholder
        textView.textContainerInset = NSSize(width: InputMetrics.innerLeading, height: AutoSizingTextEditorLayout.verticalInset)
        textView.isRichText = false
        textView.isAutomaticDataDetectionEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 1, height: InputMetrics.defaultHeight)
        textView.autoresizingMask = [.width]
        textView.string = text

        textView.delegate = context.coordinator
        textView.onCommit = onCommit
        textView.allowsImagePasting = allowsImagePasting
        textView.maxPastedImages = maxPastedImages
        textView.onPasteImages = onPasteImages

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lastAppliedExternalTextRevision = externalTextRevision
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = context.coordinator.textView else { return }
        tv.allowsImagePasting = allowsImagePasting
        tv.maxPastedImages = maxPastedImages
        tv.onPasteImages = onPasteImages
        tv.onCommit = onCommit
        tv.placeholder = placeholder
        let isComposing = tv.hasMarkedText()
        var appliedExternalText = false
        if !isComposing,
           context.coordinator.lastAppliedExternalTextRevision != externalTextRevision {
            context.coordinator.lastAppliedExternalTextRevision = externalTextRevision
            if tv.string != text {
                tv.string = text
                appliedExternalText = true
            }
        }

        let contentWidth = layoutContentWidth(for: tv)
        let layoutWidthChanged = context.coordinator.lastLayoutContentWidth.map {
            abs($0 - contentWidth) > 0.5
        } ?? true
        let layoutConfigurationChanged = layoutWidthChanged
            || context.coordinator.lastMaxLines != maxLines
        if appliedExternalText || layoutConfigurationChanged {
            let measured = updateMacLayout(for: tv, maxLines: maxLines)
            context.coordinator.recordLayout(contentWidth: contentWidth, maxLines: maxLines)
            scheduleStateUpdate(measuredHeight: measured.height, overflow: measured.shouldOverflow)
        }

        if appliedExternalText {
            if let selected = tv.selectedRanges.first as? NSRange {
                tv.scrollRangeToVisible(selected)
            } else {
                let end = NSRange(location: (tv.string as NSString).length, length: 0)
                tv.scrollRangeToVisible(end)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoSizingTextEditor
        weak var textView: CommitTextView?
        var lastAppliedExternalTextRevision: UInt64?
        var lastLayoutContentWidth: CGFloat?
        var lastMaxLines: Int?

        init(parent: AutoSizingTextEditor) { self.parent = parent }

        func recordLayout(contentWidth: CGFloat, maxLines: Int) {
            lastLayoutContentWidth = contentWidth
            lastMaxLines = maxLines
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            guard let commitTextView = tv as? CommitTextView else { return }
            if parent.text != tv.string {
                parent.text = tv.string
            }
            commitTextView.refreshPresentationState()
            let measured = parent.updateMacLayout(for: commitTextView, maxLines: parent.maxLines)
            recordLayout(
                contentWidth: parent.layoutContentWidth(for: commitTextView),
                maxLines: parent.maxLines
            )
            parent.scheduleStateUpdate(
                measuredHeight: measured.height,
                overflow: measured.shouldOverflow
            )

            if !tv.hasMarkedText() {
                let end = NSRange(location: (tv.string as NSString).length, length: 0)
                tv.scrollRangeToVisible(end)
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSTextView.insertNewline(_:)),
                  let commitTextView = textView as? CommitTextView,
                  !commitTextView.hasMarkedText(),
                  let event = NSApp.currentEvent,
                  event.type == .keyDown,
                  [UInt16(36), UInt16(76)].contains(event.keyCode) else {
                return false
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let nonSubmittingModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
            guard modifiers.intersection(nonSubmittingModifiers).isEmpty else {
                return false
            }

            commitTextView.onCommit()
            return true
        }
    }

    final class CommitTextView: NSTextView {
        private struct PastedImageImportCandidate: Sendable {
            let itemIndex: Int
            let fileURL: URL?
            let data: Data?
            let mimeTypeHint: String?
        }

        var placeholder: String = "" {
            didSet {
                guard oldValue != placeholder else { return }
                needsDisplay = true
                updateAccessibilityMetadata()
            }
        }
        var allowsImagePasting: Bool = true
        var maxPastedImages: Int = .max
        var onCommit: () -> Void = {}
        var onPasteImages: ([(data: Data, mimeType: String?)]) -> Void = { _ in }

        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override var string: String {
            didSet {
                refreshPresentationState()
            }
        }

        override var font: NSFont? {
            didSet { refreshPresentationState() }
        }

        override var textContainerInset: NSSize {
            didSet { refreshPresentationState() }
        }

        private func updateAccessibilityMetadata() {
            let accessibilityPrompt = placeholder.trimmingCharacters(in: .whitespacesAndNewlines)
            setAccessibilityPlaceholderValue(accessibilityPrompt.isEmpty ? nil : accessibilityPrompt)
        }

        func refreshPresentationState() {
            needsDisplay = true
            updateAccessibilityMetadata()
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            guard string.isEmpty, !placeholder.isEmpty else { return }

            let placeholderFont = font ?? .systemFont(ofSize: AutoSizingTextEditorLayout.fontSize)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = alignment
            paragraphStyle.lineBreakMode = .byTruncatingTail

            let attributes: [NSAttributedString.Key: Any] = [
                .font: placeholderFont,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]

            let rect = placeholderDrawingRect()
            (placeholder as NSString).draw(in: rect, withAttributes: attributes)
        }

        private func placeholderDrawingRect() -> NSRect {
            let lineFragmentPadding = textContainer?.lineFragmentPadding ?? 0
            let origin = textContainerOrigin
            return NSRect(
                x: origin.x + lineFragmentPadding,
                y: origin.y,
                width: max(0, bounds.width - (origin.x + lineFragmentPadding + textContainerInset.width + lineFragmentPadding)),
                height: max(0, bounds.height - origin.y - textContainerInset.height)
            )
        }

        override func paste(_ sender: Any?) {
            guard allowsImagePasting else {
                super.paste(sender)
                return
            }

            let pasteboard = NSPasteboard.general
            let candidates = imageImportCandidates(from: pasteboard)
            guard !candidates.isEmpty else {
                super.paste(sender)
                return
            }

            let limitedCandidates = Array(candidates.prefix(max(0, maxPastedImages)))
            guard !limitedCandidates.isEmpty else {
                if Self.pasteboardContainsNonEmptyText(pasteboard) {
                    super.paste(sender)
                }
                return
            }

            let shouldAlsoPasteText = shouldAlsoPasteText(from: pasteboard, over: limitedCandidates)
            if shouldAlsoPasteText {
                super.paste(sender)
            }

            Task(priority: .utility) { [weak self, limitedCandidates] in
                let imported = await Self.importedImages(from: limitedCandidates)
                guard !imported.isEmpty else { return }
                await MainActor.run {
                    self?.onPasteImages(imported)
                }
            }
        }

        private func shouldAlsoPasteText(
            from pasteboard: NSPasteboard,
            over candidates: [PastedImageImportCandidate]
        ) -> Bool {
            guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return false }
            let imageItemIndices = Set(candidates.map(\.itemIndex))

            for (index, item) in items.enumerated() {
                let plainText = item.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let plainText, !plainText.isEmpty, !imageItemIndices.contains(index) {
                    return true
                }
            }

            return false
        }

        private static func pasteboardContainsNonEmptyText(_ pasteboard: NSPasteboard) -> Bool {
            guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return false }

            return items.contains { item in
                guard let plainText = item.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return false
                }
                return !plainText.isEmpty
            }
        }

        private func imageImportCandidates(from pasteboard: NSPasteboard) -> [PastedImageImportCandidate] {
            guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return [] }

            var candidates: [PastedImageImportCandidate] = []
            candidates.reserveCapacity(items.count)

            for (index, item) in items.enumerated() {
                if let fileCandidate = imageFileCandidate(from: item, itemIndex: index) {
                    candidates.append(fileCandidate)
                    continue
                }

                for type in item.types {
                    guard let resolvedType = UTType(type.rawValue),
                          resolvedType.conforms(to: .image),
                          let data = item.data(forType: type),
                          !data.isEmpty else {
                        continue
                    }

                    candidates.append(
                        PastedImageImportCandidate(
                            itemIndex: index,
                            fileURL: nil,
                            data: data,
                            mimeTypeHint: resolvedType.preferredMIMEType
                        )
                    )
                    break
                }
            }

            return candidates
        }

        nonisolated private static func importedImages(from candidates: [PastedImageImportCandidate]) async -> [(data: Data, mimeType: String?)] {
            await Task.detached(priority: .utility) {
                candidates.compactMap(importedImagePayload(from:))
            }.value
        }

        nonisolated private static func importedImagePayload(from candidate: PastedImageImportCandidate) -> (data: Data, mimeType: String?)? {
            if let fileURL = candidate.fileURL {
                return importedImageFilePayload(from: fileURL)
            }

            guard let data = candidate.data, !data.isEmpty else { return nil }
            return PastedImagePayloadNormalizer.normalize(data: data, mimeTypeHint: candidate.mimeTypeHint)
        }

        private func imageFileCandidate(from item: NSPasteboardItem, itemIndex: Int) -> PastedImageImportCandidate? {
            guard let fileURLData = item.data(forType: .fileURL),
                  let fileURL = URL(dataRepresentation: fileURLData, relativeTo: nil),
                  Self.fileURLMayContainImage(fileURL) else {
                return nil
            }

            return PastedImageImportCandidate(
                itemIndex: itemIndex,
                fileURL: fileURL,
                data: nil,
                mimeTypeHint: nil
            )
        }

        nonisolated private static func fileURLMayContainImage(_ fileURL: URL) -> Bool {
            if let contentType = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
                return contentType.conforms(to: .image)
            }

            let pathExtension = fileURL.pathExtension
            guard !pathExtension.isEmpty,
                  let inferredType = UTType(filenameExtension: pathExtension) else {
                return false
            }

            return inferredType.conforms(to: .image)
        }

        nonisolated private static func importedImageFilePayload(from fileURL: URL) -> (data: Data, mimeType: String?)? {
            let didStartSecurityScope = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didStartSecurityScope {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            let contentType = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            if let contentType, !contentType.conforms(to: .image) {
                return nil
            }

            guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
                return nil
            }

            return PastedImagePayloadNormalizer.normalize(data: data, mimeTypeHint: contentType?.preferredMIMEType)
        }
    }
}
#endif
