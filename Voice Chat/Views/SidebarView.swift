//
//  SidebarView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.11.04.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SidebarView: View {
    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            // Sidebar header with toggle button
            HStack {
                Spacer()
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16, weight: .medium))
                        .help("Hide Sidebar")
                }
                .buttonStyle(PlainButtonStyle())
                .padding([.top, .trailing], 8)
            }
            #endif

            // Sidebar content
            List {
                NavigationLink(destination: ChatView()) {
                    Label("Chat Interface", systemImage: "message")
                }
                NavigationLink(destination: VoiceView()) {
                    Label("Voice Generator", systemImage: "waveform")
                }
            }
            .listStyle(SidebarListStyle())
            .navigationTitle("Menu")
        }
    }

    // Function to toggle the sidebar on macOS
    #if os(macOS)
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
    #endif
}

struct SidebarView_Previews: PreviewProvider {
    static var previews: some View {
        SidebarView()
    }
}
