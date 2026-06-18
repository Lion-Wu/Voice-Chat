//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI

/// This is a view that is able to both parse and render markdown with default configuration.
/// Use this view instead of `DocumentView` if you don't want to perform the parsing yourself.
public struct MarkdownView: View {

  private let text: String
  private let config: MarkdownRenderConfig
  @StateObject var controller: MarkdownViewController
  @Environment(\.colorScheme) private var colorScheme

  /// Create a `MarkdownView`.
  /// - Parameters:
  ///   - text: The raw Markdown source to parse and render.
  ///   - config: Render configuration. Defaults to `.default`.
  ///   - listener: Optional listener that receives render and interaction events.
  public init(
    text: String,
    config: MarkdownRenderConfig = .default,
    listener: MarkdownListener? = nil
  ) {
    self.text = text
    self.config = config
    _controller = StateObject(wrappedValue: MarkdownViewController(config: config, listener: listener))
  }

  public var body: some View {
    let resolvedConfig = config.withColorScheme(value: colorScheme)
    Group {
      if let renderable = controller.renderable {
        DocumentView(renderableDocument: renderable, config: resolvedConfig, listener: controller.listener)
      } else {
        DocumentView(renderableDocument: .empty, config: resolvedConfig, listener: controller.listener)
      }
    }
    .task(id: MarkdownViewRenderKey(text: text, colorScheme: colorScheme)) {
      await controller.parse(text: text, config: resolvedConfig)
    }
  }
}

private struct MarkdownViewRenderKey: Hashable {
  let text: String
  let colorScheme: ColorScheme
}

@MainActor
final class MarkdownViewController: ObservableObject {

  @Published var renderable: RenderableDocument?

  let listener: MarkdownListener?

  init(config: MarkdownRenderConfig = .default, listener: MarkdownListener? = nil) {
    self.listener = listener
  }

  func parse(text: String, config: MarkdownRenderConfig) async {
    let parser = MarkdownParserImpl()
    let renderable = await parser.parse(text: text, config: config)
    self.renderable = renderable
  }
}
