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
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var chatSessionsViewModel = ChatSessionsViewModel()
    @StateObject private var speechInputManager = SpeechInputManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioManager)
                .environmentObject(settingsManager)
                .environmentObject(settingsViewModel)
                .environmentObject(chatSessionsViewModel)
                .environmentObject(speechInputManager)
                // Bind the SwiftData context to shared objects once the view hierarchy is ready.
                .background(ContextBinder()
                    .environmentObject(settingsManager)
                    .environmentObject(settingsViewModel)
                    .environmentObject(chatSessionsViewModel)
                )
        }
        .modelContainer(Self.sharedContainer)

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(settingsManager)
                .environmentObject(settingsViewModel)
                .background(ContextBinder()
                    .environmentObject(settingsManager)
                    .environmentObject(settingsViewModel)
                    .environmentObject(chatSessionsViewModel)
                )
        }
        // Share the same container to avoid creating multiple stores on macOS.
        .modelContainer(Self.sharedContainer)
        .commands {
            AppMenuCommands(chatSessionsViewModel)
        }
        #endif
    }

    /// Shared SwiftData container used across the main window and the settings scene.
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            ChatSession.self,
            ChatMessage.self,
            AppSettings.self,
            VoicePreset.self
        ])
        // Use the default configuration so the system chooses the persistence location.
        let config = ModelConfiguration()
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}

#if os(macOS)
/// Replace the default “New” command with “New Chat” to match the app’s behavior.
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

/// Inject the SwiftData model context into shared objects and apply the stored preset on launch.
private struct ContextBinder: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel

    var body: some View {
        Color.clear
            .task {
                settingsManager.attach(context: context)
                chatSessionsViewModel.attach(context: context)
                // Apply the active preset after launch to keep audio settings in sync.
                await settingsManager.applyPresetOnLaunchIfNeeded()
            }
    }
}
