import XCTest
@testable import Voice_Chat

final class ChatEndpointResolverTests: XCTestCase {
    func testEndpointResolverPrioritizesAvailableStyleHint() {
        let resolver = DefaultChatEndpointResolver()

        let candidates = resolver.streamingCandidates(
            for: "http://localhost:1234",
            providerHint: .lmStudio,
            styleHint: .openAIChatCompletions
        )

        XCTAssertEqual(candidates.first?.provider, .lmStudio)
        XCTAssertEqual(candidates.first?.style, .openAIChatCompletions)
    }

    func testEndpointResolverFallsBackWhenStyleHintIsUnavailable() {
        let resolver = DefaultChatEndpointResolver()

        let candidates = resolver.streamingCandidates(
            for: "http://localhost:1234",
            providerHint: .lmStudio,
            styleHint: .lmStudioRESTV1LegacyMessage
        )

        XCTAssertEqual(candidates.first?.provider, .lmStudio)
        XCTAssertFalse(candidates.contains { $0.style == .lmStudioRESTV1LegacyMessage })
    }
}
