//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import CoreGraphics
import SwiftUI
import VoiceChatRaTeX

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum RaTeXMathRendering {
  private static let formulaCacheLock = NSLock()
  nonisolated(unsafe) private static var formulaCache: [RaTeXFormulaRenderKey: VoiceChatRaTeXFormula] = [:]
  nonisolated(unsafe) private static var formulaCacheOrder: [RaTeXFormulaRenderKey] = []
  private static let formulaCacheLimit = 128

  static func renderFormula(latex: String, displayMode: Bool, pointSize: CGFloat, color: UIColor, colorScheme: ColorScheme = .dark) -> VoiceChatRaTeXFormula? {
    renderFormula(for: renderKey(latex: latex, displayMode: displayMode, pointSize: pointSize, color: color, colorScheme: colorScheme))
  }

  static func renderFormula(for key: RaTeXFormulaRenderKey) -> VoiceChatRaTeXFormula? {
    if let cached = cachedFormula(for: key) {
      return cached
    }

    guard let formula = VoiceChatRaTeXEngine.shared.render(
      latex: key.latex,
      displayMode: key.displayMode,
      fontSize: key.pointSize,
      color: key.color
    ) else {
      return nil
    }

    storeCachedFormula(formula, for: key)
    return formula
  }

  static func renderKey(latex: String, displayMode: Bool, pointSize: CGFloat, color: UIColor, colorScheme: ColorScheme = .dark) -> RaTeXFormulaRenderKey {
    RaTeXFormulaRenderKey(
      latex: latex,
      displayMode: displayMode,
      pointSize: pointSize,
      color: ratexColor(from: color, colorScheme: colorScheme)
    )
  }

  static func attachment(latex: String, pointSize: CGFloat, color: UIColor, colorScheme: ColorScheme = .dark) -> NSTextAttachment? {
    guard let formula = renderFormula(latex: latex, displayMode: false, pointSize: pointSize, color: color, colorScheme: colorScheme) else {
      return nil
    }
    guard let image = makeImage(formula: formula, scale: platformScale) else {
      return nil
    }
    let attachment = NSTextAttachment()
    attachment.image = image
    let height = ceil(formula.totalHeight)
    let yOffset = -ceil(formula.depth)
    attachment.bounds = CGRect(x: 0, y: yOffset, width: ceil(formula.width), height: height)
    return attachment
  }

  private static var platformScale: CGFloat {
    #if os(macOS)
    return NSScreen.main?.backingScaleFactor ?? 2
    #elseif os(visionOS)
    return 2
    #else
    return 2
    #endif
  }

  private static func makeImage(formula: VoiceChatRaTeXFormula, scale: CGFloat) -> PlatformImage? {
    let width = max(1, ceil(formula.width))
    let height = max(1, ceil(formula.totalHeight))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
      data: nil,
      width: Int(width * scale),
      height: Int(height * scale),
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: bitmapInfo
    ) else {
      return nil
    }
    context.scaleBy(x: scale, y: scale)
    formula.draw(in: context)
    guard let cgImage = context.makeImage() else {
      return nil
    }
    #if os(macOS)
    return NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    #else
    return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    #endif
  }

  static func ratexColor(from color: UIColor, colorScheme: ColorScheme = .dark) -> VoiceChatRaTeXColor {
    let resolved = resolvedPlatformColor(from: color, colorScheme: colorScheme)
    #if os(macOS)
    let deviceRGB = resolved.usingColorSpace(.deviceRGB) ?? resolved
    return VoiceChatRaTeXColor(
      red: Double(deviceRGB.redComponent),
      green: Double(deviceRGB.greenComponent),
      blue: Double(deviceRGB.blueComponent),
      alpha: Double(deviceRGB.alphaComponent)
    )
    #else
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    if !resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
      UIColor.label.resolvedColor(with: traitCollection(for: colorScheme)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    }
    return VoiceChatRaTeXColor(
      red: Double(red),
      green: Double(green),
      blue: Double(blue),
      alpha: Double(alpha)
    )
    #endif
  }

  private static func resolvedPlatformColor(from color: UIColor, colorScheme: ColorScheme) -> UIColor {
    #if os(macOS)
    var resolved = color
    appearance(for: colorScheme).performAsCurrentDrawingAppearance {
      resolved = color.usingColorSpace(.deviceRGB) ?? color
    }
    return resolved
    #else
    return color.resolvedColor(with: traitCollection(for: colorScheme))
    #endif
  }

  private static func cachedFormula(for key: RaTeXFormulaRenderKey) -> VoiceChatRaTeXFormula? {
    formulaCacheLock.lock()
    defer { formulaCacheLock.unlock() }
    return formulaCache[key]
  }

  private static func storeCachedFormula(_ formula: VoiceChatRaTeXFormula, for key: RaTeXFormulaRenderKey) {
    formulaCacheLock.lock()
    defer { formulaCacheLock.unlock() }

    if formulaCache[key] == nil {
      formulaCacheOrder.append(key)
    }
    formulaCache[key] = formula

    while formulaCacheOrder.count > formulaCacheLimit {
      let oldestKey = formulaCacheOrder.removeFirst()
      formulaCache.removeValue(forKey: oldestKey)
    }
  }

  #if os(macOS)
  private static func appearance(for colorScheme: ColorScheme) -> NSAppearance {
    if let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) {
      return appearance
    }
    return NSAppearance(named: .aqua)!
  }
  #else
  private static func traitCollection(for colorScheme: ColorScheme) -> UITraitCollection {
    UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
  }
  #endif
}

struct RaTeXFormulaRenderKey: Hashable, Sendable {
  let latex: String
  let displayMode: Bool
  let pointSize: CGFloat
  let color: VoiceChatRaTeXColor
}

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif
