//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import SwiftUI
import VoiceChatRaTeX

struct BlockMathView: View {
  @Environment(\.markdownConfig) private var config

  let latex: String
  let color: Color
  let pointSize: CGFloat
  @State private var renderResult: BlockMathRenderResult?

  init(
    latex: String,
    color: Color = .primary,
    pointSize: CGFloat = Typography.base.uiFont.pointSize
  ) {
    self.latex = latex
    self.color = color
    self.pointSize = pointSize
  }

  private var renderKey: RaTeXFormulaRenderKey {
    RaTeXMathRendering.renderKey(
      latex: latex,
      displayMode: true,
      pointSize: pointSize,
      color: UIColor(color),
      colorScheme: config.colorScheme
    )
  }

  var body: some View {
    Group {
      if let renderResult,
         renderResult.key == renderKey,
         let formula = renderResult.formula {
        Canvas { context, _ in
          context.withCGContext { cgContext in
            formula.draw(in: cgContext)
          }
        }
        .frame(width: ceil(formula.width), height: ceil(formula.totalHeight))
      } else {
        Text(latex)
          .font(.system(size: pointSize, design: .monospaced))
          .foregroundStyle(color)
      }
    }
    .accessibilityLabel(latex)
    .task(id: renderKey) {
      let key = renderKey
      let formula = await Task.detached(priority: .userInitiated) {
        RaTeXMathRendering.renderFormula(for: key)
      }.value
      guard key == renderKey else {
        return
      }
      renderResult = BlockMathRenderResult(key: key, formula: formula)
    }
  }
}

private struct BlockMathRenderResult {
  let key: RaTeXFormulaRenderKey
  let formula: VoiceChatRaTeXFormula?
}
