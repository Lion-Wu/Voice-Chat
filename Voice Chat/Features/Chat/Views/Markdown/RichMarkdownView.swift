//
//  RichMarkdownView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftStreamingMarkdown
import SwiftUI

struct RichMarkdownView: View {
    let markdown: String
    var searchHighlightQuery: String? = nil
    var animateNewText = false

    @StateObject private var source = RichMarkdownSnapshotSource()
    @Environment(\.chatInitialRenderCoordinator) private var initialRenderCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        StreamedMarkdownView(
            source: source,
            config: renderConfig,
            onFirstRender: reportInitialRender
        )
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            initialRenderCoordinator?.register(source)
        }
        .onDisappear {
            initialRenderCoordinator?.unregister(source)
        }
        .task(id: markdown) {
            source.send(markdown)
        }
    }

    @MainActor
    private func reportInitialRender() {
        initialRenderCoordinator?.markRendered(source)
    }

    private var renderConfig: MarkdownRenderConfig {
        let defaults = MarkdownRenderConfig.default
        let primaryForegroundColor = platformPrimaryForegroundColor
        return MarkdownRenderConfig(
            shouldAnimateText: animateNewText,
            colorScheme: colorScheme,
            blockQuoteStyle: .init(
                textFonts: defaults.blockQuoteStyle.textFonts,
                textColor: primaryForegroundColor
            ),
            headingStyle: .init(
                h1Font: defaults.headingStyle.h1Font,
                h2Font: defaults.headingStyle.h2Font,
                h3Font: defaults.headingStyle.h3Font,
                h4Font: defaults.headingStyle.h4Font,
                h5Font: defaults.headingStyle.h5Font,
                h6Font: defaults.headingStyle.h6Font,
                textColor: primaryForegroundColor
            ),
            orderedListStyle: .init(
                textFonts: defaults.orderedListStyle.textFonts,
                textColor: primaryForegroundColor
            ),
            paragraphStyle: .init(
                textFonts: defaults.paragraphStyle.textFonts,
                textColor: primaryForegroundColor
            ),
            tableStyle: .init(
                textFonts: defaults.tableStyle.textFonts,
                headerTextColor: primaryForegroundColor,
                regularTextColor: primaryForegroundColor,
                headerBackgroundColor: tableHeaderBackgroundColor,
                borderColor: borderColor,
                actionButtonColor: secondaryForegroundColor
            ),
            inlineStyle: .init(
                boldTextColor: primaryForegroundColor,
                linkTextFont: defaults.inlineStyle.linkTextFont,
                linkTextColor: linkColor,
                codeTextFont: defaults.inlineStyle.codeTextFont,
                codeTextColor: primaryForegroundColor,
                codeBackgroundColor: tableHeaderBackgroundColor,
                codeUnderlineColor: codeHeaderForegroundColor
            ),
            citationConfig: .init(
                coder: defaults.citationConfig.coder,
                font: defaults.citationConfig.font,
                textColor: primaryForegroundColor,
                backgroundColor: citationBackgroundColor
            ),
            codeBlockConfig: CodeBlockConfig(
                theme: .xcode,
                backgroundColor: codeBlockBackgroundColor,
                foregroundColor: codeHeaderForegroundColor
            ),
            blockSpacing: MarkdownRenderConfig.defaultBlockSpacing,
            textSelectionConfig: TextSelectionConfig(isEnabled: true),
            thematicBreakColor: thematicBreakColor,
            searchHighlightQuery: searchHighlightQuery
        )
    }

    /// Keep attachment colors static at the render boundary. Dynamic platform
    /// colors can lose their appearance when bridged through SwiftUI and back.
    private var platformPrimaryForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var linkColor: Color {
        color(
            light: (0, 109, 204),
            dark: (88, 166, 255)
        )
    }

    private var tableHeaderBackgroundColor: Color {
        color(
            light: (244, 245, 247),
            dark: (42, 44, 48)
        )
    }

    private var borderColor: Color {
        color(
            light: (218, 221, 227),
            dark: (58, 61, 66)
        )
    }

    private var thematicBreakColor: Color {
        color(
            light: (201, 205, 212),
            dark: (70, 74, 80)
        )
    }

    private var secondaryForegroundColor: Color {
        color(
            light: (85, 91, 97),
            dark: (201, 205, 210)
        )
    }

    private var codeBlockBackgroundColor: Color {
        color(
            light: (224, 227, 232),
            dark: (36, 38, 42)
        )
    }

    private var codeHeaderForegroundColor: Color {
        color(
            light: (138, 143, 152),
            dark: (156, 163, 175)
        )
    }

    private var citationBackgroundColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05)
    }

    private func color(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        let components = colorScheme == .dark ? dark : light
        return Color(
            red: components.0 / 255,
            green: components.1 / 255,
            blue: components.2 / 255
        )
    }
}

@MainActor
final class ChatInitialRenderCoordinator: ObservableObject {
    @Published private(set) var isReady = false

    private var isCollecting = false
    private var renderers: Set<ObjectIdentifier> = []
    private var rendered: Set<ObjectIdentifier> = []
    private var layoutRevision: UInt64 = 0
    private var requiredLayoutRevision: UInt64?

    func begin() {
        isCollecting = true
        renderers.removeAll(keepingCapacity: true)
        rendered.removeAll(keepingCapacity: true)
        requiredLayoutRevision = nil
        isReady = false
    }

    func register(_ renderer: AnyObject) {
        guard !isReady else { return }
        if renderers.insert(ObjectIdentifier(renderer)).inserted {
            requiredLayoutRevision = nil
        }
    }

    func unregister(_ renderer: AnyObject) {
        guard !isReady else { return }
        let identifier = ObjectIdentifier(renderer)
        renderers.remove(identifier)
        rendered.remove(identifier)
        requiredLayoutRevision = nil
        resolveIfReady()
    }

    func markRendered(_ renderer: AnyObject) {
        guard !isReady else { return }
        let identifier = ObjectIdentifier(renderer)
        renderers.insert(identifier)
        rendered.insert(identifier)
        requiredLayoutRevision = nil
        resolveIfReady()
    }

    func finishCollecting() {
        guard isCollecting else { return }
        isCollecting = false
        resolveIfReady()
    }

    func contentDidLayout() {
        guard !isReady else { return }
        layoutRevision &+= 1
        resolveIfReady()
    }

    private func resolveIfReady() {
        guard rendered.isSuperset(of: renderers) else {
            return
        }
        if renderers.isEmpty {
            if !isCollecting {
                complete()
            }
            return
        }
        if requiredLayoutRevision == nil {
            requiredLayoutRevision = layoutRevision &+ 1
        }
        guard !isCollecting,
              let requiredLayoutRevision,
              layoutRevision >= requiredLayoutRevision else {
            return
        }
        complete()
    }

    private func complete() {
        isReady = true
        renderers.removeAll(keepingCapacity: true)
        rendered.removeAll(keepingCapacity: true)
        requiredLayoutRevision = nil
    }
}

private struct ChatInitialRenderCoordinatorKey: EnvironmentKey {
    static let defaultValue: ChatInitialRenderCoordinator? = nil
}

extension EnvironmentValues {
    var chatInitialRenderCoordinator: ChatInitialRenderCoordinator? {
        get { self[ChatInitialRenderCoordinatorKey.self] }
        set { self[ChatInitialRenderCoordinatorKey.self] = newValue }
    }
}

@MainActor
private final class RichMarkdownSnapshotSource:
    ObservableObject,
    StreamedMarkdownSource
{
    private var latestMarkdown: String?
    private var continuations: [
        UUID: AsyncStream<String>.Continuation
    ] = [:]

    var text: AsyncStream<String> {
        AsyncStream(
            bufferingPolicy: .bufferingNewest(1)
        ) { continuation in
            let id = UUID()
            continuations[id] = continuation
            if let latestMarkdown {
                continuation.yield(latestMarkdown)
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuations.removeValue(forKey: id)
                }
            }
        }
    }

    deinit {
        continuations.values.forEach { $0.finish() }
    }

    func send(_ markdown: String) {
        guard markdown != latestMarkdown else { return }
        latestMarkdown = markdown
        continuations.values.forEach { $0.yield(markdown) }
    }
}
