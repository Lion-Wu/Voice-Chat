//
//  MessageDetailsView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2026/01/07.
//

import SwiftUI

struct MessageDetailsView: View {
    @Bindable var message: ChatMessage
    @Environment(\.dismiss) private var dismiss

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

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sourceIndicatorsHeader

                    sectionBox("Identity", systemImage: "person.text.rectangle") {
                        detailRow("Message ID", fieldKey: "id", source: .local) { valueCode(message.id.uuidString) }
                        detailRow("Created At", fieldKey: "createdAt", source: .local) { valueDate(message.createdAt) }
                        detailRow("Sender", fieldKey: "isUser", source: .local) { valueText(message.isUser ? String(localized: "User") : String(localized: "Assistant")) }
                        detailRow("Active", fieldKey: "isActive", source: .local) { valueText(formatBool(message.isActive)) }
                    }

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

                    sectionBox("Session", systemImage: "bubble.left.and.bubble.right") {
                        detailRow("Chat Session ID", fieldKey: "session.id", source: .local) { valueCode(formatUUID(message.session?.id)) }
                        detailRow("Chat Session Title", fieldKey: "session.title", source: .local) { valueText(message.session?.title) }
                        detailRow("Active Root Message ID", fieldKey: "session.activeRootMessageID", source: .local) { valueCode(formatUUID(message.session?.activeRootMessageID)) }
                    }

                    sectionBox("Telemetry", systemImage: "chart.xyaxis.line") {
                        detailRow("Model Identifier", fieldKey: "modelIdentifier", source: .local) { valueCode(message.modelIdentifier) }
                        detailRow("API Base URL", fieldKey: "apiBaseURL", source: .local) { valueCode(message.apiBaseURL) }
                        detailRow("Request ID", fieldKey: "requestID", source: .local) { valueCode(formatUUID(message.requestID)) }
                        detailRow("Provider Response ID", fieldKey: "providerResponseID", source: .provider) { valueCode(message.providerResponseID) }
                        detailRow("Finish Reason", fieldKey: "finishReason", source: finishReasonSourceBadge) { valueText(message.finishReason) }
                        detailRow("Error Description", fieldKey: "errorDescription", source: .local) { valueWrappedText(message.errorDescription) }
                        detailRow("Token Count", fieldKey: "tokenCount", source: tokenCountSourceBadge) { valueText(formatInt(resolvedTokenCount)) }
                        detailRow("Reasoning Output Tokens", fieldKey: "reasoningOutputTokenCount", source: reasoningTokenSourceBadge) { valueText(formatInt(message.reasoningOutputTokenCount)) }
                        detailRow("Tokens Per Second", fieldKey: "tokensPerSecond", source: tokensPerSecondSourceBadge) { valueText(formatDouble(message.tokensPerSecond, decimals: 3)) }
                        detailRow("Character Count", fieldKey: "characterCount", source: .local) { valueText("\(message.characterCount)") }
                        detailRow("Prompt Message Count", fieldKey: "promptMessageCount", source: .local) { valueText(formatInt(message.promptMessageCount)) }
                        detailRow("Prompt Character Count", fieldKey: "promptCharacterCount", source: .local) { valueText(formatInt(message.promptCharacterCount)) }
                    }

                    sectionBox("Timing", systemImage: "clock") {
                        detailRow("Stream Started At", fieldKey: "streamStartedAt", source: .local) { valueDate(message.streamStartedAt) }
                        detailRow("First Token At", fieldKey: "streamFirstTokenAt", source: firstTokenAtSourceBadge) { valueDate(message.streamFirstTokenAt) }
                        detailRow("Stream Completed At", fieldKey: "streamCompletedAt", source: .local) { valueDate(message.streamCompletedAt) }
                        detailRow("Time To First Token", fieldKey: "timeToFirstToken", source: timeToFirstTokenSourceBadge) { valueText(formatInterval(message.timeToFirstToken)) }
                        detailRow("Stream Duration", fieldKey: "streamDuration", source: .local) { valueText(formatInterval(message.streamDuration)) }
                        detailRow("Generation Duration", fieldKey: "generationDuration", source: .local) { valueText(formatInterval(message.generationDuration)) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: 860, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(AppBackgroundView())
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
    private func sectionBox<Content: View>(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
        .groupBoxStyle(.automatic)
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
        .background(PlatformColor.tertiaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ChatTheme.chromeBorder, lineWidth: 1)
        )
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

    private func formatInt(_ value: Int?) -> String? {
        guard let value else { return nil }
        return String(value)
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
        .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
}
