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
        case english = "en-US"
        case simplifiedChinese = "zh-CN"
        case traditionalChinese = "zh-TW"
        case japanese = "ja-JP"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .english:
                return String(localized: "English")
            case .simplifiedChinese:
                return String(localized: "Simplified Chinese")
            case .traditionalChinese:
                return String(localized: "Traditional Chinese")
            case .japanese:
                return String(localized: "Japanese")
            }
        }

        var locale: Locale {
            Locale(identifier: rawValue)
        }
    }

    enum State: Equatable {
        case idle
        case listening
        case loading
        case speaking
        case error(String)
    }

    // UI state
    @Published var isPresented: Bool = false
    @Published var lang: Lang = .english
    @Published var state: State = .idle

    // External callback used to pipe recognized text back into the chat experience.
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
