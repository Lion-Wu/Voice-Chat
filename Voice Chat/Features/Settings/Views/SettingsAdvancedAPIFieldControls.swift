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
    @State private var draftValue: Int
    @FocusState private var isFieldFocused: Bool

    init(title: LocalizedStringKey, value: Binding<Int>) {
        self.title = title
        _value = value
        _draftValue = State(initialValue: value.wrappedValue)
    }

    var body: some View {
        #if os(macOS)
        SettingsAdvancedAPILabeledContent(title) {
            TextField("", value: $draftValue, format: .number)
                .multilineTextAlignment(.leading)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .focused($isFieldFocused)
                .onSubmit(commitDraft)
                .onChange(of: isFieldFocused) { _, isFocused in
                    if !isFocused { commitDraft() }
                }
                .onChange(of: value) { _, newValue in
                    synchronizeDraft(with: newValue)
                }
                .onDisappear(perform: commitDraft)
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("", value: $draftValue, format: .number)
                .multilineTextAlignment(.leading)
                .keyboardType(.numberPad)
                .focused($isFieldFocused)
                .onSubmit(commitDraft)
                .onChange(of: isFieldFocused) { _, isFocused in
                    if !isFocused { commitDraft() }
                }
                .onChange(of: value) { _, newValue in
                    synchronizeDraft(with: newValue)
                }
                .onDisappear(perform: commitDraft)
        }
        .padding(.vertical, 4)
        #endif
    }

    private func commitDraft() {
        guard draftValue != value else { return }
        value = draftValue
    }

    private func synchronizeDraft(with newValue: Int) {
        guard draftValue != newValue else { return }
        draftValue = newValue
    }
}

struct SettingsAdvancedAPIIntegerToggleField: View {
    let title: LocalizedStringKey
    @Binding var enabled: Bool
    @Binding var value: Int
    @State private var draftValue: Int
    @FocusState private var isFieldFocused: Bool

    init(title: LocalizedStringKey, enabled: Binding<Bool>, value: Binding<Int>) {
        self.title = title
        _enabled = enabled
        _value = value
        _draftValue = State(initialValue: value.wrappedValue)
    }

    var body: some View {
        #if os(macOS)
        SettingsAdvancedAPILabeledContent(title) {
            HStack(spacing: 10) {
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)

                if enabled {
                    TextField("", value: $draftValue, format: .number)
                        .multilineTextAlignment(.leading)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .focused($isFieldFocused)
                        .onSubmit(commitDraft)
                        .onChange(of: isFieldFocused) { _, isFocused in
                            if !isFocused { commitDraft() }
                        }
                        .onChange(of: value) { _, newValue in
                            synchronizeDraft(with: newValue)
                        }
                        .onDisappear(perform: commitDraft)
                }
            }
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: $enabled)
            if enabled {
                TextField("", value: $draftValue, format: .number)
                    .multilineTextAlignment(.leading)
                    .keyboardType(.numberPad)
                    .focused($isFieldFocused)
                    .onSubmit(commitDraft)
                    .onChange(of: isFieldFocused) { _, isFocused in
                        if !isFocused { commitDraft() }
                    }
                    .onChange(of: value) { _, newValue in
                        synchronizeDraft(with: newValue)
                    }
                    .onDisappear(perform: commitDraft)
            }
        }
        .padding(.vertical, 4)
        #endif
    }

    private func commitDraft() {
        guard draftValue != value else { return }
        value = draftValue
    }

    private func synchronizeDraft(with newValue: Int) {
        guard draftValue != newValue else { return }
        draftValue = newValue
    }
}

struct SettingsAdvancedAPIDoubleToggleField: View {
    let title: LocalizedStringKey
    @Binding var enabled: Bool
    @Binding var value: Double
    @State private var draftValue: Double
    @FocusState private var isFieldFocused: Bool

    init(title: LocalizedStringKey, enabled: Binding<Bool>, value: Binding<Double>) {
        self.title = title
        _enabled = enabled
        _value = value
        _draftValue = State(initialValue: value.wrappedValue)
    }

    var body: some View {
        #if os(macOS)
        SettingsAdvancedAPILabeledContent(title) {
            HStack(spacing: 10) {
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)

                if enabled {
                    TextField("", value: $draftValue, format: .number.precision(.fractionLength(0...3)))
                        .multilineTextAlignment(.leading)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .focused($isFieldFocused)
                        .onSubmit(commitDraft)
                        .onChange(of: isFieldFocused) { _, isFocused in
                            if !isFocused { commitDraft() }
                        }
                        .onChange(of: value) { _, newValue in
                            synchronizeDraft(with: newValue)
                        }
                        .onDisappear(perform: commitDraft)
                }
            }
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: $enabled)
            if enabled {
                TextField("", value: $draftValue, format: .number.precision(.fractionLength(0...3)))
                    .multilineTextAlignment(.leading)
                    .keyboardType(.decimalPad)
                    .focused($isFieldFocused)
                    .onSubmit(commitDraft)
                    .onChange(of: isFieldFocused) { _, isFocused in
                        if !isFocused { commitDraft() }
                    }
                    .onChange(of: value) { _, newValue in
                        synchronizeDraft(with: newValue)
                    }
                    .onDisappear(perform: commitDraft)
            }
        }
        .padding(.vertical, 4)
        #endif
    }

    private func commitDraft() {
        guard draftValue != value else { return }
        value = draftValue
    }

    private func synchronizeDraft(with newValue: Double) {
        guard draftValue != newValue else { return }
        draftValue = newValue
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
