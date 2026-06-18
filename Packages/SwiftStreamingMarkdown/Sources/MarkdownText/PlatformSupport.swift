//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import SwiftUI

#if os(macOS)
import AppKit

public typealias UIColor = NSColor
public typealias UIFont = NSFont
public typealias UIImage = NSImage

extension NSFont: @retroactive @unchecked Sendable {}

extension NSColor {
  convenience init(dynamicProvider: @escaping (NSAppearance) -> NSColor) {
    self.init(name: nil) { appearance in
      dynamicProvider(appearance)
    }
  }

  func resolvedColor(with appearance: NSAppearance) -> NSColor {
    if let color = usingColorSpace(.deviceRGB) {
      return color
    }
    return self
  }
}

extension Font {
  init(_ font: NSFont) {
    self = Font.custom(font.fontName, size: font.pointSize)
  }
}

extension NSFont {
  var lineHeight: CGFloat {
    ascender - descender + leading
  }
}
#else
import UIKit
#endif
