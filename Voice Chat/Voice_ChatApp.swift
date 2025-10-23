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
    @StateObject private var speechInputManager = SpeechInputManager()   // Shared speech input manager

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioManager)
                .environmentObject(settingsManager)
                .environmentObject(chatSessionsViewModel)
                .environmentObject(speechInputManager)   // Inject speech input manager into the view hierarchy
                // Bind the SwiftData context so singletons and view models can access persistence.
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
        // Reuse the same container to avoid concurrent container resets
        .modelContainer(Self.sharedContainer)
        .commands {
            AppMenuCommands(chatSessionsViewModel)
        }
        #endif
    }

    /// Shared SwiftData container reused across the app and settings scenes.
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            ChatSession.self,
            ChatMessage.self,
            AppSettings.self,
            VoicePreset.self              // Model preset entity
        ])
        // Allow the system to decide an appropriate persistent store location
        let config = ModelConfiguration()
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}

#if os(macOS)
/// Customizes the application-level menu to replace the default "New" command with "New Chat".
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

/// Injects the SwiftData `ModelContext` into singletons/view models and applies the selected preset once on launch.
private struct ContextBinder: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel

    var body: some View {
        Color.clear
            .task {
                settingsManager.attach(context: context)
                chatSessionsViewModel.attach(context: context)
                // Apply the selected preset after launch by invoking the weight APIs sequentially.
                await settingsManager.applyPresetOnLaunchIfNeeded()
            }
    }
}
