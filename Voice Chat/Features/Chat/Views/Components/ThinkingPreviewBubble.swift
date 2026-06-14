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
                    TailLinesText(
                        text: think,
                        lines: previewLines,
                        font: PlatformFontSpec(size: thinkFontSize, isMonospaced: true)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            iconColor: statusColor
        )
        .animation(.easeInOut(duration: 0.2), value: shouldShowPreview)
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
                    RichMarkdownView(markdown: text)
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

    func body(content: Content) -> some View {
        #if os(macOS)
        content.popover(isPresented: $isPresented, arrowEdge: .top) {
            ThinkingDetailView(
                title: title,
                iconName: iconName,
                iconColor: iconColor,
                text: think
            )
        }
        #else
        content.sheet(isPresented: $isPresented) {
            ThinkingDetailView(
                title: title,
                iconName: iconName,
                iconColor: iconColor,
                text: think
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
        iconColor: Color
    ) -> some View {
        modifier(
            ThinkDetailPresentationModifier(
                isPresented: isPresented,
                think: think,
                title: title,
                iconName: iconName,
                iconColor: iconColor
            )
        )
    }
}
