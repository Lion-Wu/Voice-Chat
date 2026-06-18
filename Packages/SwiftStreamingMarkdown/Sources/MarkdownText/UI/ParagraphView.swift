//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if !os(macOS)
struct ParagraphView: UIViewRepresentable {
  @Environment(\.openURL) var openURL
  @Environment(\.markdownConfig) var config: MarkdownRenderConfig
  @Environment(\.markdownController) var markdownController: MarkdownController?

  var contents: NSMutableAttributedString
  var lineSpacing: CGFloat?

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> ParagraphUIView {
    let openUrlFunction = openURL.callAsFunction(_:)
    let view = ParagraphUIViewCache.shared.createOrReuseParagraphUIView(contents: contents, lineSpacing: lineSpacing)
    view.onUrlTap = openUrlFunction
    view.setParagraphContents(contents, lineSpacing: lineSpacing, animatedByWord: false)
    view.setTextContextMenu(config.textContextMenu)
    view.setMarkdownController(markdownController)

    if config.shouldAnimateText {
      view.alpha = 0
      UIView.animate(withDuration: ParagraphUIView.animationDuration) {
        view.alpha = 1
      }
    }

    return view
  }

  func updateUIView(_ view: ParagraphUIView, context: Context) {
    if view.paragraphContents != contents || view.lineSpacing != lineSpacing {
      let shouldAnimate = view.window != nil && config.shouldAnimateText // only animate when visible
      view.setParagraphContents(contents, lineSpacing: lineSpacing, animatedByWord: shouldAnimate)
    }
    view.setTextContextMenu(config.textContextMenu)
    view.setMarkdownController(markdownController)
  }

  // If we don't implement this function, the snapshot tests will fail with incorrect sizing.
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: ParagraphUIView, context: Context) -> CGSize? {
    guard let width = proposal.width, width > 0, width.isFinite else {
      return nil
    }

    // Check if content or lineSpacing changed - if so, clear the cache
    if contents != context.coordinator.lastContents || lineSpacing != context.coordinator.lastLineSpacing {
      context.coordinator.sizeCache.removeAll()
      context.coordinator.lastContents = contents
      context.coordinator.lastLineSpacing = lineSpacing
    }

    // Round width to avoid cache misses from floating point precision issues
    let cacheKey = (width * 10).rounded() / 10 // Round to 1 decimal place

    // Check if we have a cached size for this width
    if let cachedSize = context.coordinator.sizeCache[cacheKey] {
      return cachedSize
    }

    // Calculate new size
    let targetSize = CGSize(width: width, height: .greatestFiniteMagnitude)
    let size = uiView.sizeThatFits(targetSize)
    let calculatedSize = CGSize(width: size.width, height: size.height.rounded(.up))

    context.coordinator.sizeCache[cacheKey] = calculatedSize

    return calculatedSize
  }

  class Coordinator {
    // Cache all calculated sizes keyed by width
    var sizeCache: [CGFloat: CGSize] = [:]
    var lastContents: NSMutableAttributedString?
    var lastLineSpacing: CGFloat?
  }
}
#else
struct ParagraphView: NSViewRepresentable {
  @Environment(\.openURL) var openURL

  var contents: NSMutableAttributedString
  var lineSpacing: CGFloat?

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> ParagraphNSTextView {
    let textView = ParagraphNSTextView()
    textView.onUrlTap = openURL.callAsFunction(_:)
    textView.setParagraphContents(contents, lineSpacing: lineSpacing)
    return textView
  }

  func updateNSView(_ nsView: ParagraphNSTextView, context: Context) {
    nsView.onUrlTap = openURL.callAsFunction(_:)
    nsView.setParagraphContents(contents, lineSpacing: lineSpacing)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: ParagraphNSTextView, context: Context) -> CGSize? {
    guard let width = proposal.width, width > 0, width.isFinite else {
      return nil
    }

    if contents != context.coordinator.lastContents || lineSpacing != context.coordinator.lastLineSpacing {
      context.coordinator.sizeCache.removeAll()
      context.coordinator.lastContents = contents
      context.coordinator.lastLineSpacing = lineSpacing
    }

    let cacheKey = (width * 10).rounded() / 10
    if let cachedSize = context.coordinator.sizeCache[cacheKey] {
      return cachedSize
    }

    let size = nsView.measuredSize(width: width)
    context.coordinator.sizeCache[cacheKey] = size
    return size
  }

  class Coordinator {
    var sizeCache: [CGFloat: CGSize] = [:]
    var lastContents: NSMutableAttributedString?
    var lastLineSpacing: CGFloat?
  }
}

final class ParagraphNSTextView: NSTextView, NSTextViewDelegate {
  private(set) var paragraphContents: NSMutableAttributedString = NSMutableAttributedString()
  private(set) var lineSpacing: CGFloat?
  var onUrlTap: (URL) -> Void = { NSWorkspace.shared.open($0) }

  init() {
    let textStorage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    let textContainer = NSTextContainer(containerSize: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    textContainer.widthTracksTextView = true
    textContainer.heightTracksTextView = false
    textContainer.lineFragmentPadding = 0
    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)
    super.init(frame: .zero, textContainer: textContainer)
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }

  private func setupView() {
    delegate = self
    isEditable = false
    isSelectable = true
    drawsBackground = false
    textContainerInset = .zero
    textContainer?.lineFragmentPadding = 0
    isVerticallyResizable = true
    isHorizontallyResizable = false
    autoresizingMask = [.width]
    linkTextAttributes = [:]
  }

  func setParagraphContents(_ newContents: NSMutableAttributedString, lineSpacing: CGFloat? = nil) {
    guard paragraphContents != newContents || self.lineSpacing != lineSpacing else {
      return
    }
    paragraphContents = newContents
    self.lineSpacing = lineSpacing
    textStorage?.setAttributedString(sanitizedForTextStorage(applyLineSpacing(to: newContents, lineSpacing: lineSpacing)))
    invalidateIntrinsicContentSize()
  }

  func measuredSize(width: CGFloat) -> CGSize {
    guard let textContainer, let layoutManager else {
      return CGSize(width: width, height: 0)
    }
    textContainer.containerSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: textContainer)
    let used = layoutManager.usedRect(for: textContainer)
    return CGSize(width: width, height: ceil(used.height))
  }

  func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
    guard let url = link as? URL else { return false }
    onUrlTap(url)
    return true
  }

  private func applyLineSpacing(to attributedString: NSMutableAttributedString, lineSpacing: CGFloat?) -> NSMutableAttributedString {
    let result = NSMutableAttributedString(attributedString: attributedString)
    guard let lineSpacing else { return result }
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = lineSpacing
    paragraphStyle.alignment = .left
    result.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: result.length))
    return result
  }

  private func sanitizedForTextStorage(_ attributedString: NSMutableAttributedString) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: attributedString)
    let fullRange = NSRange(location: 0, length: result.length)
    let drawableKeys: Set<NSAttributedString.Key> = [
      .attachment,
      .backgroundColor,
      .baselineOffset,
      .font,
      .foregroundColor,
      .kern,
      .link,
      .paragraphStyle,
      .strikethroughColor,
      .strikethroughStyle,
      .underlineColor,
      .underlineStyle
    ]

    attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
      for key in attributes.keys where !drawableKeys.contains(key) {
        result.removeAttribute(key, range: range)
      }
      for key in [NSAttributedString.Key.foregroundColor, .backgroundColor, .underlineColor, .strikethroughColor] {
        guard let color = attributes[key] as? NSColor else { continue }
        result.addAttribute(key, value: color.usingColorSpace(.deviceRGB) ?? color, range: range)
      }
    }
    return result
  }
}
#endif
