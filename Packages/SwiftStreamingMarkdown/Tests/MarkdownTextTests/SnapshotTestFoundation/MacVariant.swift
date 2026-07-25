//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(AppKit)
import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Window-size-based variant for macOS snapshot testing.
public struct MacVariant {
  let title: WindowSize
  let size: CGSize
  let snapshot: Snapshotting<NSViewController, NSImage>
  let colorScheme: ColorScheme

  enum WindowSize: String {
    case standard   // ~800pt, typical window
    case wide       // ~1200pt, full-width
  }
}

extension MacVariant {
  var name: String {
    "macOS-\(title.rawValue)-\(colorScheme.macDescription)"
  }
}

private extension ColorScheme {
  var macDescription: String {
    switch self {
    case .light: return "light"
    case .dark: return "dark"
    @unknown default: fatalError()
    }
  }
}

// MARK: - Factory Methods

extension MacVariant {
  static func standard(
    colorScheme: ColorScheme = .light,
    precision: Float = 1,
    perceptualPrecision: Float = 1
  ) -> MacVariant {
    let size = CGSize(width: 800, height: 800)
    return MacVariant(
      title: .standard,
      size: size,
      snapshot: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: size),
      colorScheme: colorScheme
    )
  }

  static func wide(
    colorScheme: ColorScheme = .light,
    precision: Float = 1,
    perceptualPrecision: Float = 1
  ) -> MacVariant {
    let size = CGSize(width: 1200, height: 800)
    return MacVariant(
      title: .wide,
      size: size,
      snapshot: .image(precision: precision, perceptualPrecision: perceptualPrecision, size: size),
      colorScheme: colorScheme
    )
  }
}

// MARK: - Standard Collections

extension Collection where Element == MacVariant {
  /// Standard macOS variants: standard light/dark
  public static func standard(
    precision: Float = 1,
    perceptualPrecision: Float = 1.0
  ) -> [MacVariant] {
    [
      .standard(colorScheme: .light, precision: precision, perceptualPrecision: perceptualPrecision),
      .standard(colorScheme: .dark, precision: precision, perceptualPrecision: perceptualPrecision)
    ]
  }

  /// Wide variants only (light and dark)
  public static func wideOnly(
    precision: Float = 1,
    perceptualPrecision: Float = 1.0
  ) -> [MacVariant] {
    [
      .wide(colorScheme: .light, precision: precision, perceptualPrecision: perceptualPrecision),
      .wide(colorScheme: .dark, precision: precision, perceptualPrecision: perceptualPrecision)
    ]
  }
}
#endif
