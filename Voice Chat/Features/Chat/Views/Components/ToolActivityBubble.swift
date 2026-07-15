//
//  ToolActivityBubble.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import SwiftUI

struct ToolActivityBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inspectedActivity: ChatToolActivity?
    let activities: [ChatToolActivity]
    var maxBubbleWidth: CGFloat? = nil
    var isEmbeddedInMessage = false
    var fillsAvailableWidth = false
    var developerModeEnabled = false
    var onAuthorize: ((String, Bool) -> Void)? = nil

    var body: some View {
        let barMaxWidth = fillsAvailableWidth
            ? (maxBubbleWidth ?? .infinity)
            : contentMaxWidthForAssistant(availableWidth: maxBubbleWidth)
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(activities) { activity in
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            inspectedActivity = activity
                        } label: {
                            row(activity)
                        }
                        .buttonStyle(.plain)
                        .disabled(!activity.hasInspectableDetails)
                        .help(activity.hasInspectableDetails ? String(localized: "View tool details") : "")
                        authorizationControls(for: activity)
                        presentationView(for: activity.presentation)
                    }
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ChatTheme.systemBubbleFill.opacity(0.9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(ChatTheme.subtleStroke.opacity(0.8))
                    }
            )
            .shadow(color: Color.black.opacity(0.035), radius: 5, x: 0, y: 2)
            .frame(maxWidth: barMaxWidth, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.vertical, isEmbeddedInMessage ? 1 : 4)
        #if os(macOS)
        .padding(.horizontal, isEmbeddedInMessage ? 0 : 16)
        #else
        .padding(.horizontal, isEmbeddedInMessage ? 0 : 2)
        #endif
        .toolActivityDetailPresentation(
            activity: $inspectedActivity,
            developerModeEnabled: developerModeEnabled
        )
    }

    @ViewBuilder
    private func authorizationControls(for activity: ChatToolActivity) -> some View {
        if activity.phase == .authorizing,
           let request = activity.authorizationRequest,
           let onAuthorize {
            VStack(alignment: .leading, spacing: 8) {
                Text(request.argumentsSummary)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Button("Allow") {
                        onAuthorize(request.id, true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Deny") {
                        onAuthorize(request.id, false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.leading, 31)
        }
    }

    @ViewBuilder
    private func presentationView(for presentation: ChatToolPresentation?) -> some View {
        if let presentation, !presentation.items.isEmpty {
            ChatToolPresentationView(
                presentation: presentation,
                style: .compactGrid
            )
            .padding(.leading, 31)
        }
    }

    private func row(_ activity: ChatToolActivity) -> some View {
        let summary = activity.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

        return HStack(alignment: .top, spacing: 9) {
            icon(for: activity)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(phaseTint(for: activity).opacity(0.12))
                )
                .padding(.top, summary == nil ? 1 : 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.84))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                if let summary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if activity.hasInspectableDetails {
                Image(systemName: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: summary == nil ? 24 : 36, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func icon(for activity: ChatToolActivity) -> some View {
        switch activity.phase {
        case .requested, .authorizing, .running, .processing:
            if reduceMotion {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(phaseTint(for: activity))
            } else {
                LoadingIndicatorView(tint: phaseTint(for: activity), dotSize: 4.5, spacing: 2.5)
            }
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(phaseTint(for: activity))
        case .denied:
            Image(systemName: "hand.raised.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(phaseTint(for: activity))
        case .unsupported:
            Image(systemName: "slash.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(phaseTint(for: activity))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(phaseTint(for: activity))
        }
    }

    private func phaseTint(for activity: ChatToolActivity) -> Color {
        switch activity.phase {
        case .requested, .authorizing, .running, .processing:
            return ChatTheme.accent.opacity(0.9)
        case .succeeded:
            return .green
        case .denied, .failed:
            return .orange
        case .unsupported:
            return .secondary
        }
    }
}

private struct ToolActivityDetailPresentationModifier: ViewModifier {
    @Binding var activity: ChatToolActivity?
    let developerModeEnabled: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content.popover(item: $activity) { activity in
            ToolActivityDetailView(
                activity: activity,
                developerModeEnabled: developerModeEnabled
            )
        }
        #else
        content.sheet(item: $activity) { activity in
            ToolActivityDetailView(
                activity: activity,
                developerModeEnabled: developerModeEnabled
            )
            #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            #elseif os(visionOS)
                .presentationDragIndicator(.visible)
            #endif
        }
        #endif
    }
}

private extension View {
    func toolActivityDetailPresentation(
        activity: Binding<ChatToolActivity?>,
        developerModeEnabled: Bool
    ) -> some View {
        modifier(ToolActivityDetailPresentationModifier(
            activity: activity,
            developerModeEnabled: developerModeEnabled
        ))
    }
}

private struct ToolActivityDetailView: View {
    let activity: ChatToolActivity
    let developerModeEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .opacity(0.55)

            ScrollView {
                detailContent
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        #if os(macOS)
            .frame(width: 640)
            .frame(maxHeight: 560)
        #else
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #endif
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = activity.summary?.nilIfBlank {
                detailSection(String(localized: "Summary")) {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let request = activity.authorizationRequest {
                detailSection(String(localized: "Requested Action")) {
                    VStack(alignment: .leading, spacing: 8) {
                        labeledValue(
                            title: String(localized: "Operation"),
                            value: request.operationKind.rawValue
                        )
                        wrappedCodeText(request.argumentsSummary)
                    }
                }
            }

            if let presentation = activity.presentation, !presentation.items.isEmpty {
                ChatToolPresentationView(
                    presentation: presentation,
                    style: .compactGrid
                )
            }

            if developerModeEnabled,
               let payload = activity.modelRequestPayload,
               !payload.isEmpty {
                detailSection(String(localized: "Model Request Data")) {
                    scrollableCodeBlock(JSONValue.object(payload).debugPreviewJSONString(
                        maxCharacters: 10_000,
                        maxDepth: 8,
                        maxCollectionItems: 80
                    ))
                }
            }

            if developerModeEnabled,
               let payload = activity.resultPayload,
               !payload.isEmpty {
                detailSection(String(localized: "Result Data")) {
                    scrollableCodeBlock(JSONValue.object(payload).debugPreviewJSONString(
                        maxCharacters: 10_000,
                        maxDepth: 8,
                        maxCollectionItems: 80
                    ))
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            phaseIcon
                .frame(width: 28, height: 28)
                .background(Circle().fill(phaseTint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(activity.toolName)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(phaseText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(phaseTint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(phaseTint.opacity(0.12)))
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var phaseIcon: some View {
        switch activity.phase {
        case .requested, .authorizing, .running, .processing:
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(phaseTint)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(phaseTint)
        case .denied:
            Image(systemName: "hand.raised.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(phaseTint)
        case .unsupported:
            Image(systemName: "slash.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(phaseTint)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(phaseTint)
        }
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ChatTheme.systemBubbleFill.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(ChatTheme.subtleStroke.opacity(0.75))
                }
        )
    }

    private func labeledValue(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private func wrappedCodeText(_ value: String) -> some View {
        Text(value)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scrollableCodeBlock(_ value: String) -> some View {
        ScrollView(.horizontal) {
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var phaseText: String {
        switch activity.phase {
        case .requested:
            return String(localized: "Requested")
        case .authorizing:
            return String(localized: "Needs Approval")
        case .running:
            return String(localized: "Running")
        case .processing:
            return String(localized: "Processing")
        case .succeeded:
            return String(localized: "Done")
        case .failed:
            return String(localized: "Failed")
        case .denied:
            return String(localized: "Denied")
        case .unsupported:
            return String(localized: "Unsupported")
        }
    }

    private var phaseTint: Color {
        switch activity.phase {
        case .requested, .authorizing, .running, .processing:
            return ChatTheme.accent.opacity(0.9)
        case .succeeded:
            return .green
        case .denied, .failed:
            return .orange
        case .unsupported:
            return .secondary
        }
    }
}

private extension ChatToolActivity {
    var hasInspectableDetails: Bool {
        if authorizationRequest != nil {
            return true
        }
        if let summary = summary?.nilIfBlank {
            return !summary.isEmpty
        }
        if let presentation, !presentation.items.isEmpty {
            return true
        }
        if let resultPayload, !resultPayload.isEmpty {
            return true
        }
        return false
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
