//
//  ChatService+PromptTools.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.23.
//

import Foundation

extension ChatService {
    func shouldGatePromptTools() -> Bool {
        guard configurationProvider.toolUseSettings.isEnabled else { return false }
        guard let endpoint = activeEndpointCandidate,
              endpoint.toolCallingTransport == .promptProtocol else {
            return false
        }
        return !configurationProvider.toolUseSettings.enabledToolIDs.isEmpty
    }

    func handlePromptToolDelta(_ piece: String, marksPrimaryOutput: Bool) {
        guard shouldGatePromptTools() else {
            emitDelta(piece, marksPrimaryOutput: marksPrimaryOutput)
            return
        }

        guard marksPrimaryOutput else {
            if shouldSuppressPromptToolThinkOpen(piece) {
                return
            }
            if isPromptToolThinkClose(piece) {
                promptToolPendingThinkClose = piece
                return
            }
            emitDelta(piece, marksPrimaryOutput: false)
            return
        }

        if promptToolStreamDecision == .normalAnswer {
            emitDelta(piece, marksPrimaryOutput: true)
            return
        }

        promptToolBufferedDeltas.append(.init(
            piece: piece,
            marksPrimaryOutput: true
        ))

        promptToolPrimaryText += piece
        updatePromptToolDecision()

        if promptToolStreamDecision == .normalAnswer {
            emitPromptToolThinkCloseBeforeAnswerIfNeeded()
            flushPromptToolBufferedDeltas()
        } else if promptToolStreamDecision == .toolCall {
            emitPromptToolPreviewActivity()
        }
    }

    func handlePromptToolFinish() {
        guard shouldGatePromptTools() else {
            emitStreamFinishedOnce()
            stopWatchdog()
            return
        }

        if shouldRunToolLoopInsteadOfFinishing() {
            resetPromptToolGate(preservingOpenThinking: promptToolKeepsThinkOpen)
            runPendingToolCallsAndContinue()
            return
        }

        let calls = ChatPromptToolProtocol.parseToolCalls(
            from: promptToolPrimaryText,
            provider: activeEndpointCandidate?.provider
        )
        if !calls.isEmpty {
            runPromptToolCallsIfAllowed(calls)
            return
        }

        emitPromptToolThinkCloseBeforeAnswerIfNeeded()
        flushPromptToolBufferedDeltas()
        emitStreamFinishedOnce()
        stopWatchdog()
    }

    @discardableResult
    func runBufferedPromptToolCallIfPresent() -> Bool {
        let calls = ChatPromptToolProtocol.parseToolCalls(
            from: promptToolPrimaryText,
            provider: activeEndpointCandidate?.provider
        )
        guard !calls.isEmpty else { return false }
        runPromptToolCallsIfAllowed(calls)
        return true
    }

    func resetPromptToolGate(preservingOpenThinking: Bool = false) {
        promptToolBufferedDeltas.removeAll(keepingCapacity: true)
        promptToolPrimaryText = ""
        promptToolStreamDecision = .undecided
        promptToolPendingThinkClose = nil
        promptToolPreviewActivityID = nil
        if !preservingOpenThinking {
            promptToolKeepsThinkOpen = false
        }
    }

    private func updatePromptToolDecision() {
        guard promptToolStreamDecision == .undecided else { return }
        let probe = promptToolPrimaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !probe.isEmpty else { return }

        if ChatPromptToolProtocol.isDefiniteToolCallStart(probe) {
            promptToolStreamDecision = .toolCall
            if promptToolPendingThinkClose != nil {
                promptToolKeepsThinkOpen = true
                promptToolPendingThinkClose = nil
            }
            return
        }
        if ChatPromptToolProtocol.canStillBecomeToolCallStart(probe) {
            return
        }
        promptToolStreamDecision = .normalAnswer
    }

    private func flushPromptToolBufferedDeltas() {
        let deltas = promptToolBufferedDeltas
        resetPromptToolGate(preservingOpenThinking: promptToolKeepsThinkOpen)
        for delta in deltas {
            emitDelta(delta.piece, marksPrimaryOutput: delta.marksPrimaryOutput)
        }
    }

    private func runPromptToolCallsIfAllowed(_ calls: [ChatToolCallEnvelope]) {
        appendPendingToolCalls(callsForPromptToolExecution(calls))
        resetPromptToolGate(preservingOpenThinking: promptToolKeepsThinkOpen)
        guard shouldRunToolLoopInsteadOfFinishing() else {
            emitStreamFinishedOnce()
            stopWatchdog()
            return
        }
        runPendingToolCallsAndContinue()
    }

    private func emitPromptToolPreviewActivity() {
        let activityID = promptToolPreviewActivityID ?? "prompt-tool-\(UUID().uuidString)"
        promptToolPreviewActivityID = activityID
        emitToolActivity(.init(
            id: activityID,
            toolName: "tool_call",
            title: NSLocalizedString("Generating Tool Call", comment: "Tool activity title"),
            phase: .requested,
            summary: promptToolPreviewSummary(),
            modelRequestPayload: [
                "partial_tool_call": .string(promptToolPrimaryText)
            ]
        ))
    }

    private func callsForPromptToolExecution(_ calls: [ChatToolCallEnvelope]) -> [ChatToolCallEnvelope] {
        guard let previewID = promptToolPreviewActivityID,
              let first = calls.first else {
            return calls
        }
        var output = calls
        output[0] = ChatToolCallEnvelope(
            callID: previewID,
            name: first.name,
            argumentsJSON: first.argumentsJSON,
            provider: first.provider
        )
        return output
    }

    private func promptToolPreviewSummary() -> String {
        let text = promptToolPrimaryText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 420 else { return text }
        return "...\(text.suffix(420))"
    }

    private func shouldSuppressPromptToolThinkOpen(_ piece: String) -> Bool {
        promptToolKeepsThinkOpen &&
        piece.trimmingCharacters(in: .whitespacesAndNewlines) == "<think>"
    }

    private func isPromptToolThinkClose(_ piece: String) -> Bool {
        piece.trimmingCharacters(in: .whitespacesAndNewlines) == "</think>"
    }

    private func emitPromptToolThinkCloseBeforeAnswerIfNeeded() {
        guard promptToolKeepsThinkOpen || promptToolPendingThinkClose != nil else { return }
        let close = promptToolPendingThinkClose ?? "\n</think>\n"
        promptToolKeepsThinkOpen = false
        promptToolPendingThinkClose = nil
        emitDelta(close, marksPrimaryOutput: false)
    }
}
