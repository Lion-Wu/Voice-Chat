//
//  VoiceChatOverlayViewModel.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import Foundation
import SwiftUI

@MainActor
final class VoiceChatOverlayViewModel: ObservableObject {

    enum Lang: String, CaseIterable, Identifiable {
        case zh
        case en
        var id: String { rawValue }

        var display: String { self == .zh ? "Chinese" : "English" }
        var locale: Locale {
            switch self {
            case .zh: return Locale(identifier: "zh-CN")
            case .en: return Locale(identifier: "en-US")
            }
        }
    }

    enum State: Equatable {
        case idle
        case listening
        case loading
        case speaking
        case error(String)
    }

    // UI State
    @Published var isPresented: Bool = false
    @Published var lang: Lang = .zh
    @Published var state: State = .idle

    // Callback invoked when the speech recognizer provides a final transcript.
    var onRecognizedFinal: ((String) -> Void)?

    func present() {
        state = .idle
        isPresented = true
    }

    func dismiss() {
        isPresented = false
        state = .idle
    }

    func setLoading() { state = .loading }
    func setListening() { state = .listening }
    func setSpeaking() { state = .speaking }

    func setError(_ msg: String) {
        state = .error(msg)
    }
}
