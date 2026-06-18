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
          Color.clear
            .preference(key: TrackedSizePreferenceKey.self, value: proxy.size)
        }
      )
      .onPreferenceChange(TrackedSizePreferenceKey.self, perform: onChange)
  }
}

private struct TrackedSizePreferenceKey: PreferenceKey {
  static let defaultValue: CGSize = .zero

  static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
    value = nextValue()
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
