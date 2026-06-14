//
//  AutoSizingTextEditor+iOS.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

#if !os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct AutoSizingTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var placeholder: String = ""
    var maxLines: Int = 6
    var allowsImagePasting: Bool = true
    var maxPastedImages: Int = .max
    var onOverflowChange: (Bool) -> Void = { _ in }
    var onPasteImages: ([(data: Data, mimeType: String?)]) -> Void = { _ in }

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

    func makeUIView(context: Context) -> UITextView {
        let tv = PasteAwareTextView()
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: AutoSizingTextEditorLayout.fontSize)
        tv.backgroundColor = .clear
        tv.textAlignment = .natural
        tv.placeholder = placeholder
        tv.textContainerInset = UIEdgeInsets(
            top: AutoSizingTextEditorLayout.verticalInset,
            left: InputMetrics.innerLeading,
            bottom: AutoSizingTextEditorLayout.verticalInset,
            right: InputMetrics.innerTrailing
        )
        tv.textContainer.lineFragmentPadding = 0
        tv.isScrollEnabled = false
        tv.alwaysBounceVertical = true
        tv.showsVerticalScrollIndicator = true
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.allowsImagePasting = allowsImagePasting
        tv.maxPastedImages = maxPastedImages
        tv.onPasteImages = onPasteImages
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        if let pasteAwareTextView = uiView as? PasteAwareTextView {
            pasteAwareTextView.allowsImagePasting = allowsImagePasting
            pasteAwareTextView.maxPastedImages = maxPastedImages
            pasteAwareTextView.onPasteImages = onPasteImages
            pasteAwareTextView.placeholder = placeholder
        }
        // Avoid stomping on in-progress IME composition during unrelated SwiftUI updates.
        uiView.semanticContentAttribute = context.environment.layoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        uiView.textAlignment = .natural
        if uiView.markedTextRange == nil, uiView.text != text {
            uiView.text = text
        }
        recalcHeight(uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    fileprivate func recalcHeight(_ tv: UITextView) {
        if let pasteAwareTextView = tv as? PasteAwareTextView {
            pasteAwareTextView.refreshPresentationState()
        }
        let lineH = tv.font?.lineHeight ?? InputMetrics.baseLineHeight
        let fitting = tv.sizeThatFits(CGSize(width: tv.bounds.width, height: .greatestFiniteMagnitude)).height
        let contentHeight = max(0, fitting - tv.textContainerInset.top - tv.textContainerInset.bottom)
        let newH = AutoSizingTextEditorLayout.measuredHeight(contentHeight: contentHeight, lineHeight: lineH, maxLines: maxLines)

        let shouldScroll = AutoSizingTextEditorLayout.shouldOverflow(contentHeight: contentHeight, lineHeight: lineH, maxLines: maxLines)
        if tv.isScrollEnabled != shouldScroll {
            tv.isScrollEnabled = shouldScroll
        }

        scheduleStateUpdate(measuredHeight: newH, overflow: shouldScroll)

        if shouldScroll, tv.markedTextRange == nil {
            let end = NSRange(location: (tv.text as NSString).length, length: 0)
            tv.scrollRangeToVisible(end)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoSizingTextEditor
        init(_ parent: AutoSizingTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            if let pasteAwareTextView = textView as? PasteAwareTextView {
                pasteAwareTextView.refreshPresentationState()
            }
            let newText = textView.text ?? ""
            if parent.text != newText {
                parent.text = newText
            }
            parent.recalcHeight(textView)
            if textView.isScrollEnabled, textView.markedTextRange == nil {
                let end = NSRange(location: (textView.text as NSString).length, length: 0)
                textView.scrollRangeToVisible(end)
            }
        }
    }

    final class PasteAwareTextView: UITextView {
        private struct IndexedImageProvider {
            let itemIndex: Int
            let provider: NSItemProvider
        }

        var placeholder: String = "" {
            didSet {
                setNeedsDisplay()
                updateAccessibilityMetadata()
            }
        }

        var allowsImagePasting: Bool = true
        var maxPastedImages: Int = .max
        var onPasteImages: ([(data: Data, mimeType: String?)]) -> Void = { _ in }

        override var text: String! {
            didSet {
                refreshPresentationState()
            }
        }

        override var font: UIFont? {
            didSet { refreshPresentationState() }
        }

        override var textContainerInset: UIEdgeInsets {
            didSet { refreshPresentationState() }
        }

        private func updateAccessibilityMetadata() {
            let accessibilityPrompt = placeholder.trimmingCharacters(in: .whitespacesAndNewlines)
            accessibilityLabel = accessibilityPrompt.isEmpty ? nil : accessibilityPrompt
            accessibilityValue = (text?.isEmpty ?? true) ? nil : text
        }

        func refreshPresentationState() {
            setNeedsDisplay()
            updateAccessibilityMetadata()
        }

        override func draw(_ rect: CGRect) {
            super.draw(rect)

            guard (text?.isEmpty ?? true), !placeholder.isEmpty else { return }

            let lineFragmentPadding = textContainer.lineFragmentPadding
            let placeholderRect = CGRect(
                x: textContainerInset.left + lineFragmentPadding,
                y: textContainerInset.top,
                width: max(0, bounds.width - textContainerInset.left - textContainerInset.right - lineFragmentPadding * 2),
                height: max(0, bounds.height - textContainerInset.top - textContainerInset.bottom)
            )
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = textAlignment
            paragraphStyle.lineBreakMode = .byTruncatingTail

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? UIFont.systemFont(ofSize: AutoSizingTextEditorLayout.fontSize),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: paragraphStyle
            ]
            (placeholder as NSString).draw(in: placeholderRect, withAttributes: attributes)
        }

        override func paste(_ sender: Any?) {
            guard allowsImagePasting else {
                super.paste(sender)
                return
            }

            let pasteboard = UIPasteboard.general
            let providers = pasteboard.itemProviders
            let indexedImageProviders = providers.enumerated().compactMap { index, provider in
                Self.itemProviderMayContainImage(provider) ? IndexedImageProvider(itemIndex: index, provider: provider) : nil
            }
            guard !indexedImageProviders.isEmpty else {
                super.paste(sender)
                return
            }

            let limitedProviders = Array(indexedImageProviders.prefix(max(0, maxPastedImages)))
            guard !limitedProviders.isEmpty else {
                if pasteboard.items.contains(where: Self.pasteboardItemContainsNonEmptyText) {
                    super.paste(sender)
                }
                return
            }

            let shouldAlsoPasteText = Self.shouldAlsoPasteText(
                from: pasteboard,
                imageItemIndices: limitedProviders.map(\.itemIndex)
            )
            if shouldAlsoPasteText {
                super.paste(sender)
            }

            Task(priority: .utility) {
                let imported = await Self.importedImages(from: limitedProviders.map(\.provider))
                guard !imported.isEmpty else { return }
                await MainActor.run {
                    self.onPasteImages(imported)
                }
            }
        }

        private static func shouldAlsoPasteText(from pasteboard: UIPasteboard, imageItemIndices: [Int]) -> Bool {
            let imageIndexSet = Set(imageItemIndices)

            for (index, item) in pasteboard.items.enumerated() {
                if imageIndexSet.contains(index) { continue }
                if pasteboardItemContainsNonEmptyText(item) {
                    return true
                }
            }

            return false
        }

        private static func pasteboardItemContainsNonEmptyText(_ item: [String: Any]) -> Bool {
            for (typeIdentifier, value) in item {
                guard let type = UTType(typeIdentifier), type.conforms(to: .text) else {
                    continue
                }

                if let string = value as? String,
                   !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return true
                }
                if let string = value as? NSString,
                   !(string as String).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return true
                }
            }

            return false
        }

        private static func importedImages(from providers: [NSItemProvider]) async -> [(data: Data, mimeType: String?)] {
            var imported: [(data: Data, mimeType: String?)] = []
            imported.reserveCapacity(providers.count)

            for provider in providers {
                guard !Task.isCancelled else { return imported }

                let imageType = provider.registeredTypeIdentifiers
                    .compactMap(UTType.init)
                    .first(where: { $0.conforms(to: .image) })

                guard let imageType,
                      let data = try? await provider.loadDataRepresentationAsync(forTypeIdentifier: imageType.identifier),
                      !data.isEmpty else {
                    guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                          let fileURL = try? await provider.loadFileURLAsync(),
                          let payload = importedImageFilePayload(from: fileURL) else {
                        continue
                    }

                    imported.append(payload)
                    continue
                }

                imported.append(PastedImagePayloadNormalizer.normalize(data: data, mimeTypeHint: imageType.preferredMIMEType))
            }

            return imported
        }

        private static func itemProviderMayContainImage(_ provider: NSItemProvider) -> Bool {
            if itemProviderHasInlineImageData(provider) {
                return true
            }

            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                return false
            }

            guard let suggestedName = provider.suggestedName,
                  !suggestedName.isEmpty else {
                return true
            }

            let pathExtension = URL(fileURLWithPath: suggestedName).pathExtension
            guard !pathExtension.isEmpty,
                  let suggestedType = UTType(filenameExtension: pathExtension) else {
                return false
            }

            return suggestedType.conforms(to: .image)
        }

        private static func itemProviderHasInlineImageData(_ provider: NSItemProvider) -> Bool {
            provider.registeredTypeIdentifiers
                .compactMap(UTType.init)
                .contains(where: { $0.conforms(to: .image) })
        }

        private static func importedImageFilePayload(from fileURL: URL) -> (data: Data, mimeType: String?)? {
            let didStartSecurityScope = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didStartSecurityScope {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            if let contentType = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType,
               !contentType.conforms(to: .image) {
                return nil
            }

            guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
                return nil
            }

            let contentType = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            if contentType == nil, PastedImagePayloadNormalizer.sniffedMIMEType(from: data) == nil {
                return nil
            }

            return PastedImagePayloadNormalizer.normalize(
                data: data,
                mimeTypeHint: contentType?.preferredMIMEType
            )
        }
    }
}
#endif
