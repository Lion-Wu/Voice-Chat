//
//  SettingsAdvancedAPIView.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

struct SettingsAdvancedAPIView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var settingsManager: SettingsManager
    @State private var showingResetConfirmation = false

    var body: some View {
        Form {
            ForEach(AdvancedAPISettingsSectionID.allCases) { section in
                advancedAPISettingsSection(section)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Advanced Options")
    }

    @ViewBuilder
    private func advancedAPISettingsSection(_ section: AdvancedAPISettingsSectionID) -> some View {
        switch section {
        case .metadata:
            SettingsAdvancedAPIMetadataSection(
                viewModel: viewModel,
                settingsManager: settingsManager
            )
        case .currentBackend:
            SettingsAdvancedAPICurrentBackendSection(
                viewModel: viewModel,
                settingsManager: settingsManager
            )
        case .backendOverrides:
            SettingsAdvancedAPIBackendOverridesSection(viewModel: viewModel)
        case .defaults:
            SettingsAdvancedAPIDefaultsSection(
                viewModel: viewModel,
                showingResetConfirmation: $showingResetConfirmation
            )
        }
    }
}
