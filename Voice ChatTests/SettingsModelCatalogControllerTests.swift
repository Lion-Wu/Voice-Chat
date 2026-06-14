import XCTest
@testable import Voice_Chat

@MainActor
final class SettingsModelCatalogControllerTests: XCTestCase {
    func testValidationFailureKeepsExistingCatalogSnapshot() {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAICompatible,
            style: .openAIChatCompletions,
            chatURL: URL(string: "https://example.com/v1/chat/completions")!,
            modelsURL: URL(string: "https://example.com/v1/models")!
        )
        let current = SettingsModelCatalogState(
            availableModels: ["existing"],
            isLoadingModels: false,
            isRetryingModels: false,
            modelRetryAttempt: 0,
            modelRetryLastError: nil,
            chatServerErrorMessage: nil,
            lastFetchedModelMetadata: [modelInfo(id: "existing")],
            lastModelFetchEndpoint: endpoint
        )

        let failed = SettingsModelCatalogState.validationFailure(
            from: SettingsModelCatalogState.loading(from: current),
            message: "Invalid Server URL"
        )

        XCTAssertEqual(failed.availableModels, ["existing"])
        XCTAssertFalse(failed.isLoadingModels)
        XCTAssertFalse(failed.isRetryingModels)
        XCTAssertEqual(failed.chatServerErrorMessage, "Invalid Server URL")
        XCTAssertEqual(failed.lastFetchedModelMetadata.map(\.id), ["existing"])
        XCTAssertEqual(failed.lastModelFetchEndpoint, endpoint)
    }

    func testFetchProjectsDetectedCatalogAndNextSelectedModel() async throws {
        let endpoint = try XCTUnwrap(ChatAPIEndpointResolver.endpointCandidate(
            for: "https://example.com",
            formatPreference: .openAICompatible
        ))
        let service = StubModelCatalogService(responses: [
            endpoint.modelsURL: .success([modelInfo(id: "vision-model", supportsImageInput: true)])
        ])
        let controller = SettingsModelCatalogController(
            modelCatalogFetchCoordinator: ModelCatalogFetchCoordinator(modelCatalogService: service)
        )
        let current = SettingsModelCatalogState(
            availableModels: ["old-model"],
            isLoadingModels: false,
            isRetryingModels: false,
            modelRetryAttempt: 0,
            modelRetryLastError: nil,
            chatServerErrorMessage: nil,
            lastFetchedModelMetadata: [],
            lastModelFetchEndpoint: nil
        )
        let detected = expectation(description: "catalog detected")
        var states: [SettingsModelCatalogState] = []
        var detection: SettingsModelCatalogDetection?

        controller.fetch(
            request: SettingsModelCatalogRequest(
                apiURL: " https://example.com ",
                apiKey: "sk-test",
                formatPreference: .openAICompatible,
                detectedProvider: nil,
                selectedModel: "missing-model"
            ),
            currentState: current,
            applyState: { state in
                states.append(state)
            },
            applyDetection: { value in
                detection = value
                detected.fulfill()
            }
        )

        await fulfillment(of: [detected], timeout: 2.0)

        XCTAssertEqual(service.requestedModelURLs, [endpoint.modelsURL])
        XCTAssertEqual(states.first?.isLoadingModels, true)
        XCTAssertEqual(states.last?.availableModels, ["vision-model"])
        XCTAssertEqual(states.last?.lastModelFetchEndpoint, endpoint)
        XCTAssertNil(states.last?.chatServerErrorMessage)
        XCTAssertEqual(detection?.apiURL, "https://example.com")
        XCTAssertEqual(detection?.nextSelectedModel, "vision-model")
        XCTAssertEqual(detection?.result.imageInputSupportByModelID, ["vision-model": true])
    }
}
