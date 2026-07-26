//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if os(visionOS)
import VoiceChatRaTeX
private typealias MarkdownAttachmentMathView = VoiceChatRaTeXView
#else
import RaTeX
private typealias MarkdownAttachmentMathView = RaTeXView
#endif

// MARK: - LatexAttachmentData Color Resolution

extension LatexAttachmentData {
  var resolvedTextColor: MDColor {
    let fallback = MDColor(Color.Theme.Foreground.Primary.Primary750)
    #if canImport(UIKit)
    guard let lightColor = UIColor(hex: lightTextColor),
          let darkColor = UIColor(hex: darkTextColor) else {
      return fallback
    }
    return UIColor { trait in
      trait.userInterfaceStyle == .dark ? darkColor : lightColor
    }
    #elseif canImport(AppKit)
    guard let lightColor = NSColor(hex: lightTextColor),
          let darkColor = NSColor(hex: darkTextColor) else {
      return fallback
    }
    return NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return isDark ? darkColor : lightColor
    }
    #endif
  }
}

// MARK: - Latex View Provider

/// TextKit invokes attachment view providers from its main-thread layout pass,
/// but its Objective-C override surface is not actor annotated in the SDK.
final class LatexViewProvider: NSTextAttachmentViewProvider {
  private let latex: String
  private let fontSize: CGFloat
  private let textColor: MDColor

  private struct DecodedAttachment {
    var latex: String = ""
    var fontSize: CGFloat = Typography.base.mdFont.pointSize
    var textColor: MDColor = MDColor(Color.Theme.Foreground.Primary.Primary750)
  }

  #if canImport(UIKit)
  required override init(textAttachment attachment: NSTextAttachment,
                         parentView: UIView?,
                         textLayoutManager: NSTextLayoutManager?,
                         location: any NSTextLocation) {
    let decoded = Self.decode(attachment: attachment)
    latex = decoded.latex
    fontSize = decoded.fontSize
    textColor = decoded.textColor
    super.init(textAttachment: attachment, parentView: parentView,
               textLayoutManager: textLayoutManager, location: location)
    tracksTextAttachmentViewBounds = true
  }
  #elseif canImport(AppKit)
  required override init(textAttachment attachment: NSTextAttachment,
                         parentView: NSView?,
                         textLayoutManager: NSTextLayoutManager?,
                         location: any NSTextLocation) {
    let decoded = Self.decode(attachment: attachment)
    latex = decoded.latex
    fontSize = decoded.fontSize
    textColor = decoded.textColor
    super.init(textAttachment: attachment, parentView: parentView,
               textLayoutManager: textLayoutManager, location: location)
    tracksTextAttachmentViewBounds = true
  }
  #endif

  private static func decode(attachment: NSTextAttachment) -> DecodedAttachment {
    var result = DecodedAttachment()
    if let data = attachment.contents,
       let attachmentData = try? JSONDecoder().decode(LatexAttachmentData.self, from: data) {
      result.latex = attachmentData.latex
      result.fontSize = attachmentData.fontSize
      result.textColor = attachmentData.resolvedTextColor
    }
    return result
  }

  override func loadView() {
    let latex = latex
    let textColor = textColor
    let fontSize = fontSize
    let mathView = MainActor.assumeIsolated {
      let mathView = MarkdownAttachmentMathView()
      mathView.color = textColor
      mathView.displayMode = false
      mathView.fontSize = fontSize
      mathView.latex = latex
      mathView.setContentHuggingPriority(.defaultHigh, for: .vertical)
      return MathViewReference(mathView)
    }
    view = mathView.value
  }

  override func attachmentBounds(for attributes: [NSAttributedString.Key: Any],
                                 location: any NSTextLocation,
                                 textContainer: NSTextContainer?,
                                 proposedLineFragment: CGRect,
                                 position: CGPoint) -> CGRect {
    guard let mathView = view as? MarkdownAttachmentMathView else {
      return .zero
    }
    let mathViewReference = MathViewReference(mathView)
    let font = attributes[.font] as? MDFont
    let fontSize = fontSize
    return MainActor.assumeIsolated {
      let mathView = mathViewReference.value
      let size = mathView.intrinsicContentSize
      let height = size.height.rounded(.up)
      let resolvedFont = font ?? MDFont.systemFont(ofSize: fontSize)
      let yOffset = (resolvedFont.xHeight - height) / 2.0
      return CGRect(x: 0, y: yOffset, width: size.width.rounded(.up), height: height)
    }
  }
}

/// A non-owning isolation bridge for TextKit's unannotated synchronous UI
/// callbacks. The referenced view is only dereferenced inside `MainActor`.
private struct MathViewReference: @unchecked Sendable {
  let value: MarkdownAttachmentMathView

  init(_ value: MarkdownAttachmentMathView) {
    self.value = value
  }
}
