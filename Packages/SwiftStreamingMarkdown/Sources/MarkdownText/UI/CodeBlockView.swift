//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import HighlightSwift
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

private actor HighlightTaskManager {
  private var latestRequest: CodeHighlightRequest?
  private var isProcessing = false

  func enqueue(
    _ request: CodeHighlightRequest,
    completion: @escaping @MainActor (CodeHighlightRequest, AttributedString) -> Void
  ) {
    latestRequest = request

    guard !isProcessing else {
      return
    }

    Task {
      await processQueue(completion: completion)
    }
  }

  private func processQueue(
    completion: @escaping @MainActor (CodeHighlightRequest, AttributedString) -> Void
  ) async {
    guard !isProcessing else { return }

    isProcessing = true

    while let request = latestRequest {
      latestRequest = nil

      let highlighted = await SharedHighlightRenderer.shared.highlight(request)
      let result = (highlighted ?? AttributedString(request.code))
        .applyingSearchHighlight(query: request.searchHighlightQuery)

      await MainActor.run {
        completion(request, result)
      }
    }

    isProcessing = false
  }
}

private actor SharedHighlightRenderer {
  static let shared = SharedHighlightRenderer()

  /// Shared Highlight instance to avoid creating multiple JSContext/HLJS instances.
  /// Each Highlight() creates its own JSContext and evaluates highlight.min.js (~600KB).
  /// All calls are serialized through this actor because the underlying JSContext
  /// should not be driven concurrently by multiple code block views.
  private let highlighter = Highlight()

  func highlight(_ request: CodeHighlightRequest) async -> AttributedString? {
    try? await highlighter.attributedText(
      request.code,
      colors: .custom(css: request.css, background: "")
    )
  }
}

struct CodeBlockView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.markdownConfig) private var config

  let language: String
  let code: String
  let searchHighlightQuery: String?
  let onCodeCopied: (() -> Void)?

  @State var copied: Bool = false
  @State var attributedString: AttributedString?
  @State private var taskManager = HighlightTaskManager()

  private var highlightRequest: CodeHighlightRequest {
    CodeHighlightRequest(
      code: code,
      css: Self.syntaxHighlightingCss(for: colorScheme),
      searchHighlightQuery: searchHighlightQuery
    )
  }

  init(language: String, code: String, searchHighlightQuery: String? = nil, onCodeCopied: (() -> Void)? = nil) {
    self.language = language
    self.code = code
    self.searchHighlightQuery = searchHighlightQuery
    self.onCodeCopied = onCodeCopied
  }

  private func updateAttributedString(for request: CodeHighlightRequest) async {
    await taskManager.enqueue(request) { completedRequest, newAttributedString in
      guard completedRequest == self.highlightRequest else {
        return
      }
      self.attributedString = newAttributedString
    }
  }

  @ViewBuilder
  var codeblock: some View {
    ScrollView(.horizontal) {
      HStack(alignment: .top) {
        if #available(iOS 16.1, *) {  // Minimum version for HighlightSwift
          Text(attributedString ?? AttributedString(code))
            .font(Font(config.inlineStyle.codeTextFont))
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          Text(code)
            .font(Font(config.inlineStyle.codeTextFont))
            .foregroundStyle(Color.Theme.Component.CodeBlock.Foreground.FunctionParameter)
            .transition(.opacity)
        }
      }

    }.transaction { transaction in
      // The horizontal scrollView resizing animation was causing the code block to animate
      // all janky.
      transaction.animation = nil
    }
    .padding(16)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top) {
        Text(language)
          .font(Typography.smallTextFonts(sizeCategory: config.sizeCategory))
          .foregroundStyle(Color.Static.Stone.Stone350)
        Spacer()
        HStack(alignment: .firstTextBaseline, spacing: 6.0) {
          Image(systemName: copied ? "checkmark" : "doc.on.doc")
            .foregroundStyle(Color.Static.Stone.Stone350)
          Text(copied ? String.codeCopiedLabel : String.codeCopyLabel)
            .accessibilityAddTraits(.isButton)
            .font(Typography.smallTextFonts(sizeCategory: config.sizeCategory))
            .foregroundStyle(Color.Static.Stone.Stone350)
            .onTapGesture {
              copied = true
              writeCodeToPasteboard(code)
              if let onCodeCopied {
                onCodeCopied()
              }
            }
        }
      }.frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
          Color.Theme.Component.CodeBlock.Background.Background750
            .clipShape(.rect(
              topLeadingRadius: 20,
              bottomLeadingRadius: 0,
              bottomTrailingRadius: 0,
              topTrailingRadius: 20
            ))
        )
      codeblock
        .fixedSize(horizontal: false, vertical: true)
        .scrollIndicators(.automatic)
        .background(Color.Theme.Component.CodeBlock.Background.Background750
          .clipShape(.rect(
            topLeadingRadius: 0,
            bottomLeadingRadius: 20,
            bottomTrailingRadius: 20,
            topTrailingRadius: 0
          ))
        )
    }
    .task(id: copied) {
      guard copied else {
        return
      }
      do {
        try await Task.sleep(seconds: 3)
        copied = false
      } catch {}
    }
    .task(id: highlightRequest) {
      await updateAttributedString(for: highlightRequest)
    }
  }
}

private struct CodeHighlightRequest: Hashable, Sendable {
  let code: String
  let css: String
  let searchHighlightQuery: String?
}

private func writeCodeToPasteboard(_ code: String) {
  #if os(macOS)
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(code, forType: .string)
  #else
  UIPasteboard.general.string = code
  #endif
}

#if DEBUG

#Preview {
  return LazyVStack {
    Spacer()
    CodeBlockView(language: "Python", code: "import random\n\ndef generate_and_add_numbers(num_numbers):\n    # Generate a list of random numbers random_numbers\n    random_numbers = [random.randint(1, 100) for _ in range(num_numbers)]\n\n\n    # Add the numbers together\n    sum_of_numbers = sum(random_numbers)\n\n    return random_numbers, sum_of_numbers\n\n# Example: Generate 5 random numbers and add them together\nnum_numbers = 5\nrandom_numbers, sum_of_numbers = generate_and_add_numbers(num_numbers)\nprint(f\"Generated numbers: {random_numbers}\")\nprint(f\"Sum of numbers: {sum_of_numbers}\")")
    Spacer()
  }.padding(24)
}

#endif
