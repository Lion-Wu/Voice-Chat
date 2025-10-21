//
//  Voice_ChatApp.swift
//  Voice Chat
//
//  Created by Lion Wu on 2023/12/25.
//

import SwiftUI
import SwiftData

@main
@MainActor
struct Voice_ChatApp: App {
    @StateObject private var audioManager = GlobalAudioManager.shared
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var chatSessionsViewModel = ChatSessionsViewModel()
    @StateObject private var speechInputManager = SpeechInputManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioManager)
                .environmentObject(settingsManager)
                .environmentObject(chatSessionsViewModel)
                .environmentObject(speechInputManager)
                // Bind the SwiftData context once the hierarchy is loaded so shared managers receive it.
                .background(ContextBinder()
                    .environmentObject(settingsManager)
                    .environmentObject(chatSessionsViewModel)
                )
        }
        .modelContainer(Self.sharedContainer)

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(settingsManager)
                .background(ContextBinder()
                    .environmentObject(settingsManager)
                    .environmentObject(chatSessionsViewModel)
                )
        }
        // Share a single container between all scenes to avoid resetting persistent storage.
        .modelContainer(Self.sharedContainer)
        .commands {
            AppMenuCommands(chatSessionsViewModel)
        }
        #endif
    }

    /// Shared SwiftData container reused across all scenes.
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            ChatSession.self,
            ChatMessage.self,
            AppSettings.self,
            VoicePreset.self
        ])
        // Use the default configuration so the system picks a persistent store location.
        let config = ModelConfiguration()
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}

#if os(macOS)
/// Replace the default “New” command with a chat specific action on macOS.
private struct AppMenuCommands: Commands {
    @ObservedObject var chatSessionsViewModel: ChatSessionsViewModel

    init(_ vm: ChatSessionsViewModel) {
        self._chatSessionsViewModel = ObservedObject(wrappedValue: vm)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                guard chatSessionsViewModel.canStartNewSession else { return }
                chatSessionsViewModel.startNewSession()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(!chatSessionsViewModel.canStartNewSession)
        }
    }
}
#endif

/// Inject the SwiftData context into shared managers once it is available.
private struct ContextBinder: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel

    var body: some View {
        Color.clear
            .task {
                settingsManager.attach(context: context)
                chatSessionsViewModel.attach(context: context)
                await settingsManager.applyPresetOnLaunchIfNeeded()
            }
    }
}
