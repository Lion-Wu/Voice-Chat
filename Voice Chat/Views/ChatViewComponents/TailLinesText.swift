//
//  TailLinesText.swift
//  Voice Chat
//

import SwiftUI
import CoreText

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
// Ensure the typealias remains accessible across the target.
typealias PlatformNativeFont = UIFont
#elseif os(macOS)
import AppKit
// Mirror the iOS typealias so computed properties compile.
typealias PlatformNativeFont = NSFont
#endif

struct PlatformFontSpec: Equatable {
    let size: CGFloat
    let isMonospaced: Bool

    var native: PlatformNativeFont {
        #if os(iOS) || os(tvOS) || os(watchOS)
        return isMonospaced ? .monospacedSystemFont(ofSize: size, weight: .regular)
                            : .systemFont(ofSize: size)
        #else
        return isMonospaced ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                            : NSFont.systemFont(ofSize: size)
        #endif
    }

    var lineHeight: CGFloat {
        #if os(iOS) || os(tvOS) || os(watchOS)
        native.lineHeight
        #else
        (native.ascender - native.descender) + native.leading
        #endif
    }

    var ctFont: CTFont { CTFontCreateWithName(native.fontName as CFString, size, nil) }
}

struct TailLinesText: View {
    let text: String
    let lines: Int
    let font: PlatformFontSpec
    private var fixedHeight: CGFloat { font.lineHeight * CGFloat(max(1, lines)) }

    @State private var displayTail: String = ""
    @State private var lastComputedForTextCount: Int = -1
    @State private var lastWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = max(1, floor(geo.size.width))

            ZStack(alignment: .bottomLeading) {
                Text(displayTail)
                    .font(.system(size: font.size, design: font.isMonospaced ? .monospaced : .default))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(nil, value: displayTail)
            }
            .frame(width: w, height: fixedHeight, alignment: .bottomLeading)
            .onAppear { recomputeIfNeeded(width: w) }
            .onChange(of: text) { _, _ in recomputeIfNeeded(width: w) }
            .onChange(of: geo.size) { _, _ in recomputeIfNeeded(width: w) }
        }
        .frame(height: fixedHeight, alignment: .bottom)
        .accessibilityLabel(Text(L10n.Accessibility.thinkingPreview))
    }

    private func recomputeIfNeeded(width: CGFloat) {
        let tcount = text.utf16.count
        let needs = (tcount != lastComputedForTextCount) || abs(width - lastWidth) > 0.5
        guard needs, width > 1 else { return }

        displayTail = computeTailVisualLines(text: text, width: width, lines: lines, font: font)
        lastComputedForTextCount = tcount
        lastWidth = width
    }
}

func computeTailVisualLines(text: String, width: CGFloat, lines: Int, font: PlatformFontSpec) -> String {
    guard !text.isEmpty, width > 1, lines > 0 else { return "" }

    let ns = text as NSString
    let total = ns.length
    var windowLen = min(2048, total)
    let maxLen = min(32768, total)

    var lastResult: String = ""
    while true {
        let start = max(0, total - windowLen)
        let range = NSRange(location: start, length: total - start)
        let chunk = ns.substring(with: range) as NSString

        let attrs: [CFString: Any] = [kCTFontAttributeName: font.ctFont]
        let attrStr = CFAttributedStringCreate(nil, chunk as CFString, attrs as CFDictionary)!
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)

        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: width, height: 10_000))
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let linesCF = CTFrameGetLines(frame)
        let count = CFArrayGetCount(linesCF)

        if count == 0 { return "" }

        let take = min(lines, count)
        var firstLoc = Int.max
        var lastMax = 0
        for i in (count - take)..<count {
            let unmanaged = CFArrayGetValueAtIndex(linesCF, i)
            let line = unsafeBitCast(unmanaged, to: CTLine.self)
            let r = CTLineGetStringRange(line)
            let loc = r.location
            let len = r.length
            firstLoc = min(firstLoc, loc)
            lastMax = max(lastMax, loc + len)
        }
        let tailRange = NSRange(location: firstLoc == Int.max ? 0 : firstLoc,
                                length: max(0, lastMax - (firstLoc == Int.max ? 0 : firstLoc)))
        let tail = chunk.substring(with: NSIntersectionRange(tailRange, NSRange(location: 0, length: chunk.length)))

        lastResult = tail

        if count >= lines || windowLen >= maxLen || windowLen >= total {
            break
        }

        windowLen = min(maxLen, min(total, windowLen * 2))
    }

    return lastResult
}
