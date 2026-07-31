//
//  SettingsInputFields.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.29.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - LabeledTextField

struct LabeledTextField: View {
    var label: String
    var placeholder: String
    @Binding var text: String
    var onCommit: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
        #if os(macOS)
        LabeledContent(LocalizedStringKey(label)) {
            TextField("", text: $text, prompt: Text(LocalizedStringKey(placeholder)))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .focused($isFocused)
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(label))
                .font(.subheadline)
                .foregroundColor(.secondary)
            TextField(LocalizedStringKey(placeholder), text: $text)
                .textInputAutocapitalization(.never)
                .focused($isFocused)
        }
        #endif
        }
        .onSubmit(onCommit)
        .onChange(of: isFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused {
                onCommit()
            }
        }
        .onDisappear(perform: onCommit)
    }
}

// MARK: - LabeledTextEditor

struct LabeledTextEditor: View {
    var label: String
    var placeholder: String
    @Binding var text: String
    var onCommit: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
        #if os(macOS)
        LabeledContent(LocalizedStringKey(label)) {
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .background(Color(NSColor.textBackgroundColor))
                .focused($isFocused)
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(label))
                .font(.subheadline)
                .foregroundColor(.secondary)
            TextEditor(text: $text)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .background(Color(.secondarySystemBackground))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(LocalizedStringKey(placeholder))
                            .foregroundColor(.secondary)
                            .padding(.top, 10)
                            .padding(.leading, 6)
                    }
                }
                .focused($isFocused)
        }
        #endif
        }
        .onChange(of: isFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused {
                onCommit()
            }
        }
        .onDisappear(perform: onCommit)
    }
}

// MARK: - LabeledSecureField

struct LabeledSecureField: View {
    var label: String
    var placeholder: String
    @Binding var text: String
    var onCommit: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
        #if os(macOS)
        LabeledContent(LocalizedStringKey(label)) {
            SecureField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .privacySensitive()
                .frame(maxWidth: .infinity)
                .focused($isFocused)
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(label))
                .font(.subheadline)
                .foregroundColor(.secondary)
            SecureField(LocalizedStringKey(placeholder), text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
                .focused($isFocused)
        }
        #endif
        }
        .onSubmit(onCommit)
        .onChange(of: isFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused {
                onCommit()
            }
        }
        .onDisappear(perform: onCommit)
    }
}
