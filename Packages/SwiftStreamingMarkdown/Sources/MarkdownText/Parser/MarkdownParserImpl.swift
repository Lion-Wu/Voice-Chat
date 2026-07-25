//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Markdown

/// The built-in, stateless `MarkdownParser` implementation.
public struct MarkdownParserImpl: MarkdownParser {

  /// Create a new parser instance using the default LaTeX preprocessor.
  public init() {}

  /// Parse `text` into a `MarkdownParseResult`. See `MarkdownParser.parse(text:option:)`.
  public func parse(
    text: String,
    option: MarkdownParseOption
  ) async -> sending MarkdownParseResult {
    let latexPreprocessor = LaTexPreProcessorImpl()
    let targetString = latexPreprocessor.process(input: text, matchingRules: option.latexMatchingRules)

    var result: MarkdownParseResult = MarkdownParseResult(
      document: Document(parsing: targetString),
      speculativeRewritten: false
    )

    if option.speculativeRewrite {
      let rewriters: [MarkupPostParsingRewriter] = [
        PartialStrongMarkupPostParsingRewriter(),
        PartialTableMarkupPostParsingRewriter()
      ]
      for rewriter in rewriters {
        if let rewrittenDoc = rewriter.rewriteIfApplicable(document: result.document) {
          result = MarkdownParseResult(document: rewrittenDoc, speculativeRewritten: true)
        }
      }
    }

    if option.imageSupport {
      let imageBlockRewriter = ImageBlockMarkupPostParsingRewriter()
      if let rewrittenDoc = imageBlockRewriter.rewriteIfApplicable(document: result.document) {
        result = MarkdownParseResult(
          document: rewrittenDoc,
          speculativeRewritten: result.speculativeRewritten
        )
      }
    }
    return result
  }

  public func parse(
    text: String,
    config: MarkdownRenderConfig
  ) async -> RenderableDocument {
    let result = await parse(
      text: text,
      option: .init(
        speculativeRewrite: false,
        imageSupport: config.imageConfig.enabled
      )
    )
    return await RenderableDocument(document: result.document, config: config)
  }
}
