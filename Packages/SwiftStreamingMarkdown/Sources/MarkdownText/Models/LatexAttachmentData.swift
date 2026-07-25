//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct LatexAttachmentData: Codable {
  let latex: String
  let fontSize: CGFloat
  let lightTextColor: String
  let darkTextColor: String
}

extension UTType {
  static let markdownLatex = UTType(
    exportedAs: "com.microsoft.swiftstreamingmarkdown.latex"
  )
}

final class LatexTextAttachment: NSTextAttachment {
  init(contents: Data) {
    super.init(
      data: contents,
      ofType: UTType.markdownLatex.identifier
    )
    self.contents = contents
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override var fileType: String? {
    get { UTType.markdownLatex.identifier }
    set {}
  }
}
