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
    @StateObject private var appEnvironment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appEnvironment)
                .environmentObject(appEnvironment.audioManager)
                .environmentObject(appEnvironment.settingsManager)
                .environmentObject(appEnvironment.chatSessionsViewModel)
                .environmentObject(appEnvironment.speechInputManager)
                .environmentObject(appEnvironment.errorCenter)
                .environmentObject(appEnvironment.voiceOverlayViewModel)
                // Bind the SwiftData context once for all shared dependencies.
                .background(ModelContextBinder()
                    .environmentObject(appEnvironment)
                )
        }
        .modelContainer(Self.sharedContainer)

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appEnvironment)
                .environmentObject(appEnvironment.settingsManager)
                .environmentObject(appEnvironment.errorCenter)
                .background(ModelContextBinder()
                    .environmentObject(appEnvironment)
                )
        }
        // Reuse the same container instance to avoid creating parallel stores.
        .modelContainer(Self.sharedContainer)
        .commands {
            AppMenuCommands(appEnvironment.chatSessionsViewModel)
        }
        #endif
    }

    /// Shared SwiftData container used by both the main scene and the Settings window.
    private static let sharedContainer: ModelContainer = {
        makeContainer()
    }()

    /// Builds a SwiftData container, falling back to in-memory storage if the persistent store fails.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            ChatSession.self,
            ChatMessage.self,
            AppSettings.self,
            VoicePreset.self
        ])
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration()])
        } catch {
            // Avoid crashing the entire app if the persistent store cannot be created (e.g., corruption,
            // permission issues, or an incompatible schema). Fall back to an in-memory store so the UI
            // can still launch and the user can fix settings/export data.
            print("SwiftData persistent store init failed, falling back to in-memory: \(error)")
            do {
                return try ModelContainer(for: schema, configurations: [.init(isStoredInMemoryOnly: true)])
            } catch {
                fatalError("Failed to create any ModelContainer: \(error)")
            }
        }
    }
}

#if os(macOS)
/// Custom app-level menu that replaces the default `.newItem` command with "New Chat".
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
