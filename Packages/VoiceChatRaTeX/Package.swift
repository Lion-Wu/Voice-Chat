// swift-tools-version: 6.0
import PackageDescription

// This package is the local visionOS compatibility adapter.
// SwiftStreamingMarkdown uses the official RaTeX Swift package directly on
// iOS and macOS.
let package = Package(
    name: "VoiceChatRaTeX",
    platforms: [
        .iOS(.v14),
        .macOS(.v14),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "VoiceChatRaTeX", targets: ["VoiceChatRaTeX"])
    ],
    targets: [
        .target(
            name: "VoiceChatRaTeX",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "VoiceChatRaTeXTests",
            dependencies: ["VoiceChatRaTeX"]
        )
    ]
)
