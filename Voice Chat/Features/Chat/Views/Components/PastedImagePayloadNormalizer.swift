//
//  PastedImagePayloadNormalizer.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import CoreGraphics
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum PastedImagePayloadNormalizer {
    private static let pasteCompatiblePassthroughMIMETypes: Set<String> = [
        "image/jpeg"
    ]

    static func normalize(data: Data, mimeTypeHint: String?) -> (data: Data, mimeType: String?) {
        let resolvedMIMEType = canonicalMIMEType(mimeTypeHint) ?? inferredMIMEType(from: data)
        if pasteCompatiblePassthroughMIMETypes.contains(resolvedMIMEType) {
            return (data, resolvedMIMEType)
        }

        guard let transcoded = transcodedPayload(from: data) else {
            return (data, resolvedMIMEType)
        }

        return transcoded
    }

    static func sniffedMIMEType(from data: Data) -> String? {
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

    private static func canonicalMIMEType(_ mimeType: String?) -> String? {
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

    private static func inferredMIMEType(from data: Data) -> String {
        sniffedMIMEType(from: data) ?? "image/png"
    }

    #if os(macOS)
    private static func transcodedPayload(from data: Data) -> (data: Data, mimeType: String?)? {
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let outputImage = cgImageUsesTransparency(cgImage) ? opaqueJPEGReadyImage(from: cgImage) ?? cgImage : cgImage
        let bitmap = NSBitmapImageRep(cgImage: outputImage)

        let jpegProperties: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: 0.9]
        guard let jpegData = bitmap.representation(using: .jpeg, properties: jpegProperties) else {
            return nil
        }
        return (jpegData, "image/jpeg")
    }
    #else
    private static func transcodedPayload(from data: Data) -> (data: Data, mimeType: String?)? {
        guard let image = UIImage(data: data),
              let cgImage = image.cgImage else {
            return nil
        }

        let outputImage = cgImageUsesTransparency(cgImage) ? opaqueJPEGReadyImage(from: cgImage) ?? cgImage : cgImage
        let renderedImage = UIImage(cgImage: outputImage)

        guard let jpegData = renderedImage.jpegData(compressionQuality: 0.9) else {
            return nil
        }
        return (jpegData, "image/jpeg")
    }
    #endif

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
