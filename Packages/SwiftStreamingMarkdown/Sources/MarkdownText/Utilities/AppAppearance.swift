//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Cross-platform appearance representation used to select
/// the precomputed light/dark citation preview image.
enum AppAppearance: Sendable {
  case light
  case dark

  private static let storage = OSAllocatedUnfairLock(initialState: AppAppearance.dark)

  static var current: AppAppearance {
    storage.withLock { $0 }
  }

  #if canImport(UIKit)
  var platformType: UIUserInterfaceStyle {
    switch self {
    case .dark: return UIUserInterfaceStyle.dark
    case .light: return UIUserInterfaceStyle.light
    }
  }

  static func update(style: UIUserInterfaceStyle) {
    storage.withLock { value in
      value = switch style {
      case .dark:
          .dark
      default:
          .light
      }
    }
  }

  #elseif canImport(AppKit)
  var platformType: NSAppearance? {
    switch self {
    case .dark: return NSAppearance(named: .darkAqua)
    case .light: return NSAppearance(named: .aqua)
    }
  }

  static func update(appearance: NSAppearance) {
    // bestMatch resolves all dark variants (vibrantDark, accessibilityHighContrastDarkAqua, etc.)
    // to .darkAqua and all light variants to .aqua.
    let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    storage.withLock { $0 = isDark ? .dark : .light }
  }
  #endif
}
