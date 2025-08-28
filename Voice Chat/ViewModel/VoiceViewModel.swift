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
    @Published var text: String = "Sample text."
    @Published var connectionStatus: String = "Waiting for connection"
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
            self.errorMessage = "Unable to set up audio session: \(error.localizedDescription)"
        }
        #endif
        // On macOS, AVAudioSession is not used.
    }
}
