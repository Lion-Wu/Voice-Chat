import XCTest
@testable import Voice_Chat

final class ChatViewStateSeamTests: XCTestCase {
    @MainActor
    func testComposerTextStateSeparatesNativeEditsFromExternalReplacements() {
        let state = ChatComposerTextState()

        state.updateFromEditor("ni hao")

        XCTAssertEqual(state.text, "ni hao")
        XCTAssertEqual(state.externalRevision, 0)

        state.replaceText("loaded draft")

        XCTAssertEqual(state.text, "loaded draft")
        XCTAssertEqual(state.externalRevision, 1)

        state.updateFromEditor("loaded draft edited")

        XCTAssertEqual(state.text, "loaded draft edited")
        XCTAssertEqual(state.externalRevision, 1)

        state.replaceText("")

        XCTAssertEqual(state.text, "")
        XCTAssertEqual(state.externalRevision, 2)
    }

    func testChatImageAttachmentImporterNormalizesAndSniffsMIMETypes() {
        XCTAssertEqual(
            ChatImageAttachmentImporter.canonicalImageMIMEType(" image/jpg; charset=utf-8 "),
            "image/jpeg"
        )
        XCTAssertEqual(ChatImageAttachmentImporter.canonicalImageMIMEType(""), "image/jpeg")
        XCTAssertEqual(ChatImageAttachmentImporter.sniffedImageMIMEType(from: Data([0xFF, 0xD8, 0xFF])), "image/jpeg")
        XCTAssertEqual(ChatImageAttachmentImporter.sniffedImageMIMEType(from: Data([0x89, 0x50, 0x4E, 0x47])), "image/png")
        XCTAssertEqual(ChatImageAttachmentImporter.sniffedImageMIMEType(from: Data([0x47, 0x49, 0x46, 0x38])), "image/gif")

        var webPHeader = Data("RIFF".utf8)
        webPHeader.append(contentsOf: [0, 0, 0, 0])
        webPHeader.append(contentsOf: Data("WEBP".utf8))
        XCTAssertEqual(ChatImageAttachmentImporter.sniffedImageMIMEType(from: webPHeader), "image/webp")
    }

    func testChatImageAttachmentImporterBuildsJPEGAttachmentWithoutTranscoding() throws {
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

        let attachment = try XCTUnwrap(ChatImageAttachmentImporter.makeImageAttachment(
            data: jpegData,
            mimeTypeHint: "image/jpg"
        ))

        XCTAssertEqual(attachment.mimeType, "image/jpeg")
        XCTAssertEqual(attachment.data, jpegData)
    }

    func testChatImageAttachmentImporterRejectsNonImageFileURL() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-chat-nonimage-\(UUID().uuidString)")
            .appendingPathExtension("txt")
        try Data("not image".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertNil(ChatImageAttachmentImporter.loadImageAttachment(fromFileURL: fileURL))
    }

    func testChatImageAttachmentImporterKeepsPayloadLimit() async {
        let payloads = [
            ChatImageImportPayload(data: Data([0xFF, 0xD8, 0xFF, 0xE0]), mimeType: "image/jpeg"),
            ChatImageImportPayload(data: Data([0xFF, 0xD8, 0xFF, 0xE1]), mimeType: "image/jpeg")
        ]

        let attachments = await ChatImageAttachmentImporter.loadImageAttachments(from: payloads, limit: 1)

        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments.first?.data, payloads.first?.data)
    }

    func testChatImageAttachmentImportCoordinatorComputesCapacityDecisions() {
        XCTAssertEqual(
            ChatImageAttachmentImportCoordinator.remainingSlots(currentCount: 2, maximumAttachmentCount: 4),
            2
        )
        XCTAssertEqual(
            ChatImageAttachmentImportCoordinator.remainingSlots(currentCount: 7, maximumAttachmentCount: 4),
            0
        )
        XCTAssertEqual(
            ChatImageAttachmentImportCoordinator.limitDecision(
                requestedCount: 3,
                currentCount: 1,
                maximumAttachmentCount: 4
            ),
            .accepted(limit: 3, didOverflow: false)
        )
        XCTAssertEqual(
            ChatImageAttachmentImportCoordinator.limitDecision(
                requestedCount: 4,
                currentCount: 2,
                maximumAttachmentCount: 4
            ),
            .accepted(limit: 2, didOverflow: true)
        )
        XCTAssertEqual(
            ChatImageAttachmentImportCoordinator.limitDecision(
                requestedCount: 1,
                currentCount: 4,
                maximumAttachmentCount: 4
            ),
            .rejected
        )
    }

    func testChatImageAttachmentImportCoordinatorTracksPhotoImportLifecycle() {
        var coordinator = ChatImageAttachmentImportCoordinator()
        let firstID = uuid(31)
        let secondID = uuid(32)
        let firstTask = sleepingTask()
        let secondTask = sleepingTask()
        defer { coordinator.cancelAll() }

        XCTAssertEqual(
            coordinator.beginImport(source: .photoPicker, cancelsEarlierPhotoImports: false) { firstID },
            firstID
        )
        coordinator.registerTask(firstTask, id: firstID)
        XCTAssertEqual(coordinator.activePhotoImportID, firstID)
        XCTAssertEqual(coordinator.tasks.count, 1)

        XCTAssertEqual(
            coordinator.beginImport(source: .photoPicker, cancelsEarlierPhotoImports: true) { secondID },
            secondID
        )
        coordinator.registerTask(secondTask, id: secondID)

        XCTAssertTrue(firstTask.isCancelled)
        XCTAssertEqual(coordinator.activePhotoImportID, secondID)
        XCTAssertEqual(coordinator.tasks.count, 1)
        XCTAssertEqual(coordinator.completeImport(id: firstID, source: .photoPicker), .stale)
        XCTAssertEqual(coordinator.completeImport(id: secondID, source: .photoPicker), .apply(clearPhotoSelection: true))
        XCTAssertNil(coordinator.activePhotoImportID)
        XCTAssertTrue(coordinator.tasks.isEmpty)
    }

    func testChatImageAttachmentImportCoordinatorClearsActivePhotoImportAsStale() {
        var coordinator = ChatImageAttachmentImportCoordinator()
        let importID = uuid(33)
        let task = sleepingTask()
        defer { coordinator.cancelAll() }

        _ = coordinator.beginImport(source: .photoPicker, cancelsEarlierPhotoImports: false) { importID }
        coordinator.registerTask(task, id: importID)
        coordinator.clearActivePhotoImport()

        XCTAssertNil(coordinator.activePhotoImportID)
        XCTAssertEqual(coordinator.completeImport(id: importID, source: .photoPicker), .stale)
        XCTAssertTrue(coordinator.tasks.isEmpty)
    }

    func testChatSearchScrollCoordinatorResolvesVisibleTarget() throws {
        let sessionID = UUID()
        let messageID = UUID()
        let target = ChatSearchNavigationTarget(
            sessionID: sessionID,
            messageID: messageID,
            query: "needle",
            anchorY: 0.82
        )

        let decision = try XCTUnwrap(ChatSearchScrollCoordinator.resolveScrollTarget(
            pending: target,
            sessionID: sessionID,
            visibleMessages: [
                ChatSearchScrollMessageSnapshot(id: messageID, searchText: "visible message")
            ]
        ))

        XCTAssertEqual(decision.targetID, target.id)
        XCTAssertEqual(decision.messageID, messageID)
        XCTAssertEqual(decision.anchorY, 0.82)
    }

    func testChatSearchScrollCoordinatorFallsBackToVisibleSearchBody() throws {
        let sessionID = uuid(1)
        let missingMessageID = uuid(2)
        let fallbackMessageID = uuid(3)
        let target = ChatSearchNavigationTarget(
            sessionID: sessionID,
            messageID: missingMessageID,
            query: "needle",
            anchorY: 0.9
        )

        let decision = try XCTUnwrap(ChatSearchScrollCoordinator.resolveScrollTarget(
            pending: target,
            sessionID: sessionID,
            visibleMessages: [
                ChatSearchScrollMessageSnapshot(id: uuid(4), searchText: "message without the query"),
                ChatSearchScrollMessageSnapshot(id: fallbackMessageID, searchText: "intro\nNeedle here\nthird\nfourth")
            ]
        ))

        XCTAssertEqual(decision.targetID, target.id)
        XCTAssertEqual(decision.messageID, fallbackMessageID)
        XCTAssertEqual(decision.anchorY, 0.375, accuracy: 0.0001)
    }

    @MainActor
    func testVisibleSearchTextUsesStructuredAssistantSegments() {
        let message = chatMessage(content: "", isUser: false)
        message.appendAssistantSegment(.reasoning(id: nil, text: "hidden reasoning"))
        message.appendAssistantSegment(.text(id: nil, text: "visible answer"))

        XCTAssertEqual(ChatView.visibleSearchText(for: message), "visible answer")
    }

    func testChatScrollInteractionStateSchedulesAndClearsNavigation() {
        let sessionID = UUID()
        let messageID = UUID()
        let target = ChatSearchNavigationTarget(
            sessionID: sessionID,
            messageID: messageID,
            query: "needle",
            anchorY: 0.4
        )
        var state = ChatScrollInteractionState()

        XCTAssertTrue(state.scheduleSearchNavigationIfNeeded(target, sessionID: sessionID))
        XCTAssertEqual(state.pendingSearchScrollTarget?.id, target.id)
        XCTAssertEqual(state.highlightQuery(for: messageID, currentTarget: target), "needle")
        XCTAssertTrue(state.hasSearchInterruption(currentTarget: nil))

        XCTAssertFalse(state.scheduleSearchNavigationIfNeeded(target, sessionID: UUID()))
        XCTAssertNil(state.pendingSearchScrollTarget)
        XCTAssertNil(state.activeSearchHighlightMessageID)
        XCTAssertNil(state.activeSearchHighlightTargetID)
        XCTAssertFalse(state.hasSearchInterruption(currentTarget: nil))
    }

    func testChatScrollInteractionStateAppliesDecisionAndClearsForSend() {
        let sessionID = UUID()
        let messageID = UUID()
        let target = ChatSearchNavigationTarget(
            sessionID: sessionID,
            messageID: messageID,
            query: "needle",
            anchorY: 0.4
        )
        var state = ChatScrollInteractionState()
        _ = state.scheduleSearchNavigationIfNeeded(target, sessionID: sessionID)

        state.applySearchScrollDecision(ChatSearchScrollDecision(
            targetID: target.id,
            messageID: messageID,
            anchorY: 0.7
        ))

        XCTAssertNil(state.pendingSearchScrollTarget)
        XCTAssertEqual(state.activeSearchHighlightMessageID, messageID)
        XCTAssertEqual(state.activeSearchHighlightTargetID, target.id)
        state.prepareScrollToBottomAfterSend()

        XCTAssertNil(state.pendingSearchScrollTarget)
        XCTAssertEqual(state.activeSearchHighlightTargetID, target.id)
    }

    func testChatVisibleMessagesCoordinatorTruncatesAtEditingBaseMessage() throws {
        let first = chatMessage(content: "first")
        let editingBase = chatMessage(content: "editing base")
        let hiddenAfterBase = chatMessage(content: "hidden")

        let visible = ChatVisibleMessagesCoordinator.visibleMessages(
            from: [first, editingBase, hiddenAfterBase],
            editingBaseMessageID: editingBase.id
        )

        XCTAssertEqual(visible.map(\.id), [first.id])
        XCTAssertEqual(ChatVisibleMessagesCoordinator.visibleMessages(
            from: [first, editingBase],
            editingBaseMessageID: UUID()
        ).map(\.id), [first.id, editingBase.id])
    }

    func testChatVisibleMessagesCoordinatorPlansAndMergesFingerprints() {
        let first = chatMessage(content: "first")
        let second = chatMessage(content: "second")
        let staleID = UUID()
        let firstFingerprint = ContentFingerprint.make("first")
        let staleFingerprint = ContentFingerprint.make("stale")
        let cache = [
            first.id: firstFingerprint,
            staleID: staleFingerprint
        ]

        let plan = ChatVisibleMessagesCoordinator.fingerprintPlan(
            for: [first, second],
            cache: cache
        )

        XCTAssertEqual(plan.visibleIDs, Set([first.id, second.id]))
        XCTAssertEqual(plan.missingSnapshots.map { $0.0 }, [second.id])

        let merged = ChatVisibleMessagesCoordinator.fingerprintsByAddingMissing(
            [second.id: ContentFingerprint.make("second")],
            to: cache,
            keepingOnly: plan.visibleIDs
        )

        XCTAssertEqual(merged[first.id], firstFingerprint)
        XCTAssertEqual(merged[second.id], ContentFingerprint.make("second"))
        XCTAssertNil(merged[staleID])
    }

    func testChatVisibleMessagesCoordinatorPrefersLiveFingerprintUpdatesAndReportsSessionChanges() {
        let messageID = UUID()
        let computed = [messageID: ContentFingerprint.make("old")]
        let live = [messageID: ContentFingerprint.make("new")]

        XCTAssertEqual(
            ChatVisibleMessagesCoordinator.fingerprintsByMergingComputed(computed, liveUpdates: live)[messageID],
            ContentFingerprint.make("new")
        )

        let sessionID = UUID()
        XCTAssertFalse(ChatVisibleMessagesCoordinator.shouldReportVisibleCount(
            targetCount: 2,
            sessionID: sessionID,
            lastReportedVisibleCount: 2,
            lastReportedSessionID: sessionID
        ))
        XCTAssertTrue(ChatVisibleMessagesCoordinator.shouldReportVisibleCount(
            targetCount: 2,
            sessionID: UUID(),
            lastReportedVisibleCount: 2,
            lastReportedSessionID: sessionID
        ))
        XCTAssertTrue(ChatVisibleMessagesCoordinator.shouldReportVisibleCount(
            targetCount: 3,
            sessionID: sessionID,
            lastReportedVisibleCount: 2,
            lastReportedSessionID: sessionID
        ))
    }

    func testChatVisibleMessageHydrationStateClearsDefersAndConsumesRefreshes() {
        let message = chatMessage(content: "hydrated")
        var state = ChatVisibleMessageHydrationState()
        state.visibleMessages = [message]
        state.fingerprintCache = [message.id: ContentFingerprint.make(message.content)]

        let token = state.nextRefreshToken()
        state.beginHydration(token: token)

        XCTAssertTrue(state.isHydrating)
        XCTAssertTrue(state.visibleMessages.isEmpty)
        XCTAssertTrue(state.fingerprintCache.isEmpty)
        XCTAssertTrue(state.shouldApply(token: token))
        XCTAssertTrue(state.deferRefreshIfHydrating())

        state.appendHydratedMessages([message])
        XCTAssertEqual(state.visibleMessages.map(\.id), [message.id])

        XCTAssertTrue(state.finishHydration(token: token))
        XCTAssertFalse(state.isHydrating)
        XCTAssertTrue(state.consumePendingRefreshAfterHydration())
        XCTAssertFalse(state.consumePendingRefreshAfterHydration())

        let supersededToken = state.nextRefreshToken()
        state.beginHydration(token: supersededToken)
        XCTAssertTrue(state.deferRefreshIfHydrating())
        let replacementToken = state.nextRefreshToken()
        state.beginHydration(token: replacementToken)
        XCTAssertFalse(state.pendingRefreshAfterHydration)
        XCTAssertFalse(state.finishHydration(token: supersededToken))
        XCTAssertTrue(state.finishHydration(token: replacementToken))

        let cancelledToken = state.nextRefreshToken()
        state.beginHydration(token: cancelledToken)
        state.cancelHydration()
        XCTAssertFalse(state.shouldApply(token: cancelledToken))
    }

    func testChatVisibleMessageHydrationStatePrefersLiveFingerprints() {
        let messageID = UUID()
        var state = ChatVisibleMessageHydrationState()
        state.fingerprintCache = [messageID: ContentFingerprint.make("live")]

        state.applyHydratedFingerprints([messageID: ContentFingerprint.make("computed")])

        XCTAssertEqual(state.fingerprintCache[messageID], ContentFingerprint.make("live"))

        let visible = chatMessage(content: "visible")
        let staleID = UUID()
        state.fingerprintCache[visible.id] = ContentFingerprint.make(visible.content)
        state.fingerprintCache[staleID] = ContentFingerprint.make("stale")

        state.applyVisibleMessagesWithoutMissingFingerprints([visible], visibleIDs: Set([visible.id]))

        XCTAssertEqual(state.visibleMessages.map(\.id), [visible.id])
        XCTAssertNotNil(state.fingerprintCache[visible.id])
        XCTAssertNil(state.fingerprintCache[staleID])
    }

    func testChatVisibleMessageHydrationStateTracksLiveUpdatesAndVisibleCountReports() {
        let messageID = UUID()
        let sessionID = UUID()
        var state = ChatVisibleMessageHydrationState()
        let token = state.nextRefreshToken()
        state.beginHydration(token: token)

        state.applyContentFingerprintUpdate(
            messageID: messageID,
            fingerprint: ContentFingerprint.make("streaming")
        )

        XCTAssertTrue(state.pendingRefreshAfterHydration)
        XCTAssertEqual(state.fingerprintCache[messageID], ContentFingerprint.make("streaming"))

        XCTAssertTrue(state.shouldReportVisibleCount(targetCount: 2, sessionID: sessionID))
        XCTAssertFalse(state.shouldReportVisibleCount(targetCount: 2, sessionID: sessionID))
        XCTAssertTrue(state.shouldReportVisibleCount(targetCount: 3, sessionID: sessionID))
        XCTAssertTrue(state.shouldReportVisibleCount(targetCount: 3, sessionID: UUID()))
    }

    func testChatScrollStateComputesGeometryAndBottomAnchorUse() {
        var state = ChatScrollState()
        state.enqueueMetricUpdate(contentHeight: 220, viewportHeight: 100, bottomAnchorMaxY: 132)
        let update = state.applyPendingMetricUpdate(messageListBottomInset: 40, threshold: 24)
        let metrics = state.metrics(messageListBottomInset: 40, threshold: 24)

        XCTAssertTrue(update.didUpdate)
        XCTAssertTrue(update.didUpdateScrollableGeometry)
        XCTAssertFalse(update.wasPastComposerOverflowThreshold)
        XCTAssertEqual(metrics.effectiveContentHeight, 180)
        XCTAssertEqual(metrics.contentDistanceBelowViewport, 120)
        XCTAssertEqual(metrics.bottomAnchorDistanceBelowViewport, 32)
        XCTAssertTrue(metrics.shouldShowScrollToBottomButton)
        XCTAssertTrue(metrics.shouldTriggerComposerOverflowScroll)
        XCTAssertTrue(metrics.shouldAnchorBottom)
        XCTAssertTrue(state.shouldUseBottomScrollAnchor(messageListBottomInset: 40, threshold: 24))
    }

    func testTransientStatusNeverAttachesToACompletedHistoricalAssistant() {
        let historicalAssistant = chatMessage(content: "Earlier answer", isUser: false)
        historicalAssistant.isActive = false
        let currentUser = chatMessage(content: "New question")

        XCTAssertNil(ChatInlineStatusHostResolver.resolve(
            in: [historicalAssistant, currentUser],
            hasTransientStatus: true
        ))

        let currentAssistant = chatMessage(content: "", isUser: false)
        XCTAssertEqual(
            ChatInlineStatusHostResolver.resolve(
                in: [historicalAssistant, currentUser, currentAssistant],
                hasTransientStatus: true
            ),
            currentAssistant.id
        )
    }

    func testChatMessageListAnimationKeyTracksTopLevelInsertionsAndRemovals() {
        let firstID = UUID()
        let secondID = UUID()
        let initial = ChatMessageListAnimationKey(
            messageIDs: [firstID],
            standaloneStatus: "none"
        )

        XCTAssertNotEqual(
            initial,
            ChatMessageListAnimationKey(
                messageIDs: [firstID, secondID],
                standaloneStatus: "none"
            )
        )
        XCTAssertNotEqual(
            initial,
            ChatMessageListAnimationKey(
                messageIDs: [],
                standaloneStatus: "none"
            )
        )
        XCTAssertNotEqual(
            initial,
            ChatMessageListAnimationKey(
                messageIDs: [firstID],
                standaloneStatus: "loading"
            )
        )
        XCTAssertEqual(
            initial,
            ChatMessageListAnimationKey(
                messageIDs: [firstID],
                standaloneStatus: "none"
            )
        )
    }

    func testChatScrollStateSendAfterScrollWaitsForNewVisibleBottomAndProxy() {
        let firstBottomID = UUID()
        let secondBottomID = UUID()
        var state = ChatScrollState()
        state.requestScrollToBottomAfterSend(visibleCount: 2, bottomMessageID: firstBottomID)

        XCTAssertFalse(state.consumeScrollToBottomAfterSendIfReady(
            visibleCount: 2,
            bottomMessageID: firstBottomID,
            scrollProxyAvailable: true
        ))
        XCTAssertFalse(state.consumeScrollToBottomAfterSendIfReady(
            visibleCount: 3,
            bottomMessageID: secondBottomID,
            scrollProxyAvailable: false
        ))
        XCTAssertTrue(state.consumeScrollToBottomAfterSendIfReady(
            visibleCount: 3,
            bottomMessageID: secondBottomID,
            scrollProxyAvailable: true
        ))
        XCTAssertFalse(state.consumeScrollToBottomAfterSendIfReady(
            visibleCount: 4,
            bottomMessageID: UUID(),
            scrollProxyAvailable: true
        ))
    }

    func testChatScrollStateHandlesOverflowTransitionScrollLifecycle() {
        var state = ChatScrollState()
        state.enqueueMetricUpdate(contentHeight: 200, viewportHeight: 120, bottomAnchorMaxY: 180)
        _ = state.applyPendingMetricUpdate(messageListBottomInset: 20, threshold: 24)
        state.requestOverflowTransitionScrollToBottom()
        let metrics = state.metrics(messageListBottomInset: 20, threshold: 24)

        XCTAssertEqual(state.consumeOverflowTransitionScrollToBottomIfReady(
            metrics: metrics,
            hasSearchInterruption: false,
            scrollProxyAvailable: false
        ), .waiting)
        XCTAssertEqual(state.consumeOverflowTransitionScrollToBottomIfReady(
            metrics: metrics,
            hasSearchInterruption: true,
            scrollProxyAvailable: true
        ), .cancelled)
        XCTAssertFalse(state.hasActivatedComposerOverflowBottomAnchor)

        state.requestOverflowTransitionScrollToBottom()
        XCTAssertEqual(state.consumeOverflowTransitionScrollToBottomIfReady(
            metrics: metrics,
            hasSearchInterruption: false,
            scrollProxyAvailable: true
        ), .scrollToBottom)
        XCTAssertTrue(state.hasActivatedComposerOverflowBottomAnchor)
        XCTAssertFalse(state.pendingComposerOverflowScrollToBottom)

        state.enqueueMetricUpdate(contentHeight: 100, viewportHeight: 120)
        _ = state.applyPendingMetricUpdate(messageListBottomInset: 20, threshold: 24)
        XCTAssertFalse(state.hasActivatedComposerOverflowBottomAnchor)
    }
}
