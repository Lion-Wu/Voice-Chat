//
//  AutoSizingTextEditor.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit

struct AutoSizingTextEditor: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    @Binding var text: String
    @Binding var height: CGFloat
    var maxLines: Int = 10
    var allowsImagePasting: Bool = true
    var maxPastedImages: Int = .max
    var onOverflowChange: (Bool) -> Void = { _ in }
    var onCommit: () -> Void = {}
    var onPasteImages: ([(data: Data, mimeType: String?)]) -> Void = { _ in }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = CommitTextView()
        textView.isEditable = true
        textView.font = .systemFont(ofSize: 17)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: InputMetrics.innerLeading, height: InputMetrics.innerTop)
        textView.isRichText = false
        textView.isAutomaticDataDetectionEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        textView.onCommit = onCommit
        textView.allowsImagePasting = allowsImagePasting
        textView.maxPastedImages = maxPastedImages
        textView.onPasteImages = onPasteImages

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        tv.allowsImagePasting = allowsImagePasting
        tv.maxPastedImages = maxPastedImages
        tv.onPasteImages = onPasteImages
        let isComposing = tv.hasMarkedText()
        if !isComposing, tv.string != text { tv.string = text }
        guard let textContainer = tv.textContainer else { return }
        let used = tv.layoutManager?.usedRect(for: textContainer) ?? .zero
        let lineH = tv.layoutManager?.defaultLineHeight(for: tv.font ?? .systemFont(ofSize: 17)) ?? 18
        let maxH = CGFloat(maxLines) * lineH + 18
        let newH = min(maxH, max(lineH, used.height + 18))
        let shouldOverflow = (used.height + 18) > (maxH - 1)
        DispatchQueue.main.async {
            if abs(height - newH) > 0.5 { height = newH }
            onOverflowChange(shouldOverflow)
        }

        if !isComposing {
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

        init(parent: AutoSizingTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            guard let textContainer = tv.textContainer else { return }
            let used = tv.layoutManager?.usedRect(for: textContainer) ?? .zero
            let lineH = tv.layoutManager?.defaultLineHeight(for: tv.font ?? .systemFont(ofSize: 17)) ?? 18
            let maxH = CGFloat(parent.maxLines) * lineH + 18
            let newH = min(maxH, max(lineH, used.height + 18))
            let shouldOverflow = (used.height + 18) > (maxH - 1)
            DispatchQueue.main.async {
                if abs(self.parent.height - newH) > 0.5 { self.parent.height = newH }
                self.parent.onOverflowChange(shouldOverflow)
            }

            if !tv.hasMarkedText() {
                let end = NSRange(location: (tv.string as NSString).length, length: 0)
                tv.scrollRangeToVisible(end)
            }
        }
    }

    final class CommitTextView: NSTextView {
        private struct PastedImageImportCandidate: Sendable {
            let itemIndex: Int
            let fileURL: URL?
            let data: Data?
            let mimeTypeHint: String?
        }

        var allowsImagePasting: Bool = true
        var maxPastedImages: Int = .max
        var onCommit: () -> Void = {}
        var onPasteImages: ([(data: Data, mimeType: String?)]) -> Void = { _ in }

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

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 {
                if event.modifierFlags.contains(.shift) {
                    super.keyDown(with: event)
                } else {
                    self.window?.makeFirstResponder(nil)
                    onCommit()
                }
            } else {
                super.keyDown(with: event)
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
            return normalizePastedImagePayload(data: data, mimeTypeHint: candidate.mimeTypeHint)
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

            return normalizePastedImagePayload(data: data, mimeTypeHint: contentType?.preferredMIMEType)
        }
    }
}

#else

import UIKit

struct AutoSizingTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var maxLines: Int = 6
    var allowsImagePasting: Bool = true
    var maxPastedImages: Int = .max
    var onOverflowChange: (Bool) -> Void = { _ in }
    var onPasteImages: ([(data: Data, mimeType: String?)]) -> Void = { _ in }

    func makeUIView(context: Context) -> UITextView {
        let tv = PasteAwareTextView()
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: 17)
        tv.backgroundColor = .clear
        tv.textAlignment = .natural
        tv.textContainerInset = UIEdgeInsets(
            top: InputMetrics.innerTop,
            left: InputMetrics.innerLeading,
            bottom: InputMetrics.innerBottom,
            right: InputMetrics.innerTrailing
        )
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
        if let pasteAwareTextView = uiView as? PasteAwareTextView {
            pasteAwareTextView.allowsImagePasting = allowsImagePasting
            pasteAwareTextView.maxPastedImages = maxPastedImages
            pasteAwareTextView.onPasteImages = onPasteImages
        }
        // Avoid stomping on in-progress IME composition (e.g., Chinese pinyin) during unrelated SwiftUI updates.
        uiView.semanticContentAttribute = context.environment.layoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        uiView.textAlignment = .natural
        if uiView.markedTextRange == nil, uiView.text != text {
            uiView.text = text
        }
        recalcHeight(uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    fileprivate func recalcHeight(_ tv: UITextView) {
        let lineH = tv.font?.lineHeight ?? 18
        let maxH = CGFloat(maxLines) * lineH + tv.textContainerInset.top + tv.textContainerInset.bottom
        let fitting = tv.sizeThatFits(CGSize(width: tv.bounds.width, height: .greatestFiniteMagnitude)).height
        let newH = min(maxH, max(lineH, fitting))

        let shouldScroll = fitting > (maxH - 1)
        if tv.isScrollEnabled != shouldScroll {
            tv.isScrollEnabled = shouldScroll
        }

        DispatchQueue.main.async {
            if abs(height - newH) > 0.5 { height = newH }
            onOverflowChange(shouldScroll)
        }

        if shouldScroll, tv.markedTextRange == nil {
            let end = NSRange(location: (tv.text as NSString).length, length: 0)
            tv.scrollRangeToVisible(end)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoSizingTextEditor
        init(_ parent: AutoSizingTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
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

        var allowsImagePasting: Bool = true
        var maxPastedImages: Int = .max
        var onPasteImages: ([(data: Data, mimeType: String?)]) -> Void = { _ in }

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

                imported.append(normalizePastedImagePayload(data: data, mimeTypeHint: imageType.preferredMIMEType))
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
            if contentType == nil, sniffedPastedImageMIMEType(from: data) == nil {
                return nil
            }

            return normalizePastedImagePayload(
                data: data,
                mimeTypeHint: contentType?.preferredMIMEType
            )
        }
    }
}
#endif

private let pasteCompatiblePassthroughMIMETypes: Set<String> = [
    "image/jpeg"
]

private func normalizePastedImagePayload(data: Data, mimeTypeHint: String?) -> (data: Data, mimeType: String?) {
    let resolvedMIMEType = canonicalPastedImageMIMEType(mimeTypeHint) ?? inferredPastedImageMIMEType(from: data)
    if pasteCompatiblePassthroughMIMETypes.contains(resolvedMIMEType) {
        return (data, resolvedMIMEType)
    }

    guard let transcoded = transcodedPastedImagePayload(from: data) else {
        return (data, resolvedMIMEType)
    }

    return transcoded
}

private func canonicalPastedImageMIMEType(_ mimeType: String?) -> String? {
    guard let mimeType else { return nil }
    let normalized = mimeType
        .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
        .first?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    switch normalized {
    case "image/jpg":
        return "image/jpeg"
    case .some(let value) where !value.isEmpty:
        return value
    default:
        return nil
    }
}

private func inferredPastedImageMIMEType(from data: Data) -> String {
    sniffedPastedImageMIMEType(from: data) ?? "image/png"
}

private func sniffedPastedImageMIMEType(from data: Data) -> String? {
    if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
    if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
    if data.starts(with: [0x49, 0x49, 0x2A, 0x00]) || data.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
        return "image/tiff"
    }

    if data.count >= 12 {
        let marker = String(decoding: data[4..<12], as: UTF8.self).lowercased()
        if marker.contains("heic") || marker.contains("heif") {
            return "image/heic"
        }
        if marker.contains("webp") {
            return "image/webp"
        }
    }

    return nil
}

#if os(macOS)
private func transcodedPastedImagePayload(from data: Data) -> (data: Data, mimeType: String?)? {
    guard let image = NSImage(data: data),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }

    let outputImage = pastedCGImageUsesTransparency(cgImage) ? pastedOpaqueJPEGReadyImage(from: cgImage) ?? cgImage : cgImage
    let bitmap = NSBitmapImageRep(cgImage: outputImage)

    let jpegProperties: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: 0.9]
    guard let jpegData = bitmap.representation(using: .jpeg, properties: jpegProperties) else {
        return nil
    }
    return (jpegData, "image/jpeg")
}
#else
private func transcodedPastedImagePayload(from data: Data) -> (data: Data, mimeType: String?)? {
    guard let image = UIImage(data: data),
          let cgImage = image.cgImage else {
        return nil
    }

    let outputImage = pastedCGImageUsesTransparency(cgImage) ? pastedOpaqueJPEGReadyImage(from: cgImage) ?? cgImage : cgImage
    let renderedImage = UIImage(cgImage: outputImage)

    guard let jpegData = renderedImage.jpegData(compressionQuality: 0.9) else {
        return nil
    }
    return (jpegData, "image/jpeg")
}
#endif

private func pastedCGImageUsesTransparency(_ image: CGImage) -> Bool {
    let alphaInfo = image.alphaInfo
    switch alphaInfo {
    case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
        break
    default:
        return false
    }

    guard let alphaOffset = pastedImageAlphaComponentOffset(in: image, alphaInfo: alphaInfo) else {
        return true
    }
    guard let provider = image.dataProvider,
          let data = provider.data,
          let bytes = CFDataGetBytePtr(data) else {
        return true
    }

    let bytesPerPixel = image.bitsPerPixel / 8
    guard bytesPerPixel > alphaOffset, image.height > 0, image.width > 0 else {
        return true
    }

    for row in 0..<image.height {
        let rowStart = row * image.bytesPerRow
        for column in 0..<image.width {
            let alphaIndex = rowStart + (column * bytesPerPixel) + alphaOffset
            if bytes[alphaIndex] < UInt8.max {
                return true
            }
        }
    }

    return false
}

private func pastedImageAlphaComponentOffset(in image: CGImage, alphaInfo: CGImageAlphaInfo) -> Int? {
    switch alphaInfo {
    case .alphaOnly:
        return 0
    case .first, .premultipliedFirst:
        return image.bitmapInfo.contains(.byteOrder32Little) ? 3 : 0
    case .last, .premultipliedLast:
        return image.bitmapInfo.contains(.byteOrder32Little) ? 0 : 3
    default:
        return nil
    }
}

private func pastedOpaqueJPEGReadyImage(from image: CGImage) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        return nil
    }

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()
}

@MainActor
extension NSItemProvider {
    func loadDataRepresentationAsync(forTypeIdentifier typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    func loadFileURLAsync() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let text = item as? String,
                          let url = URL(string: text) {
                    continuation.resume(returning: url)
                } else if let text = item as? NSString,
                          let url = URL(string: text as String) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var text: String = "Type here…"
    @Previewable @State var height: CGFloat = InputMetrics.defaultHeight

    VStack(alignment: .leading, spacing: 12) {
        Text("AutoSizingTextEditor")
            .font(.headline)

        #if os(macOS)
        AutoSizingTextEditor(
            text: $text,
            height: $height,
            maxLines: 6,
            onOverflowChange: { _ in },
            onCommit: {}
        )
        #else
        AutoSizingTextEditor(
            text: $text,
            height: $height,
            maxLines: 6,
            onOverflowChange: { _ in }
        )
        #endif
    }
    .padding()
    .background(AppBackgroundView())
    .frame(maxWidth: 520, maxHeight: 280, alignment: .topLeading)
}
