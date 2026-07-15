//
//  ThinkingPreviewBubble.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import SwiftUI

struct ThinkingPreviewBubble: View {
    let think: String
    let isComplete: Bool
    let previewLines: Int
    let thinkFontSize: CGFloat
    let toolActivityPlacements: [ChatToolActivityPlacement]
    let maxBubbleWidth: CGFloat?
    var developerModeEnabled = false
    var onAuthorizeTool: ((String, Bool) -> Void)? = nil

    @State private var isShowingFullText = false

    private var statusIconName: String {
        isComplete ? "checkmark.seal.fill" : "brain.head.profile"
    }

    private var statusColor: Color {
        isComplete ? .green : .orange
    }

    private var statusTextKey: LocalizedStringKey {
        isComplete ? "Thinking Complete" : "Thinking"
    }

    private var shouldShowTextPreview: Bool {
        !isComplete && !isShowingFullText
    }

    private var shouldShowToolPreview: Bool {
        !isShowingFullText && !toolActivityPlacements.isEmpty
    }

    private var previewTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
        )
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: shouldShowTextPreview || shouldShowToolPreview ? 8 : 0
        ) {
            Button(action: openDetail) {
                HStack(spacing: 6) {
                    Image(systemName: statusIconName)
                        .font(.subheadline)
                        .foregroundStyle(statusColor)

                    Text(statusTextKey)
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if shouldShowTextPreview {
                ThinkingInlinePreview(
                    text: think,
                    lines: previewLines,
                    font: PlatformFontSpec(size: thinkFontSize, isMonospaced: true),
                    toolActivityPlacements: toolActivityPlacements,
                    maxBubbleWidth: maxBubbleWidth,
                    developerModeEnabled: developerModeEnabled,
                    onAuthorizeTool: onAuthorizeTool,
                    onOpenDetail: openDetail
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(previewTransition)
            } else if shouldShowToolPreview {
                toolPreviews(toolActivityPlacements)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(statusTextKey)
        .accessibilityHint("Open full reasoning")
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .bubbleStyle(
            isUser: false,
            contentPadding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        )
        .contentShape(Rectangle())
        .thinkDetailPresentation(
            isPresented: $isShowingFullText,
            think: think,
            title: statusTextKey,
            iconName: statusIconName,
            iconColor: statusColor,
            toolActivityPlacements: toolActivityPlacements,
            maxBubbleWidth: maxBubbleWidth,
            developerModeEnabled: developerModeEnabled,
            onAuthorizeTool: onAuthorizeTool
        )
        .animation(.easeInOut(duration: 0.2), value: shouldShowTextPreview)
    }

    private func openDetail() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isShowingFullText = true
        }
    }

    @ViewBuilder
    private func toolPreviews(_ placements: [ChatToolActivityPlacement]) -> some View {
        ForEach(ChatToolActivityPlacementGrouper.groups(placements)) { group in
            ToolActivityBubble(
                activities: group.placements.map(\.activity),
                maxBubbleWidth: maxBubbleWidth,
                isEmbeddedInMessage: true,
                developerModeEnabled: developerModeEnabled,
                onAuthorize: onAuthorizeTool
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ThinkingInlinePreview: View {
    let text: String
    let lines: Int
    let font: PlatformFontSpec
    let toolActivityPlacements: [ChatToolActivityPlacement]
    let maxBubbleWidth: CGFloat?
    let developerModeEnabled: Bool
    let onAuthorizeTool: ((String, Bool) -> Void)?
    let onOpenDetail: () -> Void

    @State private var displayWindow = TailVisualTextWindow.empty
    @State private var lastComputedForTextCount = -1
    @State private var lastWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments) { segment in
                switch segment.kind {
                case let .text(value):
                    Text(value)
                        .font(.system(size: font.size, design: font.isMonospaced ? .monospaced : .default))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onOpenDetail)

                case let .tools(placements):
                    ToolActivityBubble(
                        activities: placements.map(\.activity),
                        maxBubbleWidth: maxBubbleWidth,
                        isEmbeddedInMessage: true,
                        developerModeEnabled: developerModeEnabled,
                        onAuthorize: onAuthorizeTool
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { geometry in
                let width = max(1, floor(geometry.size.width))
                Color.clear
                    .onAppear { recomputeIfNeeded(width: width) }
                    .onChange(of: text) { _, _ in recomputeIfNeeded(width: width) }
                    .onChange(of: geometry.size) { _, _ in recomputeIfNeeded(width: width) }
            }
        }
    }

    private var segments: [ChatToolInlineSegment] {
        ChatToolInlineSegmentBuilder.segments(
            text: displayWindow.text,
            placements: displayWindow.rebasedPlacements(toolActivityPlacements)
        )
    }

    private func recomputeIfNeeded(width: CGFloat) {
        let textCount = text.utf16.count
        let needsUpdate = textCount != lastComputedForTextCount || abs(width - lastWidth) > 0.5
        guard needsUpdate, width > 1 else { return }

        displayWindow = computeTailVisualTextWindow(
            text: text,
            width: width,
            lines: lines,
            font: font
        )
        lastComputedForTextCount = textCount
        lastWidth = width
    }
}

private struct ThinkingDetailView: View {
    #if os(visionOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    let title: LocalizedStringKey
    let iconName: String
    let iconColor: Color
    let text: String
    let toolActivityPlacements: [ChatToolActivityPlacement]
    let maxBubbleWidth: CGFloat?
    var developerModeEnabled = false
    var onAuthorizeTool: ((String, Bool) -> Void)? = nil

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.headline)
                        .foregroundStyle(iconColor)

                    Text(title)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)

                ScrollView {
                    ChatToolInlineContentView(
                        text: text,
                        placements: toolActivityPlacements,
                        maxBubbleWidth: maxBubbleWidth,
                        developerModeEnabled: developerModeEnabled,
                        onAuthorizeTool: onAuthorizeTool
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
            #if os(visionOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 680, maxWidth: 760, minHeight: 360, idealHeight: 620)
        #endif
    }
}

private struct ThinkDetailPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let think: String
    let title: LocalizedStringKey
    let iconName: String
    let iconColor: Color
    let toolActivityPlacements: [ChatToolActivityPlacement]
    let maxBubbleWidth: CGFloat?
    var developerModeEnabled = false
    var onAuthorizeTool: ((String, Bool) -> Void)? = nil

    func body(content: Content) -> some View {
        #if os(macOS)
        content.popover(isPresented: $isPresented, arrowEdge: .top) {
            ThinkingDetailView(
                title: title,
                iconName: iconName,
                iconColor: iconColor,
                text: think,
                toolActivityPlacements: toolActivityPlacements,
                maxBubbleWidth: maxBubbleWidth,
                developerModeEnabled: developerModeEnabled,
                onAuthorizeTool: onAuthorizeTool
            )
        }
        #else
        content.sheet(isPresented: $isPresented) {
            ThinkingDetailView(
                title: title,
                iconName: iconName,
                iconColor: iconColor,
                text: think,
                toolActivityPlacements: toolActivityPlacements,
                maxBubbleWidth: maxBubbleWidth,
                developerModeEnabled: developerModeEnabled,
                onAuthorizeTool: onAuthorizeTool
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
    func thinkDetailPresentation(
        isPresented: Binding<Bool>,
        think: String,
        title: LocalizedStringKey,
        iconName: String,
        iconColor: Color,
        toolActivityPlacements: [ChatToolActivityPlacement],
        maxBubbleWidth: CGFloat?,
        developerModeEnabled: Bool = false,
        onAuthorizeTool: ((String, Bool) -> Void)? = nil
    ) -> some View {
        modifier(
            ThinkDetailPresentationModifier(
                isPresented: isPresented,
                think: think,
                title: title,
                iconName: iconName,
                iconColor: iconColor,
                toolActivityPlacements: toolActivityPlacements,
                maxBubbleWidth: maxBubbleWidth,
                developerModeEnabled: developerModeEnabled,
                onAuthorizeTool: onAuthorizeTool
            )
        )
    }
}
