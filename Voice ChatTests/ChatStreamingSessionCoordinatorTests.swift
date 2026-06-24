import XCTest
@testable import Voice_Chat

@MainActor
final class ChatStreamingSessionCoordinatorTests: XCTestCase {
    func testUpdateConfigurationDefersDuringActiveRequestThenAppliesWhenIdle() {
        let initial = chatConfig(model: "initial")
        let next = chatConfig(model: "next")
        var createdModels: [String] = []
        let initialService = StubChatStreamingService()
        let coordinator = ChatStreamingSessionCoordinator(
            configuration: initial,
            service: initialService,
            serviceFactory: { configuration in
                createdModels.append(configuration.modelIdentifier)
                return StubChatStreamingService()
            }
        )

        XCTAssertEqual(
            coordinator.updateConfiguration(next, isActiveTextRequest: true),
            .deferred
        )
        XCTAssertEqual(coordinator.configuration, initial)
        XCTAssertTrue(createdModels.isEmpty)

        XCTAssertEqual(
            coordinator.applyDeferredConfigurationIfIdle(isActiveTextRequest: false),
            .applied
        )
        XCTAssertEqual(coordinator.configuration, next)
        XCTAssertEqual(createdModels, ["next"])
    }

    func testCallbacksAreReboundWhenConfigurationApplies() {
        let initial = chatConfig(model: "initial")
        let next = chatConfig(model: "next")
        let initialService = StubChatStreamingService()
        let replacementService = StubChatStreamingService()
        let coordinator = ChatStreamingSessionCoordinator(
            configuration: initial,
            service: initialService,
            serviceFactory: { _ in replacementService }
        )
        var receivedDeltas: [String] = []
        coordinator.bindHandlers(
            onDelta: { receivedDeltas.append($0) },
            onError: { _ in },
            onResponseMetadata: { _ in },
            onToolActivity: { _ in },
            onStreamFinished: {}
        )

        initialService.onDelta?("old")
        XCTAssertEqual(
            coordinator.updateConfiguration(next, isActiveTextRequest: false),
            .applied
        )
        replacementService.onDelta?("new")

        XCTAssertEqual(receivedDeltas, ["old", "new"])
    }

    private func chatConfig(model: String) -> ChatServiceConfiguration {
        ChatServiceConfiguration(
            apiBaseURL: "http://localhost:1234",
            modelIdentifier: model,
            apiKey: "key"
        )
    }
}

@MainActor
private final class StubChatStreamingService: ChatStreamingService {
    var onDelta: (@MainActor (String) -> Void)?
    var onError: (@MainActor (Error) -> Void)?
    var onResponseMetadata: (@MainActor (ChatResponseMetadata) -> Void)?
    var onToolActivity: (@MainActor (ChatToolActivity) -> Void)?
    var onStreamFinished: (@MainActor () -> Void)?

    private(set) var didCancel = false
    private(set) var requestedMessages: [ChatMessage] = []

    func fetchStreamedData(
        messages: [ChatMessage],
        developerPrompt: String?,
        includeImagesInUserContent: Bool
    ) {
        requestedMessages = messages
    }

    func cancelStreaming() {
        didCancel = true
    }
}
