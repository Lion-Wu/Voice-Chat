//
//  MarkdownUtilities.swift
//  Voice Chat
//

@preconcurrency import Foundation

#if os(iOS) || os(tvOS) || os(watchOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

func attachmentAvailableWidth(maxWidth: CGFloat, lineFragWidth: CGFloat) -> CGFloat {
    if maxWidth > 1, lineFragWidth > 1 {
        return min(maxWidth, lineFragWidth)
    }
    if maxWidth > 1 { return maxWidth }
    if lineFragWidth > 1 { return lineFragWidth }
    return 320
}

func extractPlainText(from attributed: NSAttributedString) -> String {
    var output = ""
    let range = NSRange(location: 0, length: attributed.length)
    attributed.enumerateAttributes(in: range, options: []) { attrs, subRange, _ in
        if let attachment = attrs[.attachment] as? MarkdownAttachment {
            output += attachment.plainText
        } else {
            output += attributed.attributedSubstring(from: subRange).string
        }
    }
    return output
}

func measureAttributedText(_ text: NSAttributedString, width: CGFloat) -> CGSize {
    let targetWidth: CGFloat
    if width.isFinite {
        targetWidth = min(max(1, width), 10_000)
    } else {
        targetWidth = 10_000
    }
    let textStorage = NSTextStorage(attributedString: text)
    let textContainer = NSTextContainer(size: CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
    textContainer.lineFragmentPadding = 0
    let layoutManager = NSLayoutManager()
    layoutManager.usesFontLeading = true
    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)
    layoutManager.ensureLayout(for: textContainer)
    let rect = layoutManager.usedRect(for: textContainer)
    return CGSize(width: ceil(rect.width), height: ceil(rect.height))
}

func currentLanguageCode() -> String {
    if #available(macOS 13, iOS 16, tvOS 16, watchOS 9, *) {
        return Locale.current.language.languageCode?.identifier ?? ""
    }
    return Locale.current.identifier.split(separator: "_").first.map(String.init) ?? ""
}

@MainActor
final class MarkdownImageLoader {
    static let shared = MarkdownImageLoader()
    private let cache = NSCache<NSURL, MarkdownPlatformImage>()
    private var inFlight: [NSURL: [(MarkdownPlatformImage?) -> Void]] = [:]

    private struct SendableImage: @unchecked Sendable {
        let image: MarkdownPlatformImage?
    }

    private init() {
        cache.countLimit = 128
    }

    func loadImage(source: String, completion: @escaping (MarkdownPlatformImage?) -> Void) {
        guard let url = resolveURL(from: source) else {
            completion(nil)
            return
        }

        if let cached = cache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }

        if inFlight[url as NSURL] != nil {
            inFlight[url as NSURL]?.append(completion)
            return
        }
        inFlight[url as NSURL] = [completion]

        Task.detached(priority: .utility) {
            let data: Data?
            if url.isFileURL {
                data = try? Data(contentsOf: url)
            } else {
                let policy = NetworkRetryPolicy(
                    maxAttempts: 3,
                    baseDelay: 0.3,
                    maxDelay: 2.0,
                    backoffFactor: 1.6,
                    jitterRatio: 0.2
                )
                do {
                    let (fetched, _) = try await NetworkRetry.run(policy: policy) {
                        let request = URLRequest(url: url, timeoutInterval: 20)
                        let (data, resp) = try await URLSession.shared.data(for: request)
                        if let http = resp as? HTTPURLResponse,
                           !(200...299).contains(http.statusCode) {
                            throw HTTPStatusError(statusCode: http.statusCode, bodyPreview: nil)
                        }
                        return (data, resp)
                    }
                    data = fetched
                } catch {
                    data = nil
                }
            }

            var image: MarkdownPlatformImage?
            if let data, let decoded = MarkdownPlatformImage(data: data) {
                image = decoded
            }
            let sendableImage = SendableImage(image: image)

            await MainActor.run {
                let loader = MarkdownImageLoader.shared
                if let decoded = sendableImage.image {
                    loader.cache.setObject(decoded, forKey: url as NSURL)
                }
                let completions = loader.inFlight.removeValue(forKey: url as NSURL) ?? []
                completions.forEach { $0(sendableImage.image) }
            }
        }
    }

    private func resolveURL(from source: String) -> URL? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        let expandedPath = (trimmed as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expandedPath) {
            return URL(fileURLWithPath: expandedPath)
        }

        if let bundleURL = Bundle.main.url(forResource: trimmed, withExtension: nil) {
            return bundleURL
        }

        return URL(string: trimmed)
    }
}

final class MarkdownRenderCache: @unchecked Sendable {
    static let shared = MarkdownRenderCache()
    private let cache = NSCache<NSString, NSAttributedString>()

    private init() {
        cache.countLimit = 120
    }

    func attributedString(for markdown: String, styleKey: String) -> NSAttributedString? {
        cache.object(forKey: cacheKey(markdown: markdown, styleKey: styleKey))
    }

    func store(_ attributedString: NSAttributedString, markdown: String, styleKey: String) {
        cache.setObject(attributedString, forKey: cacheKey(markdown: markdown, styleKey: styleKey))
    }

    private func cacheKey(markdown: String, styleKey: String) -> NSString {
        "\(styleKey):\(markdown)" as NSString
    }
}

func boldFont(from font: MarkdownPlatformFont) -> MarkdownPlatformFont {
    #if os(iOS) || os(tvOS) || os(watchOS)
    return fontByAddingTraits(font, traits: .traitBold)
    #elseif os(macOS)
    return fontByAddingTraits(font, traits: .bold)
    #endif
}

func italicFont(from font: MarkdownPlatformFont) -> MarkdownPlatformFont {
    #if os(iOS) || os(tvOS) || os(watchOS)
    return fontByAddingTraits(font, traits: .traitItalic)
    #elseif os(macOS)
    return fontByAddingTraits(font, traits: .italic)
    #endif
}

func fontByAddingTraits(
    _ font: MarkdownPlatformFont,
    traits: MarkdownFontTraits
) -> MarkdownPlatformFont {
    #if os(iOS) || os(tvOS) || os(watchOS)
    let combinedTraits = font.fontDescriptor.symbolicTraits.union(traits)
    guard let descriptor = font.fontDescriptor.withSymbolicTraits(combinedTraits) else { return font }
    return MarkdownPlatformFont(descriptor: descriptor, size: font.pointSize)
    #elseif os(macOS)
    let combinedTraits = font.fontDescriptor.symbolicTraits.union(traits)
    let descriptor = font.fontDescriptor.withSymbolicTraits(combinedTraits)
    return MarkdownPlatformFont(descriptor: descriptor, size: font.pointSize) ?? font
    #endif
}
