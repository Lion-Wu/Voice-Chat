//
//  VoiceChatOverlayViewModel+Connectivity.swift
//  Voice Chat
//
//  Created by OpenAI on 2026.06.14.
//

import Foundation

extension VoiceChatOverlayViewModel {
    func beginConnectivityPreflight() {
        cancelConnectivityTask()

        let attemptID = UUID()
        connectivityAttemptID = attemptID

        connectivityTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.connectivityAttemptID == attemptID {
                    self.connectivityTask = nil
                    self.connectivityAttemptID = nil
                }
            }

            await self.reachabilityMonitor.checkAll(snapshot: self.settingsManager.serverReachabilitySnapshot)

            guard self.isPresented else { return }
            guard self.connectivityAttemptID == attemptID else { return }

            let chatOK = self.reachabilityMonitor.isChatReachable
            let ttsOK = self.reachabilityMonitor.isTTSReachable

            if chatOK == true && ttsOK == true {
                self.autoResumeEnabled = true
                self.state = .listening
                self.startListening()
            } else {
                self.handleError(self.connectivityErrorMessage(chatOK: chatOK, ttsOK: ttsOK))
            }
        }
    }

    func cancelConnectivityTask() {
        connectivityTask?.cancel()
        connectivityTask = nil
        connectivityAttemptID = nil
    }

    func attemptReconnect() {
        activeChatSession?.cancelRealtimeVoiceRequest()
        autoResumeEnabled = false
        cancelStartTasks()
        stopLoadingWatchdog()
        cancelConnectivityTask()
        isSendSuppressed = false
        speechInputManager.setHoldToSpeakActive(false)
        showErrorBanner = false
        errorMessage = nil

        closeAudioIfVoiceWorkIsActive()

        state = .loading
        beginConnectivityPreflight()
    }

    func connectivityErrorMessage(chatOK: Bool?, ttsOK: Bool?) -> String {
        let chatBase = settingsManager.chatSettings.apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let ttsBase = settingsManager.serverSettings.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        if chatBase.isEmpty || ttsBase.isEmpty {
            return NSLocalizedString("Server address is not configured.", comment: "Shown when realtime voice mode is started but server addresses are missing")
        }

        if chatOK == false && ttsOK == false {
            return NSLocalizedString("Unable to connect to the chat and voice servers.", comment: "Shown when both chat and voice servers are unreachable")
        }
        if chatOK == false {
            return NSLocalizedString("Unable to connect to the chat server.", comment: "Shown when the chat server is unreachable for realtime voice mode")
        }
        if ttsOK == false {
            return NSLocalizedString("Unable to connect to the voice server.", comment: "Shown when the voice server is unreachable for realtime voice mode")
        }
        return NSLocalizedString("Unable to connect. Please check your server settings.", comment: "Fallback message when realtime voice mode cannot connect")
    }
}
