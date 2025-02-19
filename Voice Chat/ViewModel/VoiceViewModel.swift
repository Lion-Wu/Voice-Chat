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
    @Published var text = "Sample text."
    @Published var connectionStatus = "Waiting for connection"
    @Published var errorMessage: String?
    @Published var isLoading = false

    func setupAudioSession() {
        #if os(iOS) || os(tvOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Unable to set up audio session: \(error.localizedDescription)"
            }
        }
        #endif
        // On macOS, AVAudioSession is not used. It's safe to skip.
    }
}
