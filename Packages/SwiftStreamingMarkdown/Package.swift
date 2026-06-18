// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SwiftStreamingMarkdown",
  defaultLocalization: "en",
  platforms: [
    .iOS(.v16),
    .macOS(.v15),
    .visionOS(.v2)
  ],
  products: [
    .library(
      name: "SwiftStreamingMarkdown",
      targets: ["SwiftStreamingMarkdown"])
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.7.3"),
    .package(url: "https://github.com/appstefan/highlightswift", revision: "99c431b38a1444a5fd6a4978307fbbefe3a7af53"),
    .package(path: "../VoiceChatRaTeX")
  ],
  targets: [
    .target(
      name: "SwiftStreamingMarkdown",
      dependencies: [
        .product(name: "Markdown", package: "swift-markdown"),
        .product(name: "HighlightSwift", package: "highlightswift"),
        .product(name: "VoiceChatRaTeX", package: "VoiceChatRaTeX")
      ],
      path: "Sources/MarkdownText"
    ),
    .testTarget(
      name: "SwiftStreamingMarkdownTests",
      dependencies: ["SwiftStreamingMarkdown"],
      path: "Tests/MarkdownTextTests"
    )
  ]
)
