//
//  SettingsToolUseSection.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import SwiftUI

struct SettingsToolUseSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    let hideHeader: Bool
    @State private var isConfirmingToolUse = false
    @State private var isConfirmingHighRiskAutoExecution = false

    var body: some View {
        Group {
            Section {
                Toggle("Enable Tool Use", isOn: toolUseEnabledBinding)
                    .alert("Enable Tool Use?", isPresented: $isConfirmingToolUse) {
                        Button("Cancel", role: .cancel) {}
                        Button("Enable") {
                            setToolUseEnabled(true)
                        }
                    } message: {
                        Text("Not all models support tool use. Enabling it may increase token usage.")
                    }

                if viewModel.toolUseSettings.isEnabled {
                    Picker("Authorization", selection: toolBinding(\.authorizationMode)) {
                        Text("Ask Every Time").tag(ToolAuthorizationMode.askEveryTime)
                        Text("Read Only").tag(ToolAuthorizationMode.readOnly)
                        Text("Read and Write").tag(ToolAuthorizationMode.readWrite)
                    }

                    Toggle(isOn: highRiskAutoExecutionBinding) {
                        Text("Allow Automatic High-Risk Tools")
                            .foregroundStyle(.red)
                    }
                    .tint(.red)
                    .alert("Allow Automatic High-Risk Tools?", isPresented: $isConfirmingHighRiskAutoExecution) {
                        Button("Cancel", role: .cancel) {}
                        Button("Allow", role: .destructive) {
                            setHighRiskAutoExecution(true)
                        }
                    } message: {
                        Text("This will allow location, clipboard, URL, and JavaScript Runtime tools to run automatically when permitted by the authorization mode. This may increase the risk of privacy exposure.")
                    }
                }
            } header: {
                header
            }

            if viewModel.toolUseSettings.isEnabled {
                Section {
                    HStack {
                        Spacer()
                        Button {
                            setAllToolsEnabled(!allToolsEnabled)
                        } label: {
                            Label(
                                allToolsEnabled ? "Disable All Tools" : "Enable All Tools",
                                systemImage: allToolsEnabled ? "xmark.circle" : "checkmark.circle"
                            )
                        }
                        .settingsActionButtonStyle()
                    }

                    Toggle("Calendar", isOn: toolBinding(\.calendarEnabled))
                    Toggle("Reminders", isOn: toolBinding(\.remindersEnabled))
                    Toggle("Location", isOn: toolBinding(\.locationEnabled))
                    Toggle("Motion", isOn: toolBinding(\.motionEnabled))
                    Toggle("Device Context", isOn: toolBinding(\.deviceContextEnabled))
                    Toggle("Time", isOn: toolBinding(\.timeEnabled))
                        .disabled(viewModel.toolUseSettings.requiresTimeTool)
                    Toggle("Clipboard", isOn: toolBinding(\.clipboardEnabled))
                    Toggle("URL Actions", isOn: toolBinding(\.urlActionsEnabled))
                    Toggle("JavaScript Runtime", isOn: toolBinding(\.javaScriptRuntimeEnabled))

                    if let status = viewModel.toolUseStatusMessage {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var allToolsEnabled: Bool {
        let settings = viewModel.toolUseSettings
        return settings.calendarEnabled &&
            settings.remindersEnabled &&
            settings.locationEnabled &&
            settings.motionEnabled &&
            settings.deviceContextEnabled &&
            settings.timeEnabled &&
            settings.clipboardEnabled &&
            settings.urlActionsEnabled &&
            settings.javaScriptRuntimeEnabled
    }

    private var highRiskAutoExecutionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.toolUseSettings.allowHighRiskToolAutoExecution },
            set: { value in
                if value {
                    isConfirmingHighRiskAutoExecution = true
                } else {
                    setHighRiskAutoExecution(false)
                }
            }
        )
    }

    private var toolUseEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.toolUseSettings.isEnabled },
            set: { enabled in
                if enabled {
                    guard !viewModel.toolUseSettings.isEnabled else { return }
                    isConfirmingToolUse = true
                } else {
                    setToolUseEnabled(false)
                }
            }
        )
    }

    private func setToolUseEnabled(_ enabled: Bool) {
        var next = viewModel.toolUseSettings
        next.isEnabled = enabled
        viewModel.toolUseSettings = next
    }

    private func setHighRiskAutoExecution(_ enabled: Bool) {
        var next = viewModel.toolUseSettings
        next.allowHighRiskToolAutoExecution = enabled
        viewModel.toolUseSettings = next
    }

    private func setAllToolsEnabled(_ enabled: Bool) {
        var next = viewModel.toolUseSettings
        next.calendarEnabled = enabled
        next.remindersEnabled = enabled
        next.locationEnabled = enabled
        next.motionEnabled = enabled
        next.deviceContextEnabled = enabled
        next.timeEnabled = enabled
        next.clipboardEnabled = enabled
        next.urlActionsEnabled = enabled
        next.javaScriptRuntimeEnabled = enabled
        viewModel.toolUseSettings = next
    }

    private func toolBinding(_ keyPath: WritableKeyPath<ToolUseSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { viewModel.toolUseSettings[keyPath: keyPath] },
            set: { value in
                var next = viewModel.toolUseSettings
                next[keyPath: keyPath] = value
                viewModel.toolUseSettings = next
            }
        )
    }

    private func toolBinding<Value: Equatable>(_ keyPath: WritableKeyPath<ToolUseSettings, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.toolUseSettings[keyPath: keyPath] },
            set: { value in
                var next = viewModel.toolUseSettings
                next[keyPath: keyPath] = value
                viewModel.toolUseSettings = next
            }
        )
    }

    @ViewBuilder
    private var header: some View {
        if hideHeader {
            EmptyView()
        } else {
            #if os(macOS)
            Text("Tool Use")
                .font(.headline)
                .textCase(.none)
            #else
            Text("Tool Use")
            #endif
        }
    }
}

struct SettingsDeveloperRequestPolicySection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var statefulEndpointPendingRemoval: String?

    var body: some View {
        Section {
            Toggle("Enable Stateful Chat for LM Studio", isOn: toolBoolBinding(\.useProviderContinuationIDs))

            Text("Enables Stateful Chat for conversations that support it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI Responses Stateful Chat")
                    .font(.subheadline.weight(.semibold))

                if let currentEndpointURL = viewModel.currentOpenAIResponsesStatefulEndpointURL {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current Endpoint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(currentEndpointURL)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if viewModel.isCurrentOpenAIResponsesStatefulEndpointEnabled {
                        Label("Stateful chat is enabled for this backend.", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    } else {
                        HStack {
                            Spacer()
                            Button {
                                viewModel.enableStatefulChatForCurrentOpenAIResponsesEndpoint()
                            } label: {
                                Label("Enable for This Backend", systemImage: "plus.circle")
                            }
                            .settingsActionButtonStyle()
                        }
                    }
                } else {
                    Text("Select or auto-detect an OpenAI Responses API endpoint to enable the current backend.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Enabled Endpoints")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Only the endpoint URLs listed below may continue from an OpenAI Responses response ID.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.openAIResponsesStatefulEndpointURLs.isEmpty {
                    Text("No endpoint URLs are enabled.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.openAIResponsesStatefulEndpointURLs, id: \.self) { endpointURL in
                        statefulEndpointRow(endpointURL)
                    }
                }
            }
            .padding(.top, 4)

        } header: {
            #if os(macOS)
            Text("Request Policy")
                .font(.headline)
                .textCase(.none)
            #else
            Text("Request Policy")
            #endif
        }
        .alert(
            "Delete Stateful Endpoint?",
            isPresented: isConfirmingStatefulEndpointRemoval
        ) {
            Button("Cancel", role: .cancel) {
                statefulEndpointPendingRemoval = nil
            }
            Button("Delete", role: .destructive) {
                guard let endpointURL = statefulEndpointPendingRemoval else { return }
                viewModel.removeOpenAIResponsesStatefulEndpointURL(endpointURL)
                statefulEndpointPendingRemoval = nil
            }
        } message: {
            Text("This endpoint will no longer continue chats from an OpenAI Responses response ID.")
        }
    }

    private var isConfirmingStatefulEndpointRemoval: Binding<Bool> {
        Binding(
            get: { statefulEndpointPendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    statefulEndpointPendingRemoval = nil
                }
            }
        )
    }

    private func toolBoolBinding(_ keyPath: WritableKeyPath<ToolUseSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { viewModel.toolUseSettings[keyPath: keyPath] },
            set: { value in
                var next = viewModel.toolUseSettings
                next[keyPath: keyPath] = value
                viewModel.toolUseSettings = next
            }
        )
    }

    @ViewBuilder
    private func statefulEndpointRow(_ endpointURL: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(endpointURL)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive) {
                statefulEndpointPendingRemoval = endpointURL
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .help("Remove endpoint")
        }
        .padding(.vertical, 3)
    }
}

struct SettingsDeveloperToolUseSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var allDefinitions: [ChatToolDefinition] {
        ChatToolID.allCases.map { ChatToolDefinitions.definition(for: $0) }
    }

    var body: some View {
        Section {
            LabeledContent("Global State") {
                Text(viewModel.toolUseSettings.isEnabled
                    ? LocalizedStringKey("Enabled")
                    : LocalizedStringKey("Disabled"))
                    .foregroundStyle(viewModel.toolUseSettings.isEnabled ? .green : .secondary)
            }

            LabeledContent("Enabled Tools") {
                Text("\(viewModel.toolUseSettings.enabledToolIDs.count) / \(ChatToolID.allCases.count)")
                    .monospacedDigit()
            }

            if let status = viewModel.toolUseStatusMessage {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LabeledContent("Authorization Mode") {
                Text(viewModel.toolUseSettings.authorizationMode.rawValue)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
            LabeledContent("Automatic High-Risk Tools") {
                Text(viewModel.toolUseSettings.allowHighRiskToolAutoExecution
                    ? LocalizedStringKey("Enabled")
                    : LocalizedStringKey("Disabled"))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(viewModel.toolUseSettings.allowHighRiskToolAutoExecution ? .red : .secondary)
                    .textSelection(.enabled)
            }

            ForEach(allDefinitions, id: \.id) { definition in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        toolSectionTitle("Description")
                        Text(definition.description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        toolSectionTitle("Parameters")
                        parameterFieldsView(for: definition.parametersSchema)

                        toolSectionTitle("Metadata")
                        rawDefinitionView(for: definition)
                    }
                    .padding(.top, 6)
                } label: {
                    HStack {
                        Label(definition.id.rawValue, systemImage: iconName(for: definition.id))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(stateText(for: definition.id))
                            .font(.caption)
                            .foregroundStyle(isEnabled(definition.id) ? .green : .secondary)
                    }
                }
            }
        } header: {
            #if os(macOS)
            Text("Tool Use Details")
                .font(.headline)
                .textCase(.none)
            #else
            Text("Tool Use Details")
            #endif
        }
    }

    private func isEnabled(_ id: ChatToolID) -> Bool {
        viewModel.toolUseSettings.isEnabled && viewModel.toolUseSettings.enabledToolIDs.contains(id)
    }

    private func stateText(for id: ChatToolID) -> String {
        isEnabled(id) ? String(localized: "Enabled") : String(localized: "Disabled")
    }

    private func iconName(for id: ChatToolID) -> String {
        switch id {
        case .calendarListEvents, .calendarCreateEvent, .calendarDeleteEvent, .calendarShowEvents:
            return "calendar"
        case .remindersListReminders, .remindersCreateReminder, .remindersDeleteReminder, .remindersShowReminders:
            return "checklist"
        case .locationCurrent:
            return "location"
        case .motionDevice:
            return "gyroscope"
        case .deviceContext:
            return "desktopcomputer"
        case .clipboardGetText, .clipboardSetText:
            return "doc.on.clipboard"
        case .systemOpenURL:
            return "arrow.up.forward.app"
        case .systemGetTime:
            return "clock"
        case .javaScriptRun:
            return "curlybraces"
        }
    }

    private func toolDetailRow(_ title: LocalizedStringKey, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func toolSectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func parameterFieldsView(for schema: JSONValue) -> some View {
        let fields = parameterFields(from: schema)
        if fields.isEmpty {
            Text("No parameters")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(fields) { field in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(field.name)
                                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                                .textSelection(.enabled)
                            Text(field.required
                                ? LocalizedStringKey("required")
                                : LocalizedStringKey("optional"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    PlatformColor.tertiaryGroupedBackground,
                                    in: Capsule()
                                )
                        }

                        if let description = stringValue("description", in: field.schema) {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(parameterMetadata(for: field.schema))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        PlatformColor.tertiaryGroupedBackground,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
            }
        }
    }

    private func rawDefinitionView(for definition: ChatToolDefinition) -> some View {
        Text(rawToolDefinition(for: definition).prettyPrintedJSONString)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                PlatformColor.tertiaryGroupedBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }

    private func rawToolDefinition(for definition: ChatToolDefinition) -> JSONValue {
        .object([
            "type": .string("function"),
            "name": .string(definition.id.rawValue),
            "description": .string(definition.description),
            "parameters": definition.parametersSchema
        ])
    }

    private struct ToolParameterField: Identifiable {
        let name: String
        let required: Bool
        let schema: JSONValue

        var id: String { name }
    }

    private func parameterFields(from schema: JSONValue) -> [ToolParameterField] {
        guard case let .object(root) = schema,
              case let .object(properties)? = root["properties"] else {
            return []
        }

        let requiredNames = requiredFieldNames(from: root["required"])
        return properties.keys.sorted().map { name in
            ToolParameterField(
                name: name,
                required: requiredNames.contains(name),
                schema: properties[name] ?? .null
            )
        }
    }

    private func requiredFieldNames(from value: JSONValue?) -> Set<String> {
        guard case let .array(values)? = value else { return [] }
        return Set(values.compactMap { item in
            guard case let .string(name) = item else { return nil }
            return name
        })
    }

    private func parameterMetadata(for schema: JSONValue) -> String {
        var parts: [String] = []
        if let type = stringValue("type", in: schema) {
            parts.append("type: \(type)")
        }
        if let values = stringArrayValue("enum", in: schema), !values.isEmpty {
            parts.append("enum: \(values.joined(separator: " | "))")
        }
        if let pattern = stringValue("pattern", in: schema) {
            parts.append("pattern: \(pattern)")
        }
        if let minimum = numberValue("minimum", in: schema) {
            parts.append("min: \(formatNumber(minimum))")
        }
        if let maximum = numberValue("maximum", in: schema) {
            parts.append("max: \(formatNumber(maximum))")
        }
        return parts.isEmpty ? "schema: \(schema.compactJSONString)" : parts.joined(separator: "  ")
    }

    private func stringValue(_ key: String, in schema: JSONValue) -> String? {
        guard case let .object(object) = schema,
              case let .string(value)? = object[key] else {
            return nil
        }
        return value
    }

    private func stringArrayValue(_ key: String, in schema: JSONValue) -> [String]? {
        guard case let .object(object) = schema,
              case let .array(values)? = object[key] else {
            return nil
        }
        return values.compactMap { item in
            guard case let .string(value) = item else { return nil }
            return value
        }
    }

    private func numberValue(_ key: String, in schema: JSONValue) -> Double? {
        guard case let .object(object) = schema,
              case let .number(value)? = object[key] else {
            return nil
        }
        return value
    }

    private func formatNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}
