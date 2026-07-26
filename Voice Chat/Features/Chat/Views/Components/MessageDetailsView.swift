//
//  MessageDetailsView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2026/01/07.
//

import SwiftUI

struct MessageDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    let message: ChatMessage
    let toolActivities: [ChatToolActivity]
    let toolActivityPlacements: [ChatToolActivityPlacement]
    let developerModeEnabled: Bool
    private let requestContextRows: [MessageDetailsRequestContextRow]

    init(
        message: ChatMessage,
        toolActivities: [ChatToolActivity] = [],
        toolActivityPlacements: [ChatToolActivityPlacement] = [],
        developerModeEnabled: Bool = false
    ) {
        self.message = message
        self.toolActivities = toolActivities
        self.toolActivityPlacements = toolActivityPlacements
        self.developerModeEnabled = developerModeEnabled
        self.requestContextRows = Self.makeRequestContextRows(for: message)
    }

    private enum MetricSourceBadge {
        case provider
        case local

        var icon: String {
            switch self {
            case .provider:
                return "cloud.fill"
            case .local:
                return "laptopcomputer"
            }
        }

        var color: Color {
            switch self {
            case .provider:
                return .blue
            case .local:
                return .secondary
            }
        }

        var legendText: LocalizedStringKey {
            switch self {
            case .provider:
                return "According to Model Provider"
            case .local:
                return "Recorded Locally"
            }
        }
    }

    private struct ToolTraceItem: Identifiable {
        let activity: ChatToolActivity
        let placement: ChatToolActivityPlacement?

        var id: String {
            activity.id
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                PlatformColor.groupedBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        sourceIndicatorsHeader
                        identitySection
                        branchingSection
                        sessionSection
                        contentSection
                        requestContextSection

                        if !message.isUser {
                            assistantGenerationSection
                            toolTraceSection
                            assistantTimingSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 860, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .background(PlatformColor.groupedBackground)
#if os(iOS) || os(tvOS)
                .scrollContentBackground(.hidden)
#endif
            }
            .navigationTitle("Message Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 640, minHeight: 640)
#endif
    }

    @ViewBuilder
    private var identitySection: some View {
        sectionBox("Identity", systemImage: "person.text.rectangle") {
            detailRow("Message ID", fieldKey: "id", source: .local) { valueCode(message.id.uuidString) }
            detailRow("Created At", fieldKey: "createdAt", source: .local) { valueDate(message.createdAt) }
            detailRow("Sender", fieldKey: "isUser", source: .local) { valueText(message.isUser ? String(localized: "User") : String(localized: "Assistant")) }
            detailRow("Active", fieldKey: "isActive", source: .local) { valueText(formatBool(message.isActive)) }
        }
    }

    @ViewBuilder
    private var branchingSection: some View {
        sectionBox("Branching", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
            detailRow("Active Child Message ID", fieldKey: "activeChildMessageID", source: .local) { valueCode(formatUUID(message.activeChildMessageID)) }
            detailRow("Parent Message ID", fieldKey: "parentMessageID", source: .local) { valueCode(formatUUID(message.parentMessage?.id)) }
            detailRow("Child Messages", fieldKey: "childMessages.count", source: .local) { valueText("\(message.childMessages.count)") }

            if !message.childMessages.isEmpty {
                DisclosureGroup {
                    valueCode(message.childMessages.map(\.id.uuidString).joined(separator: "\n"))
                } label: {
                    fieldLabel("Child Message IDs", fieldKey: "childMessages[].id", source: .local)
                }
            }
        }
    }

    @ViewBuilder
    private var sessionSection: some View {
        sectionBox("Session", systemImage: "bubble.left.and.bubble.right") {
            detailRow("Chat Session ID", fieldKey: "session.id", source: .local) { valueCode(formatUUID(message.session?.id)) }
            detailRow("Chat Session Title", fieldKey: "session.title", source: .local) { valueText(message.session?.title) }
            detailRow("Active Root Message ID", fieldKey: "session.activeRootMessageID", source: .local) { valueCode(formatUUID(message.session?.activeRootMessageID)) }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        sectionBox("Content", systemImage: "doc.text") {
            detailRow("Character Count", fieldKey: "characterCount", source: .local) { valueText("\(resolvedCharacterCount)") }
            detailRow("Image Attachments", fieldKey: "imageAttachments.count", source: .local) { valueText("\(message.imageAttachments.count)") }
            if !message.assistantSegments.isEmpty {
                detailRow("Assistant Segments", fieldKey: "assistantSegments", source: .local) {
                    valueCode(formatAssistantSegments(message.assistantSegments))
                }
            }
        }
    }

    @ViewBuilder
    private var requestContextSection: some View {
        sectionBox("Request Context", systemImage: "doc.text.magnifyingglass") {
            ForEach(requestContextRows) { row in
                requestContextRow(row)
            }
        }
    }

    @ViewBuilder
    private func requestContextRow(_ row: MessageDetailsRequestContextRow) -> some View {
        detailRow(row.title, fieldKey: row.fieldKey, source: .local) {
            switch row.value {
            case .text(let value):
                valueText(value)
            case .code(let value):
                valueCode(value)
            case .date(let value):
                valueDate(value)
            }
        }
    }

    @ViewBuilder
    private var assistantGenerationSection: some View {
        sectionBox("Generation", systemImage: "chart.xyaxis.line") {
            detailRow("Model Identifier", fieldKey: "modelIdentifier", source: .local) { valueCode(message.modelIdentifier) }
            detailRow("API Base URL", fieldKey: "apiBaseURL", source: .local) { valueCode(message.apiBaseURL) }
            detailRow("Thinking Setting", fieldKey: "thinkingOptionRawValue", source: .local) { valueText(formatThinkingOption(message.thinkingOptionRawValue)) }
            detailRow("Request ID", fieldKey: "requestID", source: .local) { valueCode(formatUUID(message.requestID)) }
            detailRow("Provider Response ID", fieldKey: "providerResponseID", source: .provider) { valueCode(message.providerResponseID) }
            if !message.providerResponseIDs.isEmpty {
                detailRow("Provider Response IDs", fieldKey: "providerResponseIDs", source: .provider) {
                    valueCode(message.providerResponseIDs.enumerated().map { index, responseID in
                        "\(index + 1). \(responseID)"
                    }.joined(separator: "\n"))
                }
            }
            detailRow("Finish Reason", fieldKey: "finishReason", source: finishReasonSourceBadge) { valueText(message.finishReason) }
            detailRow("Error Description", fieldKey: "errorDescription", source: .local) { valueWrappedText(message.errorDescription) }
            detailRow("Output Token Count", fieldKey: "tokenCount", source: tokenCountSourceBadge) { valueText(formatInt(resolvedTokenCount)) }
            detailRow("Reasoning Output Tokens", fieldKey: "reasoningOutputTokenCount", source: reasoningTokenSourceBadge) { valueText(formatInt(message.reasoningOutputTokenCount)) }
            detailRow("Tokens Per Second", fieldKey: "tokensPerSecond", source: tokensPerSecondSourceBadge) { valueText(formatDouble(message.tokensPerSecond, decimals: 3)) }
            detailRow("Prompt Message Count", fieldKey: "promptMessageCount", source: .local) { valueText(formatInt(message.promptMessageCount)) }
            detailRow("Prompt Character Count", fieldKey: "promptCharacterCount", source: .local) { valueText(formatInt(message.promptCharacterCount)) }
        }
    }

    @ViewBuilder
    private var assistantTimingSection: some View {
        sectionBox("Timing", systemImage: "clock") {
            detailRow("Stream Started At", fieldKey: "streamStartedAt", source: .local) { valueDate(message.streamStartedAt) }
            detailRow("First Token At", fieldKey: "streamFirstTokenAt", source: firstTokenAtSourceBadge) { valueDate(message.streamFirstTokenAt) }
            detailRow("Stream Completed At", fieldKey: "streamCompletedAt", source: .local) { valueDate(message.streamCompletedAt) }
            detailRow("Time To First Token", fieldKey: "timeToFirstToken", source: timeToFirstTokenSourceBadge) { valueText(formatInterval(message.timeToFirstToken)) }
            detailRow("Stream Duration", fieldKey: "streamDuration", source: .local) { valueText(formatInterval(message.streamDuration)) }
            detailRow("Generation Duration", fieldKey: "generationDuration", source: .local) { valueText(formatInterval(message.generationDuration)) }
        }
    }

    @ViewBuilder
    private func sectionBox<Content: View>(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .labelStyle(.titleAndIcon)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(MessageDetailsChrome.sectionFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MessageDetailsChrome.sectionBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func detailRow<Value: View>(
        _ title: LocalizedStringKey,
        fieldKey: String,
        source: MetricSourceBadge? = nil,
        @ViewBuilder value: () -> Value
    ) -> some View {
        #if os(macOS)
        HStack(alignment: .top, spacing: 14) {
            fieldLabel(title, fieldKey: fieldKey, source: source)
                .frame(width: 240, alignment: .leading)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        #else
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(title, fieldKey: fieldKey, source: source)
            value()
        }
#endif
    }

    private func fieldLabel(_ title: LocalizedStringKey, fieldKey: String, source: MetricSourceBadge? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let source {
                    Image(systemName: source.icon)
                        .font(.caption2)
                        .foregroundStyle(source.color)
                }
            }
            Text(fieldKey)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospaced()
        }
    }

    private var toolTraceItems: [ToolTraceItem] {
        var seen = Set<String>()
        var items = toolActivityPlacements
            .sorted {
                if $0.offset == $1.offset {
                    return $0.id < $1.id
                }
                return $0.offset < $1.offset
            }
            .map { placement in
                seen.insert(placement.id)
                return ToolTraceItem(activity: placement.activity, placement: placement)
            }

        for activity in toolActivities.sorted(by: { $0.id < $1.id }) where !seen.contains(activity.id) {
            seen.insert(activity.id)
            items.append(ToolTraceItem(activity: activity, placement: nil))
        }
        return items
    }

    @ViewBuilder
    private var toolTraceSection: some View {
        sectionBox("Tool Trace", systemImage: "wrench.and.screwdriver") {
            let items = toolTraceItems
            detailRow("Tool Calls", fieldKey: "toolTrace.count", source: .local) {
                valueText(items.isEmpty ? String(localized: "None") : "\(items.count)")
            }

            if !items.isEmpty {
                detailRow("Used Tools", fieldKey: "toolTrace[].toolName", source: .local) {
                    valueCode(uniqueToolNames(from: items).joined(separator: "\n"))
                }

                ForEach(items) { item in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            detailRow("Activity ID", fieldKey: "toolTrace[].id", source: .local) {
                                valueCode(item.activity.id)
                            }
                            detailRow("Tool Name", fieldKey: "toolTrace[].toolName", source: .local) {
                                valueCode(item.activity.toolName)
                            }
                            detailRow("Title", fieldKey: "toolTrace[].title", source: .local) {
                                valueText(item.activity.title)
                            }
                            detailRow("Phase", fieldKey: "toolTrace[].phase", source: .local) {
                                valueText(formatToolPhase(item.activity.phase))
                            }
                            detailRow("Summary", fieldKey: "toolTrace[].summary", source: .local) {
                                valueWrappedText(item.activity.summary)
                            }
                            if let presentation = item.activity.presentation, !presentation.items.isEmpty {
                                detailRow("Displayed Items", fieldKey: "toolTrace[].presentation", source: .local) {
                                    ChatToolPresentationView(presentation: presentation)
                                }
                            }
                            if developerModeEnabled,
                               let resultPayload = item.activity.resultPayload,
                               !resultPayload.isEmpty {
                                detailRow("Result Payload", fieldKey: "toolTrace[].resultPayload", source: .local) {
                                    valueCode(JSONValue.object(resultPayload).debugPreviewJSONString(
                                        maxCharacters: 12_000,
                                        maxDepth: 8,
                                        maxCollectionItems: 80
                                    ))
                                }
                            }
                            detailRow("Placement Scope", fieldKey: "toolTrace[].scope", source: .local) {
                                valueText(item.placement?.scope.rawValue)
                            }
                            detailRow("Placement Offset", fieldKey: "toolTrace[].offset", source: .local) {
                                valueText(item.placement.map { "\($0.offset)" })
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: iconName(forToolName: item.activity.toolName))
                                .foregroundStyle(.secondary)
                            Text(item.activity.toolName)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 8)
                            Text(formatToolPhase(item.activity.phase))
                                .font(.caption)
                                .foregroundStyle(color(for: item.activity.phase))
                        }
                    }
                }
            }
        }
    }

    private func sourceLegendRow(_ source: MetricSourceBadge) -> some View {
        HStack(spacing: 8) {
            Image(systemName: source.icon)
                .foregroundStyle(source.color)
                .font(.caption)
            Text(source.legendText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var sourceIndicatorsHeader: some View {
        HStack(spacing: 18) {
            sourceLegendRow(.provider)
            sourceLegendRow(.local)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .appChromedContainer(cornerRadius: 10, shadowOpacity: 0.18)
    }

    private func metricSourceBadge(from raw: String?) -> MetricSourceBadge? {
        guard let raw else { return nil }
        switch raw {
        case "provider":
            return .provider
        case "local":
            return .local
        default:
            return nil
        }
    }

    private var tokenCountSourceBadge: MetricSourceBadge {
        if let explicit = metricSourceBadge(from: message.tokenCountSource) {
            return explicit
        }
        if message.outputTokenCount != nil && message.tokenCount <= 0 {
            return .provider
        }
        return .local
    }

    private var resolvedTokenCount: Int? {
        if message.tokenCount > 0 {
            return message.tokenCount
        }
        if let legacyProviderTokenCount = message.outputTokenCount,
           legacyProviderTokenCount > 0 {
            return legacyProviderTokenCount
        }
        return nil
    }

    private var resolvedCharacterCount: Int {
        message.characterCount > 0 ? message.characterCount : message.content.count
    }

    private var timeToFirstTokenSourceBadge: MetricSourceBadge {
        if let explicit = metricSourceBadge(from: message.timeToFirstTokenSource) {
            return explicit
        }
        return .local
    }

    private var tokensPerSecondSourceBadge: MetricSourceBadge {
        if let explicit = metricSourceBadge(from: message.tokensPerSecondSource) {
            return explicit
        }
        return .local
    }

    private var finishReasonSourceBadge: MetricSourceBadge {
        if let explicit = metricSourceBadge(from: message.finishReasonSource) {
            return explicit
        }
        return .local
    }

    private var reasoningTokenSourceBadge: MetricSourceBadge {
        .provider
    }

    private var firstTokenAtSourceBadge: MetricSourceBadge {
        if let explicit = metricSourceBadge(from: message.timeToFirstTokenSource),
           explicit == .provider {
            return .provider
        }
        return .local
    }

    private var horizontalValueIndicators: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    private func valueCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PlatformColor.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(ChatTheme.chromeBorder, lineWidth: 1)
            )
    }

    private func valueCode(_ value: String?) -> some View {
        let raw = value ?? ""
        let isPlaceholder = raw.isEmpty
        let display = isPlaceholder ? String(localized: "Not Available") : raw
        return valueCard {
            ScrollView(.horizontal, showsIndicators: horizontalValueIndicators) {
                Text(display)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(isPlaceholder ? .secondary : .primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.vertical, 1)
            }
        }
    }

    private func valueText(_ value: String?) -> some View {
        let raw = value ?? ""
        let isPlaceholder = raw.isEmpty
        let display = isPlaceholder ? String(localized: "Not Available") : raw
        return valueCard {
            Text(display)
                .font(.body)
                .foregroundStyle(isPlaceholder ? .secondary : .primary)
                .textSelection(.enabled)
        }
    }

    private func formatAssistantSegments(_ segments: [ChatAssistantSegment]) -> String {
        segments.enumerated().map { index, segment in
            let id = segment.itemID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let idLine = (id?.isEmpty == false) ? " id=\(id!)" : ""
            return "[\(index)] \(segment.kind.rawValue)\(idLine)\n\(segment.text)"
        }
        .joined(separator: "\n\n")
    }

    private func valueWrappedText(_ value: String?) -> some View {
        let raw = value ?? ""
        let isPlaceholder = raw.isEmpty
        let display = isPlaceholder ? String(localized: "Not Available") : raw
        return valueCard {
            Text(display)
                .font(.body)
                .foregroundStyle(isPlaceholder ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func valueDate(_ date: Date?) -> some View {
        if let date {
            let localized = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .medium)
            let iso = Self.isoFormatter.string(from: date)

            valueCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized)
                        .font(.body)
                    ScrollView(.horizontal, showsIndicators: horizontalValueIndicators) {
                        Text(iso)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true)
                            .padding(.vertical, 1)
                    }
                }
            }
        } else {
            valueText(nil)
        }
    }

    private func formatBool(_ value: Bool) -> String {
        value ? String(localized: "Yes") : String(localized: "No")
    }

    private func formatOptionalBool(_ value: Bool?) -> String? {
        guard let value else { return nil }
        return formatBool(value)
    }

    private func formatInt(_ value: Int?) -> String? {
        guard let value else { return nil }
        return String(value)
    }

    private func formatToolLoopLimit(_ value: Int?) -> String? {
        guard let value else { return nil }
        return value > 0 ? String(value) : String(localized: "Unlimited")
    }

    private func formatUUID(_ value: UUID?) -> String? {
        value?.uuidString
    }

    private func formatDouble(_ value: Double?, decimals: Int) -> String? {
        guard let value, value.isFinite else { return nil }
        return String(format: "%.\(decimals)f", value)
    }

    private func formatInterval(_ value: TimeInterval?) -> String? {
        guard let value else { return nil }
        return String(format: "%.3fs", value)
    }

    private func formatThinkingOption(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        guard let option = ModelThinkingOption.normalized(raw) else {
            return raw
        }
        return "\(option.displayName) (\(option.rawValue))"
    }

    private func uniqueToolNames(from items: [ToolTraceItem]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for item in items {
            let name = item.activity.toolName
            guard !seen.contains(name) else { continue }
            seen.insert(name)
            names.append(name)
        }
        return names
    }

    private func formatToolPhase(_ phase: ChatToolActivityPhase) -> String {
        switch phase {
        case .generating:
            return String(localized: "Generating")
        case .requested:
            return String(localized: "Requested")
        case .authorizing:
            return String(localized: "Authorizing")
        case .running:
            return String(localized: "Running")
        case .processing:
            return String(localized: "Processing")
        case .succeeded:
            return String(localized: "Succeeded")
        case .failed:
            return String(localized: "Failed")
        case .denied:
            return String(localized: "Denied")
        case .unsupported:
            return String(localized: "Unsupported")
        }
    }

    private func iconName(forToolName name: String) -> String {
        switch ChatToolID(toolName: name) {
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
        case .codeInterpreterRun:
            return "curlybraces"
        case .none:
            return "wrench.and.screwdriver"
        }
    }

    private func color(for phase: ChatToolActivityPhase) -> Color {
        switch phase {
        case .generating, .requested, .authorizing, .running, .processing:
            return .secondary
        case .succeeded:
            return .green
        case .failed, .denied:
            return .orange
        case .unsupported:
            return .secondary
        }
    }

    @MainActor
    private static func makeRequestContextRows(for message: ChatMessage) -> [MessageDetailsRequestContextRow] {
        var rows: [MessageDetailsRequestContextRow] = [
            .code("Fingerprint", fieldKey: "requestContextFingerprint", value: message.requestContextFingerprint),
            .text(
                "Previous Response ID Used",
                fieldKey: "requestUsedPreviousResponseID",
                value: Self.formatOptionalBoolValue(message.requestUsedPreviousResponseID)
            ),
            .code("Request Previous Response ID", fieldKey: "requestPreviousResponseID", value: message.requestPreviousResponseID)
        ]

        let metadata = ChatRequestContextMetadataStore.fetch(
            fingerprint: message.requestContextFingerprint,
            in: message.modelContext
        )
        if let metadata {
            rows.append(.text("Version", fieldKey: "requestContext.version", value: "\(metadata.version)"))
            rows.append(.code("Model", fieldKey: "requestContext.modelIdentifier", value: metadata.modelIdentifier))
            rows.append(.text("Provider", fieldKey: "requestContext.providerRawValue", value: metadata.providerRawValue))
            rows.append(.text("Request Style", fieldKey: "requestContext.requestStyleRawValue", value: metadata.requestStyleRawValue))
            rows.append(.code("Endpoint URL Hash", fieldKey: "requestContext.endpointURLHash", value: metadata.endpointURLHash))
            rows.append(.code("Developer Prompt Hash", fieldKey: "requestContext.developerPromptHash", value: metadata.developerPromptHash))
            rows.append(.text(
                "Developer Prompt Characters",
                fieldKey: "requestContext.developerPromptCharacterCount",
                value: "\(metadata.developerPromptCharacterCount)"
            ))
            rows.append(.text(
                "Thinking Setting",
                fieldKey: "requestContext.thinkingOptionRawValue",
                value: Self.formatThinkingOptionValue(metadata.thinkingOptionRawValue)
            ))
            rows.append(.text(
                "Tool Use Enabled",
                fieldKey: "requestContext.toolUseEnabled",
                value: Self.formatBoolValue(metadata.toolUseEnabled)
            ))
            rows.append(.code(
                "Enabled Tools",
                fieldKey: "requestContext.enabledToolIDs",
                value: metadata.enabledToolIDs.joined(separator: "\n")
            ))
            rows.append(.code("Tool Schema Digest", fieldKey: "requestContext.toolSchemaDigest", value: metadata.toolSchemaDigest))
            rows.append(.code(
                "Tool Schema Metadata",
                fieldKey: "requestContext.toolSchemaSummaryJSON",
                value: metadata.toolSchemaSummaryJSON
            ))
            rows.append(.text(
                "Authorization Mode",
                fieldKey: "requestContext.toolAuthorizationModeRawValue",
                value: metadata.toolAuthorizationModeRawValue
            ))
            rows.append(.text(
                "Automatic High-Risk Tools",
                fieldKey: "requestContext.allowHighRiskToolAutoExecution",
                value: Self.formatOptionalBoolValue(metadata.allowHighRiskToolAutoExecution)
            ))
            rows.append(.text(
                "Use Provider Continuation IDs",
                fieldKey: "requestContext.useProviderContinuationIDs",
                value: Self.formatOptionalBoolValue(metadata.useProviderContinuationIDs)
            ))
            rows.append(.text("Reference Count", fieldKey: "requestContext.referenceCount", value: "\(metadata.referenceCount)"))
            rows.append(.date("Created At", fieldKey: "requestContext.createdAt", value: metadata.createdAt))
            rows.append(.date("Last Seen At", fieldKey: "requestContext.lastSeenAt", value: metadata.lastSeenAt))
        } else if !(message.requestContextFingerprint?.isEmpty ?? true) {
            rows.append(.text("Metadata", fieldKey: "requestContext.metadata", value: String(localized: "Not Available")))
        }

        return rows
    }

    private static func formatBoolValue(_ value: Bool) -> String {
        value ? String(localized: "Yes") : String(localized: "No")
    }

    private static func formatOptionalBoolValue(_ value: Bool?) -> String? {
        guard let value else { return nil }
        return formatBoolValue(value)
    }

    private static func formatThinkingOptionValue(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        guard let option = ModelThinkingOption.normalized(raw) else {
            return raw
        }
        return "\(option.displayName) (\(option.rawValue))"
    }
}

private struct MessageDetailsRequestContextRow: Identifiable {
    enum Value {
        case text(String?)
        case code(String?)
        case date(Date?)
    }

    let id: String
    let title: LocalizedStringKey
    let fieldKey: String
    let value: Value

    static func text(_ title: LocalizedStringKey, fieldKey: String, value: String?) -> Self {
        Self(id: fieldKey, title: title, fieldKey: fieldKey, value: .text(value))
    }

    static func code(_ title: LocalizedStringKey, fieldKey: String, value: String?) -> Self {
        Self(id: fieldKey, title: title, fieldKey: fieldKey, value: .code(value))
    }

    static func date(_ title: LocalizedStringKey, fieldKey: String, value: Date?) -> Self {
        Self(id: fieldKey, title: title, fieldKey: fieldKey, value: .date(value))
    }
}

private enum MessageDetailsChrome {
    static var sectionFill: Color {
        Color.primary.opacity(0.045)
    }

    static var sectionBorder: Color {
        Color.primary.opacity(0.08)
    }
}

#Preview {
    let message: ChatMessage = {
        let session = ChatSession(title: "Preview Session")
        let now = Date()
        let message = ChatMessage(
            content: "Hello from the assistant.",
            isUser: false,
            isActive: false,
            createdAt: now.addingTimeInterval(-12),
            modelIdentifier: "preview-model",
            apiBaseURL: "http://localhost:1234",
            thinkingOptionRawValue: ModelThinkingOption.high.rawValue,
            requestID: UUID(),
            streamStartedAt: now.addingTimeInterval(-12),
            streamFirstTokenAt: now.addingTimeInterval(-11),
            streamCompletedAt: now.addingTimeInterval(-10),
            timeToFirstToken: 1.0,
            streamDuration: 2.0,
            generationDuration: 1.0,
            deltaCount: 42,
            characterCount: 128,
            promptMessageCount: 6,
            promptCharacterCount: 512,
            finishReason: "stop",
            errorDescription: nil,
            session: session
        )
        session.messages.append(message)
        return message
    }()

    MessageDetailsView(message: message)
        .modelContainer(for: [ChatSession.self, ChatMessage.self, ChatRequestContextMetadata.self, AppSettings.self], inMemory: true)
}
