//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

public protocol MarkdownListener: Sendable {
  func onRender(markdown: RenderableDocument) async
  func onTableCopyTap(content: String) async
  func onTableDownloadTap(content: String) async
  func onContextMenuAppear(id: String, selectedContent: String) async
  func onContextMenuTap(id: String, selectedContent: String) async
}

@MainActor
public final class MarkdownController: ObservableObject {

  private let listener: MarkdownListener?
  private var continuation: AsyncStream<RenderableDocument>.Continuation?
  private var listenerTask: Task<Void, Never>?
  var hasListener: Bool { listener != nil }

  init(listener: MarkdownListener?) {
    self.listener = listener
  }

  func onAppear(markdown: RenderableDocument) {
    cleanup()

    guard let listener else {
      return
    }

    let stream = AsyncStream<RenderableDocument>(bufferingPolicy: .bufferingNewest(1)) { continuation in
      self.continuation = continuation
    }

    listenerTask = Task { [listener] in
      // Deliver the initial markdown directly so it can't be overwritten
      // in the 1-slot buffer by an `onChange` arriving before this task
      // starts iterating the stream.
      await listener.onRender(markdown: markdown)
      for await md in stream {
        await listener.onRender(markdown: md)
      }
    }
  }

  func onChange(markdown: RenderableDocument) {
    continuation?.yield(markdown)
  }

  func onDisappear() {
    cleanup()
  }

  func onTableCopyTap(content: String) {
    guard let listener else { return }
    Task { [listener] in
      await listener.onTableCopyTap(content: content)
    }
  }

  func onTableDownloadTap(content: String) {
    guard let listener else { return }
    Task { [listener] in
      await listener.onTableDownloadTap(content: content)
    }
  }

  func onContextMenuAppear(id: String, selectedContent: String) {
    guard let listener else { return }
    Task { [listener] in
      await listener.onContextMenuAppear(id: id, selectedContent: selectedContent)
    }
  }

  func onContextMenuTap(id: String, selectedContent: String) {
    guard let listener else { return }
    Task { [listener] in
      await listener.onContextMenuTap(id: id, selectedContent: selectedContent)
    }
  }

  private func cleanup() {
    continuation?.finish()
    continuation = nil
    listenerTask?.cancel()
    listenerTask = nil
  }
}
