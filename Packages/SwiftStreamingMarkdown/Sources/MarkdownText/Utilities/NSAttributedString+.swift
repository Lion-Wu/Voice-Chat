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
    let cleanedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !cleanedQuery.isEmpty, !string.isEmpty else {
      return self
    }

    let fullString = string as NSString
    var searchRange = NSRange(location: 0, length: fullString.length)
    let highlightColor = UIColor.systemYellow.withAlphaComponent(0.35)

    while searchRange.location < fullString.length {
      let matchRange = fullString.range(
        of: cleanedQuery,
        options: [.caseInsensitive, .diacriticInsensitive],
        range: searchRange
      )
      guard matchRange.location != NSNotFound else {
        break
      }

      addAttribute(.backgroundColor, value: highlightColor, range: matchRange)
      let nextLocation = NSMaxRange(matchRange)
      searchRange = NSRange(location: nextLocation, length: fullString.length - nextLocation)
    }

    return self
  }
}

extension AttributedString {
  func applyingSearchHighlight(query: String?) -> AttributedString {
    let cleanedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !cleanedQuery.isEmpty, !characters.isEmpty else {
      return self
    }

    var result = self
    let plainString = String(result.characters)
    var searchStart = plainString.startIndex
    let highlightColor = Color.yellow.opacity(0.35)

    while searchStart < plainString.endIndex,
          let range = plainString.range(
            of: cleanedQuery,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchStart..<plainString.endIndex
          ),
          let lowerBound = AttributedString.Index(range.lowerBound, within: result),
          let upperBound = AttributedString.Index(range.upperBound, within: result) {
      result[lowerBound..<upperBound].backgroundColor = highlightColor
      searchStart = range.upperBound
    }

    return result
  }
}
