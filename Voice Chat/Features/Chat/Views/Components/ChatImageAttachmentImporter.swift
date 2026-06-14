//
//  ChatImageAttachmentImporter.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ChatImageImportPayload: Sendable {
    let data: Data
    let mimeType: String?
}

enum ChatImageAttachmentImporter {
    private static let imageProcessingQueue = DispatchQueue(
        label: "com.lionwu.voicechat.image-processing",
        qos: .utility,
        attributes: .concurrent
    )

    static func loadImageAttachments(from items: [PhotosPickerItem], limit: Int) async -> [ChatImageAttachment] {
        guard limit > 0 else { return [] }
        var imported: [ChatImageAttachment] = []
        imported.reserveCapacity(min(items.count, limit))

        for item in items {
            guard !Task.isCancelled else { return imported }
            guard imported.count < limit else { return imported }
            guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { continue }

            let mimeType = preferredImageMIMEType(for: item, data: data)
            guard let attachment = await makeImageAttachmentAsync(data: data, mimeTypeHint: mimeType) else { continue }
            imported.append(attachment)
        }

        return imported
    }

    static func loadImageAttachments(fromFileURLs urls: [URL], limit: Int) async -> [ChatImageAttachment] {
        guard limit > 0 else { return [] }
        let worker = Task.detached(priority: .utility) {
            var imported: [ChatImageAttachment] = []
            imported.reserveCapacity(min(urls.count, limit))

            for url in urls {
                guard !Task.isCancelled else { return imported }
                guard imported.count < limit else { return imported }
                guard let attachment = await loadImageAttachmentAsync(fromFileURL: url) else { continue }
                imported.append(attachment)
            }

            return imported
        }

        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func loadImageAttachments(from payloads: [ChatImageImportPayload], limit: Int) async -> [ChatImageAttachment] {
        guard limit > 0 else { return [] }
        let worker = Task.detached(priority: .utility) {
            var imported: [ChatImageAttachment] = []
            imported.reserveCapacity(min(payloads.count, limit))

            for payload in payloads {
                guard !Task.isCancelled else { return imported }
                guard imported.count < limit else { return imported }
                guard let attachment = await makeImageAttachmentAsync(data: payload.data, mimeTypeHint: payload.mimeType) else {
                    continue
                }
                imported.append(attachment)
            }

            return imported
        }

        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    @MainActor
    static func loadImageAttachments(fromItemProviders providers: [NSItemProvider], limit: Int) async -> [ChatImageAttachment] {
        guard limit > 0 else { return [] }
        var imported: [ChatImageAttachment] = []
        imported.reserveCapacity(min(providers.count, limit))

        for provider in providers {
            guard !Task.isCancelled else { return imported }
            guard imported.count < limit else { return imported }
            guard let attachment = await loadImageAttachment(from: provider) else { continue }
            imported.append(attachment)
        }

        return imported
    }

    static func itemProviderMayContainImage(_ provider: NSItemProvider) -> Bool {
        let registeredTypes = provider.registeredTypeIdentifiers.compactMap(UTType.init)
        if registeredTypes.contains(where: { $0.conforms(to: .image) }) {
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

    @MainActor
    static func loadImageAttachment(from provider: NSItemProvider) async -> ChatImageAttachment? {
        let imageType = provider.registeredTypeIdentifiers
            .compactMap(UTType.init)
            .first(where: { $0.conforms(to: .image) })

        if let imageType,
           let data = try? await provider.loadDataRepresentationAsync(forTypeIdentifier: imageType.identifier) {
            return await makeImageAttachmentAsync(data: data, mimeTypeHint: imageType.preferredMIMEType)
        }

        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
              let url = try? await provider.loadFileURLAsync() else {
            return nil
        }

        return await loadImageAttachmentAsync(fromFileURL: url)
    }

    static func loadImageAttachment(fromFileURL url: URL) -> ChatImageAttachment? {
        let didStartSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        if let contentType, !contentType.conforms(to: .image) {
            return nil
        }

        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        if contentType == nil, sniffedImageMIMEType(from: data) == nil {
            return nil
        }
        return makeImageAttachment(data: data, mimeTypeHint: contentType?.preferredMIMEType)
    }

    static func loadImageAttachmentAsync(fromFileURL url: URL) async -> ChatImageAttachment? {
        await withCheckedContinuation { continuation in
            imageProcessingQueue.async {
                continuation.resume(returning: loadImageAttachment(fromFileURL: url))
            }
        }
    }

    static func makeImageAttachmentAsync(data: Data, mimeTypeHint: String?) async -> ChatImageAttachment? {
        await withCheckedContinuation { continuation in
            imageProcessingQueue.async {
                continuation.resume(returning: makeImageAttachment(data: data, mimeTypeHint: mimeTypeHint))
            }
        }
    }

    static func makeImageAttachment(data: Data, mimeTypeHint: String?) -> ChatImageAttachment? {
        guard !data.isEmpty else { return nil }
        let resolvedMIMEType = sniffedImageMIMEType(from: data)
            ?? canonicalImageMIMEType(mimeTypeHint ?? "")

        if shouldTranscodeToCompatibleFormat(resolvedMIMEType),
           let transcodedPayload = transcodeToCompatibleImagePayload(from: data) {
            return ChatImageAttachment(mimeType: transcodedPayload.mimeType, data: transcodedPayload.data)
        }

        return ChatImageAttachment(mimeType: resolvedMIMEType, data: data)
    }

    static func canonicalImageMIMEType(_ mimeType: String) -> String {
        let normalized = mimeType
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        switch normalized {
        case "image/jpg":
            return "image/jpeg"
        default:
            return normalized.isEmpty ? "image/jpeg" : normalized
        }
    }

    static func isUserCancelledImageImport(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return true
        }

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return underlyingError.domain == NSCocoaErrorDomain && underlyingError.code == NSUserCancelledError
        }

        return false
    }

    static func shouldTranscodeToCompatibleFormat(_ mimeType: String) -> Bool {
        canonicalImageMIMEType(mimeType) != "image/jpeg"
    }

    static func preferredImageMIMEType(for item: PhotosPickerItem, data: Data) -> String {
        if let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }),
           let mime = type.preferredMIMEType {
            return canonicalImageMIMEType(mime)
        }
        return inferredMIMEType(from: data)
    }

    static func inferredMIMEType(from data: Data) -> String {
        sniffedImageMIMEType(from: data) ?? "image/jpeg"
    }

    static func sniffedImageMIMEType(from data: Data) -> String? {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        if data.starts(with: [0x49, 0x49, 0x2A, 0x00]) || data.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return "image/tiff"
        }
        if data.starts(with: [0x42, 0x4D]) { return "image/bmp" }

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

    private static func transcodeToCompatibleImagePayload(from data: Data) -> (data: Data, mimeType: String)? {
        #if os(macOS)
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let outputImage = cgImageUsesTransparency(cgImage) ? opaqueJPEGReadyImage(from: cgImage) ?? cgImage : cgImage
        let bitmap = NSBitmapImageRep(cgImage: outputImage)
        let properties: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: 0.9]
        guard let jpegData = bitmap.representation(using: .jpeg, properties: properties) else {
            return nil
        }
        return (jpegData, "image/jpeg")
        #else
        guard let image = UIImage(data: data),
              let cgImage = image.cgImage else {
            return nil
        }

        let outputImage = cgImageUsesTransparency(cgImage) ? opaqueJPEGReadyImage(from: cgImage) ?? cgImage : cgImage
        let renderedImage = UIImage(cgImage: outputImage, scale: image.scale, orientation: image.imageOrientation)
        guard let jpegData = renderedImage.jpegData(compressionQuality: 0.9) else {
            return nil
        }
        return (jpegData, "image/jpeg")
        #endif
    }

    private static func cgImageUsesTransparency(_ image: CGImage) -> Bool {
        let alphaInfo = image.alphaInfo
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            break
        default:
            return false
        }

        guard let alphaOffset = alphaComponentOffset(in: image, alphaInfo: alphaInfo) else {
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

    private static func alphaComponentOffset(in image: CGImage, alphaInfo: CGImageAlphaInfo) -> Int? {
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

    private static func opaqueJPEGReadyImage(from image: CGImage) -> CGImage? {
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
}
#endif
