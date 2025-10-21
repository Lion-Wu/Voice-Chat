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
                .environmentObject(speechInputManager)
                // Bind the SwiftData context so singletons have access before Settings appears
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
        // Reuse the same container to avoid concurrent initialization resets
        .modelContainer(Self.sharedContainer)
        .commands {
            AppMenuCommands(chatSessionsViewModel)
        }
        #endif
    }

    /// Shared SwiftData container reused by the app and settings scenes
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            ChatSession.self,
            ChatMessage.self,
            AppSettings.self,
            VoicePreset.self
        ])
        // Use the default configuration and let the system choose the storage location
        let config = ModelConfiguration()
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}

#if os(macOS)
/// Replace the default new-item menu with a "New Chat" command
private struct AppMenuCommands: Commands {
    @ObservedObject var chatSessionsViewModel: ChatSessionsViewModel

    init(_ vm: ChatSessionsViewModel) {
        self._chatSessionsViewModel = ObservedObject(wrappedValue: vm)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.Sidebar.newChat) {
                guard chatSessionsViewModel.canStartNewSession else { return }
                chatSessionsViewModel.startNewSession()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(!chatSessionsViewModel.canStartNewSession)
        }
    }
}
#endif

/// Inject the SwiftData model context and apply the current preset when the app becomes active
private struct ContextBinder: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel

    var body: some View {
        Color.clear
            .task {
                settingsManager.attach(context: context)
                chatSessionsViewModel.attach(context: context)
                // Apply the current preset once the context becomes available
                await settingsManager.applyPresetOnLaunchIfNeeded()
            }
    }
}
