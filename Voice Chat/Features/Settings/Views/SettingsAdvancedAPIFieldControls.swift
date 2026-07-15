//
//  SettingsAdvancedAPIFieldControls.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/14.
//

import SwiftUI

struct SettingsAdvancedAPISectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        #if os(macOS)
        Text(title)
            .font(.headline)
            .textCase(.none)
        #else
        Text(title)
        #endif
    }
}

struct SettingsAdvancedAPIMetadataRow: View {
    let title: LocalizedStringKey
    let value: String

    init(_ title: LocalizedStringKey, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? String(localized: "None") : value)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

struct SettingsAdvancedAPIBooleanToggleField: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        #if os(macOS)
        SettingsAdvancedAPILabeledContent(title) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        #else
        Toggle(title, isOn: $isOn)
        #endif
    }
}

struct SettingsAdvancedAPIIntegerField: View {
    let title: LocalizedStringKey
    @Binding var value: Int

    var body: some View {
        #if os(macOS)
        SettingsAdvancedAPILabeledContent(title) {
            TextField("", value: $value, format: .number)
                .multilineTextAlignment(.leading)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("", value: $value, format: .number)
                .multilineTextAlignment(.leading)
                .keyboardType(.numberPad)
        }
        .padding(.vertical, 4)
        #endif
    }
}

struct SettingsAdvancedAPIIntegerToggleField: View {
    let title: LocalizedStringKey
    @Binding var enabled: Bool
    @Binding var value: Int

    var body: some View {
        #if os(macOS)
        SettingsAdvancedAPILabeledContent(title) {
            HStack(spacing: 10) {
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)

                if enabled {
                    TextField("", value: $value, format: .number)
                        .multilineTextAlignment(.leading)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
            }
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: $enabled)
            if enabled {
                TextField("", value: $value, format: .number)
                    .multilineTextAlignment(.leading)
                    .keyboardType(.numberPad)
            }
        }
        .padding(.vertical, 4)
        #endif
    }
}

struct SettingsAdvancedAPIDoubleToggleField: View {
    let title: LocalizedStringKey
    @Binding var enabled: Bool
    @Binding var value: Double

    var body: some View {
        #if os(macOS)
        SettingsAdvancedAPILabeledContent(title) {
            HStack(spacing: 10) {
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)

                if enabled {
                    TextField("", value: $value, format: .number.precision(.fractionLength(0...3)))
                        .multilineTextAlignment(.leading)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
            }
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: $enabled)
            if enabled {
                TextField("", value: $value, format: .number.precision(.fractionLength(0...3)))
                    .multilineTextAlignment(.leading)
                    .keyboardType(.decimalPad)
            }
        }
        .padding(.vertical, 4)
        #endif
    }
}

struct SettingsAdvancedAPIVerbosityControl: View {
    @Binding var sampling: APIAdvancedSamplingSettings
    let title: LocalizedStringKey
    let options: [String]

    var body: some View {
        #if os(macOS)
        SettingsAdvancedAPILabeledContent(title) {
            HStack(spacing: 10) {
                Toggle("", isOn: $sampling.verbosityEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)

                if sampling.verbosityEnabled {
                    Picker("verbosity", selection: $sampling.verbosity) {
                        ForEach(options, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
            }
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: $sampling.verbosityEnabled)
            if sampling.verbosityEnabled {
                Picker("verbosity", selection: $sampling.verbosity) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.vertical, 4)
        #endif
    }
}

#if os(macOS)
private struct SettingsAdvancedAPILabeledContent<Content: View>: View {
    let title: LocalizedStringKey
    let content: () -> Content

    init(
        _ title: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.content = content
    }

    var body: some View {
        LabeledContent {
            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        } label: {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
