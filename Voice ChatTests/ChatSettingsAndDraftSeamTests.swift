import XCTest
@testable import Voice_Chat

final class ChatSettingsAndDraftSeamTests: XCTestCase {
    func testAdvancedAPIStyleInferenceMatchesAutomaticEndpointRouting() {
        XCTAssertEqual(
            SettingsAPIRequestStyleResolver.inferredStyle(for: "https://api.deepseek.com"),
            .openAIChatCompletions
        )
        XCTAssertEqual(
            SettingsAPIRequestStyleResolver.inferredStyle(for: "https://openrouter.ai/api/v1/responses"),
            .openAIResponses
        )
        XCTAssertEqual(
            SettingsAPIRequestStyleResolver.inferredStyle(for: "https://compatible.example.com/v1/chat/completions"),
            .openAIChatCompletions
        )
    }

    func testModelCapabilityResolverInfersImageInputAndProviderHints() {
        XCTAssertEqual(ModelCapabilityResolver.imageInputSupport(fromModelIdentifier: " GPT-5.4 "), true)
        XCTAssertEqual(ModelCapabilityResolver.imageInputSupport(fromModelIdentifier: "qwen2.5-vl-chat"), true)
        XCTAssertNil(ModelCapabilityResolver.imageInputSupport(fromModelIdentifier: "plain-text-model"))
        XCTAssertNil(ModelCapabilityResolver.imageInputSupport(fromModelIdentifier: " "))

        XCTAssertEqual(ModelCapabilityResolver.providerHint(from: .anthropicMessages), .anthropic)
        XCTAssertEqual(ModelCapabilityResolver.providerHint(from: .lmStudioRESTV1), .lmStudio)
        XCTAssertNil(ModelCapabilityResolver.providerHint(from: .openAIChatCompletions))
        XCTAssertNil(ModelCapabilityResolver.providerHint(from: nil))
    }

    func testModelCapabilityResolverInfersProviderThinkingCapabilities() throws {
        let gpt56 = try XCTUnwrap(ModelCapabilityResolver.thinkingCapability(
            fromModelIdentifier: "openai/gpt-5.6-luna-pro",
            provider: .openAI,
            requestStyle: .openAIResponses
        ))
        XCTAssertEqual(gpt56.options, [.none, .low, .medium, .high, .xhigh, .max])
        XCTAssertEqual(gpt56.defaultOption, .medium)

        let openAI = try XCTUnwrap(ModelCapabilityResolver.thinkingCapability(
            fromModelIdentifier: "gpt-5.4",
            provider: .openAI,
            requestStyle: .openAIChatCompletions
        ))
        XCTAssertEqual(openAI.options, [.none, .low, .medium, .high, .xhigh])
        XCTAssertEqual(openAI.defaultOption, ModelThinkingOption.none)

        let anthropic = try XCTUnwrap(ModelCapabilityResolver.thinkingCapability(
            fromModelIdentifier: "claude-sonnet-4-6",
            provider: .anthropic,
            requestStyle: .anthropicMessages
        ))
        XCTAssertEqual(anthropic.options, [.off, .low, .medium, .high, .max])
        XCTAssertEqual(anthropic.defaultOption, .off)

        let openAICompatibleModel = try XCTUnwrap(ModelCapabilityResolver.thinkingCapability(
            fromModelIdentifier: "deepseek-reasoner",
            provider: .openAI,
            requestStyle: .openAIChatCompletions
        ))
        XCTAssertEqual(openAICompatibleModel.options, [.off, .high, .max])
        XCTAssertEqual(openAICompatibleModel.defaultOption, .high)
        XCTAssertEqual(openAICompatibleModel.requestParameter, .reasoning)

        XCTAssertNil(ModelCapabilityResolver.thinkingCapability(
            fromModelIdentifier: "gpt-5",
            provider: .lmStudio,
            requestStyle: .lmStudioRESTV1
        ))
    }

    func testThinkingDisabledAliasesCollapseToOneOption() {
        XCTAssertEqual(ModelThinkingOption.normalized("none"), .off)
        XCTAssertEqual(ModelThinkingOption(rawValue: "none"), .off)
        XCTAssertEqual(ModelThinkingOption(rawValue: "disabled"), .off)
        XCTAssertEqual(ModelThinkingOption.normalized("ultra"), .ultra)
        XCTAssertEqual(ModelThinkingOption.ultra.displayName, NSLocalizedString("Ultra", comment: ""))

        let capability = ModelThinkingCapability(
            options: [.off, ModelThinkingOption.none, ModelThinkingOption(rawValue: "disabled"), .low],
            defaultOption: ModelThinkingOption.none
        )

        XCTAssertEqual(capability.options, [.off, .low])
        XCTAssertEqual(capability.options.filter(\.isDisabled).count, 1)
        XCTAssertEqual(capability.defaultOption, .off)
    }

    func testAPIAdvancedSettingsSanitizesValues() {
        let settings = APIAdvancedSettings(
            openAIChatMaxCompletionTokens: -1,
            openAIChatSampling: APIAdvancedSamplingSettings(
                temperatureEnabled: true,
                temperature: 5,
                topPEnabled: true,
                topP: -1,
                topLogprobsEnabled: true,
                topLogprobs: 99,
                verbosityEnabled: true,
                verbosity: "LOUD"
            ),
            anthropicMaxTokens: 0,
            anthropicThinkingResponseReserve: 0,
            anthropicLowThinkingBudget: 1
        ).sanitized

        XCTAssertEqual(settings.openAIChatMaxCompletionTokens, 0)
        XCTAssertEqual(settings.openAIChatSampling.temperature, 2)
        XCTAssertEqual(settings.openAIChatSampling.topP, 0)
        XCTAssertEqual(settings.openAIChatSampling.topLogprobs, 20)
        XCTAssertEqual(settings.openAIChatSampling.verbosity, "medium")
        XCTAssertEqual(settings.anthropicMaxTokens, 1)
        XCTAssertEqual(settings.anthropicThinkingResponseReserve, 1)
        XCTAssertEqual(settings.anthropicLowThinkingBudget, 1024)
    }

    func testModelListResponseDecodesOpenAIAndLMStudioCatalogs() throws {
        let openAIJSON = """
        {
          "object": "list",
          "data": [
            {
              "id": "gpt-test",
              "object": "model",
              "owned_by": "owner",
              "architecture": "transformer"
            }
          ]
        }
        """.data(using: .utf8)!
        let openAI = try JSONDecoder().decode(ModelListResponse.self, from: openAIJSON)
        XCTAssertEqual(openAI.data.map(\.id), ["gpt-test"])
        XCTAssertNil(openAI.data.first?.architecture)

        let lmStudioJSON = """
        {
          "models": [
            {
              "type": "llm",
              "key": "fallback-key",
              "loaded_instances": [{"identifier": "loaded-model"}],
              "capabilities": {
                "supports_image_input": true,
                "input_modalities": ["text", "image"],
                "reasoning": {
                  "options": ["off", "high"],
                  "default": "off"
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let lmStudio = try JSONDecoder().decode(ModelListResponse.self, from: lmStudioJSON)
        let model = try XCTUnwrap(lmStudio.data.first)

        XCTAssertEqual(model.id, "loaded-model")
        XCTAssertEqual(model.input_modalities, ["text", "image"])
        XCTAssertEqual(model.supports_image_input, true)
        let thinkingCapability = try XCTUnwrap(model.thinkingCapabilityHint)
        XCTAssertEqual(thinkingCapability.options, [.off, .high])
        XCTAssertEqual(thinkingCapability.defaultOption, .off)
    }

    func testModelListResponseDecodesOpenRouterReasoningMetadata() throws {
        let openRouterJSON = """
        {
          "data": [
            {
              "id": "openai/gpt-oss-120b:free",
              "supported_parameters": ["reasoning"],
              "reasoning": {
                "mandatory": true,
                "supported_efforts": ["high", "medium", "low"],
                "default_effort": "medium"
              }
            },
            {
              "id": "deepseek/deepseek-v4-pro",
              "supported_parameters": ["reasoning"],
              "reasoning": {
                "mandatory": false,
                "supported_efforts": ["xhigh", "high"],
                "default_effort": "high"
              }
            },
            {
              "id": "openai/gpt-5.5",
              "supported_parameters": ["reasoning"],
              "reasoning": {
                "mandatory": false,
                "default_enabled": false,
                "supported_efforts": ["xhigh", "high", "medium", "low", "none"],
                "default_effort": "medium"
              }
            },
            {
              "id": "openai/gpt-5.6-luna-pro",
              "architecture": {
                "modality": "text+image+file->text",
                "input_modalities": ["file", "image", "text"],
                "output_modalities": ["text"],
                "tokenizer": "GPT",
                "instruct_type": null
              },
              "supported_parameters": ["reasoning", "reasoning_effort"],
              "reasoning": {
                "mandatory": false,
                "default_enabled": true,
                "supported_efforts": ["max", "xhigh", "high", "medium", "low", "none"],
                "default_effort": "medium"
              }
            },
            {
              "id": "tencent/hy3:free",
              "architecture": {
                "modality": "text->text",
                "input_modalities": ["text"],
                "output_modalities": ["text"],
                "tokenizer": "Other",
                "instruct_type": null
              },
              "supported_parameters": ["reasoning"],
              "reasoning": {
                "mandatory": false,
                "default_enabled": false,
                "supported_efforts": ["high", "low", "none"],
                "default_effort": "high"
              }
            },
            {
              "id": "future/reasoner",
              "supported_parameters": ["reasoning"],
              "reasoning": {
                "mandatory": true,
                "supported_efforts": ["turbo"],
                "default_effort": "turbo"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ModelListResponse.self, from: openRouterJSON)
        let gptOSS = try XCTUnwrap(response.data.first { $0.id == "openai/gpt-oss-120b:free" }?.thinkingCapabilityHint)
        XCTAssertEqual(gptOSS.options, [.high, .medium, .low])
        XCTAssertEqual(gptOSS.defaultOption, .medium)
        XCTAssertNil(gptOSS.disabledOption)

        let deepSeek = try XCTUnwrap(response.data.first { $0.id == "deepseek/deepseek-v4-pro" }?.thinkingCapabilityHint)
        XCTAssertEqual(deepSeek.options, [.off, .xhigh, .high])
        XCTAssertEqual(deepSeek.defaultOption, .high)
        XCTAssertEqual(deepSeek.disabledOption, .off)

        let gpt55 = try XCTUnwrap(response.data.first { $0.id == "openai/gpt-5.5" }?.thinkingCapabilityHint)
        XCTAssertEqual(gpt55.options, [.off, .xhigh, .high, .medium, .low])
        XCTAssertEqual(gpt55.options.filter(\.isDisabled).count, 1)
        XCTAssertEqual(gpt55.defaultOption, .off)
        XCTAssertEqual(gpt55.disabledOption, .off)

        let gpt56Model = try XCTUnwrap(response.data.first { $0.id == "openai/gpt-5.6-luna-pro" })
        XCTAssertEqual(gpt56Model.architecture?.input_modalities, ["file", "image", "text"])
        XCTAssertEqual(gpt56Model.supportsImageInputHint, true)
        let gpt56 = try XCTUnwrap(gpt56Model.thinkingCapabilityHint)
        XCTAssertEqual(gpt56.options, [.off, .max, .xhigh, .high, .medium, .low])
        XCTAssertEqual(gpt56.defaultOption, .medium)

        let hy3 = try XCTUnwrap(response.data.first { $0.id == "tencent/hy3:free" })
        XCTAssertEqual(hy3.architecture?.input_modalities, ["text"])
        XCTAssertEqual(hy3.supportsImageInputHint, false)

        let future = try XCTUnwrap(response.data.first { $0.id == "future/reasoner" }?.thinkingCapabilityHint)
        XCTAssertEqual(future.options.map(\.rawValue), ["turbo"])
        XCTAssertEqual(future.defaultOption?.rawValue, "turbo")
        XCTAssertEqual(future.defaultOption?.displayName, "turbo")
    }

    func testOpenAICompatibleReasoningParameterDoesNotRequireOfficialOpenAIProvider() throws {
        let model = ModelInfo(
            id: "third-party/reasoner",
            object: "model",
            created: nil,
            owned_by: nil,
            type: nil,
            arch: nil,
            input_modalities: nil,
            modalities: nil,
            vision: nil,
            multimodal: nil,
            supports_vision: nil,
            supports_image_input: nil,
            capabilities: nil,
            details: nil,
            model_info: nil,
            reasoning: nil,
            supported_parameters: ["reasoning"]
        )

        let compatible = try XCTUnwrap(model.thinkingCapabilityHint(
            provider: .unknown,
            requestStyle: .openAIResponses
        ))
        XCTAssertEqual(compatible.options, [.off, .minimal, .low, .medium, .high, .xhigh])
        XCTAssertEqual(compatible.requestParameter, .reasoning)

        let anthropic = model.thinkingCapabilityHint(
            provider: .anthropic,
            requestStyle: .anthropicMessages
        )
        XCTAssertEqual(anthropic?.options, [.off, .on])
    }

    func testModelCatalogFetchCoordinatorBuildsForcedProviderCandidates() {
        let coordinator = ModelCatalogFetchCoordinator()

        let candidates = coordinator.modelDetectionCandidates(
            for: "http://localhost:1234",
            formatPreference: .lmStudio,
            detectedProvider: .openAI
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.provider, .lmStudio)
        XCTAssertEqual(candidates.first?.style, .lmStudioRESTV1)
    }

    func testModelCatalogAutoDetectionKeepsOpenRouterChatCompletionsFallback() {
        let coordinator = ModelCatalogFetchCoordinator()

        let candidates = coordinator.modelDetectionCandidates(
            for: "https://openrouter.ai/api/v1",
            formatPreference: .automatic,
            detectedProvider: nil
        )

        XCTAssertEqual(candidates.first?.provider, .openAI)
        XCTAssertEqual(candidates.first?.style, .openAIResponses)
        XCTAssertEqual(candidates.first?.chatURL.absoluteString, "https://openrouter.ai/api/v1/responses")
        XCTAssertTrue(candidates.contains {
            $0.provider == .openAI &&
            $0.style == .openAIChatCompletions &&
            $0.chatURL.absoluteString == "https://openrouter.ai/api/v1/chat/completions"
        })
        XCTAssertFalse(candidates.contains { $0.provider == .anthropic })
    }

    func testModelCatalogFetchCoordinatorFallsBackAndProjectsModelHints() async throws {
        let failingEndpoint = ChatAPIEndpointCandidate(
            provider: .openAI,
            style: .openAIChatCompletions,
            chatURL: try XCTUnwrap(URL(string: "https://example.invalid/v1/chat/completions")),
            modelsURL: try XCTUnwrap(URL(string: "https://example.invalid/v1/models"))
        )
        let workingEndpoint = ChatAPIEndpointCandidate(
            provider: .lmStudio,
            style: .lmStudioRESTV1,
            chatURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/chat")),
            modelsURL: try XCTUnwrap(URL(string: "http://localhost:1234/api/v1/models"))
        )
        let model = modelInfo(id: "vision-model", supportsImageInput: true)
        let service = StubModelCatalogService(responses: [
            failingEndpoint.modelsURL: .failure(StubModelCatalogError.unavailable),
            workingEndpoint.modelsURL: .success([model])
        ])

        let result = try await ModelCatalogFetchCoordinator(modelCatalogService: service).fetchFirstAvailableCatalog(
            from: [failingEndpoint, workingEndpoint],
            apiKey: "sk-test",
            initialRetryPolicy: noRetryPolicy(),
            probeRetryPolicy: noRetryPolicy(),
            onRetry: nil
        )

        XCTAssertEqual(service.requestedModelURLs, [failingEndpoint.modelsURL, workingEndpoint.modelsURL])
        XCTAssertEqual(result.endpoint, workingEndpoint)
        XCTAssertEqual(result.modelIDs, ["vision-model"])
        XCTAssertEqual(result.imageInputSupportByModelID, ["vision-model": true])
    }

    @MainActor
    func testChatModelCatalogRefreshCoordinatorReturnsProviderHintsAndModelMetadata() async throws {
        let endpoint = try XCTUnwrap(ChatAPIEndpointResolver.endpointCandidate(
            for: "https://example.com",
            formatPreference: .openAIResponses
        ))
        let model = ModelInfo(
            id: "vision-reasoner",
            object: nil,
            created: nil,
            owned_by: nil,
            type: nil,
            arch: nil,
            input_modalities: nil,
            modalities: nil,
            vision: nil,
            multimodal: nil,
            supports_vision: nil,
            supports_image_input: true,
            capabilities: nil,
            details: nil,
            model_info: nil,
            reasoning: nil,
            supported_parameters: ["reasoning_effort"]
        )
        let service = StubModelCatalogService(responses: [
            endpoint.modelsURL: .success([model])
        ])
        let coordinator = ChatModelCatalogRefreshCoordinator(
            modelCatalogFetchCoordinator: ModelCatalogFetchCoordinator(modelCatalogService: service)
        )

        let refreshResult = await coordinator.refresh(
            chatSettings: ChatSettings(apiURL: " https://example.com ", selectedModel: "", apiKey: "sk-test"),
            formatPreference: .openAIResponses,
            detectedProvider: nil
        )
        let result = try XCTUnwrap(refreshResult)

        XCTAssertEqual(service.requestedModelURLs, [endpoint.modelsURL])
        XCTAssertEqual(result.rawBase, "https://example.com")
        XCTAssertEqual(result.endpoint, endpoint)
        XCTAssertEqual(result.modelIDs, ["vision-reasoner"])
        XCTAssertEqual(result.imageInputSupportByModelID, ["vision-reasoner": true])
        XCTAssertEqual(result.thinkingCapabilitiesByModelID["vision-reasoner"]?.requestParameter, .reasoningEffort)
    }

    func testTTSConfigurationResolverBuildsStableConfiguration() throws {
        let resolver = TTSConfigurationResolver(mediaType: "wav")
        XCTAssertEqual(
            resolver.constructTTSURL(from: "localhost:9880/api")?.absoluteString,
            "http://localhost:9880/api/tts"
        )

        let batchConfig = try XCTUnwrap(resolver.makeConfiguration(
            snapshot: TTSSettingsSnapshot(
                serverAddress: "localhost:9880",
                textLanguage: "auto",
                autoSplit: "cut5",
                enableStreaming: false,
                referenceAudioPath: "/tmp/ref.wav",
                promptText: "hello",
                promptLanguage: "zh"
            ),
            isRealtime: false
        ))
        XCTAssertEqual(batchConfig.url.absoluteString, "http://localhost:9880/tts")
        XCTAssertEqual(batchConfig.referenceAudioPath, "/tmp/ref.wav")
        XCTAssertEqual(batchConfig.promptText, "hello")
        XCTAssertEqual(batchConfig.promptLanguage, "zh")
        XCTAssertEqual(batchConfig.textSplitMethod, "cut5")
        XCTAssertFalse(batchConfig.usesStreamingSegments)

        let realtimeConfig = try XCTUnwrap(resolver.makeConfiguration(
            snapshot: TTSSettingsSnapshot(
                serverAddress: "http://localhost:9880/",
                textLanguage: "auto",
                autoSplit: "cut5",
                enableStreaming: false,
                referenceAudioPath: "",
                promptText: "",
                promptLanguage: "auto"
            ),
            isRealtime: true
        ))
        XCTAssertEqual(realtimeConfig.textSplitMethod, "cut0")
    }

    func testTTSConfigurationResolverHandlesInvalidInputAndStreamingMode() throws {
        let resolver = TTSConfigurationResolver(mediaType: "mp3")

        XCTAssertNil(resolver.constructTTSURL(from: "   "))
        XCTAssertEqual(
            resolver.constructTTSURL(from: "https://voice.example.com/base/")?.absoluteString,
            "https://voice.example.com/base/tts"
        )

        let streamingConfig = try XCTUnwrap(resolver.makeConfiguration(
            snapshot: TTSSettingsSnapshot(
                serverAddress: "voice.example.com",
                textLanguage: "en",
                autoSplit: "cut5",
                enableStreaming: true,
                referenceAudioPath: "",
                promptText: "",
                promptLanguage: "auto"
            ),
            isRealtime: false
        ))
        XCTAssertEqual(streamingConfig.url.absoluteString, "http://voice.example.com/tts")
        XCTAssertEqual(streamingConfig.textLanguage, "en")
        XCTAssertEqual(streamingConfig.textSplitMethod, "cut0")
        XCTAssertTrue(streamingConfig.usesStreamingSegments)

        XCTAssertNil(resolver.makeConfiguration(
            snapshot: TTSSettingsSnapshot(
                serverAddress: " ",
                textLanguage: "auto",
                autoSplit: "cut5",
                enableStreaming: false,
                referenceAudioPath: "",
                promptText: "",
                promptLanguage: "auto"
            ),
            isRealtime: false
        ))
    }

    func testTTSPresetApplyServiceBuildsWeightEndpointURLs() throws {
        let request = TTSPresetApplyRequest(
            serverAddress: " localhost:9880/api/ ",
            gptWeightsPath: "/models/gpt.ckpt",
            sovitsWeightsPath: "sovits weights.pth"
        )
        let service = TTSPresetApplyService()

        let gptURL = try XCTUnwrap(service.endpointURL(for: request, stage: .gptWeights))
        let gptComponents = try XCTUnwrap(URLComponents(url: gptURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(gptComponents.scheme, "http")
        XCTAssertEqual(gptComponents.host, "localhost")
        XCTAssertEqual(gptComponents.port, 9880)
        XCTAssertEqual(gptComponents.path, "/api/set_gpt_weights")
        XCTAssertEqual(gptComponents.queryItems, [
            URLQueryItem(name: "weights_path", value: "/models/gpt.ckpt")
        ])

        let sovitsURL = try XCTUnwrap(service.endpointURL(for: request, stage: .sovitsWeights))
        let sovitsComponents = try XCTUnwrap(URLComponents(url: sovitsURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(sovitsComponents.path, "/api/set_sovits_weights")
        XCTAssertEqual(sovitsComponents.queryItems, [
            URLQueryItem(name: "weights_path", value: "sovits weights.pth")
        ])

        XCTAssertNil(TTSPresetApplyService.endpointURL(
            serverAddress: " ",
            endpointPath: "/set_gpt_weights",
            weightsPath: "gpt.ckpt"
        ))
    }

    func testTTSPresetApplyServiceMapsRetryStatusAndFailureMessages() {
        let retryStatus = TTSPresetApplyRetryStatus(nextAttempt: 3, errorDescription: "timeout")
        XCTAssertEqual(retryStatus.retryAttempt, 2)
        XCTAssertEqual(retryStatus.lastErrorDescription, "timeout")

        XCTAssertEqual(
            TTSPresetApplyError.invalidServerAddress(stage: .gptWeights).settingsMessage,
            NSLocalizedString(
                "Invalid server address for GPT weights",
                comment: "Shown when the GPT weights endpoint cannot be constructed"
            )
        )
        XCTAssertEqual(
            TTSPresetApplyError.invalidServerAddress(stage: .sovitsWeights).settingsMessage,
            NSLocalizedString(
                "Invalid server address for SoVITS weights",
                comment: "Shown when the SoVITS weights endpoint cannot be constructed"
            )
        )
        XCTAssertEqual(
            TTSPresetApplyError.requestFailed(
                stage: .sovitsWeights,
                statusCode: 503,
                errorDescription: "HTTP 503"
            ).settingsMessage,
            String(
                format: NSLocalizedString(
                    "Set SoVITS weights failed (HTTP %d)",
                    comment: "Shown when setting SoVITS weights fails with an HTTP status."
                ),
                503
            )
        )
        XCTAssertEqual(
            TTSPresetApplyError.requestFailed(
                stage: .gptWeights,
                statusCode: nil,
                errorDescription: "offline"
            ).settingsMessage,
            String(
                format: NSLocalizedString(
                    "Set GPT weights failed: %@",
                    comment: "Shown when setting GPT weights fails with an error."
                ),
                "offline"
            )
        )
    }

    func testChatTurnDraftPlannerAcceptsSupportedImageDrafts() throws {
        let editID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000044"))
        let attachment = ChatImageAttachment(mimeType: "image/png", data: Data([1, 2, 3]))
        let draft = QueuedChatDraft(
            text: " hello\n",
            imageAttachments: [attachment],
            editingBaseMessageID: editID
        )

        let result = ChatTurnDraftPlanner.plan(
            draft: draft,
            hasActiveTextRequest: false,
            supportsImageInputs: true,
            hasImageInputContext: true,
            ignoringUnsupportedImageInputs: false,
            clearComposerAfterSend: true
        )

        guard case let .accepted(plan) = result else {
            return XCTFail("Expected the supported image draft to be accepted")
        }
        XCTAssertEqual(plan.text, "hello")
        XCTAssertEqual(plan.imageAttachments, [attachment])
        XCTAssertEqual(plan.editingBaseMessageID, editID)
        XCTAssertTrue(plan.clearComposerAfterSend)
    }

    func testChatTurnDraftPlannerRejectsUnsupportedImagesUnlessSendingTextOnly() {
        let attachment = ChatImageAttachment(mimeType: "image/png", data: Data([1, 2, 3]))
        let imageOnlyDraft = QueuedChatDraft(text: " ", imageAttachments: [attachment])

        XCTAssertEqual(
            ChatTurnDraftPlanner.plan(
                draft: imageOnlyDraft,
                hasActiveTextRequest: false,
                supportsImageInputs: false,
                hasImageInputContext: true,
                ignoringUnsupportedImageInputs: false,
                clearComposerAfterSend: false
            ),
            .rejected(.unsupportedImageInputContext)
        )
        XCTAssertEqual(
            ChatTurnDraftPlanner.plan(
                draft: imageOnlyDraft,
                hasActiveTextRequest: false,
                supportsImageInputs: false,
                hasImageInputContext: true,
                ignoringUnsupportedImageInputs: true,
                clearComposerAfterSend: false
            ),
            .rejected(.emptyAfterFilteringUnsupportedImages)
        )

        XCTAssertEqual(
            ChatTurnDraftPlanner.plan(
                draft: QueuedChatDraft(text: "follow-up"),
                hasActiveTextRequest: false,
                supportsImageInputs: false,
                hasImageInputContext: true,
                ignoringUnsupportedImageInputs: false,
                clearComposerAfterSend: false
            ),
            .rejected(.unsupportedImageInputContext)
        )

        let textAndImageDraft = QueuedChatDraft(text: " keep text ", imageAttachments: [attachment])
        let ignoredResult = ChatTurnDraftPlanner.plan(
            draft: textAndImageDraft,
            hasActiveTextRequest: false,
            supportsImageInputs: false,
            hasImageInputContext: true,
            ignoringUnsupportedImageInputs: true,
            clearComposerAfterSend: false
        )

        guard case let .accepted(plan) = ignoredResult else {
            return XCTFail("Expected confirmed unsupported images to send as text-only")
        }
        XCTAssertEqual(plan.text, "keep text")
        XCTAssertTrue(plan.imageAttachments.isEmpty)
        XCTAssertFalse(plan.clearComposerAfterSend)
    }

    func testChatTurnDraftPlannerRejectsEmptyOrActiveRequests() {
        XCTAssertEqual(
            ChatTurnDraftPlanner.plan(
                draft: QueuedChatDraft(text: " "),
                hasActiveTextRequest: false,
                supportsImageInputs: true,
                hasImageInputContext: false,
                ignoringUnsupportedImageInputs: false,
                clearComposerAfterSend: true
            ),
            .rejected(.emptyDraft)
        )
        XCTAssertEqual(
            ChatTurnDraftPlanner.plan(
                draft: QueuedChatDraft(text: "hello"),
                hasActiveTextRequest: true,
                supportsImageInputs: true,
                hasImageInputContext: false,
                ignoringUnsupportedImageInputs: false,
                clearComposerAfterSend: true
            ),
            .rejected(.activeTextRequest)
        )
    }

    func testChatStreamRetryCoordinatorClassifiesRetryableErrors() {
        let coordinator = ChatStreamRetryCoordinator(retryPolicy: NetworkRetryPolicy(
            maxAttempts: 2,
            baseDelay: 0,
            maxDelay: 0,
            backoffFactor: 1,
            jitterRatio: 0
        ))

        XCTAssertTrue(coordinator.shouldAutoRetry(
            after: ChatNetworkError.timeout("slow"),
            currentAttempt: 0
        ))
        XCTAssertFalse(coordinator.shouldAutoRetry(
            after: ChatNetworkError.timeout("slow"),
            currentAttempt: 1
        ))
        XCTAssertFalse(coordinator.shouldAutoRetry(
            after: ChatNetworkError.invalidURL,
            currentAttempt: 0
        ))
        XCTAssertFalse(coordinator.shouldAutoRetry(
            after: ChatNetworkError.invalidRequestHistory,
            currentAttempt: 0
        ))
        XCTAssertFalse(coordinator.shouldAutoRetry(
            after: ChatNetworkError.emptyResponse,
            currentAttempt: 0
        ))
        XCTAssertTrue(coordinator.shouldAutoRetry(
            after: ChatNetworkError.serverError(statusCode: 503, message: "busy"),
            currentAttempt: 0
        ))
        XCTAssertTrue(coordinator.shouldAutoRetry(
            after: ChatNetworkError.serverError(statusCode: 429, message: "rate limited"),
            currentAttempt: 0
        ))
        XCTAssertTrue(coordinator.shouldAutoRetry(
            after: ChatNetworkError.serverError(statusCode: 529, message: "overloaded"),
            currentAttempt: 0
        ))
        XCTAssertFalse(coordinator.shouldAutoRetry(
            after: ChatNetworkError.serverError(statusCode: 400, message: "bad request"),
            currentAttempt: 0
        ))
        XCTAssertFalse(coordinator.shouldAutoRetry(
            after: ChatNetworkError.serverError(statusCode: 401, message: "unauthorized"),
            currentAttempt: 0
        ))
        XCTAssertFalse(coordinator.shouldAutoRetry(
            after: ChatNetworkError.serverError(statusCode: 403, message: "forbidden"),
            currentAttempt: 0
        ))
        XCTAssertFalse(coordinator.shouldAutoRetry(
            after: ChatNetworkError.serverError(statusCode: nil, message: "unknown"),
            currentAttempt: 0
        ))
        XCTAssertTrue(coordinator.shouldAutoRetry(
            after: URLError(.networkConnectionLost),
            currentAttempt: 0
        ))
        XCTAssertFalse(coordinator.shouldAutoRetry(
            after: URLError(.cancelled),
            currentAttempt: 0
        ))
    }

    func testChatStreamRetryCoordinatorPlansAttemptsAndClearsProgress() {
        let coordinator = ChatStreamRetryCoordinator(retryPolicy: NetworkRetryPolicy(
            maxAttempts: 3,
            baseDelay: 0,
            maxDelay: 0,
            backoffFactor: 1,
            jitterRatio: 0
        ))

        let first = coordinator.planRetry(
            after: ChatNetworkError.timeout("slow"),
            errorText: "",
            currentState: ChatStreamRetryState(),
            hasAssistantMessage: false
        )

        XCTAssertEqual(first.state, ChatStreamRetryState(
            isRetrying: true,
            retryAttempt: 1,
            retryLastError: "slow"
        ))
        XCTAssertEqual(first.delay, 0)
        XCTAssertTrue(first.shouldPrime)

        let second = coordinator.planRetry(
            after: ChatNetworkError.serverError(statusCode: 503, message: "busy"),
            errorText: "network down",
            currentState: first.state,
            hasAssistantMessage: true
        )

        XCTAssertEqual(second.state, ChatStreamRetryState(
            isRetrying: true,
            retryAttempt: 2,
            retryLastError: "network down"
        ))
        XCTAssertEqual(second.delay, 0)
        XCTAssertFalse(second.shouldPrime)
        XCTAssertEqual(
            coordinator.clearedAfterProgress(from: second.state),
            ChatStreamRetryState(isRetrying: false, retryAttempt: 2, retryLastError: nil)
        )

        let idleState = ChatStreamRetryState(
            isRetrying: false,
            retryAttempt: 2,
            retryLastError: "left alone"
        )
        XCTAssertEqual(coordinator.clearedAfterProgress(from: idleState), idleState)
    }

    @MainActor
    func testChatAutoRetryCoordinatorPlansAndClearsState() {
        let coordinator = ChatAutoRetryCoordinator(streamRetryCoordinator: ChatStreamRetryCoordinator(
            retryPolicy: NetworkRetryPolicy(
                maxAttempts: 3,
                baseDelay: 0,
                maxDelay: 0,
                backoffFactor: 1,
                jitterRatio: 0
            )
        ))

        XCTAssertTrue(coordinator.shouldAutoRetry(
            after: ChatNetworkError.timeout("slow"),
            currentAttempt: 0
        ))

        let plan = coordinator.planRetry(
            after: ChatNetworkError.timeout("slow"),
            errorText: "network stalled",
            currentState: ChatStreamRetryState(),
            hasAssistantMessage: false
        )
        XCTAssertEqual(plan.state, ChatStreamRetryState(
            isRetrying: true,
            retryAttempt: 1,
            retryLastError: "network stalled"
        ))
        XCTAssertEqual(plan.delay, 0)
        XCTAssertEqual(
            coordinator.clearRetryStateAfterProgress(plan.state),
            ChatStreamRetryState(isRetrying: false, retryAttempt: 1, retryLastError: nil)
        )
    }

    func testQueuedDraftEditCoordinatorRestoresDraftPosition() throws {
        let middleID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        var drafts = [
            QueuedChatDraft(id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")), text: "first"),
            QueuedChatDraft(id: middleID, text: "second"),
            QueuedChatDraft(id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003")), text: "third")
        ]
        var coordinator = QueuedDraftEditCoordinator()

        let edited = try XCTUnwrap(coordinator.beginEditing(id: middleID, in: &drafts))
        XCTAssertEqual(edited.text, "second")
        XCTAssertEqual(drafts.map(\.text), ["first", "third"])

        let replacement = QueuedChatDraft(text: "second revised")
        XCTAssertTrue(coordinator.commitEditedDraft(replacement, into: &drafts))

        XCTAssertEqual(drafts.map(\.text), ["first", "second revised", "third"])
        XCTAssertEqual(drafts[1].id, middleID)
    }

    func testQueuedDraftEditCoordinatorRestoresAfterNeighborRemovalAndClearsState() throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000011"))
        let secondID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000012"))
        let thirdID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000013"))
        var drafts = [
            QueuedChatDraft(id: firstID, text: "first"),
            QueuedChatDraft(id: secondID, text: "second"),
            QueuedChatDraft(id: thirdID, text: "third")
        ]
        var coordinator = QueuedDraftEditCoordinator()

        XCTAssertNotNil(coordinator.beginEditing(id: secondID, in: &drafts))
        XCTAssertTrue(coordinator.isEditing)
        drafts.removeAll { $0.id == thirdID }

        XCTAssertTrue(coordinator.restoreEditedDraft(into: &drafts))
        XCTAssertEqual(drafts.map(\.text), ["first", "second"])
        XCTAssertFalse(coordinator.isEditing)

        XCTAssertNotNil(coordinator.beginEditing(id: firstID, in: &drafts))
        coordinator.clear()
        XCTAssertFalse(coordinator.isEditing)
        XCTAssertFalse(coordinator.commitEditedDraft(QueuedChatDraft(text: "ignored"), into: &drafts))
        XCTAssertEqual(drafts.map(\.text), ["second"])
    }
}
