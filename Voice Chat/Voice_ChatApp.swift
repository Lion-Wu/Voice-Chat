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
                // Bind the SwiftData context so managers can persist correctly even when settings load first.
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
        // Share a single container instance to avoid unexpected resets when multiple windows appear.
        .modelContainer(Self.sharedContainer)
        .commands {
            AppMenuCommands(chatSessionsViewModel)
        }
        #endif
    }

    /// Shared SwiftData container used by both the application window and the settings scene.
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            ChatSession.self,
            ChatMessage.self,
            AppSettings.self,
            VoicePreset.self
        ])
        // Use the default configuration so the system picks the appropriate persistence location.
        let config = ModelConfiguration()
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}

#if os(macOS)
/// Custom menu commands that replace the default "New Item" entry with "New Chat".
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

/// Injects the SwiftData model context into singletons and view models, and applies presets after launch.
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
