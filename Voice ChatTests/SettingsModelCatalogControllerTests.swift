import XCTest
@testable import Voice_Chat

@MainActor
final class SettingsModelCatalogControllerTests: XCTestCase {
    func testAnthropicCatalogFetchesEveryPageWithoutChangingHeaders() async throws {
        let loader = ModelCatalogPageLoader()
        let service = DefaultModelCatalogService { request in
            try await loader.load(request)
        }
        let endpoint = ChatAPIEndpointCandidate(
            provider: .anthropic,
            style: .anthropicMessages,
            chatURL: try XCTUnwrap(URL(string: "https://api.anthropic.com/v1/messages")),
            modelsURL: try XCTUnwrap(URL(string: "https://api.anthropic.com/v1/models?limit=1"))
        )

        let models = try await service.fetchModels(
            from: endpoint,
            apiKey: "test-key",
            retryPolicy: NetworkRetryPolicy(maxAttempts: 1),
            onRetry: nil
        )
        let requests = await loader.requests

        XCTAssertEqual(models.map(\.id), ["claude-page-1", "claude-page-2"])
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "x-api-key"), "test-key")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "x-api-key"), "test-key")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let secondComponents = try XCTUnwrap(URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false))
        XCTAssertEqual(secondComponents.queryItems?.first(where: { $0.name == "limit" })?.value, "1")
        XCTAssertEqual(secondComponents.queryItems?.first(where: { $0.name == "after_id" })?.value, "claude-page-1")
    }

    func testValidationFailureKeepsExistingCatalogSnapshot() {
        let endpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
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
            formatPreference: .openAIResponses
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
                formatPreference: .openAIResponses,
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

private actor ModelCatalogPageLoader {
    private(set) var requests: [URLRequest] = []

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let cursor = components?.queryItems?.first(where: { $0.name == "after_id" })?.value
        let body: String
        if cursor == nil {
            body = #"{"data":[{"id":"claude-page-1"}],"has_more":true,"first_id":"claude-page-1","last_id":"claude-page-1"}"#
        } else {
            body = #"{"data":[{"id":"claude-page-2"}],"has_more":false,"first_id":"claude-page-2","last_id":"claude-page-2"}"#
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}
