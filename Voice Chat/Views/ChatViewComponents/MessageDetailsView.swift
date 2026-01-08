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

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionBox("Identity", systemImage: "person.text.rectangle") {
                        detailRow("Message ID", fieldKey: "id") { valueCode(message.id.uuidString) }
                        detailRow("Created At", fieldKey: "createdAt") { valueDate(message.createdAt) }
                        detailRow("Sender", fieldKey: "isUser") { valueText(message.isUser ? String(localized: "User") : String(localized: "Assistant")) }
                        detailRow("Active", fieldKey: "isActive") { valueText(formatBool(message.isActive)) }
                    }

                    sectionBox("Branching", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                        detailRow("Active Child Message ID", fieldKey: "activeChildMessageID") { valueCode(formatUUID(message.activeChildMessageID)) }
                        detailRow("Parent Message ID", fieldKey: "parentMessageID") { valueCode(formatUUID(message.parentMessage?.id)) }
                        detailRow("Child Messages", fieldKey: "childMessages.count") { valueText("\(message.childMessages.count)") }

                        if !message.childMessages.isEmpty {
                            DisclosureGroup {
                                valueCode(message.childMessages.map(\.id.uuidString).joined(separator: "\n"))
                            } label: {
                                fieldLabel("Child Message IDs", fieldKey: "childMessages[].id")
                            }
                        }
                    }

                    sectionBox("Session", systemImage: "bubble.left.and.bubble.right") {
                        detailRow("Chat Session ID", fieldKey: "session.id") { valueCode(formatUUID(message.session?.id)) }
                        detailRow("Chat Session Title", fieldKey: "session.title") { valueText(message.session?.title) }
                        detailRow("Active Root Message ID", fieldKey: "session.activeRootMessageID") { valueCode(formatUUID(message.session?.activeRootMessageID)) }
                    }

                    sectionBox("Telemetry", systemImage: "chart.xyaxis.line") {
                        detailRow("Model Identifier", fieldKey: "modelIdentifier") { valueCode(message.modelIdentifier) }
                        detailRow("API Base URL", fieldKey: "apiBaseURL") { valueCode(message.apiBaseURL) }
                        detailRow("Request ID", fieldKey: "requestID") { valueCode(formatUUID(message.requestID)) }
                        detailRow("Finish Reason", fieldKey: "finishReason") { valueText(message.finishReason) }
                        detailRow("Error Description", fieldKey: "errorDescription") { valueWrappedText(message.errorDescription) }
                        detailRow("Delta Count", fieldKey: "deltaCount") { valueText("\(message.deltaCount)") }
                        detailRow("Character Count", fieldKey: "characterCount") { valueText("\(message.characterCount)") }
                        detailRow("Prompt Message Count", fieldKey: "promptMessageCount") { valueText(formatInt(message.promptMessageCount)) }
                        detailRow("Prompt Character Count", fieldKey: "promptCharacterCount") { valueText(formatInt(message.promptCharacterCount)) }
                    }

                    sectionBox("Timing", systemImage: "clock") {
                        detailRow("Stream Started At", fieldKey: "streamStartedAt") { valueDate(message.streamStartedAt) }
                        detailRow("First Token At", fieldKey: "streamFirstTokenAt") { valueDate(message.streamFirstTokenAt) }
                        detailRow("Stream Completed At", fieldKey: "streamCompletedAt") { valueDate(message.streamCompletedAt) }
                        detailRow("Time To First Token", fieldKey: "timeToFirstToken") { valueText(formatInterval(message.timeToFirstToken)) }
                        detailRow("Stream Duration", fieldKey: "streamDuration") { valueText(formatInterval(message.streamDuration)) }
                        detailRow("Generation Duration", fieldKey: "generationDuration") { valueText(formatInterval(message.generationDuration)) }
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
        @ViewBuilder value: () -> Value
    ) -> some View {
        #if os(macOS)
        HStack(alignment: .top, spacing: 14) {
            fieldLabel(title, fieldKey: fieldKey)
                .frame(width: 240, alignment: .leading)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        #else
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(title, fieldKey: fieldKey)
            value()
        }
        #endif
    }

    private func fieldLabel(_ title: LocalizedStringKey, fieldKey: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(fieldKey)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospaced()
        }
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

    private func formatInterval(_ value: TimeInterval?) -> String? {
        guard let value else { return nil }
        return String(format: "%.3fs", value)
    }
}
