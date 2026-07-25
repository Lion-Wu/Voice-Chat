//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import SwiftUI

struct TrackSizeModifier: ViewModifier {

  let onChange: (CGSize) -> Void

  func body(content: Content) -> some View {
    content
      .background(
        GeometryReader { proxy in
          sizeObserver(for: proxy.size)
        }
      )
  }

  @ViewBuilder
  private func sizeObserver(for size: CGSize) -> some View {
    if #available(iOS 17, *) {
      Color.clear
        .hidden()
        .onAppear {
          onChange(size)
        }
        .onChange(of: size) { _, newSize in
          onChange(newSize)
        }
    } else {
      Color.clear
        .hidden()
        .onAppear {
          onChange(size)
        }
        .onChange(of: size) { newSize in
          onChange(newSize)
        }
    }
  }
}

extension View {

  func onSizeChange(perform onChange: @escaping (CGSize) -> Void) -> some View {
    modifier(TrackSizeModifier(onChange: onChange))
  }

  func onHeightChange(perform onChange: @escaping (CGFloat) -> Void) -> some View {
    onSizeChange { size in onChange(size.height) }
  }

  func onWidthChange(perform onChange: @escaping (CGFloat) -> Void) -> some View {
    onSizeChange { size in onChange(size.width) }
  }
}
