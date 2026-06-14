//
//  ChatImageAttachmentStrip.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import ImageIO
import SwiftUI

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ChatImageAttachmentStrip: View {
    let attachments: [ChatImageAttachment]
    let removable: Bool
    let maxItemSize: CGFloat
    let onPreview: (ChatImageAttachment) -> Void
    let onRemove: ((ChatImageAttachment) -> Void)?
    let horizontalAlignment: HorizontalAlignment

    init(
        attachments: [ChatImageAttachment],
        removable: Bool,
        maxItemSize: CGFloat,
        onPreview: @escaping (ChatImageAttachment) -> Void,
        onRemove: ((ChatImageAttachment) -> Void)?,
        horizontalAlignment: HorizontalAlignment = .leading
    ) {
        self.attachments = attachments
        self.removable = removable
        self.maxItemSize = maxItemSize
        self.onPreview = onPreview
        self.onRemove = onRemove
        self.horizontalAlignment = horizontalAlignment
    }

    private var stripAlignment: Alignment {
        horizontalAlignment == .trailing ? .trailing : .leading
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        ChatImageAttachmentItem(
                            attachment: attachment,
                            removable: removable,
                            maxItemSize: maxItemSize,
                            onPreview: onPreview,
                            onRemove: onRemove
                        )
                    }
                }
                .frame(minWidth: proxy.size.width, alignment: stripAlignment)
                .padding(.vertical, 2)
            }
        }
        .frame(height: maxItemSize + 4)
    }
}

private struct ChatImageAttachmentItem: View {
    let attachment: ChatImageAttachment
    let removable: Bool
    let maxItemSize: CGFloat
    let onPreview: (ChatImageAttachment) -> Void
    let onRemove: ((ChatImageAttachment) -> Void)?

    private var removeTapSize: CGFloat {
        #if os(iOS) || os(tvOS)
        return 32
        #else
        return 28
        #endif
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                onPreview(attachment)
            } label: {
                Group {
                    if let image = chatSwiftUIImage(for: attachment, maxItemSize: maxItemSize) {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.secondary.opacity(0.15))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            )
                    }
                }
                .frame(width: maxItemSize, height: maxItemSize)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)

            if removable, let onRemove {
                Button {
                    onRemove(attachment)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.65))
                        .frame(width: removeTapSize, height: removeTapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove image"))
            }
        }
    }
}

private final class ChatImageThumbnailCache: @unchecked Sendable {
    static let shared = ChatImageThumbnailCache()

    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    private let cache = NSCache<NSString, UIImage>()
    #elseif os(macOS)
    private let cache = NSCache<NSString, NSImage>()
    #endif

    private init() {
        cache.countLimit = 256
    }

    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    func image(for attachment: ChatImageAttachment, maxPixelSize: Int) -> UIImage? {
        let key = cacheKey(for: attachment, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let decoded = decodeThumbnail(from: attachment.data, maxPixelSize: maxPixelSize) else {
            return nil
        }
        cache.setObject(decoded, forKey: key)
        return decoded
    }
    #elseif os(macOS)
    func image(for attachment: ChatImageAttachment, maxPixelSize: Int) -> NSImage? {
        let key = cacheKey(for: attachment, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let decoded = decodeThumbnail(from: attachment.data, maxPixelSize: maxPixelSize) else {
            return nil
        }
        cache.setObject(decoded, forKey: key)
        return decoded
    }
    #endif

    private func cacheKey(for attachment: ChatImageAttachment, maxPixelSize: Int) -> NSString {
        "\(attachment.id.uuidString)-\(max(1, maxPixelSize))" as NSString
    }
}

@MainActor
private func chatSwiftUIImage(for attachment: ChatImageAttachment, maxItemSize: CGFloat) -> Image? {
    let maxPixelSize = max(1, Int((maxItemSize * chatThumbnailDisplayScale()).rounded(.up)))
#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    guard let image = ChatImageThumbnailCache.shared.image(for: attachment, maxPixelSize: maxPixelSize) else { return nil }
    return Image(uiImage: image)
#elseif os(macOS)
    guard let image = ChatImageThumbnailCache.shared.image(for: attachment, maxPixelSize: maxPixelSize) else { return nil }
    return Image(nsImage: image)
#else
    return nil
#endif
}

@MainActor
private func chatThumbnailDisplayScale() -> CGFloat {
#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    #if os(visionOS)
    return 2
    #else
    return UIScreen.main.scale
    #endif
#elseif os(macOS)
    return NSScreen.main?.backingScaleFactor ?? 2
#else
    return 1
#endif
}

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
private func decodeThumbnail(from data: Data, maxPixelSize: Int) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
        return UIImage(data: data)
    }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCache: false,
        kCGImageSourceShouldCacheImmediately: false,
        kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return UIImage(data: data)
    }
    return UIImage(cgImage: cgImage)
}
#elseif os(macOS)
private func decodeThumbnail(from data: Data, maxPixelSize: Int) -> NSImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
        return NSImage(data: data)
    }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCache: false,
        kCGImageSourceShouldCacheImmediately: false,
        kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return NSImage(data: data)
    }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}
#endif
