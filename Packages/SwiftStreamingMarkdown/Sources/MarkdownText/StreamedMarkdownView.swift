//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI

/// A source of incremental Markdown text for `StreamedMarkdownView`.
///
/// Each value yielded by `text` is a *complete snapshot* of the Markdown
/// source so far (a growing prefix), not an incremental delta. The view
/// re-parses each snapshot and updates the rendered output.
public protocol StreamedMarkdownSource {
  var text: AsyncStream<String> { get }
}

/// A SwiftUI view that incrementally parses and renders streamed Markdown.
///
/// Provide a `StreamedMarkdownSource` whose `text` async sequence yields
/// progressively larger snapshots of the Markdown source; the view re-parses
/// on each emission and refreshes the rendered output.
public struct StreamedMarkdownView: View {

  private let config: MarkdownRenderConfig
  @StateObject private var controller: StreamedMarkdownController
  @Environment(\.colorScheme) private var colorScheme

  /// Create a `StreamedMarkdownView`.
  /// - Parameters:
  ///   - source: The streamed Markdown source. Each emission must be the
  ///     complete Markdown source so far, not an incremental delta.
  ///   - config: Render configuration. Defaults to `.default`.
  ///   - listener: Optional listener that receives render and interaction events.
  public init(
    source: StreamedMarkdownSource,
    config: MarkdownRenderConfig = .default,
    listener: MarkdownListener? = nil
  ) {
    self.config = config
    _controller = StateObject(
      wrappedValue: StreamedMarkdownController(source: source, config: config, listener: listener)
    )
  }

  public var body: some View {
    let resolvedConfig = config.withColorScheme(value: colorScheme)
    DocumentView(
      renderableDocument: controller.markdownToRender,
      config: resolvedConfig,
      listener: controller.listener
    )
    .task {
      controller.start()
    }
    .task(id: resolvedConfig) {
      await controller.updateConfig(resolvedConfig)
    }
    .onDisappear {
      controller.end()
    }
  }
}

@MainActor
final class StreamedMarkdownController: ObservableObject {

  @Published var markdownToRender: RenderableDocument = .empty
  let listener: MarkdownListener?

  private let source: StreamedMarkdownSource
  private let parserWorker = MarkdownRenderWorker()
  private var config: MarkdownRenderConfig
  private var task: Task<Void, Never>?
  private var latestText: String?
  private var latestTextRevision = 0
  private var renderToken = 0

  init(
    source: StreamedMarkdownSource,
    config: MarkdownRenderConfig,
    listener: MarkdownListener? = nil
  ) {
    self.source = source
    self.config = config
    self.listener = listener
  }

  func start() {
    task?.cancel()
    task = Task { [weak self] in
      guard let self else { return }
      for await text in self.source.text {
        if Task.isCancelled { return }
        guard let request = await MainActor.run(body: { self.nextStreamRenderRequest(for: text) }) else {
          continue
        }
        let renderable = await self.parserWorker.parse(text: request.text, config: request.config)
        if Task.isCancelled { return }
        await MainActor.run { self.apply(renderable, for: request) }
      }
    }
  }

  func reparseLatestSnapshot() async {
    guard let request = nextReparseRenderRequest() else { return }
    let renderable = await parserWorker.parse(text: request.text, config: request.config)
    apply(renderable, for: request)
  }

  func updateConfig(_ newConfig: MarkdownRenderConfig) async {
    guard newConfig != config else { return }
    let previousParseKey = config.parseAffectingKey
    config = newConfig
    guard newConfig.parseAffectingKey != previousParseKey else {
      return
    }
    guard let request = nextReparseRenderRequest() else { return }
    let renderable = await parserWorker.parse(text: request.text, config: request.config)
    apply(renderable, for: request)
  }

  func end() {
    task?.cancel()
    task = nil
  }

  private func nextStreamRenderRequest(for text: String) -> RenderRequest? {
    guard text != latestText else {
      return nil
    }
    latestTextRevision += 1
    renderToken += 1
    latestText = text
    return RenderRequest(
      text: text,
      config: config,
      textRevision: latestTextRevision,
      renderToken: renderToken
    )
  }

  private func nextReparseRenderRequest() -> RenderRequest? {
    guard let latestText else { return nil }
    renderToken += 1
    return RenderRequest(
      text: latestText,
      config: config,
      textRevision: latestTextRevision,
      renderToken: renderToken
    )
  }

  private func apply(_ renderable: RenderableDocument, for request: RenderRequest) {
    guard request.textRevision == latestTextRevision, request.renderToken == renderToken else {
      return
    }
    markdownToRender = renderable
  }
}

private struct RenderRequest: Sendable {
  let text: String
  let config: MarkdownRenderConfig
  let textRevision: Int
  let renderToken: Int
}

private actor MarkdownRenderWorker {
  func parse(text: String, config: MarkdownRenderConfig) async -> RenderableDocument {
    let parser = MarkdownParserImpl()
    let result = await parser.parse(text: text, option: .init(speculativeRewrite: config.speculativeRewrite))
    return await RenderableDocument(document: result.document, config: config)
  }
}
