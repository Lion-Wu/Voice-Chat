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

extension NSAttributedString {
  func splitIntoWords(withIn range: NSRange) -> [NSRange] {
    var words: [NSRange] = []
    let string = self.string as NSString

    guard range.location != NSNotFound,
          range.location >= 0,
          NSMaxRange(range) <= string.length else {
      return words
    }

    string.enumerateSubstrings(
      in: range,
      options: [.byWords, .localized, .substringNotRequired]
    ) { (_, substringRange, _, _) in

      // Add any separator/whitespace before this word
      if let lastWord = words.last {
        let gapStart = NSMaxRange(lastWord)
        let gapLength = substringRange.location - gapStart

        if gapLength > 0 {
          let gapRange = NSRange(location: gapStart, length: gapLength)
          words.append(gapRange)
        }
      } else {
        // Handle any leading separators/whitespace
        let leadingGapLength = substringRange.location - range.location
        if leadingGapLength > 0 {
          let leadingGapRange = NSRange(location: range.location, length: leadingGapLength)
          words.append(leadingGapRange)
        }
      }

      // Add the word range
      words.append(substringRange)
    }

    // Handle any trailing separators/whitespace
    if let lastWord = words.last {
      let trailingStart = NSMaxRange(lastWord)
      let trailingLength = NSMaxRange(range) - trailingStart

      if trailingLength > 0 {
        let trailingRange = NSRange(location: trailingStart, length: trailingLength)
        words.append(trailingRange)
      }
    } else {
      // If no words were found, return entire range
      if range.length > 0 {
        words.append(range)
      }
    }

    return words
  }
}

extension NSMutableAttributedString {
  func applyingSearchHighlight(query: String?) -> NSMutableAttributedString {
    let query = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !query.isEmpty, !string.isEmpty else { return self }

    let source = string as NSString
    var searchRange = NSRange(location: 0, length: source.length)
    let highlightColor = MDColor.systemYellow.withAlphaComponent(0.35)

    while searchRange.length > 0 {
      let match = source.range(
        of: query,
        options: [.caseInsensitive, .diacriticInsensitive],
        range: searchRange
      )
      guard match.location != NSNotFound else { break }

      addAttribute(.backgroundColor, value: highlightColor, range: match)
      let nextLocation = NSMaxRange(match)
      searchRange = NSRange(
        location: nextLocation,
        length: source.length - nextLocation
      )
    }

    return self
  }
}

extension AttributedString {
  func applyingSearchHighlight(query: String?) -> AttributedString {
    let query = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !query.isEmpty, !characters.isEmpty else { return self }

    var result = self
    let source = String(result.characters)
    var searchStart = source.startIndex

    while searchStart < source.endIndex,
          let match = source.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchStart..<source.endIndex
          ),
          let lowerBound = AttributedString.Index(match.lowerBound, within: result),
          let upperBound = AttributedString.Index(match.upperBound, within: result) {
      result[lowerBound..<upperBound].backgroundColor = Color.yellow.opacity(0.35)
      searchStart = match.upperBound
    }

    return result
  }
}
