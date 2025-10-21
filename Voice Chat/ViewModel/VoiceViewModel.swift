//
//  VoiceViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import Foundation
import AVFoundation

@MainActor
class VoiceViewModel: ObservableObject {
    // MARK: - State
    @Published var text: String = L10n.Voice.sampleText
    @Published var connectionStatus: String = L10n.Voice.waitingForConnection
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false

    // MARK: - Audio Session
    func setupAudioSession() {
        #if os(iOS) || os(tvOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
        } catch {
            self.errorMessage = L10n.Audio.errorSessionSetup(error.localizedDescription)
        }
        #endif
        // On macOS, AVAudioSession is not used.
    }
}
