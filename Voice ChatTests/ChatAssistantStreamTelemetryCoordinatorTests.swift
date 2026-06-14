import XCTest
@testable import Voice_Chat

final class ChatAssistantStreamTelemetryCoordinatorTests: XCTestCase {
    func testRecordStartAndApplyFirstTokenMetadata() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let firstTokenAt = startedAt.addingTimeInterval(2)
        let streamID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11))
        let configuration = chatConfiguration()
        let promptMessages = [
            ChatMessage(content: "hello", isUser: true),
            ChatMessage(content: "!error:previous", isUser: false)
        ]
        let assistant = ChatMessage(content: "", isUser: false, createdAt: firstTokenAt)
        var coordinator = ChatAssistantStreamTelemetryCoordinator()

        coordinator.recordStreamStart(
            using: promptMessages,
            configuration: configuration,
            developerPrompt: "developer",
            includeImagesInUserContent: true,
            startedAt: startedAt,
            streamID: streamID
        )
        coordinator.applyStreamMetadata(
            to: assistant,
            firstTokenTimestamp: firstTokenAt,
            fallbackConfiguration: configuration
        )

        XCTAssertEqual(assistant.streamStartedAt, startedAt)
        XCTAssertEqual(assistant.streamFirstTokenAt, firstTokenAt)
        XCTAssertEqual(assistant.requestID, streamID)
        XCTAssertEqual(assistant.modelIdentifier, configuration.modelIdentifier)
        XCTAssertEqual(assistant.apiBaseURL, configuration.apiBaseURL)
        XCTAssertEqual(assistant.promptMessageCount, 1)
        XCTAssertEqual(assistant.promptCharacterCount, 5)
        XCTAssertEqual(assistant.timeToFirstToken, 2)
        XCTAssertEqual(assistant.timeToFirstTokenSource, ChatStreamMetricValueSource.local.rawValue)
        XCTAssertEqual(coordinator.activeDeveloperPrompt, "developer")
        XCTAssertTrue(coordinator.activeIncludeImagesInUserContent)
    }

    func testFinalizeAppliesProviderMetadataAndClearsActiveTelemetry() {
        let startedAt = Date(timeIntervalSince1970: 200)
        let firstTokenAt = startedAt.addingTimeInterval(1)
        let finishedAt = startedAt.addingTimeInterval(5)
        let configuration = chatConfiguration()
        let assistant = ChatMessage(
            content: "provider text",
            isUser: false,
            isActive: true,
            createdAt: startedAt,
            streamFirstTokenAt: firstTokenAt
        )
        var coordinator = ChatAssistantStreamTelemetryCoordinator()

        coordinator.recordStreamStart(
            using: [ChatMessage(content: "prompt", isUser: true)],
            configuration: configuration,
            developerPrompt: nil,
            includeImagesInUserContent: false,
            startedAt: startedAt
        )
        coordinator.mergeServerMetadata(ChatResponseMetadata(
            providerResponseID: "resp-123",
            outputTokenCount: 42,
            reasoningOutputTokenCount: 7,
            tokensPerSecond: 12.5,
            timeToFirstTokenSeconds: 0.75,
            finishReason: "stop"
        ))

        let finalized = coordinator.finalizeActiveAssistantMessage(
            assistant,
            reason: "completed",
            finishedAt: finishedAt,
            errorDescription: nil,
            fallbackConfiguration: configuration
        )

        XCTAssertTrue(finalized === assistant)
        XCTAssertFalse(assistant.isActive)
        XCTAssertEqual(assistant.providerResponseID, "resp-123")
        XCTAssertEqual(assistant.tokenCount, 42)
        XCTAssertEqual(assistant.reasoningOutputTokenCount, 7)
        XCTAssertEqual(assistant.timeToFirstToken, 0.75)
        XCTAssertEqual(assistant.tokensPerSecond, 12.5)
        XCTAssertEqual(assistant.finishReason, "stop")
        XCTAssertEqual(assistant.tokenCountSource, ChatStreamMetricValueSource.provider.rawValue)
        XCTAssertEqual(assistant.timeToFirstTokenSource, ChatStreamMetricValueSource.provider.rawValue)
        XCTAssertEqual(assistant.tokensPerSecondSource, ChatStreamMetricValueSource.provider.rawValue)
        XCTAssertNil(coordinator.activeTelemetry)
    }

    func testFinalizeDanglingAssistantBackfillsLocalMetrics() {
        let startedAt = Date(timeIntervalSince1970: 300)
        let now = startedAt.addingTimeInterval(4)
        let message = ChatMessage(
            content: "dangling assistant",
            isUser: false,
            isActive: true,
            createdAt: startedAt,
            streamFirstTokenAt: startedAt.addingTimeInterval(1)
        )
        let coordinator = ChatAssistantStreamTelemetryCoordinator()

        XCTAssertTrue(coordinator.finalizeDanglingActiveAssistantMessage(message, now: now))
        XCTAssertFalse(message.isActive)
        XCTAssertEqual(message.finishReason, "interrupted")
        XCTAssertEqual(message.streamCompletedAt, now)
        XCTAssertEqual(message.streamDuration, 4)
        XCTAssertEqual(message.generationDuration, 3)
        XCTAssertEqual(message.tokenCount, 5)
        XCTAssertEqual(message.tokenCountSource, ChatStreamMetricValueSource.local.rawValue)
    }

    private func chatConfiguration() -> ChatServiceConfiguration {
        ChatServiceConfiguration(
            apiBaseURL: "https://example.test/v1",
            modelIdentifier: "model-a",
            apiKey: "token",
            thinkingOption: ModelThinkingOption.none
        )
    }
}
