//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

@MainActor
final class ParagraphViewCache {
  private var cachedViews: [MDParagraphView] = []
  private let maxCacheSize = 50

  private init() {}

  static let shared: ParagraphViewCache = .init()

  func createOrReuseView(contents: NSMutableAttributedString, lineSpacing: CGFloat?) -> MDParagraphView {
    if let availableView = findAvailableCachedView() {
      return availableView
    }
    let newView = MDParagraphView()
    if cachedViews.count < maxCacheSize {
      cachedViews.append(newView)
    }
    return newView
  }

  func clearCache() {
    cachedViews.removeAll()
  }

  private func findAvailableCachedView() -> MDParagraphView? {
    cachedViews.first { view in
      view.superview == nil && view.window == nil
    }
  }
}
