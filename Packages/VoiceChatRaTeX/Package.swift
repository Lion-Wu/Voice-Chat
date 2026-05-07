// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceChatRaTeX",
    platforms: [
        .iOS(.v14),
        .macOS(.v15),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "VoiceChatRaTeX", targets: ["VoiceChatRaTeX"])
    ],
    targets: [
        .binaryTarget(
            name: "RaTeXFFI",
            path: "Vendor/RaTeX.xcframework"
        ),
        .target(
            name: "VoiceChatRaTeX",
            dependencies: [
                .target(name: "RaTeXFFI", condition: .when(platforms: [.iOS]))
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
