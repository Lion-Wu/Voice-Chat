//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI

extension CodeBlockView {

  static func syntaxHighlightingCss(for colorScheme: ColorScheme) -> String {
    switch colorScheme {
    case .dark:
      darkSyntaxHighlightingCss
    default:
      lightSyntaxHighlightingCss
    }
  }

  private static let lightSyntaxHighlightingCss = """
  code {
  color: #24292F
  }

  .hljs-comment,
  .hljs-meta {
  color: #6E7781
  }

  .hljs-built_in,
  .hljs-class .hljs-title {
  color: #8250DF
  }

  .hljs-doctag,
  .hljs-formula,
  .hljs-keyword,
  .hljs-literal {
  color: #0969DA
  }
  .hljs-addition,
  .hljs-attribute,
  .hljs-meta-string,
  .hljs-regexp,
  .hljs-string {
  color: #1A7F37
  }
  .hljs-attr,
  .hljs-number,
  .hljs-selector-attr,
  .hljs-selector-class,
  .hljs-selector-pseudo,
  .hljs-template-variable,
  .hljs-type,
  .hljs-variable {
  color: #57606A
  }

  .hljs-bullet,
  .hljs-link,
  .hljs-selector-id,
  .hljs-symbol,
  .hljs-title {
  color: #6639BA
  }
  """

  private static let darkSyntaxHighlightingCss = """
  code {
  color: #F0F3F6
  }

  .hljs-comment,
  .hljs-meta {
  color: #9EA7B3
  }

  .hljs-built_in,
  .hljs-class .hljs-title {
  color: #D2A8FF
  }

  .hljs-doctag,
  .hljs-formula,
  .hljs-keyword,
  .hljs-literal {
  color: #79C0FF
  }
  .hljs-addition,
  .hljs-attribute,
  .hljs-meta-string,
  .hljs-regexp,
  .hljs-string {
  color: #A5D6A7
  }
  .hljs-attr,
  .hljs-number,
  .hljs-selector-attr,
  .hljs-selector-class,
  .hljs-selector-pseudo,
  .hljs-template-variable,
  .hljs-type,
  .hljs-variable {
  color: #B6BDC6
  }

  .hljs-bullet,
  .hljs-link,
  .hljs-selector-id,
  .hljs-symbol,
  .hljs-title {
  color: #D2A8FF
  }
  """
}
