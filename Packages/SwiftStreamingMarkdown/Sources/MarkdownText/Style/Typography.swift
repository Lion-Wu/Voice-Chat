//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Typography: CaseIterable, Sendable {
  case extraLargeStrong
  case extraLargeStrongItalic
  case extraLarge
  case extraLargeItalic

  case largeStrong
  case largeStrongItalic
  case large
  case largeItalic

  case mediumStrong
  case mediumStrongItalic
  case medium
  case mediumItalic

  case baseStrong
  case baseStrongItalic
  case baseItalic
  case base

  case smallStrong
  case smallStrongItalic
  case small
  case smallItalic

  case extraSmallStrong
  case extraSmallStrongItalic
  case extraSmall
  case extraSmallItalic

  case code
  case tripleExtraSmallCustom450

  var uiFont: UIFont {
    uiFont(sizeCategory: .large)
  }

  func uiFont(sizeCategory: ContentSizeCategory) -> UIFont {
    return switch self {
    case .tripleExtraSmallCustom450: Self.systemFont(size: 10.0, weight: .regular, sizeCategory: sizeCategory)
    case .code: Self.systemMonospacedFont(size: 15.0, weight: .regular, sizeCategory: sizeCategory)

    case .extraLargeStrong: Self.systemFont(size: 28.0, weight: .semibold, sizeCategory: sizeCategory)
    case .extraLargeStrongItalic: Self.systemFont(size: 28.0, weight: .semibold, italic: true, sizeCategory: sizeCategory)
    case .extraLarge: Self.systemFont(size: 28.0, weight: .regular, sizeCategory: sizeCategory)
    case .extraLargeItalic: Self.systemFont(size: 28.0, weight: .regular, italic: true, sizeCategory: sizeCategory)

    case .largeStrong: Self.systemFont(size: 24.0, weight: .semibold, sizeCategory: sizeCategory)
    case .largeStrongItalic: Self.systemFont(size: 24.0, weight: .semibold, italic: true, sizeCategory: sizeCategory)
    case .large: Self.systemFont(size: 24.0, weight: .regular, sizeCategory: sizeCategory)
    case .largeItalic: Self.systemFont(size: 24.0, weight: .regular, italic: true, sizeCategory: sizeCategory)

    case .mediumStrong: Self.systemFont(size: 20.0, weight: .semibold, sizeCategory: sizeCategory)
    case .mediumStrongItalic: Self.systemFont(size: 20.0, weight: .semibold, italic: true, sizeCategory: sizeCategory)
    case .medium: Self.systemFont(size: 20.0, weight: .regular, sizeCategory: sizeCategory)
    case .mediumItalic: Self.systemFont(size: 20.0, weight: .regular, italic: true, sizeCategory: sizeCategory)

    case .baseStrong: Self.systemFont(size: 17.0, weight: .semibold, sizeCategory: sizeCategory)
    case .baseStrongItalic: Self.systemFont(size: 17.0, weight: .semibold, italic: true, sizeCategory: sizeCategory)
    case .baseItalic: Self.systemFont(size: 17.0, weight: .regular, italic: true, sizeCategory: sizeCategory)
    case .base: Self.systemFont(size: 17.0, weight: .regular, sizeCategory: sizeCategory)

    case .smallStrong: Self.systemFont(size: 15.0, weight: .semibold, sizeCategory: sizeCategory)
    case .smallStrongItalic: Self.systemFont(size: 15.0, weight: .semibold, italic: true, sizeCategory: sizeCategory)
    case .small: Self.systemFont(size: 15.0, weight: .regular, sizeCategory: sizeCategory)
    case .smallItalic: Self.systemFont(size: 15.0, weight: .regular, italic: true, sizeCategory: sizeCategory)

    case .extraSmallStrong: Self.systemFont(size: 14.0, weight: .semibold, sizeCategory: sizeCategory)
    case .extraSmallStrongItalic: Self.systemFont(size: 14.0, weight: .semibold, italic: true, sizeCategory: sizeCategory)
    case .extraSmall: Self.systemFont(size: 14.0, weight: .regular, sizeCategory: sizeCategory)
    case .extraSmallItalic: Self.systemFont(size: 14.0, weight: .regular, italic: true, sizeCategory: sizeCategory)
    }
  }

  private static func systemFont(size: CGFloat, weight: UIFont.Weight, italic: Bool = false, sizeCategory: ContentSizeCategory) -> UIFont {
    #if os(macOS)
    let scaledSize = macOSScaledSize(size, sizeCategory: sizeCategory)
    #else
    let scaledSize = UIFontMetrics.default.scaledValue(for: size, compatibleWith: UITraitCollection(preferredContentSizeCategory: sizeCategory.uiContentSizeCategory))
    #endif
    let baseFont = UIFont.systemFont(ofSize: scaledSize, weight: weight)
    guard italic else {
      return baseFont
    }
    return baseFont.withItalicTrait()
  }

  private static func systemMonospacedFont(size: CGFloat, weight: UIFont.Weight, sizeCategory: ContentSizeCategory) -> UIFont {
    #if os(macOS)
    let scaledSize = macOSScaledSize(size, sizeCategory: sizeCategory)
    #else
    let scaledSize = UIFontMetrics.default.scaledValue(for: size, compatibleWith: UITraitCollection(preferredContentSizeCategory: sizeCategory.uiContentSizeCategory))
    #endif
    return UIFont.monospacedSystemFont(ofSize: scaledSize, weight: weight)
  }

  private static func platformLineHeight(_ value: CGFloat, sizeCategory: ContentSizeCategory) -> CGFloat {
    #if os(macOS)
    return macOSScaledSize(value, sizeCategory: sizeCategory).rounded(.up)
    #else
    return value
    #endif
  }

  #if os(macOS)
  private static func macOSScaledSize(_ size: CGFloat, sizeCategory: ContentSizeCategory) -> CGFloat {
    return (size * 0.86 * sizeCategory.macOSScaleFactor).rounded(.toNearestOrAwayFromZero)
  }
  #endif

  var font: Font {
    return Font(uiFont)
  }

  static var extraLargeTextFonts: TextFonts {
    extraLargeTextFonts(sizeCategory: .large)
  }

  static func extraLargeTextFonts(sizeCategory: ContentSizeCategory) -> TextFonts {
    return TextFonts(
      normal: Typography.extraLarge.uiFont(sizeCategory: sizeCategory),
      italic: Typography.extraLargeItalic.uiFont(sizeCategory: sizeCategory),
      bold: Typography.extraLargeStrong.uiFont(sizeCategory: sizeCategory),
      boldItalic: Typography.extraLargeStrongItalic.uiFont(sizeCategory: sizeCategory),
      preferredLetterSpacing: -0.28,
      preferredLineHeight: platformLineHeight(32.0, sizeCategory: sizeCategory)
    )
  }

  static var largeTextFonts: TextFonts {
    largeTextFonts(sizeCategory: .large)
  }

  static func largeTextFonts(sizeCategory: ContentSizeCategory) -> TextFonts {
    return TextFonts(
      normal: Typography.large.uiFont(sizeCategory: sizeCategory),
      italic: Typography.largeItalic.uiFont(sizeCategory: sizeCategory),
      bold: Typography.largeStrong.uiFont(sizeCategory: sizeCategory),
      boldItalic: Typography.largeStrongItalic.uiFont(sizeCategory: sizeCategory),
      preferredLetterSpacing: -0.24,
      preferredLineHeight: platformLineHeight(32.0, sizeCategory: sizeCategory)
    )
  }

  static var mediumTextFonts: TextFonts {
    mediumTextFonts(sizeCategory: .large)
  }

  static func mediumTextFonts(sizeCategory: ContentSizeCategory) -> TextFonts {
    return TextFonts(
      normal: Typography.medium.uiFont(sizeCategory: sizeCategory),
      italic: Typography.mediumItalic.uiFont(sizeCategory: sizeCategory),
      bold: Typography.mediumStrong.uiFont(sizeCategory: sizeCategory),
      boldItalic: Typography.mediumStrongItalic.uiFont(sizeCategory: sizeCategory),
      preferredLetterSpacing: -0.2,
      preferredLineHeight: platformLineHeight(26.0, sizeCategory: sizeCategory)
    )
  }

  static var baseTextFonts: TextFonts {
    baseTextFonts(sizeCategory: .large)
  }

  static func baseTextFonts(sizeCategory: ContentSizeCategory) -> TextFonts {
    return TextFonts(
      normal: Typography.base.uiFont(sizeCategory: sizeCategory),
      italic: Typography.baseItalic.uiFont(sizeCategory: sizeCategory),
      bold: Typography.baseStrong.uiFont(sizeCategory: sizeCategory),
      boldItalic: Typography.baseStrongItalic.uiFont(sizeCategory: sizeCategory),
      preferredLetterSpacing: 0.0,
      preferredLineHeight: platformLineHeight(26.0, sizeCategory: sizeCategory)
    )
  }

  static var smallTextFonts: TextFonts {
    smallTextFonts(sizeCategory: .large)
  }

  static func smallTextFonts(sizeCategory: ContentSizeCategory) -> TextFonts {
    return TextFonts(
      normal: Typography.small.uiFont(sizeCategory: sizeCategory),
      italic: Typography.smallItalic.uiFont(sizeCategory: sizeCategory),
      bold: Typography.smallStrong.uiFont(sizeCategory: sizeCategory),
      boldItalic: Typography.smallStrongItalic.uiFont(sizeCategory: sizeCategory),
      preferredLetterSpacing: 0.0,
      preferredLineHeight: platformLineHeight(20.0, sizeCategory: sizeCategory)
    )
  }

  static var extraSmallTextFonts: TextFonts {
    extraSmallTextFonts(sizeCategory: .large)
  }

  static func extraSmallTextFonts(sizeCategory: ContentSizeCategory) -> TextFonts {
    return TextFonts(
      normal: Typography.extraSmall.uiFont(sizeCategory: sizeCategory),
      italic: Typography.extraSmallItalic.uiFont(sizeCategory: sizeCategory),
      bold: Typography.extraSmallStrong.uiFont(sizeCategory: sizeCategory),
      boldItalic: Typography.extraSmallStrongItalic.uiFont(sizeCategory: sizeCategory),
      preferredLetterSpacing: 0.0,
      preferredLineHeight: platformLineHeight(20.0, sizeCategory: sizeCategory)
    )
  }

  static var codeTextFonts: TextFonts {
    codeTextFonts(sizeCategory: .large)
  }

  static func codeTextFonts(sizeCategory: ContentSizeCategory) -> TextFonts {
    return TextFonts(
      normal: Typography.code.uiFont(sizeCategory: sizeCategory),
      italic: nil,
      bold: nil,
      boldItalic: nil,
      preferredLetterSpacing: -0.12,
      preferredLineHeight: platformLineHeight(20.0, sizeCategory: sizeCategory)
    )
  }
}

#if os(macOS)
private extension ContentSizeCategory {
  var macOSScaleFactor: CGFloat {
    switch self {
    case .extraSmall: return 0.88
    case .small: return 0.94
    case .medium: return 0.98
    case .large: return 1.0
    case .extraLarge: return 1.08
    case .extraExtraLarge: return 1.16
    case .extraExtraExtraLarge: return 1.24
    case .accessibilityMedium: return 1.35
    case .accessibilityLarge: return 1.5
    case .accessibilityExtraLarge: return 1.65
    case .accessibilityExtraExtraLarge: return 1.8
    case .accessibilityExtraExtraExtraLarge: return 2.0
    @unknown default: return 1.0
    }
  }
}
#else
private extension ContentSizeCategory {
  var uiContentSizeCategory: UIContentSizeCategory {
    switch self {
    case .extraSmall: return .extraSmall
    case .small: return .small
    case .medium: return .medium
    case .large: return .large
    case .extraLarge: return .extraLarge
    case .extraExtraLarge: return .extraExtraLarge
    case .extraExtraExtraLarge: return .extraExtraExtraLarge
    case .accessibilityMedium: return .accessibilityMedium
    case .accessibilityLarge: return .accessibilityLarge
    case .accessibilityExtraLarge: return .accessibilityExtraLarge
    case .accessibilityExtraExtraLarge: return .accessibilityExtraExtraLarge
    case .accessibilityExtraExtraExtraLarge: return .accessibilityExtraExtraExtraLarge
    @unknown default: return .large
    }
  }
}
#endif

private extension UIFont {
  func withItalicTrait() -> UIFont {
    #if os(macOS)
    return NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask)
    #else
    let traits = fontDescriptor.symbolicTraits.union(.traitItalic)
    guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else {
      return self
    }
    return UIFont(descriptor: descriptor, size: pointSize)
    #endif
  }
}
