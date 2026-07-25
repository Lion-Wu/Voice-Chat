//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import XCTest
@testable import SwiftStreamingMarkdown

@MainActor
final class StreamedMarkdownViewTests: XCTestCase {
  func testFirstRenderCallbackRunsOnceForMultipleSnapshots() async {
    let source = FiniteMarkdownSource(values: ["First", "First second"])
    var callbackCount = 0
    let controller = StreamedMarkdownController(
      source: source,
      onFirstRender: { callbackCount += 1 }
    )

    await controller.render(config: .default)

    XCTAssertEqual(callbackCount, 1)
    XCTAssertFalse(controller.markdownToRender.isEmpty)
  }
}

@MainActor
private struct FiniteMarkdownSource: StreamedMarkdownSource {
  let values: [String]

  var text: AsyncStream<String> {
    AsyncStream { continuation in
      values.forEach { continuation.yield($0) }
      continuation.finish()
    }
  }
}
