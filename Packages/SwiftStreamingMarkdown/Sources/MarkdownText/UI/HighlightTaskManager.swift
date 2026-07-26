//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import HighlightSwift

/// Owns the package's single HighlightSwift runtime.
///
/// A `Highlight` instance owns a JavaScriptCore-backed highlighter. Keeping that
/// ownership in one actor avoids constructing a runtime for every code block and
/// gives all callers one concurrency boundary.
actor HighlightTaskManager {
  static let shared = HighlightTaskManager()

  private let highlighter = Highlight()

  func highlight(code: String, colors: HighlightColors) async throws -> AttributedString {
    try Task.checkCancellation()
    let result = try await highlighter.attributedText(code, colors: colors)
    try Task.checkCancellation()
    return result
  }
}
