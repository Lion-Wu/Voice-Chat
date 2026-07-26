//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import SwiftUI

#if os(visionOS)
import VoiceChatRaTeX
#else
import RaTeX
#endif

#if canImport(UIKit)

#if os(visionOS)
struct BlockMathView: UIViewRepresentable {
  let latex: String
  let color: Color
  let pointSize: CGFloat
  let colorScheme: ColorScheme

  init(
    latex: String,
    color: Color = Color.Theme.Foreground.Primary.Primary750,
    pointSize: CGFloat = Typography.base.mdFont.pointSize,
    colorScheme: ColorScheme = .light
  ) {
    self.latex = latex
    self.color = color
    self.pointSize = pointSize
    self.colorScheme = colorScheme
  }

  func makeUIView(context: Context) -> VoiceChatRaTeXView {
    let view = VoiceChatRaTeXView()
    view.setContentHuggingPriority(.required, for: .horizontal)
    view.setContentHuggingPriority(.required, for: .vertical)
    configure(view)
    return view
  }

  func updateUIView(_ uiView: VoiceChatRaTeXView, context: Context) {
    configure(uiView)
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: VoiceChatRaTeXView,
    context: Context
  ) -> CGSize? {
    let size = uiView.intrinsicContentSize
    return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
  }

  private func configure(_ view: VoiceChatRaTeXView) {
    let traits = UITraitCollection(
      userInterfaceStyle: colorScheme == .dark ? .dark : .light
    )
    view.fontSize = pointSize
    view.displayMode = true
    view.color = UIColor(color).resolvedColor(with: traits)
    view.latex = latex
  }
}
#endif

#endif

#if !os(visionOS)
struct BlockMathView: View {
  let latex: String
  let color: Color
  let pointSize: CGFloat
  let colorScheme: ColorScheme

  init(
    latex: String,
    color: Color = Color.Theme.Foreground.Primary.Primary750,
    pointSize: CGFloat = Typography.base.mdFont.pointSize,
    colorScheme: ColorScheme = .light
  ) {
    self.latex = latex
    self.color = color
    self.pointSize = pointSize
    self.colorScheme = colorScheme
  }

  var body: some View {
    RaTeXFormula(
      latex: latex,
      fontSize: pointSize,
      displayMode: true,
      color: resolvedColor
    )
    .accessibilityLabel(latex)
  }

  private var resolvedColor: Color {
    #if canImport(UIKit)
    let traits = UITraitCollection(
      userInterfaceStyle: colorScheme == .dark ? .dark : .light
    )
    return Color(uiColor: UIColor(color).resolvedColor(with: traits))
    #elseif canImport(AppKit)
    let appearance: NSAppearance.Name = colorScheme == .dark
      ? .darkAqua
      : .aqua
    return Color(nsColor: NSColor(color).resolvedForAppearance(appearance))
    #endif
  }
}
#endif
