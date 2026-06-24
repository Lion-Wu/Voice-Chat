//
//  ChatService+LMStudioPromptTools.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.23.
//

import Foundation

extension ChatService {
    func shouldGateLMStudioPromptTools() -> Bool {
        guard configurationProvider.toolUseSettings.isEnabled else { return false }
        switch activeEndpointCandidate?.style {
        case .lmStudioRESTV1, .lmStudioRESTV1LegacyMessage:
            guard let endpoint = activeEndpointCandidate else {
                return !configurationProvider.toolUseSettings.enabledToolIDs.isEmpty
            }
            return !configurationProvider.toolUseSettings.enabledToolIDs(for: endpoint).isEmpty
        case .openAIChatCompletions, .anthropicMessages, .none:
            return false
        }
    }

    func handleLMStudioPromptToolDelta(_ piece: String, marksPrimaryOutput: Bool) {
        guard shouldGateLMStudioPromptTools() else {
            emitDelta(piece, marksPrimaryOutput: marksPrimaryOutput)
            return
        }

        guard marksPrimaryOutput else {
            if shouldSuppressLMStudioPromptToolThinkOpen(piece) {
                return
            }
            if isLMStudioPromptToolThinkClose(piece) {
                lmStudioPromptToolPendingThinkClose = piece
                return
            }
            emitDelta(piece, marksPrimaryOutput: false)
            return
        }

        if lmStudioPromptToolStreamDecision == .normalAnswer {
            emitDelta(piece, marksPrimaryOutput: true)
            return
        }

        lmStudioPromptToolBufferedDeltas.append(.init(
            piece: piece,
            marksPrimaryOutput: true
        ))

        lmStudioPromptToolPrimaryText += piece
        updateLMStudioPromptToolDecision()

        if lmStudioPromptToolStreamDecision == .normalAnswer {
            emitLMStudioPromptToolThinkCloseBeforeAnswerIfNeeded()
            flushLMStudioPromptToolBufferedDeltas()
        }
    }

    func handleLMStudioPromptToolFinish() {
        guard shouldGateLMStudioPromptTools() else {
            emitStreamFinishedOnce()
            stopWatchdog()
            return
        }

        let calls = LMStudioPromptToolProtocol.parseToolCalls(
            from: lmStudioPromptToolPrimaryText,
            provider: activeEndpointCandidate?.provider
        )
        if !calls.isEmpty {
            runLMStudioPromptToolCallsIfAllowed(calls)
            return
        }

        emitLMStudioPromptToolThinkCloseBeforeAnswerIfNeeded()
        flushLMStudioPromptToolBufferedDeltas()
        emitStreamFinishedOnce()
        stopWatchdog()
    }

    @discardableResult
    func runBufferedLMStudioPromptToolCallIfPresent() -> Bool {
        let calls = LMStudioPromptToolProtocol.parseToolCalls(
            from: lmStudioPromptToolPrimaryText,
            provider: activeEndpointCandidate?.provider
        )
        guard !calls.isEmpty else { return false }
        runLMStudioPromptToolCallsIfAllowed(calls)
        return true
    }

    func resetLMStudioPromptToolGate(preservingOpenThinking: Bool = false) {
        lmStudioPromptToolBufferedDeltas.removeAll(keepingCapacity: true)
        lmStudioPromptToolPrimaryText = ""
        lmStudioPromptToolStreamDecision = .undecided
        lmStudioPromptToolPendingThinkClose = nil
        if !preservingOpenThinking {
            lmStudioPromptToolKeepsThinkOpen = false
        }
    }

    private func updateLMStudioPromptToolDecision() {
        guard lmStudioPromptToolStreamDecision == .undecided else { return }
        let probe = lmStudioPromptToolPrimaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !probe.isEmpty else { return }

        if LMStudioPromptToolProtocol.isDefiniteToolCallStart(probe) {
            lmStudioPromptToolStreamDecision = .toolCall
            if lmStudioPromptToolPendingThinkClose != nil {
                lmStudioPromptToolKeepsThinkOpen = true
                lmStudioPromptToolPendingThinkClose = nil
            }
            return
        }
        if LMStudioPromptToolProtocol.canStillBecomeToolCallStart(probe) {
            return
        }
        lmStudioPromptToolStreamDecision = .normalAnswer
    }

    private func flushLMStudioPromptToolBufferedDeltas() {
        let deltas = lmStudioPromptToolBufferedDeltas
        resetLMStudioPromptToolGate(preservingOpenThinking: lmStudioPromptToolKeepsThinkOpen)
        for delta in deltas {
            emitDelta(delta.piece, marksPrimaryOutput: delta.marksPrimaryOutput)
        }
    }

    private func runLMStudioPromptToolCallsIfAllowed(_ calls: [ChatToolCallEnvelope]) {
        appendPendingToolCalls(calls)
        resetLMStudioPromptToolGate(preservingOpenThinking: lmStudioPromptToolKeepsThinkOpen)
        guard shouldRunToolLoopInsteadOfFinishing() else {
            emitStreamFinishedOnce()
            stopWatchdog()
            return
        }
        runPendingToolCallsAndContinue()
    }

    private func shouldSuppressLMStudioPromptToolThinkOpen(_ piece: String) -> Bool {
        lmStudioPromptToolKeepsThinkOpen &&
        piece.trimmingCharacters(in: .whitespacesAndNewlines) == "<think>"
    }

    private func isLMStudioPromptToolThinkClose(_ piece: String) -> Bool {
        piece.trimmingCharacters(in: .whitespacesAndNewlines) == "</think>"
    }

    private func emitLMStudioPromptToolThinkCloseBeforeAnswerIfNeeded() {
        guard lmStudioPromptToolKeepsThinkOpen || lmStudioPromptToolPendingThinkClose != nil else { return }
        let close = lmStudioPromptToolPendingThinkClose ?? "\n</think>\n"
        lmStudioPromptToolKeepsThinkOpen = false
        lmStudioPromptToolPendingThinkClose = nil
        emitDelta(close, marksPrimaryOutput: false)
    }
}
