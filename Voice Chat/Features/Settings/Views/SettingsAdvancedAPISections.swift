//
//  SettingsAdvancedAPISections.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import SwiftUI

struct SettingsAdvancedAPICurrentBackendSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var settingsManager: SettingsManager

    private var context: SettingsAdvancedAPIContext {
        SettingsAdvancedAPIContext(
            viewModel: viewModel,
            settingsManager: settingsManager
        )
    }

    var body: some View {
        Section {
            SettingsAdvancedAPIParameterControls(
                viewModel: viewModel,
                profile: .init(current: context)
            )
        } header: {
            SettingsAdvancedAPISectionHeader(title: "Current Backend Parameters")
        } footer: {
            Text("Only enabled sampling fields are added to requests.")
        }
    }
}

struct SettingsAdvancedAPIBackendOverridesSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Section {
            ForEach(AdvancedAPIBackendOverrideID.allCases) { backend in
                DisclosureGroup(backend.title) {
                    SettingsAdvancedAPIParameterControls(
                        viewModel: viewModel,
                        profile: .init(override: backend)
                    )
                }
            }
        } header: {
            SettingsAdvancedAPISectionHeader(title: "Backend Request Overrides")
        }
    }
}

struct SettingsAdvancedAPIDefaultsSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var showingResetConfirmation: Bool

    var body: some View {
        Section {
            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: {
                Label("Restore Defaults", systemImage: "arrow.counterclockwise")
            }
            .confirmationDialog(
                "Restore defaults?",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Restore Defaults", role: .destructive) {
                    viewModel.resetAPIAdvancedSettingsToDefaults()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will reset all options to defaults.")
            }
        } header: {
            SettingsAdvancedAPISectionHeader(title: "Defaults")
        }
    }
}
