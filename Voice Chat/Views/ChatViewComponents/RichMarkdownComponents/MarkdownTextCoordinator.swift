//
//  MarkdownTextCoordinator.swift
//  Voice Chat
//

@preconcurrency import Foundation
import SwiftUI

#if os(iOS) || os(tvOS) || os(watchOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

@MainActor
final class MarkdownTextCoordinator: NSObject, @unchecked Sendable {
    private var lastMarkdown: String = ""
    private var lastStyleKey: String = ""
    private var currentRenderID: UInt64 = 0
    private var attachments: [MarkdownAttachment] = []
    private var lastLayoutWidth: CGFloat = 0
    private weak var currentTextView: MarkdownPlatformTextView?

    private let renderQueue = DispatchQueue(label: "voicechat.markdown.render", qos: .userInitiated)
    private let imageLoader = MarkdownImageLoader.shared

    private var streamingState: MarkdownStreamingState?
    private var streamingCommittedMarkdownUTF16Count: Int = 0
    private var streamingCommittedAttributedString: NSMutableAttributedString?
    private var streamingCommittedAttachments: [MarkdownAttachment] = []
    private var streamingCommittedStyleKey: String = ""
    private var streamingCommittedOrderedList: MarkdownStreamingState.OrderedListRenderState?
    private weak var streamingActiveTailAttachment: MarkdownAttachment?
    private var streamingActiveTailAttachmentRange: NSRange?
    private weak var streamingActiveTableAttachment: MarkdownTableAttachment?
    private var streamingActiveTableLineBuffer: String = ""
    private var streamingActiveTableHasDraftRow: Bool = false
    private var streamingActiveTableDraftLine: String = ""
    private weak var pendingInvalidationTextView: MarkdownPlatformTextView?
    private var pendingInvalidationRange: NSRange?
    private var pendingInvalidationScheduled: Bool = false

    private struct SendableAttributes: @unchecked Sendable {
        let attributes: [NSAttributedString.Key: Any]
    }

    private func needsBlockSeparator(prefix: NSAttributedString, next: NSAttributedString) -> Bool {
        guard prefix.length > 0, next.length > 0 else { return false }
        if prefix.string.hasSuffix("\n") { return false }
        if next.string.hasPrefix("\n") { return false }
        return true
    }

    private func tailWithSeparator(
        prefix: NSAttributedString,
        tail: NSAttributedString,
        newlineAttributes: SendableAttributes
    ) -> NSAttributedString {
        guard needsBlockSeparator(prefix: prefix, next: tail) else { return tail }
        let combined = NSMutableAttributedString(string: "\n", attributes: newlineAttributes.attributes)
        combined.append(tail)
        return combined
    }

    func updateLayoutWidth(_ width: CGFloat) {
        let resolved = resolveLayoutWidth(width, textView: currentTextView)
        guard resolved > 1 else { return }
        guard abs(resolved - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = resolved
        updateAttachmentWidth()
        if let textView = currentTextView {
            invalidateLayout(for: textView, changedRange: nil)
        }
    }

    func update(
        textView: MarkdownPlatformTextView,
        markdown: String,
        colorScheme: ColorScheme,
        sizeCategory: ContentSizeCategory,
        force: Bool = false
    ) {
        currentTextView = textView
        let resolvedScheme = resolvedColorScheme(for: textView, fallback: colorScheme)
        let style = MarkdownStyle(colorScheme: resolvedScheme, sizeCategory: sizeCategory)
        let styleKey = style.cacheKey
        configure(textView: textView, style: style)
        if lastLayoutWidth <= 1 {
            let width = resolveLayoutWidth(textView.bounds.width, textView: textView)
            if width > 1 { lastLayoutWidth = width }
        }

        if !force, markdown == lastMarkdown && styleKey == lastStyleKey {
            return
        }

        if !force,
           styleKey == lastStyleKey,
           attemptIncrementalAppend(to: textView, newMarkdown: markdown, style: style) {
            lastMarkdown = markdown
            return
        }

        if !force,
           styleKey == lastStyleKey,
           attemptSegmentedStreamingUpdate(to: textView, newMarkdown: markdown, style: style, styleKey: styleKey) {
            return
        }

        renderMarkdown(markdown, style: style, styleKey: styleKey, textView: textView)
    }

    private func configure(textView: MarkdownPlatformTextView, style: MarkdownStyle) {
        #if os(iOS) || os(tvOS) || os(watchOS)
        textView.tintColor = style.linkColor
        #endif
        textView.linkTextAttributes = style.linkAttributes
    }

    private func attemptIncrementalAppend(
        to textView: MarkdownPlatformTextView,
        newMarkdown: String,
        style: MarkdownStyle
    ) -> Bool {
        guard !lastMarkdown.isEmpty, newMarkdown.hasPrefix(lastMarkdown) else { return false }
        let delta = String(newMarkdown.dropFirst(lastMarkdown.count))
        guard !delta.isEmpty else { return true }
        guard isSafePlainAppend(delta) else { return false }
        guard let storage = textStorage(for: textView), storage.length > 0 else { return false }

        let lastIndex = max(0, storage.length - 1)
        let lastAttributes = storage.attributes(at: lastIndex, effectiveRange: nil)
        guard attributesAreBase(lastAttributes, style: style) else { return false }

        currentRenderID &+= 1

        var attrs = style.baseAttributes
        attrs[.paragraphStyle] = lastAttributes[.paragraphStyle] ?? style.paragraphStyle()
        let appended = NSAttributedString(string: delta, attributes: attrs)
        let oldLength = storage.length
        storage.append(appended)
        let start = invalidationStart(in: storage, insertionLocation: oldLength)
        invalidateLayout(for: textView, changedRange: NSRange(location: start, length: max(0, storage.length - start)))

        if var state = streamingState, state.processedUTF16Count == lastMarkdown.utf16.count {
            state.ingest(delta: delta)
            streamingState = state
        }
        return true
    }

    private func attemptIncrementalOpenAttachmentUpdate(
        textView: MarkdownPlatformTextView,
        storage: NSTextStorage,
        committedLength: Int,
        delta: String,
        baseState: MarkdownStreamingState,
        nextState: MarkdownStreamingState,
        style: MarkdownStyle,
        styleKey: String
    ) -> Bool {
        _ = styleKey
        guard !delta.isEmpty else { return false }

        if baseState.isInsideFence, nextState.isInsideFence,
           let codeAttachment = attachments.last as? MarkdownCodeBlockAttachment {
            streamingActiveTableAttachment = nil
            streamingActiveTableLineBuffer = ""
            streamingActiveTableHasDraftRow = false
            streamingActiveTableDraftLine = ""

            let tailRange = NSRange(location: committedLength, length: max(0, storage.length - committedLength))
            let attachmentRange = resolveStreamingActiveAttachmentRange(
                codeAttachment,
                storage: storage,
                searchRange: tailRange
            )
            guard let attachmentRange else { return false }

            codeAttachment.appendCode(delta)
            streamingActiveTailAttachment = codeAttachment
            streamingActiveTailAttachmentRange = attachmentRange
            invalidateLayout(for: textView, changedRange: attachmentRange)
            return true
        }

        if baseState.isInsideTable, nextState.isInsideTable,
           let tableAttachment = attachments.last as? MarkdownTableAttachment {
            let tailRange = NSRange(location: committedLength, length: max(0, storage.length - committedLength))
            let attachmentRange = resolveStreamingActiveAttachmentRange(
                tableAttachment,
                storage: storage,
                searchRange: tailRange
            )
            guard let attachmentRange else { return false }

            if streamingActiveTableAttachment !== tableAttachment {
                streamingActiveTableAttachment = tableAttachment
                let suffix = currentLineSuffix(from: lastMarkdown)
                streamingActiveTableLineBuffer = suffix
                streamingActiveTableHasDraftRow = false
                streamingActiveTableDraftLine = ""

                if let draftRow = makeStreamingTableRow(
                    from: suffix,
                    style: style,
                    columnCountHint: tableAttachment.rows.first?.cells.count
                ), let existingLast = tableAttachment.rows.last {
                    let existingText = existingLast.cells.map(\.string).joined(separator: "\t")
                    let draftText = draftRow.cells.map(\.string).joined(separator: "\t")
                    if existingText == draftText {
                        streamingActiveTableHasDraftRow = true
                        streamingActiveTableDraftLine = suffix
                    }
                }
            }

            streamingActiveTableLineBuffer.append(contentsOf: delta)
            let (rowsToAppend, remainder) = consumeCompletedTableLines(
                from: streamingActiveTableLineBuffer,
                style: style,
                columnCountHint: tableAttachment.rows.first?.cells.count
            )
            streamingActiveTableLineBuffer = remainder

            var didUpdate = false

            if !rowsToAppend.isEmpty {
                if streamingActiveTableHasDraftRow {
                    tableAttachment.replaceLastRow(rowsToAppend[0])
                    if rowsToAppend.count > 1 {
                        tableAttachment.appendRows(Array(rowsToAppend.dropFirst()))
                    }
                } else {
                    tableAttachment.appendRows(rowsToAppend)
                }
                didUpdate = true
                streamingActiveTableHasDraftRow = false
                streamingActiveTableDraftLine = ""
            }

            if remainder.isEmpty || remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                streamingActiveTableHasDraftRow = false
                streamingActiveTableDraftLine = ""
            } else if remainder != streamingActiveTableDraftLine,
                      let draftRow = makeStreamingTableRow(
                          from: remainder,
                          style: style,
                          columnCountHint: tableAttachment.rows.first?.cells.count
                      ) {
                if streamingActiveTableHasDraftRow {
                    tableAttachment.replaceLastRow(draftRow)
                } else {
                    tableAttachment.appendRows([draftRow])
                    streamingActiveTableHasDraftRow = true
                }
                streamingActiveTableDraftLine = remainder
                didUpdate = true
            }

            if didUpdate {
                invalidateLayout(for: textView, changedRange: attachmentRange)
            }

            streamingActiveTailAttachment = tableAttachment
            streamingActiveTailAttachmentRange = attachmentRange
            return true
        }

        return false
    }

    private func attemptSegmentedStreamingUpdate(
        to textView: MarkdownPlatformTextView,
        newMarkdown: String,
        style: MarkdownStyle,
        styleKey: String
    ) -> Bool {
        guard !lastMarkdown.isEmpty, newMarkdown.hasPrefix(lastMarkdown) else { return false }
        guard let storage = textStorage(for: textView), storage.length > 0 else { return false }

        var baseState: MarkdownStreamingState
        if let existing = streamingState, existing.processedUTF16Count == lastMarkdown.utf16.count {
            baseState = existing
        } else {
            var rebuilt = MarkdownStreamingState()
            rebuilt.ingest(fullMarkdown: lastMarkdown)
            baseState = rebuilt
        }

        let lastUTF16Count = lastMarkdown.utf16.count
        let newUTF16Count = newMarkdown.utf16.count
        let deltaStart = String.Index(utf16Offset: lastUTF16Count, in: newMarkdown)
        let delta = String(newMarkdown[deltaStart...])

        var nextState = baseState
        nextState.ingest(delta: delta)
        let safeCommitUTF16Count = min(nextState.safeCommitUTF16Count, newUTF16Count)
        guard safeCommitUTF16Count > 0 else { return false }

        let maxWidth = lastLayoutWidth > 1 ? lastLayoutWidth : nil
        let baseAttributes = style.baseAttributes

        struct SegmentedPlan: Sendable {
            enum Mode: Sendable {
                case initialize
                case extend(oldCommittedLength: Int, oldCommittedUTF16: Int)
                case updateTail(committedLength: Int)
            }

            let mode: Mode
            let nextState: MarkdownStreamingState
            let safeCommitUTF16Count: Int
            let orderedListAtOldCommit: MarkdownStreamingState.OrderedListRenderState?
            let orderedListAtSafeCommit: MarkdownStreamingState.OrderedListRenderState?
            let markdown: String
        }

        let isCommittedValid: Bool = {
            guard streamingCommittedStyleKey == styleKey else { return false }
            guard streamingCommittedMarkdownUTF16Count > 0 else { return false }
            guard streamingCommittedMarkdownUTF16Count <= lastUTF16Count else { return false }
            guard let committed = streamingCommittedAttributedString else { return false }
            return committed.length > 0
        }()

        let orderedListAtOldCommit = isCommittedValid ? streamingCommittedOrderedList : nil
        let orderedListAtSafeCommit = nextState.safeCommitOrderedList

        let plan: SegmentedPlan
        if !isCommittedValid || safeCommitUTF16Count < streamingCommittedMarkdownUTF16Count {
            plan = SegmentedPlan(
                mode: .initialize,
                nextState: nextState,
                safeCommitUTF16Count: safeCommitUTF16Count,
                orderedListAtOldCommit: nil,
                orderedListAtSafeCommit: orderedListAtSafeCommit,
                markdown: newMarkdown
            )
        } else if safeCommitUTF16Count > streamingCommittedMarkdownUTF16Count {
            let oldLength = streamingCommittedAttributedString?.length ?? 0
            plan = SegmentedPlan(
                mode: .extend(oldCommittedLength: oldLength, oldCommittedUTF16: streamingCommittedMarkdownUTF16Count),
                nextState: nextState,
                safeCommitUTF16Count: safeCommitUTF16Count,
                orderedListAtOldCommit: orderedListAtOldCommit,
                orderedListAtSafeCommit: orderedListAtSafeCommit,
                markdown: newMarkdown
            )
        } else {
            let committedLength = streamingCommittedAttributedString?.length ?? 0
            plan = SegmentedPlan(
                mode: .updateTail(committedLength: committedLength),
                nextState: nextState,
                safeCommitUTF16Count: safeCommitUTF16Count,
                orderedListAtOldCommit: orderedListAtOldCommit,
                orderedListAtSafeCommit: orderedListAtSafeCommit,
                markdown: newMarkdown
            )
        }

        currentRenderID &+= 1
        let renderID = currentRenderID
        let sendableBaseAttributes = SendableAttributes(attributes: baseAttributes)

        if case let .updateTail(committedLength) = plan.mode,
           committedLength <= storage.length,
           attemptIncrementalOpenAttachmentUpdate(
               textView: textView,
               storage: storage,
               committedLength: committedLength,
               delta: delta,
               baseState: baseState,
               nextState: nextState,
               style: style,
               styleKey: styleKey
           ) {
            streamingState = nextState
            lastMarkdown = newMarkdown
            lastStyleKey = styleKey
            return true
        }

#if os(macOS)
        Task { @MainActor [weak self] in
            guard let self, self.currentRenderID == renderID else { return }
            guard let textView = self.currentTextView, let storage = self.textStorage(for: textView) else { return }

            func patchOrderedListStart(_ markdown: String, startNumber: Int) -> String {
                guard startNumber > 0 else { return markdown }
                guard !markdown.isEmpty else { return markdown }

                var idx = markdown.startIndex
                while idx < markdown.endIndex {
                    let ch = markdown[idx]
                    if ch == "\n" || ch == "\r" || ch == " " || ch == "\t" {
                        idx = markdown.index(after: idx)
                        continue
                    }
                    break
                }
                guard idx < markdown.endIndex else { return markdown }

                let digitStart = idx
                var digitEnd = idx
                while digitEnd < markdown.endIndex, markdown[digitEnd].wholeNumberValue != nil {
                    digitEnd = markdown.index(after: digitEnd)
                }
                guard digitEnd > digitStart else { return markdown }
                guard digitEnd < markdown.endIndex else { return markdown }

                let delimiter = markdown[digitEnd]
                guard delimiter == "." || delimiter == ")" else { return markdown }
                let afterDelimiter = markdown.index(after: digitEnd)
                guard afterDelimiter < markdown.endIndex else { return markdown }
                let ws = markdown[afterDelimiter]
                guard ws == " " || ws == "\t" else { return markdown }

                let replacement = String(startNumber)
                var out = markdown
                out.replaceSubrange(digitStart..<digitEnd, with: replacement)
                return out
            }

            @MainActor
            func renderSegment(_ segmentMarkdown: String, orderedListStartNumber: Int?) -> MarkdownRenderResult {
                let effectiveMarkdown: String
                if let orderedListStartNumber {
                    effectiveMarkdown = patchOrderedListStart(segmentMarkdown, startNumber: orderedListStartNumber)
                } else {
                    effectiveMarkdown = segmentMarkdown
                }

                if let cached = MarkdownRenderCache.shared.attributedString(for: effectiveMarkdown, styleKey: styleKey) {
                    return MarkdownRenderResult(attributedString: cached, attachments: [])
                }
                let renderer = MarkdownAttributedStringRenderer(style: style, maxImageWidth: maxWidth)
                let result = renderer.render(markdown: effectiveMarkdown)
                if result.attachments.isEmpty {
                    MarkdownRenderCache.shared.store(result.attributedString, markdown: effectiveMarkdown, styleKey: styleKey)
                }
                return result
            }

            switch plan.mode {
            case .initialize:
                let committedMarkdown = utf16Substring(plan.markdown, from: 0, to: plan.safeCommitUTF16Count)
                let tailMarkdown = utf16Substring(plan.markdown, from: plan.safeCommitUTF16Count, to: plan.markdown.utf16.count)
                let tailStart = plan.orderedListAtSafeCommit.map { max(1, $0.startIndex + $0.committedItemCount) }
                let committedResult = renderSegment(committedMarkdown, orderedListStartNumber: nil)
                let tailResult = renderSegment(tailMarkdown, orderedListStartNumber: tailStart)
                let committedAttachments = committedResult.attachments
                let tailAttachments = tailResult.attachments

                let committedAttributed = NSMutableAttributedString(attributedString: committedResult.attributedString)
                let tailAttributed = self.tailWithSeparator(
                    prefix: committedAttributed,
                    tail: tailResult.attributedString,
                    newlineAttributes: sendableBaseAttributes
                )

                storage.beginEditing()
                storage.setAttributedString(committedAttributed)
                if tailAttributed.length > 0 {
                    storage.append(tailAttributed)
                }
                storage.endEditing()

                self.streamingCommittedAttributedString = committedAttributed
                self.streamingCommittedAttachments = committedAttachments
                self.streamingCommittedMarkdownUTF16Count = plan.safeCommitUTF16Count
                self.streamingCommittedStyleKey = styleKey
                self.streamingCommittedOrderedList = plan.orderedListAtSafeCommit
                self.streamingState = plan.nextState

                var allAttachments = committedAttachments
                allAttachments.append(contentsOf: tailAttachments)
                self.attachments = allAttachments
                self.resetStreamingOpenAttachmentState()
                self.updateAttachmentWidth(for: allAttachments)
                self.queueImageLoads(attachments: allAttachments)
                self.lastMarkdown = plan.markdown
                self.lastStyleKey = styleKey
                self.invalidateLayout(for: textView, changedRange: nil)

            case let .extend(oldCommittedLength, oldCommittedUTF16):
                guard let committedAttributed = self.streamingCommittedAttributedString else {
                    return
                }
                let newCommittedUTF16 = plan.safeCommitUTF16Count
                let commitDeltaMarkdown = utf16Substring(plan.markdown, from: oldCommittedUTF16, to: newCommittedUTF16)
                let tailMarkdown = utf16Substring(plan.markdown, from: newCommittedUTF16, to: plan.markdown.utf16.count)
                let commitDeltaStart = plan.orderedListAtOldCommit.map { max(1, $0.startIndex + $0.committedItemCount) }
                let tailStart = plan.orderedListAtSafeCommit.map { max(1, $0.startIndex + $0.committedItemCount) }
                let commitDeltaResult = renderSegment(commitDeltaMarkdown, orderedListStartNumber: commitDeltaStart)
                let tailResult = renderSegment(tailMarkdown, orderedListStartNumber: tailStart)
                let oldCommittedAttachmentCount = self.streamingCommittedAttachments.count
                let oldTailAttachmentCount = max(0, self.attachments.count - oldCommittedAttachmentCount)

                let commitDeltaAttributed = commitDeltaResult.attributedString
                let commitAppend = NSMutableAttributedString()
                if self.needsBlockSeparator(prefix: committedAttributed, next: commitDeltaAttributed) {
                    let sep = NSAttributedString(string: "\n", attributes: sendableBaseAttributes.attributes)
                    commitAppend.append(sep)
                    committedAttributed.append(sep)
                }
                commitAppend.append(commitDeltaAttributed)
                committedAttributed.append(commitDeltaAttributed)

                let tailAttributed = self.tailWithSeparator(
                    prefix: committedAttributed,
                    tail: tailResult.attributedString,
                    newlineAttributes: sendableBaseAttributes
                )
                let replacement = NSMutableAttributedString(attributedString: commitAppend)
                replacement.append(tailAttributed)

                let oldTailAttachments = oldTailAttachmentCount > 0
                    ? Array(self.attachments.suffix(oldTailAttachmentCount))
                    : []
                let incomingNewAttachments = commitDeltaResult.attachments + tailResult.attachments
                let reconciledNewAttachments = self.reconcileReplacementAttachments(
                    replacement: replacement,
                    incomingAttachments: incomingNewAttachments,
                    reusableAttachments: oldTailAttachments
                )
                let split = self.splitReconciledAttachments(
                    reconciledNewAttachments,
                    expectedCommitCount: commitDeltaResult.attachments.count,
                    expectedTailCount: tailResult.attachments.count,
                    fallbackCommit: commitDeltaResult.attachments,
                    fallbackTail: tailResult.attachments
                )
                let resolvedCommitDeltaAttachments = split.commit
                let resolvedTailAttachments = split.tail

                self.streamingCommittedAttachments.append(contentsOf: resolvedCommitDeltaAttachments)
                self.streamingCommittedMarkdownUTF16Count = newCommittedUTF16
                self.streamingCommittedOrderedList = plan.orderedListAtSafeCommit
                self.streamingState = plan.nextState

                let replaceRange = NSRange(location: oldCommittedLength, length: max(0, storage.length - oldCommittedLength))
                storage.beginEditing()
                storage.replaceCharacters(in: replaceRange, with: replacement)
                storage.endEditing()

                let newAttachments = resolvedCommitDeltaAttachments + resolvedTailAttachments
                if self.attachments.count >= oldCommittedAttachmentCount {
                    if oldTailAttachmentCount > 0 {
                        self.attachments.removeLast(oldTailAttachmentCount)
                    }
                    self.attachments.append(contentsOf: resolvedCommitDeltaAttachments)
                    self.attachments.append(contentsOf: resolvedTailAttachments)
                } else {
                    var allAttachments = self.streamingCommittedAttachments
                    allAttachments.append(contentsOf: resolvedTailAttachments)
                    self.attachments = allAttachments
                }
                self.resetStreamingOpenAttachmentState()
                self.updateAttachmentWidth(for: newAttachments)
                self.queueImageLoads(attachments: newAttachments)
                self.lastMarkdown = plan.markdown
                self.lastStyleKey = styleKey
                let start = self.invalidationStart(in: storage, insertionLocation: oldCommittedLength)
                self.invalidateLayout(for: textView, changedRange: NSRange(location: start, length: max(0, storage.length - start)))

            case let .updateTail(committedLength):
                guard let committedAttributed = self.streamingCommittedAttributedString else {
                    return
                }
                let tailMarkdown = utf16Substring(plan.markdown, from: plan.safeCommitUTF16Count, to: plan.markdown.utf16.count)
                let tailStart = plan.orderedListAtSafeCommit.map { max(1, $0.startIndex + $0.committedItemCount) }
                let tailResult = renderSegment(tailMarkdown, orderedListStartNumber: tailStart)
                let tailAttributed = NSMutableAttributedString(attributedString: self.tailWithSeparator(
                    prefix: committedAttributed,
                    tail: tailResult.attributedString,
                    newlineAttributes: sendableBaseAttributes
                ))
                let committedAttachmentCount = self.streamingCommittedAttachments.count
                let oldTailAttachmentCount = max(0, self.attachments.count - committedAttachmentCount)
                let oldTailAttachments = oldTailAttachmentCount > 0
                    ? Array(self.attachments.suffix(oldTailAttachmentCount))
                    : []
                let resolvedTailAttachments = self.reconcileReplacementAttachments(
                    replacement: tailAttributed,
                    incomingAttachments: tailResult.attachments,
                    reusableAttachments: oldTailAttachments
                )

                let replaceRange = NSRange(location: committedLength, length: max(0, storage.length - committedLength))
                storage.beginEditing()
                storage.replaceCharacters(in: replaceRange, with: tailAttributed)
                storage.endEditing()

                self.streamingState = plan.nextState
                self.streamingCommittedOrderedList = plan.orderedListAtSafeCommit
                if self.attachments.count >= committedAttachmentCount {
                    if oldTailAttachmentCount > 0 {
                        self.attachments.removeLast(oldTailAttachmentCount)
                    }
                    self.attachments.append(contentsOf: resolvedTailAttachments)
                } else {
                    var allAttachments = self.streamingCommittedAttachments
                    allAttachments.append(contentsOf: resolvedTailAttachments)
                    self.attachments = allAttachments
                }
                self.resetStreamingOpenAttachmentState()
                self.updateAttachmentWidth(for: resolvedTailAttachments)
                self.queueImageLoads(attachments: resolvedTailAttachments)
                self.lastMarkdown = plan.markdown
                self.lastStyleKey = styleKey
                let start = self.invalidationStart(in: storage, insertionLocation: committedLength)
                self.invalidateLayout(for: textView, changedRange: NSRange(location: start, length: max(0, storage.length - start)))
            }
        }
#else
        renderQueue.async {

            func patchOrderedListStart(_ markdown: String, startNumber: Int) -> String {
                guard startNumber > 0 else { return markdown }
                guard !markdown.isEmpty else { return markdown }

                var idx = markdown.startIndex
                while idx < markdown.endIndex {
                    let ch = markdown[idx]
                    if ch == "\n" || ch == "\r" || ch == " " || ch == "\t" {
                        idx = markdown.index(after: idx)
                        continue
                    }
                    break
                }
                guard idx < markdown.endIndex else { return markdown }

                var digitStart = idx
                var digitEnd = idx
                while digitEnd < markdown.endIndex, markdown[digitEnd].wholeNumberValue != nil {
                    digitEnd = markdown.index(after: digitEnd)
                }
                guard digitEnd > digitStart else { return markdown }
                guard digitEnd < markdown.endIndex else { return markdown }

                let delimiter = markdown[digitEnd]
                guard delimiter == "." || delimiter == ")" else { return markdown }
                let afterDelimiter = markdown.index(after: digitEnd)
                guard afterDelimiter < markdown.endIndex else { return markdown }
                let ws = markdown[afterDelimiter]
                guard ws == " " || ws == "\t" else { return markdown }

                let replacement = String(startNumber)
                var out = markdown
                out.replaceSubrange(digitStart..<digitEnd, with: replacement)
                return out
            }

            func renderSegment(_ segmentMarkdown: String, orderedListStartNumber: Int?) -> MarkdownRenderResult {
                let effectiveMarkdown: String
                if let orderedListStartNumber {
                    effectiveMarkdown = patchOrderedListStart(segmentMarkdown, startNumber: orderedListStartNumber)
                } else {
                    effectiveMarkdown = segmentMarkdown
                }

                if let cached = MarkdownRenderCache.shared.attributedString(for: effectiveMarkdown, styleKey: styleKey) {
                    return MarkdownRenderResult(attributedString: cached, attachments: [])
                }
                let renderer = MarkdownAttributedStringRenderer(style: style, maxImageWidth: maxWidth)
                let result = renderer.render(markdown: effectiveMarkdown)
                if result.attachments.isEmpty {
                    MarkdownRenderCache.shared.store(result.attributedString, markdown: effectiveMarkdown, styleKey: styleKey)
                }
                return result
            }

            enum Results {
                case initial(committed: MarkdownRenderResult, tail: MarkdownRenderResult)
                case extended(commitDelta: MarkdownRenderResult, tail: MarkdownRenderResult)
                case tailOnly(tail: MarkdownRenderResult)
            }

            let results: Results
            switch plan.mode {
            case .initialize:
                let committedMarkdown = utf16Substring(plan.markdown, from: 0, to: plan.safeCommitUTF16Count)
                let tailMarkdown = utf16Substring(plan.markdown, from: plan.safeCommitUTF16Count, to: plan.markdown.utf16.count)
                let tailStart = plan.orderedListAtSafeCommit.map { max(1, $0.startIndex + $0.committedItemCount) }
                results = .initial(
                    committed: renderSegment(committedMarkdown, orderedListStartNumber: nil),
                    tail: renderSegment(tailMarkdown, orderedListStartNumber: tailStart)
                )

            case let .extend(_, oldCommittedUTF16):
                let newCommittedUTF16 = plan.safeCommitUTF16Count
                let commitDeltaMarkdown = utf16Substring(plan.markdown, from: oldCommittedUTF16, to: newCommittedUTF16)
                let tailMarkdown = utf16Substring(plan.markdown, from: newCommittedUTF16, to: plan.markdown.utf16.count)
                let commitDeltaStart = plan.orderedListAtOldCommit.map { max(1, $0.startIndex + $0.committedItemCount) }
                let tailStart = plan.orderedListAtSafeCommit.map { max(1, $0.startIndex + $0.committedItemCount) }
                results = .extended(
                    commitDelta: renderSegment(commitDeltaMarkdown, orderedListStartNumber: commitDeltaStart),
                    tail: renderSegment(tailMarkdown, orderedListStartNumber: tailStart)
                )

            case .updateTail:
                let tailMarkdown = utf16Substring(plan.markdown, from: plan.safeCommitUTF16Count, to: plan.markdown.utf16.count)
                let tailStart = plan.orderedListAtSafeCommit.map { max(1, $0.startIndex + $0.committedItemCount) }
                results = .tailOnly(tail: renderSegment(tailMarkdown, orderedListStartNumber: tailStart))
            }

            Task { @MainActor [weak self] in
                guard let self, self.currentRenderID == renderID else { return }
                guard let textView = self.currentTextView, let storage = self.textStorage(for: textView) else { return }

                switch (plan.mode, results) {
                case (.initialize, let .initial(committedResult, tailResult)):
                    let committedAttachments = committedResult.attachments
                    let tailAttachments = tailResult.attachments
                    let committedAttributed = NSMutableAttributedString(attributedString: committedResult.attributedString)
                    let tailAttributed = self.tailWithSeparator(
                        prefix: committedAttributed,
                        tail: tailResult.attributedString,
                        newlineAttributes: sendableBaseAttributes
                    )

                    storage.beginEditing()
                    storage.setAttributedString(committedAttributed)
                    if tailAttributed.length > 0 {
                        storage.append(tailAttributed)
                    }
                    storage.endEditing()

                    self.streamingCommittedAttributedString = committedAttributed
                    self.streamingCommittedAttachments = committedAttachments
                    self.streamingCommittedMarkdownUTF16Count = plan.safeCommitUTF16Count
                    self.streamingCommittedStyleKey = styleKey
                    self.streamingCommittedOrderedList = plan.orderedListAtSafeCommit
                    self.streamingState = plan.nextState

                    var allAttachments = committedAttachments
                    allAttachments.append(contentsOf: tailAttachments)
                    self.attachments = allAttachments
                    self.resetStreamingOpenAttachmentState()
                    self.updateAttachmentWidth(for: allAttachments)
                    self.queueImageLoads(attachments: allAttachments)
                    self.lastMarkdown = plan.markdown
                    self.lastStyleKey = styleKey
                    self.invalidateLayout(for: textView, changedRange: nil)

                case let (.extend(oldCommittedLength, _), .extended(commitDeltaResult, tailResult)):
                    guard let committedAttributed = self.streamingCommittedAttributedString else { return }
                    let oldCommittedAttachmentCount = self.streamingCommittedAttachments.count
                    let oldTailAttachmentCount = max(0, self.attachments.count - oldCommittedAttachmentCount)

                    let commitDeltaAttributed = commitDeltaResult.attributedString
                    let commitAppend = NSMutableAttributedString()
                    if self.needsBlockSeparator(prefix: committedAttributed, next: commitDeltaAttributed) {
                        let sep = NSAttributedString(string: "\n", attributes: sendableBaseAttributes.attributes)
                        commitAppend.append(sep)
                        committedAttributed.append(sep)
                    }
                    commitAppend.append(commitDeltaAttributed)
                    committedAttributed.append(commitDeltaAttributed)

                    let tailAttributed = self.tailWithSeparator(
                        prefix: committedAttributed,
                        tail: tailResult.attributedString,
                        newlineAttributes: sendableBaseAttributes
                    )
                    let replacement = NSMutableAttributedString(attributedString: commitAppend)
                    replacement.append(tailAttributed)

                    let oldTailAttachments = oldTailAttachmentCount > 0
                        ? Array(self.attachments.suffix(oldTailAttachmentCount))
                        : []
                    let incomingNewAttachments = commitDeltaResult.attachments + tailResult.attachments
                    let reconciledNewAttachments = self.reconcileReplacementAttachments(
                        replacement: replacement,
                        incomingAttachments: incomingNewAttachments,
                        reusableAttachments: oldTailAttachments
                    )
                    let split = self.splitReconciledAttachments(
                        reconciledNewAttachments,
                        expectedCommitCount: commitDeltaResult.attachments.count,
                        expectedTailCount: tailResult.attachments.count,
                        fallbackCommit: commitDeltaResult.attachments,
                        fallbackTail: tailResult.attachments
                    )
                    let resolvedCommitDeltaAttachments = split.commit
                    let resolvedTailAttachments = split.tail

                    self.streamingCommittedAttachments.append(contentsOf: resolvedCommitDeltaAttachments)
                    self.streamingCommittedMarkdownUTF16Count = plan.safeCommitUTF16Count
                    self.streamingCommittedOrderedList = plan.orderedListAtSafeCommit
                    self.streamingState = plan.nextState

                    let replaceRange = NSRange(location: oldCommittedLength, length: max(0, storage.length - oldCommittedLength))
                    storage.beginEditing()
                    storage.replaceCharacters(in: replaceRange, with: replacement)
                    storage.endEditing()

                    let newAttachments = resolvedCommitDeltaAttachments + resolvedTailAttachments
                    if self.attachments.count >= oldCommittedAttachmentCount {
                        if oldTailAttachmentCount > 0 {
                            self.attachments.removeLast(oldTailAttachmentCount)
                        }
                        self.attachments.append(contentsOf: resolvedCommitDeltaAttachments)
                        self.attachments.append(contentsOf: resolvedTailAttachments)
                    } else {
                        var allAttachments = self.streamingCommittedAttachments
                        allAttachments.append(contentsOf: resolvedTailAttachments)
                        self.attachments = allAttachments
                    }
                    self.resetStreamingOpenAttachmentState()
                    self.updateAttachmentWidth(for: newAttachments)
                    self.queueImageLoads(attachments: newAttachments)
                    self.lastMarkdown = plan.markdown
                    self.lastStyleKey = styleKey
                    let start = self.invalidationStart(in: storage, insertionLocation: oldCommittedLength)
                    self.invalidateLayout(for: textView, changedRange: NSRange(location: start, length: max(0, storage.length - start)))

                case let (.updateTail(committedLength), .tailOnly(tailResult)):
                    guard let committedAttributed = self.streamingCommittedAttributedString else { return }
                    let tailAttributed = NSMutableAttributedString(attributedString: self.tailWithSeparator(
                        prefix: committedAttributed,
                        tail: tailResult.attributedString,
                        newlineAttributes: sendableBaseAttributes
                    ))
                    let committedAttachmentCount = self.streamingCommittedAttachments.count
                    let oldTailAttachmentCount = max(0, self.attachments.count - committedAttachmentCount)
                    let oldTailAttachments = oldTailAttachmentCount > 0
                        ? Array(self.attachments.suffix(oldTailAttachmentCount))
                        : []
                    let resolvedTailAttachments = self.reconcileReplacementAttachments(
                        replacement: tailAttributed,
                        incomingAttachments: tailResult.attachments,
                        reusableAttachments: oldTailAttachments
                    )

                    let replaceRange = NSRange(location: committedLength, length: max(0, storage.length - committedLength))
                    storage.beginEditing()
                    storage.replaceCharacters(in: replaceRange, with: tailAttributed)
                    storage.endEditing()

                    self.streamingState = plan.nextState
                    self.streamingCommittedOrderedList = plan.orderedListAtSafeCommit
                    if self.attachments.count >= committedAttachmentCount {
                        if oldTailAttachmentCount > 0 {
                            self.attachments.removeLast(oldTailAttachmentCount)
                        }
                        self.attachments.append(contentsOf: resolvedTailAttachments)
                    } else {
                        var allAttachments = self.streamingCommittedAttachments
                        allAttachments.append(contentsOf: resolvedTailAttachments)
                        self.attachments = allAttachments
                    }
                    self.resetStreamingOpenAttachmentState()
                    self.updateAttachmentWidth(for: resolvedTailAttachments)
                    self.queueImageLoads(attachments: resolvedTailAttachments)
                    self.lastMarkdown = plan.markdown
                    self.lastStyleKey = styleKey
                    let start = self.invalidationStart(in: storage, insertionLocation: committedLength)
                    self.invalidateLayout(for: textView, changedRange: NSRange(location: start, length: max(0, storage.length - start)))

                default:
                    break
                }
            }
        }
#endif

        return true
    }

    private struct MarkdownStreamingState: Sendable {
        var processedUTF16Count: Int = 0
        var safeCommitUTF16Count: Int = 0
        var safeCommitOrderedList: OrderedListRenderState?

        struct OrderedListRenderState: Sendable, Equatable {
            let startIndex: Int
            let committedItemCount: Int
            let markerIndent: Int
        }

        var isInsideFence: Bool {
            fence != nil
        }

        var isInsideTable: Bool {
            if case .inTable = tableState { return true }
            return false
        }

        private struct FenceState: Sendable {
            let marker: Character
            let count: Int

            func closes(with marker: Character, count: Int) -> Bool {
                self.marker == marker && count >= self.count
            }
        }

        private enum TableState: Sendable {
            case none
            case sawHeaderCandidate
            case inTable(lastRowEndUTF16Count: Int)

            var isNone: Bool {
                if case .none = self { return true }
                return false
            }
        }

        private var currentLine: String = ""
        private var lastLineEndUTF16Count: Int = 0

        private var fence: FenceState?
        private var tableState: TableState = .none

        private var inBlockQuote: Bool = false
        private var lastQuoteLineEndUTF16Count: Int = 0

        private struct ListState: Sendable {
            enum Kind: Sendable {
                case unordered
                case ordered(startIndex: Int)
            }

            var kind: Kind
            let markerIndent: Int
            var contentIndent: Int
            var committedItemCount: Int
            var startedItemCount: Int
        }

        private struct ParsedListMarker: Sendable {
            let kind: ListState.Kind
            let markerIndent: Int
            let contentIndent: Int
        }

        private var listState: ListState?
        private var didCheckCurrentLineForListMarker: Bool = false
        private var isInsideList: Bool { listState != nil }

        mutating func ingest(fullMarkdown: String) {
            self = MarkdownStreamingState()
            ingest(delta: fullMarkdown)
        }

        mutating func ingest(delta: String) {
            guard !delta.isEmpty else { return }
            for ch in delta {
                currentLine.append(ch)
                processedUTF16Count += String(ch).utf16.count

                if ch != "\n",
                   !didCheckCurrentLineForListMarker,
                   fence == nil,
                   tableState.isNone,
                   !inBlockQuote,
                   currentLine.count <= 32 {
                    if let marker = parseListMarkerPrefix(in: currentLine) {
                        applyListMarkerStart(marker)
                        didCheckCurrentLineForListMarker = true
                    } else {
                        let trimmed = currentLine.drop(while: { $0 == " " || $0 == "\t" })
                        if let first = trimmed.first {
                            let isCandidate = first == "-" || first == "*" || first == "+" || first.wholeNumberValue != nil
                            if !isCandidate {
                                didCheckCurrentLineForListMarker = true
                            }
                        }
                    }
                } else if ch != "\n",
                          !didCheckCurrentLineForListMarker,
                          currentLine.count > 32 {
                    didCheckCurrentLineForListMarker = true
                }

                if ch == "\n" {
                    let line = String(currentLine.dropLast())
                    processCompletedLine(line, lineEndUTF16Count: processedUTF16Count)
                    currentLine.removeAll(keepingCapacity: true)
                    lastLineEndUTF16Count = processedUTF16Count
                    didCheckCurrentLineForListMarker = false
                }
            }
        }

        private mutating func processCompletedLine(_ line: String, lineEndUTF16Count: Int) {
            if let marker = parseFenceMarker(in: line) {
                if let existing = fence {
                    if existing.closes(with: marker.marker, count: marker.count) {
                        fence = nil
                        if !isInsideList && !inBlockQuote && tableState.isNone {
                            safeCommitUTF16Count = max(safeCommitUTF16Count, lineEndUTF16Count)
                            safeCommitOrderedList = nil
                        }
                    }
                } else {
                    fence = FenceState(marker: marker.marker, count: marker.count)
                    tableState = .none
                }
                return
            }

            if fence != nil {
                return
            }

            if case .sawHeaderCandidate = tableState {
                if looksLikeTableSeparator(line), !isInsideList && !inBlockQuote {
                    tableState = .inTable(lastRowEndUTF16Count: lineEndUTF16Count)
                    return
                }
                if !isInsideList && !inBlockQuote {
                    safeCommitUTF16Count = max(safeCommitUTF16Count, lastLineEndUTF16Count)
                    safeCommitOrderedList = nil
                }
                tableState = .none
            }

            if case let .inTable(lastRowEndUTF16Count) = tableState {
                if looksLikeTableRow(line) {
                    tableState = .inTable(lastRowEndUTF16Count: lineEndUTF16Count)
                    return
                }
                if !isInsideList && !inBlockQuote {
                    safeCommitUTF16Count = max(safeCommitUTF16Count, lastRowEndUTF16Count)
                    safeCommitOrderedList = nil
                }
                tableState = .none
            }

            if inBlockQuote {
                if isBlockQuoteLine(line) {
                    lastQuoteLineEndUTF16Count = lineEndUTF16Count
                    return
                }
                if !isInsideList {
                    safeCommitUTF16Count = max(safeCommitUTF16Count, lastQuoteLineEndUTF16Count)
                    safeCommitOrderedList = nil
                }
                inBlockQuote = false
                lastQuoteLineEndUTF16Count = 0
            }

            if isBlockQuoteLine(line) {
                inBlockQuote = true
                lastQuoteLineEndUTF16Count = lineEndUTF16Count
                return
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let isBlank = trimmed.isEmpty

            if var list = listState {
                if isBlank {
                    // Keep the list open.
                } else if let marker = parseListMarkerPrefix(in: line), marker.markerIndent == list.markerIndent {
                    list.contentIndent = min(list.contentIndent, marker.contentIndent)
                    listState = list
                } else if leadingIndentColumns(line) < list.contentIndent {
                    safeCommitUTF16Count = max(safeCommitUTF16Count, lastLineEndUTF16Count)
                    safeCommitOrderedList = nil
                    listState = nil
                }
            } else if !isBlank, let marker = parseListMarkerPrefix(in: line) {
                listState = ListState(
                    kind: marker.kind,
                    markerIndent: marker.markerIndent,
                    contentIndent: marker.contentIndent,
                    committedItemCount: 0,
                    startedItemCount: 1
                )
            }

            if !isInsideList && !inBlockQuote && tableState.isNone && looksLikeTableHeaderRow(line) {
                tableState = .sawHeaderCandidate
            } else if !isInsideList && !inBlockQuote && tableState.isNone {
                // Safe to commit normal lines once we know they're not opening a table header candidate.
                safeCommitUTF16Count = max(safeCommitUTF16Count, lineEndUTF16Count)
                safeCommitOrderedList = nil
            }
        }

        private struct ParsedFenceMarker: Sendable {
            let marker: Character
            let count: Int
        }

        private func parseFenceMarker(in line: String) -> ParsedFenceMarker? {
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
            var count = 0
            for ch in trimmed {
                if ch == first {
                    count += 1
                } else {
                    break
                }
            }
            guard count >= 3 else { return nil }
            return ParsedFenceMarker(marker: first, count: count)
        }

        private func isBlockQuoteLine(_ line: String) -> Bool {
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            return trimmed.first == ">"
        }

        private func leadingIndentColumns(_ line: String) -> Int {
            var columns = 0
            for ch in line {
                if ch == " " {
                    columns += 1
                } else if ch == "\t" {
                    columns += 4
                } else {
                    break
                }
            }
            return columns
        }

        private mutating func applyListMarkerStart(_ marker: ParsedListMarker) {
            if var list = listState {
                if marker.markerIndent == list.markerIndent {
                    list.committedItemCount += 1
                    safeCommitUTF16Count = max(safeCommitUTF16Count, lastLineEndUTF16Count)
                    if case let .ordered(startIndex) = list.kind {
                        safeCommitOrderedList = OrderedListRenderState(
                            startIndex: startIndex,
                            committedItemCount: list.committedItemCount,
                            markerIndent: list.markerIndent
                        )
                    } else {
                        safeCommitOrderedList = nil
                    }
                    list.startedItemCount += 1
                    list.contentIndent = min(list.contentIndent, marker.contentIndent)
                    listState = list
                }
                return
            }

            listState = ListState(
                kind: marker.kind,
                markerIndent: marker.markerIndent,
                contentIndent: marker.contentIndent,
                committedItemCount: 0,
                startedItemCount: 1
            )
        }

        private func parseListMarkerPrefix(in line: String) -> ParsedListMarker? {
            var columns = 0
            var idx = line.startIndex
            while idx < line.endIndex {
                let ch = line[idx]
                if ch == " " {
                    columns += 1
                    idx = line.index(after: idx)
                } else if ch == "\t" {
                    columns += 4
                    idx = line.index(after: idx)
                } else {
                    break
                }
            }
            guard idx < line.endIndex else { return nil }

            let marker = line[idx]
            if marker == "-" || marker == "*" || marker == "+" {
                idx = line.index(after: idx)
                var spaceColumns = 0
                while idx < line.endIndex {
                    let ws = line[idx]
                    if ws == " " {
                        spaceColumns += 1
                    } else if ws == "\t" {
                        spaceColumns += 4
                    } else {
                        break
                    }
                    idx = line.index(after: idx)
                }
                guard spaceColumns > 0 else { return nil }
                return ParsedListMarker(
                    kind: .unordered,
                    markerIndent: columns,
                    contentIndent: columns + 1 + spaceColumns
                )
            }

            if marker.wholeNumberValue != nil {
                var digits = ""
                while idx < line.endIndex, line[idx].wholeNumberValue != nil {
                    digits.append(line[idx])
                    idx = line.index(after: idx)
                }
                guard !digits.isEmpty, idx < line.endIndex else { return nil }
                let delimiter = line[idx]
                guard delimiter == "." || delimiter == ")" else { return nil }
                idx = line.index(after: idx)
                var spaceColumns = 0
                while idx < line.endIndex {
                    let ws = line[idx]
                    if ws == " " {
                        spaceColumns += 1
                    } else if ws == "\t" {
                        spaceColumns += 4
                    } else {
                        break
                    }
                    idx = line.index(after: idx)
                }
                guard spaceColumns > 0 else { return nil }
                let startIndex = max(1, Int(digits) ?? 1)
                return ParsedListMarker(
                    kind: .ordered(startIndex: startIndex),
                    markerIndent: columns,
                    contentIndent: columns + digits.count + 1 + spaceColumns
                )
            }

            return nil
        }

        private func looksLikeTableHeaderRow(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            guard trimmed.contains("|") else { return false }
            guard !looksLikeTableSeparator(trimmed) else { return false }
            for ch in trimmed where ch != "|" && ch != " " && ch != "\t" {
                return true
            }
            return false
        }

        private func looksLikeTableRow(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return trimmed.contains("|")
        }

        private func looksLikeTableSeparator(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            guard trimmed.contains("|"), trimmed.contains("-") else { return false }
            for ch in trimmed {
                switch ch {
                case "|", "-", ":", " ", "\t":
                    continue
                default:
                    return false
                }
            }
            return true
        }
    }

    private func renderMarkdown(
        _ markdown: String,
        style: MarkdownStyle,
        styleKey: String,
        textView: MarkdownPlatformTextView
    ) {
        currentRenderID &+= 1
        let renderID = currentRenderID
        let resolvedWidth = resolveLayoutWidth(textView.bounds.width, textView: textView)
        if resolvedWidth > 1 { lastLayoutWidth = resolvedWidth }
        let maxWidth = lastLayoutWidth > 1 ? lastLayoutWidth : nil

        if let cached = MarkdownRenderCache.shared.attributedString(
            for: markdown,
            styleKey: styleKey
        ) {
            applyRender(
                MarkdownRenderResult(attributedString: cached, attachments: []),
                to: textView,
                markdown: markdown,
                styleKey: styleKey,
                renderID: renderID
            )
            return
        }

#if os(macOS)
        Task { @MainActor [weak self] in
            guard let self, self.currentRenderID == renderID else { return }
            let renderer = MarkdownAttributedStringRenderer(style: style, maxImageWidth: maxWidth)
            let result = renderer.render(markdown: markdown)
            if result.attachments.isEmpty {
                MarkdownRenderCache.shared.store(
                    result.attributedString,
                    markdown: markdown,
                    styleKey: styleKey
                )
            }
            guard let textView = self.currentTextView else { return }
            self.applyRender(
                result,
                to: textView,
                markdown: markdown,
                styleKey: styleKey,
                renderID: renderID
            )
        }
#else
        renderQueue.async { [weak self] in
            let renderer = MarkdownAttributedStringRenderer(style: style, maxImageWidth: maxWidth)
            let result = renderer.render(markdown: markdown)
            if result.attachments.isEmpty {
                MarkdownRenderCache.shared.store(
                    result.attributedString,
                    markdown: markdown,
                    styleKey: styleKey
                )
            }
            Task { @MainActor [weak self] in
                guard let self, self.currentRenderID == renderID else { return }
                guard let textView = self.currentTextView else { return }
                self.applyRender(
                    result,
                    to: textView,
                    markdown: markdown,
                    styleKey: styleKey,
                    renderID: renderID
                )
            }
        }
#endif
    }

    private func applyRender(
        _ result: MarkdownRenderResult,
        to textView: MarkdownPlatformTextView,
        markdown: String,
        styleKey: String,
        renderID: UInt64
    ) {
        guard currentRenderID == renderID else { return }
        if let storage = textStorage(for: textView) {
            storage.setAttributedString(result.attributedString)
        }
        attachments = result.attachments
        resetStreamingIncrementalState()
        updateAttachmentWidth()
        queueImageLoads(attachments: result.attachments)
        lastMarkdown = markdown
        lastStyleKey = styleKey
        invalidateLayout(for: textView, changedRange: nil)
    }

    private func queueImageLoads(
        attachments: [MarkdownAttachment]
    ) {
        guard !attachments.isEmpty else { return }
        for attachment in attachments {
            guard let imageAttachment = attachment as? MarkdownImageAttachment else { continue }
            imageLoader.loadImage(source: imageAttachment.source) { [weak self] image in
                guard let self else { return }
                guard let textView = self.currentTextView else { return }
                guard self.containsAttachment(imageAttachment) else { return }
                imageAttachment.setImage(image)
                self.invalidateLayout(for: textView, changedRange: self.rangeOfAttachment(imageAttachment, in: textView))
            }
        }
    }

    private func resetStreamingIncrementalState() {
        streamingState = nil
        streamingCommittedMarkdownUTF16Count = 0
        streamingCommittedAttributedString = nil
        streamingCommittedAttachments = []
        streamingCommittedStyleKey = ""
        streamingCommittedOrderedList = nil
        resetStreamingOpenAttachmentState()
    }

    private func resetStreamingOpenAttachmentState() {
        streamingActiveTailAttachment = nil
        streamingActiveTailAttachmentRange = nil
        streamingActiveTableAttachment = nil
        streamingActiveTableLineBuffer = ""
        streamingActiveTableHasDraftRow = false
        streamingActiveTableDraftLine = ""
    }

    private func resolveStreamingActiveAttachmentRange(
        _ attachment: MarkdownAttachment,
        storage: NSTextStorage,
        searchRange: NSRange
    ) -> NSRange? {
        if streamingActiveTailAttachment === attachment, let cached = streamingActiveTailAttachmentRange {
            let clamped = clampRange(cached, upperBound: storage.length)
            if clamped.length > 0,
               clamped.location < storage.length,
               let existing = storage.attribute(.attachment, at: clamped.location, effectiveRange: nil) as? MarkdownAttachment,
               existing === attachment {
                return clamped
            }
        }

        guard let found = rangeOfAttachment(attachment, in: storage, searchRange: searchRange) else { return nil }
        streamingActiveTailAttachment = attachment
        streamingActiveTailAttachmentRange = found
        return found
    }

    private func currentLineSuffix(from markdown: String) -> String {
        guard let newline = markdown.lastIndex(of: "\n") else { return markdown }
        let nextIndex = markdown.index(after: newline)
        return String(markdown[nextIndex...])
    }

    private func consumeCompletedTableLines(
        from buffer: String,
        style: MarkdownStyle,
        columnCountHint: Int?
    ) -> (rows: [MarkdownTableRow], remainder: String) {
        guard buffer.contains("\n") else {
            return ([], buffer)
        }
        var rows: [MarkdownTableRow] = []
        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: "\n") {
            var line = String(buffer[start..<newline])
            if line.hasSuffix("\r") { line.removeLast() }
            if let row = makeStreamingTableRow(from: line, style: style, columnCountHint: columnCountHint) {
                rows.append(row)
            }
            start = buffer.index(after: newline)
        }
        return (rows, String(buffer[start...]))
    }

    private func makeStreamingTableRow(
        from line: String,
        style: MarkdownStyle,
        columnCountHint: Int?
    ) -> MarkdownTableRow? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.contains("|") else { return nil }
        guard !looksLikeTableSeparatorLine(trimmed) else { return nil }

        let rawCells = splitTableRowCells(trimmed)
        let columnCount = columnCountHint ?? rawCells.count
        guard columnCount > 0 else { return nil }

        var attrs = style.baseAttributes
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byWordWrapping
        attrs[.paragraphStyle] = paragraphStyle

        var cells: [NSAttributedString] = []
        cells.reserveCapacity(columnCount)
        for column in 0..<columnCount {
            let text = column < rawCells.count ? rawCells[column] : ""
            cells.append(NSAttributedString(string: text, attributes: attrs))
        }
        return MarkdownTableRow(cells: cells, isHeader: false)
    }

    private func looksLikeTableSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.contains("|"), trimmed.contains("-") else { return false }
        for ch in trimmed {
            switch ch {
            case "|", "-", ":", " ", "\t":
                continue
            default:
                return false
            }
        }
        return true
    }

    private func splitTableRowCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return [] }

        var cells: [String] = []
        cells.reserveCapacity(4)

        var current = ""
        var idx = trimmed.startIndex
        var inCodeSpan = false
        var codeDelimiterCount = 0
        var isEscaped = false

        func flushCell() {
            cells.append(current.trimmingCharacters(in: .whitespaces))
            current = ""
        }

        while idx < trimmed.endIndex {
            let ch = trimmed[idx]

            if isEscaped {
                current.append(ch)
                isEscaped = false
                idx = trimmed.index(after: idx)
                continue
            }

            if ch == "\\" {
                isEscaped = true
                idx = trimmed.index(after: idx)
                continue
            }

            if ch == "`" {
                var runCount = 0
                var runEnd = idx
                while runEnd < trimmed.endIndex, trimmed[runEnd] == "`" {
                    runCount += 1
                    runEnd = trimmed.index(after: runEnd)
                }
                current.append(contentsOf: trimmed[idx..<runEnd])
                if !inCodeSpan {
                    inCodeSpan = true
                    codeDelimiterCount = runCount
                } else if runCount == codeDelimiterCount {
                    inCodeSpan = false
                    codeDelimiterCount = 0
                }
                idx = runEnd
                continue
            }

            if ch == "|", !inCodeSpan {
                flushCell()
                idx = trimmed.index(after: idx)
                continue
            }

            current.append(ch)
            idx = trimmed.index(after: idx)
        }

        flushCell()
        return cells
    }

    private struct AttachmentOccurrence {
        let range: NSRange
        let attachment: MarkdownAttachment
    }

    private func attachmentOccurrences(in attributed: NSAttributedString) -> [AttachmentOccurrence] {
        guard attributed.length > 0 else { return [] }
        var occurrences: [AttachmentOccurrence] = []
        occurrences.reserveCapacity(4)
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length),
            options: []
        ) { value, range, _ in
            guard let attachment = value as? MarkdownAttachment else { return }
            occurrences.append(AttachmentOccurrence(range: range, attachment: attachment))
        }
        return occurrences
    }

    private func reconcileReplacementAttachments(
        replacement: NSMutableAttributedString,
        incomingAttachments: [MarkdownAttachment],
        reusableAttachments: [MarkdownAttachment]
    ) -> [MarkdownAttachment] {
        guard !incomingAttachments.isEmpty else { return [] }
        guard !reusableAttachments.isEmpty else { return incomingAttachments }

        let occurrences = attachmentOccurrences(in: replacement)
        guard occurrences.count == incomingAttachments.count else {
            return incomingAttachments
        }

        var resolved: [MarkdownAttachment] = []
        resolved.reserveCapacity(occurrences.count)
        var preferredStart = 0
        var usedIndices: Set<Int> = []

        for occurrence in occurrences {
            let incoming = occurrence.attachment
            guard let matchedIndex = reusableAttachmentIndex(
                for: incoming,
                in: reusableAttachments,
                preferredStart: preferredStart,
                excluding: usedIndices
            ), let reused = synchronizeReusableAttachment(
                existing: reusableAttachments[matchedIndex],
                incoming: incoming
            ) else {
                resolved.append(incoming)
                continue
            }
            replacement.removeAttribute(.attachment, range: occurrence.range)
            replacement.addAttribute(.attachment, value: reused, range: occurrence.range)
            resolved.append(reused)
            usedIndices.insert(matchedIndex)
            preferredStart = min(reusableAttachments.count, matchedIndex + 1)
        }

        return resolved
    }

    private func reusableAttachmentIndex(
        for incoming: MarkdownAttachment,
        in reusableAttachments: [MarkdownAttachment],
        preferredStart: Int,
        excluding usedIndices: Set<Int>
    ) -> Int? {
        guard !reusableAttachments.isEmpty else { return nil }
        let normalizedPreferredStart: Int = {
            if preferredStart <= 0 { return 0 }
            return preferredStart % reusableAttachments.count
        }()
        var bestIndex: Int?
        var bestScore = Int.min

        for index in reusableAttachments.indices {
            if usedIndices.contains(index) { continue }
            guard let similarityScore = attachmentReuseSimilarityScore(
                existing: reusableAttachments[index],
                incoming: incoming
            ) else {
                continue
            }
            let score = similarityScore + attachmentOrderBonus(
                index: index,
                preferredStart: normalizedPreferredStart,
                count: reusableAttachments.count
            )
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func canReuseAttachment(
        existing: MarkdownAttachment,
        incoming: MarkdownAttachment
    ) -> Bool {
        attachmentReuseSimilarityScore(existing: existing, incoming: incoming) != nil
    }

    private func attachmentReuseSimilarityScore(
        existing: MarkdownAttachment,
        incoming: MarkdownAttachment
    ) -> Int? {
        switch (existing, incoming) {
        case (let existing as MarkdownCodeBlockAttachment, let incoming as MarkdownCodeBlockAttachment):
            guard existing.languageLabel == incoming.languageLabel,
                  existing.copyLabel == incoming.copyLabel,
                  codeBlockStylesEqual(existing.style, incoming.style)
            else {
                return nil
            }
            return codeReuseSimilarityScore(existing: existing.code, incoming: incoming.code)
        case (let existing as MarkdownTableAttachment, let incoming as MarkdownTableAttachment):
            guard tableStylesEqual(existing.style, incoming.style) else { return nil }
            return tableReuseSimilarityScore(existingRows: existing.rows, incomingRows: incoming.rows)
        case (let existing as MarkdownQuoteAttachment, let incoming as MarkdownQuoteAttachment):
            guard quoteStylesEqual(existing.style, incoming.style),
                  existing.content.isEqual(to: incoming.content)
            else {
                return nil
            }
            return 260_000 + existing.content.length
        case (let existing as MarkdownRuleAttachment, let incoming as MarkdownRuleAttachment):
            guard colorsEqual(existing.color, incoming.color),
                  abs(existing.thickness - incoming.thickness) < 0.5,
                  abs(existing.verticalPadding - incoming.verticalPadding) < 0.5
            else {
                return nil
            }
            return 100_000
        case (let existing as MarkdownImageAttachment, let incoming as MarkdownImageAttachment):
            guard existing.source == incoming.source,
                  existing.altText == incoming.altText
            else {
                return nil
            }
            return 180_000
        default:
            return nil
        }
    }

    private func attachmentOrderBonus(index: Int, preferredStart: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let normalizedStart = max(0, min(preferredStart, count - 1))
        let forwardDistance = index >= normalizedStart ? index - normalizedStart : count - normalizedStart + index
        return max(0, 512 - forwardDistance)
    }

    private func codeReuseSimilarityScore(existing: String, incoming: String) -> Int? {
        if existing == incoming {
            return 320_000 + existing.utf16.count
        }
        if incoming.hasPrefix(existing) {
            return 300_000 + existing.utf16.count
        }
        if existing.hasPrefix(incoming) {
            return 290_000 + incoming.utf16.count
        }
        return nil
    }

    private func tableReuseSimilarityScore(
        existingRows: [MarkdownTableRow],
        incomingRows: [MarkdownTableRow]
    ) -> Int? {
        if existingRows.isEmpty || incomingRows.isEmpty {
            return existingRows.isEmpty && incomingRows.isEmpty ? 200_000 : nil
        }

        // Require the first row (header/first data row) to match exactly.
        guard tableRowsEqual(existingRows[0], incomingRows[0]) else { return nil }

        let sharedRowCount = min(existingRows.count, incomingRows.count)
        var exactSharedRows = 0
        var cellMatchScore = 0

        for rowIndex in 0..<sharedRowCount {
            let existingRow = existingRows[rowIndex]
            let incomingRow = incomingRows[rowIndex]
            if tableRowsEqual(existingRow, incomingRow) {
                exactSharedRows += 1
                cellMatchScore += existingRow.cells.count
                continue
            }

            // Streaming table updates may mutate the last shared draft row; accept if cells still share a leading prefix.
            guard rowIndex == sharedRowCount - 1,
                  let partialScore = tableRowPartialPrefixScore(existingRow, incomingRow)
            else {
                return nil
            }
            cellMatchScore += partialScore
            break
        }

        guard exactSharedRows > 0 else { return nil }
        let rowDepthScore = exactSharedRows * 256
        let sizeScore = min(existingRows.count, incomingRows.count) * 8
        return 240_000 + rowDepthScore + cellMatchScore + sizeScore
    }

    private func tableRowsEqual(_ lhs: MarkdownTableRow, _ rhs: MarkdownTableRow) -> Bool {
        guard lhs.isHeader == rhs.isHeader else { return false }
        guard lhs.cells.count == rhs.cells.count else { return false }
        for index in 0..<lhs.cells.count {
            if !lhs.cells[index].isEqual(to: rhs.cells[index]) { return false }
        }
        return true
    }

    private func tableRowPartialPrefixScore(_ lhs: MarkdownTableRow, _ rhs: MarkdownTableRow) -> Int? {
        guard lhs.isHeader == rhs.isHeader else { return nil }
        let sharedCount = min(lhs.cells.count, rhs.cells.count)
        guard sharedCount > 0 else { return nil }
        var matchingPrefixCells = 0
        for index in 0..<sharedCount {
            if lhs.cells[index].isEqual(to: rhs.cells[index]) {
                matchingPrefixCells += 1
            } else {
                break
            }
        }
        guard matchingPrefixCells > 0 else { return nil }
        return matchingPrefixCells * 16
    }

    private func synchronizeReusableAttachment(
        existing: MarkdownAttachment,
        incoming: MarkdownAttachment
    ) -> MarkdownAttachment? {
        switch (existing, incoming) {
        case (let existing as MarkdownCodeBlockAttachment, let incoming as MarkdownCodeBlockAttachment):
            guard canReuseAttachment(existing: existing, incoming: incoming) else { return nil }
            if existing.code != incoming.code {
                if incoming.code.hasPrefix(existing.code) {
                    let delta = String(incoming.code.dropFirst(existing.code.count))
                    existing.appendCode(delta)
                } else {
                    existing.replaceCode(incoming.code)
                }
            }
            return existing

        case (let existing as MarkdownTableAttachment, let incoming as MarkdownTableAttachment):
            guard canReuseAttachment(existing: existing, incoming: incoming) else { return nil }
            existing.synchronizeRows(to: incoming.rows)
            return existing

        case (let existing as MarkdownQuoteAttachment, let incoming as MarkdownQuoteAttachment):
            guard canReuseAttachment(existing: existing, incoming: incoming) else { return nil }
            guard existing.content.isEqual(to: incoming.content) else { return nil }
            return existing

        case (let existing as MarkdownRuleAttachment, let incoming as MarkdownRuleAttachment):
            guard canReuseAttachment(existing: existing, incoming: incoming) else { return nil }
            return existing

        case (let existing as MarkdownImageAttachment, let incoming as MarkdownImageAttachment):
            guard canReuseAttachment(existing: existing, incoming: incoming) else { return nil }
            return existing

        default:
            return nil
        }
    }

    private func splitReconciledAttachments(
        _ reconciled: [MarkdownAttachment],
        expectedCommitCount: Int,
        expectedTailCount: Int,
        fallbackCommit: [MarkdownAttachment],
        fallbackTail: [MarkdownAttachment]
    ) -> (commit: [MarkdownAttachment], tail: [MarkdownAttachment]) {
        guard reconciled.count == expectedCommitCount + expectedTailCount else {
            return (fallbackCommit, fallbackTail)
        }
        let commit = Array(reconciled.prefix(expectedCommitCount))
        let tail = Array(reconciled.dropFirst(expectedCommitCount))
        return (commit, tail)
    }

    private func tableStylesEqual(_ lhs: MarkdownTableStyle, _ rhs: MarkdownTableStyle) -> Bool {
        fontsEqual(lhs.baseFont, rhs.baseFont) &&
            colorsEqual(lhs.headerBackground, rhs.headerBackground) &&
            colorsEqual(lhs.stripeBackground, rhs.stripeBackground) &&
            colorsEqual(lhs.borderColor, rhs.borderColor) &&
            abs(lhs.borderWidth - rhs.borderWidth) < 0.5 &&
            abs(lhs.cellPadding.width - rhs.cellPadding.width) < 0.5 &&
            abs(lhs.cellPadding.height - rhs.cellPadding.height) < 0.5
    }

    private func codeBlockStylesEqual(_ lhs: MarkdownCodeBlockStyle, _ rhs: MarkdownCodeBlockStyle) -> Bool {
        fontsEqual(lhs.codeFont, rhs.codeFont) &&
            fontsEqual(lhs.headerFont, rhs.headerFont) &&
            colorsEqual(lhs.textColor, rhs.textColor) &&
            colorsEqual(lhs.headerTextColor, rhs.headerTextColor) &&
            colorsEqual(lhs.backgroundColor, rhs.backgroundColor) &&
            colorsEqual(lhs.headerBackground, rhs.headerBackground) &&
            colorsEqual(lhs.borderColor, rhs.borderColor) &&
            colorsEqual(lhs.copyTextColor, rhs.copyTextColor) &&
            colorsEqual(lhs.copyBackground, rhs.copyBackground) &&
            abs(lhs.borderWidth - rhs.borderWidth) < 0.5 &&
            abs(lhs.cornerRadius - rhs.cornerRadius) < 0.5 &&
            abs(lhs.codePadding.width - rhs.codePadding.width) < 0.5 &&
            abs(lhs.codePadding.height - rhs.codePadding.height) < 0.5 &&
            abs(lhs.headerPadding.width - rhs.headerPadding.width) < 0.5 &&
            abs(lhs.headerPadding.height - rhs.headerPadding.height) < 0.5
    }

    private func quoteStylesEqual(_ lhs: MarkdownQuoteStyle, _ rhs: MarkdownQuoteStyle) -> Bool {
        colorsEqual(lhs.textColor, rhs.textColor) &&
            colorsEqual(lhs.borderColor, rhs.borderColor) &&
            abs(lhs.borderWidth - rhs.borderWidth) < 0.5 &&
            abs(lhs.padding.width - rhs.padding.width) < 0.5 &&
            abs(lhs.padding.height - rhs.padding.height) < 0.5
    }

    private func updateAttachmentWidth() {
        updateAttachmentWidth(for: attachments)
    }

    private func updateAttachmentWidth(for attachments: [MarkdownAttachment]) {
        guard !attachments.isEmpty else { return }
        let maxWidth = max(0, lastLayoutWidth - 4)
        guard maxWidth > 0 else { return }
        #if os(macOS)
        let lineFrag = CGRect(x: 0, y: 0, width: maxWidth, height: 0)
        #endif
        for attachment in attachments {
            attachment.maxWidth = maxWidth
            #if os(macOS)
            if !attachment.allowsTextAttachmentView, attachment.image == nil {
                // AppKit layout doesn't consult attachmentBounds for sizing, so prime the image explicitly.
                _ = attachment.attachmentBounds(
                    for: nil,
                    proposedLineFragment: lineFrag,
                    glyphPosition: .zero,
                    characterIndex: 0
                )
            }
            #endif
        }
    }

    private func invalidateLayout(
        for textView: MarkdownPlatformTextView,
        changedRange: NSRange?
    ) {
        enqueueLayoutInvalidation(for: textView, changedRange: changedRange)
    }

    private func enqueueLayoutInvalidation(
        for textView: MarkdownPlatformTextView,
        changedRange: NSRange?
    ) {
        if let pendingView = pendingInvalidationTextView, pendingView !== textView {
            let pendingRange = pendingInvalidationRange
            pendingInvalidationTextView = nil
            pendingInvalidationRange = nil
            pendingInvalidationScheduled = false
            performInvalidateLayout(for: pendingView, changedRange: pendingRange)
        }

        let hadPendingRange = pendingInvalidationTextView != nil
        pendingInvalidationTextView = textView
        pendingInvalidationRange = hadPendingRange
            ? mergeInvalidationRanges(pendingInvalidationRange, changedRange)
            : changedRange

        guard !pendingInvalidationScheduled else { return }
        pendingInvalidationScheduled = true

        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self else { return }
            guard self.pendingInvalidationScheduled else { return }
            self.pendingInvalidationScheduled = false
            let targetView = self.pendingInvalidationTextView ?? textView
            let targetRange = self.pendingInvalidationRange
            self.pendingInvalidationTextView = nil
            self.pendingInvalidationRange = nil
            guard let targetView else { return }
            self.performInvalidateLayout(for: targetView, changedRange: targetRange)
        }
    }

    private func mergeInvalidationRanges(_ lhs: NSRange?, _ rhs: NSRange?) -> NSRange? {
        if lhs == nil || rhs == nil {
            return nil
        }
        return NSUnionRange(lhs!, rhs!)
    }

    private func performInvalidateLayout(
        for textView: MarkdownPlatformTextView,
        changedRange: NSRange?
    ) {
        #if os(iOS) || os(tvOS) || os(watchOS)
        if #available(iOS 16.0, tvOS 16.0, *) {
            if let textLayoutManager = textView.textLayoutManager,
               let documentRange = textLayoutManager.textContentManager?.documentRange {
                let storageLength = textView.textStorage.length
                let range = normalizedInvalidationRange(
                    changedRange: changedRange,
                    storageLength: storageLength
                )
                if let textRange = makeTextRange(
                    range,
                    documentRange: documentRange,
                    contentManager: textLayoutManager.textContentManager,
                    storageLength: storageLength
                ) {
                    textLayoutManager.invalidateLayout(for: textRange)
                } else {
                    textLayoutManager.invalidateLayout(for: documentRange)
                }
            }
        } else {
            let layoutManager = textView.layoutManager
            let storage = textView.textStorage
            let range = normalizedInvalidationRange(
                changedRange: changedRange,
                storageLength: storage.length
            )
            layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: range)
        }
        textView.setNeedsLayout()
        if let markdownTextView = textView as? MarkdownUIKitTextView {
            markdownTextView.markLayoutChanged(changedRange: changedRange)
        } else {
            textView.invalidateIntrinsicContentSize()
        }
        #elseif os(macOS)
        if #available(macOS 12.0, *) {
            if let textLayoutManager = textView.textLayoutManager,
               let documentRange = textLayoutManager.textContentManager?.documentRange {
                let storageLength = textView.textStorage?.length ?? 0
                let range = normalizedInvalidationRange(
                    changedRange: changedRange,
                    storageLength: storageLength
                )
                if let textRange = makeTextRange(
                    range,
                    documentRange: documentRange,
                    contentManager: textLayoutManager.textContentManager,
                    storageLength: storageLength
                ) {
                    textLayoutManager.invalidateLayout(for: textRange)
                } else {
                    textLayoutManager.invalidateLayout(for: documentRange)
                }
            } else if let layoutManager = textView.layoutManager, let storage = textView.textStorage {
                let range = normalizedInvalidationRange(
                    changedRange: changedRange,
                    storageLength: storage.length
                )
                layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                layoutManager.invalidateDisplay(forCharacterRange: range)
            }
        } else if let layoutManager = textView.layoutManager, let storage = textView.textStorage {
            let range = normalizedInvalidationRange(
                changedRange: changedRange,
                storageLength: storage.length
            )
            layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: range)
        }
        textView.needsLayout = true
        textView.needsDisplay = true
        if let markdownTextView = textView as? MarkdownAppKitTextView {
            markdownTextView.markLayoutChanged(changedRange: changedRange)
        } else {
            textView.invalidateIntrinsicContentSize()
        }
        #endif
    }

    private func invalidationStart(
        in storage: NSTextStorage,
        insertionLocation: Int
    ) -> Int {
        let clamped = max(0, min(insertionLocation, storage.length))
        let priorIndex = clamped - 1
        guard priorIndex >= 0 else { return 0 }

        if storage.attribute(.attachment, at: priorIndex, effectiveRange: nil) != nil {
            return clamped
        }

        let prior = (storage.string as NSString).character(at: priorIndex)
        switch prior {
        case 0x0A, 0x0D, 0x2028, 0x2029:
            return clamped
        default:
            return priorIndex
        }
    }

    private func normalizedInvalidationRange(
        changedRange: NSRange?,
        storageLength: Int
    ) -> NSRange {
        let fullRange = NSRange(location: 0, length: storageLength)
        let clamped = clampRange(changedRange ?? fullRange, upperBound: storageLength)
        if clamped.length > 0 || storageLength == 0 {
            return clamped
        }
        let fallbackLocation = max(0, min(clamped.location, storageLength - 1))
        return NSRange(location: fallbackLocation, length: 1)
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    private func makeTextRange(
        _ range: NSRange,
        documentRange: NSTextRange,
        contentManager: NSTextContentManager?,
        storageLength: Int
    ) -> NSTextRange? {
        guard let contentManager else { return nil }
        let clamped = clampRange(range, upperBound: storageLength)
        let startOffset = max(0, clamped.location)
        let length = max(0, clamped.length)
        let endOffset = min(storageLength, startOffset + length)

        if startOffset == 0, endOffset == storageLength {
            return documentRange
        }

        let startDistanceToStart = startOffset
        let startDistanceToEnd = storageLength - startOffset
        let useEndForStart = startDistanceToEnd < startDistanceToStart
        let startAnchor = useEndForStart ? documentRange.endLocation : documentRange.location
        let startAnchorOffset = useEndForStart ? startOffset - storageLength : startOffset
        guard let startLocation = contentManager.location(startAnchor, offsetBy: startAnchorOffset) else {
            return nil
        }
        if length == 0 {
            return NSTextRange(location: startLocation)
        }

        let endLocation: any NSTextLocation
        if endOffset == storageLength {
            endLocation = documentRange.endLocation
        } else {
            let endDistanceToStart = endOffset
            let endDistanceToEnd = storageLength - endOffset
            let useEndForEnd = endDistanceToEnd < endDistanceToStart
            let endAnchor = useEndForEnd ? documentRange.endLocation : documentRange.location
            let endAnchorOffset = useEndForEnd ? endOffset - storageLength : endOffset
            guard let resolvedEndLocation = contentManager.location(endAnchor, offsetBy: endAnchorOffset) else {
                return nil
            }
            endLocation = resolvedEndLocation
        }

        return NSTextRange(location: startLocation, end: endLocation)
    }

    private func isSafePlainAppend(_ delta: String) -> Bool {
        if delta.contains("\n") { return false }
        let forbidden = CharacterSet(charactersIn: "*_`[]()!#>|~")
        return delta.rangeOfCharacter(from: forbidden) == nil
    }

    private func clampRange(_ range: NSRange, upperBound: Int) -> NSRange {
        let start = Swift.max(0, Swift.min(range.location, upperBound))
        let end = Swift.max(0, Swift.min(range.location + range.length, upperBound))
        return NSRange(location: start, length: max(0, end - start))
    }

    private func containsAttachment(_ target: MarkdownAttachment) -> Bool {
        attachments.contains(where: { $0 === target })
    }

    private func rangeOfAttachment(
        _ target: MarkdownAttachment,
        in textView: MarkdownPlatformTextView
    ) -> NSRange? {
        guard let storage = textStorage(for: textView), storage.length > 0 else { return nil }
        var found: NSRange?
        storage.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: storage.length),
            options: []
        ) { value, range, stop in
            guard let attachment = value as? MarkdownAttachment else { return }
            guard attachment === target else { return }
            found = range
            stop.pointee = true
        }
        return found
    }

    private func rangeOfAttachment(
        _ target: MarkdownAttachment,
        in storage: NSTextStorage,
        searchRange: NSRange
    ) -> NSRange? {
        guard storage.length > 0 else { return nil }
        let range = clampRange(searchRange, upperBound: storage.length)
        var found: NSRange?
        storage.enumerateAttribute(
            .attachment,
            in: range,
            options: []
        ) { value, range, stop in
            guard let attachment = value as? MarkdownAttachment else { return }
            guard attachment === target else { return }
            found = range
            stop.pointee = true
        }
        return found
    }

    private func attributesAreBase(
        _ attributes: [NSAttributedString.Key: Any],
        style: MarkdownStyle
    ) -> Bool {
        guard let font = attributes[.font] as? MarkdownPlatformFont else { return false }
        guard let color = attributes[.foregroundColor] as? MarkdownPlatformColor else { return false }
        if !fontsEqual(font, style.baseFont) { return false }
        if !colorsEqual(color, style.baseColor) { return false }
        if attributes[.link] != nil { return false }
        if attributes[.backgroundColor] != nil { return false }
        if attributes[.attachment] != nil { return false }
        return true
    }

    private func textStorage(for textView: MarkdownPlatformTextView) -> NSTextStorage? {
        #if os(iOS) || os(tvOS) || os(watchOS)
        return textView.textStorage
        #elseif os(macOS)
        return textView.textStorage
        #endif
    }

    private func fontsEqual(_ lhs: MarkdownPlatformFont, _ rhs: MarkdownPlatformFont) -> Bool {
        lhs.fontName == rhs.fontName && abs(lhs.pointSize - rhs.pointSize) < 0.5
    }

    private func colorsEqual(_ lhs: MarkdownPlatformColor, _ rhs: MarkdownPlatformColor) -> Bool {
        lhs.isEqual(rhs)
    }

    private func resolveLayoutWidth(
        _ width: CGFloat,
        textView: MarkdownPlatformTextView?
    ) -> CGFloat {
        if width > 1 { return width }
        guard let textView else { return width }
        #if os(macOS)
        if let containerWidth = textView.textContainer?.containerSize.width, containerWidth > 1 {
            let inset = textView.textContainerInset.width * 2
            return containerWidth + inset
        }
        if let superWidth = textView.superview?.bounds.width, superWidth > 1 {
            return superWidth
        }
        #endif
        return 320
    }

    private func resolvedColorScheme(
        for textView: MarkdownPlatformTextView,
        fallback: ColorScheme
    ) -> ColorScheme {
        #if os(iOS) || os(tvOS) || os(watchOS)
        switch textView.traitCollection.userInterfaceStyle {
        case .dark:
            return .dark
        case .light:
            return .light
        default:
            return fallback
        }
        #else
        return fallback
        #endif
    }
}

private func utf16Substring(_ string: String, from start: Int, to end: Int) -> String {
    let upperBound = string.utf16.count
    let clampedStart = max(0, min(start, upperBound))
    let clampedEnd = max(clampedStart, min(end, upperBound))
    let startIndex = String.Index(utf16Offset: clampedStart, in: string)
    let endIndex = String.Index(utf16Offset: clampedEnd, in: string)
    return String(string[startIndex..<endIndex])
}
