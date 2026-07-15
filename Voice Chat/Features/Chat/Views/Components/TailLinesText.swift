//
//  TailLinesText.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI
import CoreText

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import UIKit
// Keep the typealias internal to avoid access-level mismatches with helpers below.
typealias PlatformNativeFont = UIFont
#elseif os(macOS)
import AppKit
// Match the access level used on other platforms.
typealias PlatformNativeFont = NSFont
#endif

struct PlatformFontSpec: Equatable {
    let size: CGFloat
    let isMonospaced: Bool

    var native: PlatformNativeFont {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        return isMonospaced ? .monospacedSystemFont(ofSize: size, weight: .regular)
                            : .systemFont(ofSize: size)
        #else
        return isMonospaced ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                            : NSFont.systemFont(ofSize: size)
        #endif
    }

    var lineHeight: CGFloat {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
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
        .accessibilityLabel("Reasoning preview")
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

struct TailVisualTextWindow: Equatable {
    let text: String
    let sourceStartOffset: Int

    static let empty = TailVisualTextWindow(text: "", sourceStartOffset: 0)

    var sourceEndOffset: Int {
        sourceStartOffset + text.count
    }

    func rebasedPlacements(
        _ placements: [ChatToolActivityPlacement]
    ) -> [ChatToolActivityPlacement] {
        placements.compactMap { placement in
            guard placement.offset >= sourceStartOffset,
                  placement.offset <= sourceEndOffset else {
                return nil
            }
            return ChatToolActivityPlacement(
                activity: placement.activity,
                scope: placement.scope,
                offset: placement.offset - sourceStartOffset,
                assistantSegmentAnchor: placement.assistantSegmentAnchor
            )
        }
    }
}

func computeTailVisualLines(text: String, width: CGFloat, lines: Int, font: PlatformFontSpec) -> String {
    computeTailVisualTextWindow(text: text, width: width, lines: lines, font: font).text
}

func computeTailVisualTextWindow(
    text: String,
    width: CGFloat,
    lines: Int,
    font: PlatformFontSpec
) -> TailVisualTextWindow {
    guard !text.isEmpty, width > 1, lines > 0 else { return .empty }

    let ns = text as NSString
    let total = ns.length
    var windowLen = min(2048, total)
    let maxLen = min(32768, total)

    var lastResult = TailVisualTextWindow.empty
    while true {
        let rawStart = max(0, total - windowLen)
        let start = rawStart > 0
            ? ns.rangeOfComposedCharacterSequence(at: rawStart).location
            : 0
        let range = NSRange(location: start, length: total - start)
        let chunk = ns.substring(with: range) as NSString

        // CoreText omits the empty visual line after a terminal line break unless
        // another character follows it. Measure with a zero-width sentinel so the
        // returned tail never contains `lines` text rows plus an extra blank row.
        let measuredChunk = NSMutableString(string: chunk)
        measuredChunk.append("\u{2060}")
        let attrs: [CFString: Any] = [kCTFontAttributeName: font.ctFont]
        guard let attrStr = CFAttributedStringCreate(nil, measuredChunk as CFString, attrs as CFDictionary) else {
            return lastResult
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)

        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: width, height: 10_000))
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let linesCF = CTFrameGetLines(frame)
        let count = CFArrayGetCount(linesCF)

        if count == 0 { return .empty }

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
        let first = firstLoc == Int.max ? 0 : firstLoc
        let tailRange = NSIntersectionRange(
            NSRange(location: first, length: max(0, lastMax - first)),
            NSRange(location: 0, length: chunk.length)
        )
        let safeTailRange = chunk.rangeOfComposedCharacterSequences(for: tailRange)
        let absoluteRange = NSRange(
            location: start + safeTailRange.location,
            length: safeTailRange.length
        )
        guard let stringRange = Range(absoluteRange, in: text) else {
            return lastResult
        }
        lastResult = TailVisualTextWindow(
            text: String(text[stringRange]),
            sourceStartOffset: text.distance(from: text.startIndex, to: stringRange.lowerBound)
        )

        if count >= lines || windowLen >= maxLen || windowLen >= total {
            break
        }

        windowLen = min(maxLen, min(total, windowLen * 2))
    }

    return lastResult
}

#Preview {
    TailLinesText(
        text: """
        This is a long reasoning section that may contain multiple lines.
        The preview should show only the tail lines so the UI can display a compact snippet.
        Line 3
        Line 4
        Line 5
        Line 6
        """,
        lines: 4,
        font: PlatformFontSpec(size: 14, isMonospaced: true)
    )
    .padding()
    .background(AppBackgroundView())
}
