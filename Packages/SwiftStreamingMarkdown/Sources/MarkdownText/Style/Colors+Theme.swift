//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

// swiftlint:disable type_name

import SwiftUI

extension Color {
  enum Theme {
    enum Accent {
      static let Accent600 = Color.markdownDynamic(light: 0x006DCC, dark: 0x58A6FF)
    }

    enum Background {
      enum Page {
        enum Chat {
          static let Flat = Color.markdownDynamic(light: 0xFFFFFF, dark: 0x111113)
        }
      }
    }

    enum Component {
      enum Button {
        enum Foreground {
          static let Pressed = Color.markdownDynamic(light: 0x2F3337, dark: 0xF2F2F3)
          static let Rest = Color.markdownDynamic(light: 0x555B61, dark: 0xC9CDD2)
        }
      }

      enum CodeBlock {
        enum Background {
          static let Background750 = Color.markdownDynamic(light: 0xE0E3E8, dark: 0x24262A)
        }

        enum Foreground {
          static let FunctionParameter = Color.markdownDynamic(light: 0x5F6368, dark: 0xD1D5DB)
          static let Header = Color.markdownDynamic(light: 0x8A8F98, dark: 0x9CA3AF)
        }
      }

      enum Table {
        enum Background {
          static let Header = Color.markdownDynamic(light: 0xF4F5F7, dark: 0x2A2C30)
        }
      }
    }

    enum Foreground {
      enum Primary {
        static let Primary450 = Color.markdownDynamic(light: 0x5F6368, dark: 0xBFC5CF)
        static let Primary550 = Color.markdownDynamic(light: 0x4B5056, dark: 0xD1D5DB)
        static let Primary650 = Color.markdownDynamic(light: 0x343941, dark: 0xE5E7EB)
        static let Primary750 = Color.primary
        static let Primary800 = Color.primary
      }
    }

    enum Overlay {
      enum Black {
        static let Black5 = Color.markdownDynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.05, darkAlpha: 0.08)
      }
    }

    enum Stroke {
      enum Default {
        static let Default250 = Color.markdownDynamic(light: 0xDADDE3, dark: 0x3A3D42)
        static let Default300 = Color.markdownDynamic(light: 0xC9CDD4, dark: 0x464A50)
      }

      enum Muted {
        static let Muted300 = Color.markdownDynamic(light: 0xE1E4E8, dark: 0x383B40)
      }
    }
  }
}

extension Color {
  static func markdownDynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
    #if os(macOS)
    return Color(UIColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return UIColor.markdownColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
    })
    #else
    return Color(UIColor { traitCollection in
      let isDark = traitCollection.userInterfaceStyle == .dark
      return UIColor.markdownColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
    })
    #endif
  }
}

private extension UIColor {
  static func markdownColor(hex: UInt32, alpha: CGFloat = 1) -> UIColor {
    let red = CGFloat((hex >> 16) & 0xFF) / 255
    let green = CGFloat((hex >> 8) & 0xFF) / 255
    let blue = CGFloat(hex & 0xFF) / 255
    #if os(macOS)
    return UIColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    #else
    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    #endif
  }
}
