//
//  MarkdownUtilities.swift
//  Voice Chat
//

@preconcurrency import Foundation
@preconcurrency import CoreText

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
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

func markdownCleanedSearchHighlightQuery(_ query: String?) -> String? {
    let cleaned = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return cleaned.isEmpty ? nil : cleaned
}

func markdownAttributedStringByApplyingSearchHighlight(
    to attributedString: NSAttributedString,
    query: String?
) -> NSAttributedString {
    guard let query = markdownCleanedSearchHighlightQuery(query) else {
        return attributedString
    }

    let mutable = NSMutableAttributedString(attributedString: attributedString)
    markdownApplySearchHighlight(to: mutable, query: query)
    return mutable
}

func markdownApplySearchHighlight(
    to mutable: NSMutableAttributedString,
    query: String
) {
    let nsString = mutable.string as NSString
    guard nsString.length > 0 else { return }

    let fullRange = NSRange(location: 0, length: nsString.length)
    let highlightColor = MarkdownPlatformColor.markdownHex(0xffd84d, alpha: 0.58)

    var searchRange = fullRange
    while searchRange.location < nsString.length {
        let foundRange = nsString.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchRange
        )
        guard foundRange.location != NSNotFound, foundRange.length > 0 else { break }

        mutable.addAttribute(.backgroundColor, value: highlightColor, range: foundRange)

        let nextLocation = foundRange.location + foundRange.length
        searchRange = NSRange(
            location: nextLocation,
            length: max(0, nsString.length - nextLocation)
        )
    }
}

private final class MarkdownAttributedTextMeasurementCache: @unchecked Sendable {
    static let shared = MarkdownAttributedTextMeasurementCache()

    private let lock = NSLock()
    private let identityCache = NSMapTable<NSAttributedString, NSMutableDictionary>(
        keyOptions: .weakMemory,
        valueOptions: .strongMemory
    )

    private init() {}

    func measure(
        _ text: NSAttributedString,
        widthKey: Int,
        namespace: Int = 0,
        compute: () -> CGSize
    ) -> CGSize {
        if !shouldCacheMeasurement(for: text) {
            return compute()
        }

        let widthNumber = NSNumber(value: widthKey * 16 + namespace)

        lock.lock()
        if let map = identityCache.object(forKey: text),
           let cachedValue = map.object(forKey: widthNumber) as? NSValue {
            let cached = sizeFromNSValue(cachedValue)
            lock.unlock()
            return cached
        }
        lock.unlock()

        let measured = compute()

        lock.lock()
        cacheIdentityMeasurement(measured, for: text, widthNumber: widthNumber)
        lock.unlock()
        return measured
    }

    private func shouldCacheMeasurement(for text: NSAttributedString) -> Bool {
        // Mutable attributed strings (including NSTextStorage) can change in place while preserving identity.
        // Caching them by object identity risks returning stale sizes during streaming updates.
        !(text is NSMutableAttributedString)
    }

    private func cacheIdentityMeasurement(_ size: CGSize, for text: NSAttributedString, widthNumber: NSNumber) {
        let map: NSMutableDictionary
        if let existing = identityCache.object(forKey: text) {
            map = existing
        } else {
            map = NSMutableDictionary()
            identityCache.setObject(map, forKey: text)
        }
        map.setObject(nsValue(from: size), forKey: widthNumber)
    }
}

private func sizeFromNSValue(_ value: NSValue) -> CGSize {
    #if os(macOS)
    return value.sizeValue
    #else
    return value.cgSizeValue
    #endif
}

private func nsValue(from size: CGSize) -> NSValue {
    #if os(macOS)
    return NSValue(size: size)
    #else
    return NSValue(cgSize: size)
    #endif
}

func measureAttributedText(_ text: NSAttributedString, width: CGFloat) -> CGSize {
    measureAttributedText(text, width: width, usingTextContainer: false)
}

func measureHostedAttributedText(_ text: NSAttributedString, width: CGFloat) -> CGSize {
    measureAttributedText(text, width: width, usingTextContainer: true)
}

func measureUnwrappedAttributedTextWidth(
    _ text: NSAttributedString,
    fallbackFont: MarkdownPlatformFont? = nil
) -> CGFloat {
    let cacheKey = unwrappedMeasurementCacheKey(fallbackFont: fallbackFont)
    return MarkdownAttributedTextMeasurementCache.shared.measure(
        text,
        widthKey: cacheKey,
        namespace: 2
    ) {
        CGSize(width: computeUnwrappedAttributedTextWidth(text, fallbackFont: fallbackFont), height: 0)
    }.width
}

private func computeUnwrappedAttributedTextWidth(
    _ text: NSAttributedString,
    fallbackFont: MarkdownPlatformFont?
) -> CGFloat {
    guard text.length > 0 else { return 0 }

    let normalized = NSMutableAttributedString(attributedString: text)
    if let fallbackFont {
        normalized.enumerateAttribute(
            .font,
            in: NSRange(location: 0, length: normalized.length),
            options: []
        ) { value, range, _ in
            if value == nil {
                normalized.addAttribute(.font, value: fallbackFont, range: range)
            }
        }
    }

    let line = CTLineCreateWithAttributedString(normalized as CFAttributedString)
    let coreTextWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    let measuredWidth = max(
        0,
        coreTextWidth,
        measureUnwrappedBoundingWidth(normalized),
        measureUnwrappedRunWidth(normalized, fallbackFont: fallbackFont),
        measurePlainUnwrappedWidth(normalized.string, fallbackFont: fallbackFont)
    )
    guard measuredWidth > 0 else { return 0 }
    return ceil(measuredWidth + lineFragmentRoundingSlack(fallbackFont: fallbackFont))
}

private func unwrappedMeasurementCacheKey(fallbackFont: MarkdownPlatformFont?) -> Int {
    guard let fallbackFont else { return 0 }
    let pointKey = Int((fallbackFont.pointSize * 16).rounded(.toNearestOrAwayFromZero))
    let nameKey = fallbackFont.fontName.unicodeScalars.reduce(0) { partial, scalar in
        (partial &* 31 &+ Int(scalar.value)) & 0x3fff
    }
    return pointKey * 16_384 + nameKey
}

private func measureUnwrappedBoundingWidth(_ text: NSAttributedString) -> CGFloat {
    let rect = text.boundingRect(
        with: CGSize(width: 10_000, height: 10_000_000),
        options: [.usesLineFragmentOrigin, .usesFontLeading, .usesDeviceMetrics],
        context: nil
    )
    return max(0, rect.width)
}

private func measureUnwrappedRunWidth(
    _ text: NSAttributedString,
    fallbackFont: MarkdownPlatformFont?
) -> CGFloat {
    var maxLineWidth: CGFloat = 0
    var currentLineWidth: CGFloat = 0
    text.enumerateAttributes(
        in: NSRange(location: 0, length: text.length),
        options: []
    ) { attributes, range, _ in
        if let attachment = attributes[.attachment] as? NSTextAttachment {
            currentLineWidth += markdownMeasuredAttachmentBounds(
                attachment,
                availableWidth: nil,
                fallbackFont: fallbackFont
            ).width
            return
        }

        let string = text.attributedSubstring(from: range).string
        let segments = string.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                maxLineWidth = max(maxLineWidth, currentLineWidth)
                currentLineWidth = 0
            }
            guard !segment.isEmpty else { continue }
            var runAttributes = attributes
            if runAttributes[.font] == nil, let fallbackFont {
                runAttributes[.font] = fallbackFont
            }
            currentLineWidth += (String(segment) as NSString).size(withAttributes: runAttributes).width
        }
    }
    return max(maxLineWidth, currentLineWidth)
}

private func markdownMeasuredAttachmentBounds(
    _ attachment: NSTextAttachment,
    availableWidth: CGFloat?,
    fallbackFont: MarkdownPlatformFont?
) -> CGRect {
    if let mathAttachment = attachment as? MarkdownMathAttachment {
        let targetWidth: CGFloat
        if let availableWidth, availableWidth.isFinite, availableWidth > 1 {
            targetWidth = availableWidth
        } else if mathAttachment.maxWidth > 1 {
            targetWidth = mathAttachment.maxWidth
        } else {
            targetWidth = 10_000
        }
        return mathAttachment.layoutBounds(availableWidth: targetWidth)
    }

    let bounds = attachment.bounds
    if bounds.width > 0 || bounds.height > 0 {
        return bounds
    }

    if let image = attachment.image {
        return CGRect(origin: .zero, size: image.size)
    }

    if let fallbackFont {
        return CGRect(x: 0, y: 0, width: 0, height: markdownFallbackLineHeight(for: fallbackFont))
    }

    return .zero
}

private func markdownFallbackLineHeight(for font: MarkdownPlatformFont) -> CGFloat {
    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    return font.lineHeight
    #elseif os(macOS)
    return NSLayoutManager().defaultLineHeight(for: font)
    #endif
}

private func measurePlainUnwrappedWidth(
    _ string: String,
    fallbackFont: MarkdownPlatformFont?
) -> CGFloat {
    guard let fallbackFont else { return 0 }
    var maxLineWidth: CGFloat = 0
    for line in string.split(separator: "\n", omittingEmptySubsequences: false) {
        let width = (String(line) as NSString).size(withAttributes: [.font: fallbackFont]).width
        maxLineWidth = max(maxLineWidth, width)
    }
    return maxLineWidth
}

private func lineFragmentRoundingSlack(fallbackFont: MarkdownPlatformFont?) -> CGFloat {
    guard let fallbackFont else { return 1 }
    return max(2, ceil(fallbackFont.pointSize * 0.6))
}

func markdownMeasuredTableContentWidths(
    rows: [MarkdownTableRow],
    columnCount: Int,
    availableWidth: CGFloat,
    paddingX: CGFloat,
    columnGap: CGFloat,
    baseFont: MarkdownPlatformFont,
    emptyCell: NSAttributedString,
    measure: (NSAttributedString, CGFloat) -> CGSize
) -> [CGFloat] {
    guard columnCount > 0 else { return [] }

    let maxTextWidth = markdownTableMaximumTextWidth(
        availableWidth: availableWidth,
        columnCount: columnCount,
        baseFont: baseFont
    )
    var desiredWidths = Array(repeating: CGFloat(0), count: columnCount)
    for row in rows {
        for column in 0..<columnCount {
            let cell = column < row.cells.count ? row.cells[column] : emptyCell
            let measured = measure(cell, .greatestFiniteMagnitude)
            desiredWidths[column] = max(desiredWidths[column], min(measured.width, maxTextWidth))
        }
    }

    return markdownFittedTableContentWidths(
        desiredWidths,
        availableWidth: availableWidth,
        paddingX: paddingX,
        columnGap: columnGap,
        baseFont: baseFont
    )
}

func markdownFittedTableContentWidths(
    _ desiredWidths: [CGFloat],
    availableWidth: CGFloat,
    paddingX: CGFloat,
    columnGap: CGFloat,
    baseFont: MarkdownPlatformFont
) -> [CGFloat] {
    let columnCount = desiredWidths.count
    guard columnCount > 0 else { return [] }

    let normalizedDesired = desiredWidths.map { max(0, ceil($0)) }
    let fixedWidth = paddingX * 2 * CGFloat(columnCount) + columnGap * CGFloat(max(0, columnCount - 1))
    let availableTextWidth = max(0, availableWidth - fixedWidth)
    guard availableTextWidth > 0 else {
        return normalizedDesired
    }

    let currentTotal = normalizedDesired.reduce(0, +)
    guard currentTotal > availableTextWidth + 0.5 else {
        return normalizedDesired
    }

    let minTextWidth = markdownTableMinimumTextWidth(
        availableTextWidth: availableTextWidth,
        columnCount: columnCount,
        baseFont: baseFont
    )
    let minimumWidths = normalizedDesired.map { min($0, minTextWidth) }
    let minimumTotal = minimumWidths.reduce(0, +)
    guard currentTotal > minimumTotal + 0.5 else {
        return normalizedDesired
    }

    let shrinkableTotal = zip(normalizedDesired, minimumWidths).reduce(CGFloat(0)) { partial, pair in
        partial + max(0, pair.0 - pair.1)
    }
    guard shrinkableTotal > 0.5 else {
        return normalizedDesired
    }

    let neededShrink = min(currentTotal - availableTextWidth, currentTotal - minimumTotal)
    return zip(normalizedDesired, minimumWidths).map { width, minimum in
        let shrinkable = max(0, width - minimum)
        let shrink = neededShrink * (shrinkable / shrinkableTotal)
        return ceil(max(minimum, width - shrink))
    }
}

func markdownTableMaximumTextWidth(
    availableWidth: CGFloat,
    columnCount: Int,
    baseFont: MarkdownPlatformFont
) -> CGFloat {
    guard columnCount > 0 else { return 0 }
    let readableCap = baseFont.pointSize * (columnCount <= 2 ? 20 : 16)
    let ratio: CGFloat
    switch columnCount {
    case 1:
        ratio = 1
    case 2:
        ratio = 0.62
    case 3:
        ratio = 0.48
    default:
        ratio = 0.38
    }
    let viewportCap = max(72, availableWidth * ratio)
    return max(72, min(360, max(viewportCap, readableCap)))
}

func markdownStreamingTableColumnWidthGrowthStep(baseFont: MarkdownPlatformFont) -> CGFloat {
    max(24, ceil(baseFont.pointSize * 1.5))
}

private func markdownTableMinimumTextWidth(
    availableTextWidth: CGFloat,
    columnCount: Int,
    baseFont: MarkdownPlatformFont
) -> CGFloat {
    guard columnCount > 0 else { return 0 }
    let balancedWidth = availableTextWidth / CGFloat(columnCount)
    let readableFloor = baseFont.pointSize * (columnCount <= 2 ? 7 : 5)
    return max(48, min(120, max(balancedWidth, readableFloor)))
}

private func measureAttributedText(
    _ text: NSAttributedString,
    width: CGFloat,
    usingTextContainer: Bool
) -> CGSize {
    let targetWidth: CGFloat
    if width.isFinite {
        targetWidth = min(max(1, width), 10_000)
    } else {
        targetWidth = 10_000
    }
    let widthKey = Int((targetWidth * 2).rounded(.toNearestOrAwayFromZero))
    return MarkdownAttributedTextMeasurementCache.shared.measure(
        text,
        widthKey: widthKey,
        namespace: usingTextContainer ? 1 : 0
    ) {
        if usingTextContainer || attributedStringContainsAttachment(text) {
            return measureAttributedTextUsingTextContainer(text, width: targetWidth)
        } else {
            let constraint = CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
            let rect = text.boundingRect(
                with: constraint,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            return CGSize(width: ceil(rect.width), height: ceil(rect.height))
        }
    }
}

private func attributedStringContainsAttachment(_ text: NSAttributedString) -> Bool {
    guard text.length > 0 else { return false }
    var foundAttachment = false
    text.enumerateAttribute(
        .attachment,
        in: NSRange(location: 0, length: text.length),
        options: []
    ) { value, _, stop in
        if value is NSTextAttachment {
            foundAttachment = true
            stop.pointee = true
        }
    }
    return foundAttachment
}

private func measureAttributedTextUsingTextContainer(
    _ text: NSAttributedString,
    width: CGFloat
) -> CGSize {
    let textStorage = NSTextStorage(attributedString: text)
    prepareDynamicMarkdownTextAttachments(in: textStorage, width: width)
    let layoutManager = NSLayoutManager()
    layoutManager.allowsNonContiguousLayout = false
    layoutManager.usesFontLeading = true

    let textContainer = NSTextContainer(size: CGSize(width: width, height: 10_000_000))
    textContainer.lineFragmentPadding = 0
    textContainer.maximumNumberOfLines = 0
    textContainer.lineBreakMode = .byWordWrapping

    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)

    _ = layoutManager.glyphRange(for: textContainer)
    layoutManager.ensureLayout(for: textContainer)
    let usedRect = measuredTextContainerBounds(layoutManager: layoutManager, textContainer: textContainer)
    return integralTextMeasurementSize(for: usedRect)
}

func prepareDynamicMarkdownTextAttachments(in textStorage: NSTextStorage, width: CGFloat) {
    guard textStorage.length > 0 else { return }
    let targetWidth = width.isFinite ? max(1, width) : 10_000
    textStorage.enumerateAttribute(
        .attachment,
        in: NSRange(location: 0, length: textStorage.length),
        options: []
    ) { value, _, _ in
        guard let attachment = value as? NSTextAttachment else { return }
        let bounds = markdownMeasuredAttachmentBounds(
            attachment,
            availableWidth: targetWidth,
            fallbackFont: nil
        )
        guard bounds.width > 0 || bounds.height > 0 else { return }
        attachment.bounds = bounds
    }
}

private func measuredTextContainerBounds(
    layoutManager: NSLayoutManager,
    textContainer: NSTextContainer
) -> CGRect {
    markdownMeasuredTextContainerBounds(layoutManager: layoutManager, textContainer: textContainer)
}

func markdownMeasuredTextContainerBounds(
    layoutManager: NSLayoutManager,
    textContainer: NSTextContainer
) -> CGRect {
    var usedRect = layoutManager.usedRect(for: textContainer)
    let glyphRange = layoutManager.glyphRange(for: textContainer)
    if glyphRange.length > 0 {
        usedRect = usedRect.union(layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer))
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineFragmentRect, _, _, _, _ in
            usedRect = usedRect.union(lineFragmentRect)
        }
        if let attachmentRect = markdownTextAttachmentDisplayBounds(
            layoutManager: layoutManager,
            textContainer: textContainer,
            glyphRange: glyphRange
        ) {
            usedRect = usedRect.union(attachmentRect)
        }
    }
    if layoutManager.extraLineFragmentTextContainer != nil {
        usedRect = usedRect.union(layoutManager.extraLineFragmentRect)
    }
    return usedRect
}

private func markdownTextAttachmentDisplayBounds(
    layoutManager: NSLayoutManager,
    textContainer: NSTextContainer,
    glyphRange: NSRange
) -> CGRect? {
    guard let textStorage = layoutManager.textStorage, textStorage.length > 0 else {
        return nil
    }

    var result: CGRect?
    textStorage.enumerateAttribute(
        .attachment,
        in: NSRange(location: 0, length: textStorage.length),
        options: []
    ) { value, characterRange, _ in
        guard let attachment = value as? NSTextAttachment else { return }
        let attachmentGlyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        let visibleGlyphRange = NSIntersectionRange(attachmentGlyphRange, glyphRange)
        guard visibleGlyphRange.length > 0 else { return }

        let glyphIndex = visibleGlyphRange.location
        guard glyphIndex >= 0, glyphIndex < layoutManager.numberOfGlyphs else { return }

        let lineFragmentRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil
        )
        let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
        let attachmentBounds = markdownMeasuredAttachmentBounds(
            attachment,
            availableWidth: textContainer.size.width,
            fallbackFont: nil
        )
        guard attachmentBounds.width > 0 || attachmentBounds.height > 0 else { return }

        let displayRect = CGRect(
            x: lineFragmentRect.minX + glyphLocation.x + attachmentBounds.minX,
            y: lineFragmentRect.minY + glyphLocation.y + attachmentBounds.minY,
            width: attachmentBounds.width,
            height: attachmentBounds.height
        )
        result = result.map { $0.union(displayRect) } ?? displayRect
    }
    return result
}

private func integralTextMeasurementSize(for rect: CGRect) -> CGSize {
    guard !rect.isNull, !rect.isInfinite else {
        return .zero
    }
    let minX = min(0, floor(rect.minX))
    let minY = min(0, floor(rect.minY))
    let maxX = max(0, ceil(rect.maxX))
    let maxY = max(0, ceil(rect.maxY))
    return CGSize(
        width: max(0, maxX - minX),
        height: max(0, maxY - minY)
    )
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
    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    return fontByAddingTraits(font, traits: .traitBold)
    #elseif os(macOS)
    return fontByAddingTraits(font, traits: .bold)
    #endif
}

func italicFont(from font: MarkdownPlatformFont) -> MarkdownPlatformFont {
    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    return fontByAddingTraits(font, traits: .traitItalic)
    #elseif os(macOS)
    return fontByAddingTraits(font, traits: .italic)
    #endif
}

func fontByAddingTraits(
    _ font: MarkdownPlatformFont,
    traits: MarkdownFontTraits
) -> MarkdownPlatformFont {
    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    let combinedTraits = font.fontDescriptor.symbolicTraits.union(traits)
    guard let descriptor = font.fontDescriptor.withSymbolicTraits(combinedTraits) else { return font }
    return MarkdownPlatformFont(descriptor: descriptor, size: font.pointSize)
    #elseif os(macOS)
    let combinedTraits = font.fontDescriptor.symbolicTraits.union(traits)
    let descriptor = font.fontDescriptor.withSymbolicTraits(combinedTraits)
    return MarkdownPlatformFont(descriptor: descriptor, size: font.pointSize) ?? font
    #endif
}
