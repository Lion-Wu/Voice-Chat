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
    let includeDeveloperSections: Bool

    init(
        viewModel: SettingsViewModel,
        settingsManager: SettingsManager,
        includeDeveloperSections: Bool = false
    ) {
        self.viewModel = viewModel
        self.settingsManager = settingsManager
        self.includeDeveloperSections = includeDeveloperSections
    }

    var body: some View {
        Form {
            SettingsAdvancedAPISectionsContent(
                viewModel: viewModel,
                settingsManager: settingsManager,
                showingResetConfirmation: $showingResetConfirmation,
                includeDefaultsSection: !includeDeveloperSections
            )

            if includeDeveloperSections {
                SettingsDeveloperRequestPolicySection(viewModel: viewModel)
                SettingsDeveloperToolUseSection(viewModel: viewModel)
                SettingsDeveloperDefaultsSection(
                    viewModel: viewModel,
                    showingResetConfirmation: $showingResetConfirmation
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Advanced Options")
    }
}

struct SettingsAdvancedAPISectionsContent: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var settingsManager: SettingsManager
    @Binding var showingResetConfirmation: Bool
    var includeDefaultsSection: Bool = true

    var body: some View {
        ForEach(sections) { section in
            advancedAPISettingsSection(section)
        }
    }

    private var sections: [AdvancedAPISettingsSectionID] {
        AdvancedAPISettingsSectionID.allCases.filter { section in
            includeDefaultsSection || section != .defaults
        }
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
