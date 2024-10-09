//
//  Voice_ChatApp.swift
//  Voice Chat
//
//  Created by 吴子宸 on 2023/12/25.
//

import SwiftUI

@main
struct Voice_ChatApp: App {
    @StateObject private var audioManager = GlobalAudioManager.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(audioManager)  // 注入 GlobalAudioManager
        }
    }
}
