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

    private var shouldShowPreview: Bool {
        !isComplete && !isShowingFullText
    }

    private var previewTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
        )
    }

    var body: some View {
        let previewWindow = inlinePreviewWindow
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isShowingFullText = true
            }
        } label: {
            VStack(alignment: .leading, spacing: shouldShowPreview ? 8 : 0) {
                HStack(spacing: 6) {
                    Image(systemName: statusIconName)
                        .font(.subheadline)
                        .foregroundStyle(statusColor)

                    Text(statusTextKey)
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Spacer(minLength: 0)
                }

                if shouldShowPreview {
                    ChatToolInlineContentView(
                        text: previewWindow.text,
                        placements: previewWindow.placements,
                        textStyle: .thinking(fontSize: thinkFontSize),
                        maxBubbleWidth: maxBubbleWidth
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: previewHeight, alignment: .bottom)
                    .clipped()
                    .transition(previewTransition)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .clipped()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
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
            maxBubbleWidth: maxBubbleWidth
        )
        .animation(.easeInOut(duration: 0.2), value: shouldShowPreview)
    }

    private var previewHeight: CGFloat {
        PlatformFontSpec(size: thinkFontSize, isMonospaced: true).lineHeight * CGFloat(max(1, previewLines))
    }

    private var inlinePreviewWindow: (text: String, placements: [ChatToolActivityPlacement]) {
        let maxCharacters = 4_000
        let length = think.count
        let cutoff = max(0, length - maxCharacters)
        guard cutoff > 0 else {
            return (think, toolActivityPlacements)
        }
        let start = think.index(think.startIndex, offsetBy: cutoff)
        let visibleText = String(think[start...])
        let visiblePlacements = toolActivityPlacements
            .filter { $0.offset >= cutoff }
            .map {
                ChatToolActivityPlacement(
                    activity: $0.activity,
                    scope: $0.scope,
                    offset: $0.offset - cutoff
                )
            }
        return (visibleText, visiblePlacements)
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
                        textStyle: .markdown,
                        maxBubbleWidth: maxBubbleWidth
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

    func body(content: Content) -> some View {
        #if os(macOS)
        content.popover(isPresented: $isPresented, arrowEdge: .top) {
            ThinkingDetailView(
                title: title,
                iconName: iconName,
                iconColor: iconColor,
                text: think,
                toolActivityPlacements: toolActivityPlacements,
                maxBubbleWidth: maxBubbleWidth
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
                maxBubbleWidth: maxBubbleWidth
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
        maxBubbleWidth: CGFloat?
    ) -> some View {
        modifier(
            ThinkDetailPresentationModifier(
                isPresented: isPresented,
                think: think,
                title: title,
                iconName: iconName,
                iconColor: iconColor,
                toolActivityPlacements: toolActivityPlacements,
                maxBubbleWidth: maxBubbleWidth
            )
        )
    }
}
