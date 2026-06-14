import XCTest
@testable import Voice_Chat

final class ChatEndpointProviderOrderTests: XCTestCase {
    func testLocalLMStudioPortPrioritizesLMStudioThenFallbacks() {
        let providers = ChatEndpointProviderOrder.providers(
            for: ChatEndpointProviderOrderContext(
                path: "",
                host: "localhost",
                port: 1234,
                isLocal: true
            ),
            preferred: nil
        )

        XCTAssertEqual(Array(providers.prefix(3)), [.lmStudio, .llamaCpp, .openAICompatible])
        XCTAssertEqual(providers.last, .openRouter)
    }

    func testHeuristicProviderKeepsPreferredAsSecondaryWhenDistinct() {
        let providers = ChatEndpointProviderOrder.providers(
            for: ChatEndpointProviderOrderContext(
                path: "/v1/messages",
                host: "proxy.example.com",
                port: nil,
                isLocal: false
            ),
            preferred: .openAICompatible
        )

        XCTAssertEqual(Array(providers.prefix(2)), [.anthropic, .openAICompatible])
    }

    func testNoHeuristicUsesPreferredBeforeDefaultLocalFallbacks() {
        let providers = ChatEndpointProviderOrder.providers(
            for: ChatEndpointProviderOrderContext(
                path: "/custom",
                host: "example.internal",
                port: nil,
                isLocal: false
            ),
            preferred: .gemini
        )

        XCTAssertEqual(Array(providers.prefix(4)), [.gemini, .lmStudio, .llamaCpp, .openAICompatible])
    }

    func testUnknownPreferredIsIgnored() {
        let providers = ChatEndpointProviderOrder.providers(
            for: ChatEndpointProviderOrderContext(
                path: "",
                host: "example.com",
                port: nil,
                isLocal: false
            ),
            preferred: .unknown
        )

        XCTAssertEqual(Array(providers.prefix(3)), [.lmStudio, .llamaCpp, .openAICompatible])
    }
}
