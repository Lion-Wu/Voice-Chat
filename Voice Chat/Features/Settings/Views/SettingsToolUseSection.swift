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

    var body: some View {
        Group {
            Section {
                Toggle("Enable Tool Use", isOn: toolBinding(\.isEnabled))

                if viewModel.toolUseSettings.isEnabled {
                    Toggle("Allow Sensitive Tools Remotely", isOn: toolBinding(\.allowRemoteSensitiveTools))
                    Text("When disabled, calendar, reminders, location, and motion tools are available only to local or private-network endpoints.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                header
            }

            if viewModel.toolUseSettings.isEnabled {
                Section {
                    Toggle("Calendar", isOn: toolBinding(\.calendarEnabled))
                    Toggle("Reminders", isOn: toolBinding(\.remindersEnabled))
                    Toggle("Location", isOn: toolBinding(\.locationEnabled))
                    Toggle("Motion", isOn: toolBinding(\.motionEnabled))
                    Toggle("Device Context", isOn: toolBinding(\.deviceContextEnabled))

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

struct SettingsDeveloperToolUseSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var allDefinitions: [ChatToolDefinition] {
        ChatToolID.allCases.map { ChatToolDefinitions.definition(for: $0) }
    }

    var body: some View {
        Section {
            LabeledContent("Global State") {
                Text(viewModel.toolUseSettings.isEnabled ? "Enabled" : "Disabled")
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
        case .calendarListEvents:
            return "calendar"
        case .remindersListReminders:
            return "checklist"
        case .locationCurrent:
            return "location"
        case .motionDevice:
            return "gyroscope"
        case .deviceContext:
            return "desktopcomputer"
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
                            Text(field.required ? "required" : "optional")
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
