//
//  ContentView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @EnvironmentObject var audioManager: GlobalAudioManager
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        ZStack {
            #if os(macOS)
            NavigationSplitView {
                SidebarView()
            } detail: {
                HomeView()
            }
            .frame(minWidth: 800, minHeight: 600)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            #else
            NavigationView {
                HomeView()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            #endif
        }
    }
}
struct SidebarView: View {
    var body: some View {
        List {
            Section(header: Text("Options")) {
                NavigationLink(destination: ChatView()) {
                    Label("Chat Interface", systemImage: "message")
                }
                NavigationLink(destination: VoiceView()) {
                    Label("Voice Generator", systemImage: "waveform")
                }
            }
        }
        .listStyle(SidebarListStyle())
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(SettingsManager.shared)
    }
}
