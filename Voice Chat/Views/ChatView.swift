//
//  ChatView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024/1/8.
//

import SwiftUI
#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import Foundation
import MarkdownUI
import CoreText

// MARK: - ─────────── 平台类型别名 ────────────

#if os(iOS) || os(tvOS) || os(watchOS)
private typealias PlatformNativeFont = UIFont
#elseif os(macOS)
private typealias PlatformNativeFont = NSFont
#endif

// MARK: - ─────────── 平台颜色映射 ────────────

private enum PlatformColor {
    static var systemBackground: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }
    static var secondaryBackground: Color {
        #if os(macOS)
        return Color(NSColor.underPageBackgroundColor)
        #else
        return Color(UIColor.secondarySystemBackground)
        #endif
    }
    static var bubbleSystemFill: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(UIColor.secondarySystemBackground)
        #endif
    }
}

// MARK: - ─────────── 主题与辅助样式 ────────────

private enum ChatTheme {
    static let bgGradient = LinearGradient(
        gradient: Gradient(colors: [
            PlatformColor.systemBackground,
            PlatformColor.secondaryBackground.opacity(0.6)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let inputBG: Material = .thin
    static let bubbleRadius: CGFloat = 16
    static let bubbleShadow = Color.black.opacity(0.06)
    static let separator = Color.primary.opacity(0.06)

    static let userBubbleGradient = LinearGradient(
        colors: [Color.blue.opacity(0.85), Color.blue.opacity(0.75)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let systemBubbleFill = PlatformColor.bubbleSystemFill
    static let subtleStroke = Color.primary.opacity(0.08)
    static let accent = Color.blue
}

private struct BubbleBackground: ViewModifier {
    let isUser: Bool
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(isUser ? AnyView(ChatTheme.userBubbleGradient) : AnyView(ChatTheme.systemBubbleFill))
            .overlay(
                RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous)
                    .stroke(ChatTheme.subtleStroke, lineWidth: isUser ? 0 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous))
            .shadow(color: ChatTheme.bubbleShadow, radius: 8, x: 0, y: 4)
    }
}
private extension View { func bubbleStyle(isUser: Bool) -> some View { modifier(BubbleBackground(isUser: isUser)) } }

// MARK: - ─────────── 使用 MarkdownUI 的 Markdown 渲染 ────────────

fileprivate struct RichMarkdownView: View {
    let markdown: String
    var body: some View {
        Markdown(markdown)
            .markdownTheme(.gitHub)
            .markdownImageProvider(.default)
            .textSelection(.enabled)
            .tint(ChatTheme.accent)
            .font(.system(size: 16))
    }
}

// MARK: - ─────────── <think> 提取 ────────────

private struct ThinkParts {
    let think: String?
    let isClosed: Bool
    let body: String
}

private extension String {
    func extractThinkParts() -> ThinkParts {
        guard let start = range(of: "<think>") else { return ThinkParts(think: nil, isClosed: true, body: self) }
        let afterStart = self[start.upperBound...]
        if let end = afterStart.range(of: "</think>") {
            let thinkContent = String(afterStart[..<end.lowerBound])
            let bodyContent  = String(afterStart[end.upperBound...])
            return ThinkParts(think: thinkContent, isClosed: true, body: bodyContent)
        } else {
            return ThinkParts(think: String(afterStart), isClosed: false, body: "")
        }
    }
}

// MARK: - ─────────── 仅渲染“最后 N 条视觉行”的高性能预览（CoreText 断行 + Text 渲染） ────────────

/// 平台字体规格
private struct PlatformFontSpec: Equatable {
    let size: CGFloat
    let isMonospaced: Bool

    var native: PlatformNativeFont {
        #if os(iOS) || os(tvOS) || os(watchOS)
        return isMonospaced ? .monospacedSystemFont(ofSize: size, weight: .regular)
                            : .systemFont(ofSize: size)
        #else
        return isMonospaced ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                            : NSFont.systemFont(ofSize: size)
        #endif
    }

    var lineHeight: CGFloat {
        #if os(iOS) || os(tvOS) || os(watchOS)
        native.lineHeight
        #else
        (native.ascender - native.descender) + native.leading
        #endif
    }

    var ctFont: CTFont { CTFontCreateWithName(native.fontName as CFString, size, nil) }
}

/// 只渲染“最后 N 条视觉行”（真实换行），始终**底对齐**，最新行在**最下方**
private struct TailLinesText: View {
    let text: String
    let lines: Int
    let font: PlatformFontSpec
    /// 固定高度（行高 × 行数）
    private var fixedHeight: CGFloat { font.lineHeight * CGFloat(max(1, lines)) }

    @State private var displayTail: String = ""   // 实际展示的那段小文本
    @State private var lastComputedForTextCount: Int = -1
    @State private var lastWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = max(1, floor(geo.size.width))

            // 底对齐展示（最新行在最下）
            ZStack(alignment: .bottomLeading) {
                Text(displayTail)
                    .font(.system(size: font.size, design: font.isMonospaced ? .monospaced : .default))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(nil, value: displayTail)
            }
            .frame(width: w, height: fixedHeight, alignment: .bottomLeading)
            .onAppear { recomputeIfNeeded(width: w) }
            .onChange(of: text) { _, _ in recomputeIfNeeded(width: w) }
            .onChange(of: geo.size) { _, _ in recomputeIfNeeded(width: w) }
        }
        .frame(height: fixedHeight, alignment: .bottom)
        .accessibilityLabel("思考预览（仅尾部若干真实视觉行）")
    }

    /// 只在必要时重算，避免重复开销
    private func recomputeIfNeeded(width: CGFloat) {
        let tcount = text.utf16.count
        let needs = (tcount != lastComputedForTextCount) || abs(width - lastWidth) > 0.5
        guard needs, width > 1 else { return }

        displayTail = computeTailVisualLines(text: text, width: width, lines: lines, font: font)
        lastComputedForTextCount = tcount
        lastWidth = width
    }
}

/// 使用 CoreText 断行，仅对**文本尾部的窗口**做布局，直到覆盖到 N 条视觉行为止
private func computeTailVisualLines(text: String, width: CGFloat, lines: Int, font: PlatformFontSpec) -> String {
    guard !text.isEmpty, width > 1, lines > 0 else { return "" }

    // 为了效率，仅对尾部窗口断行；不足时倍增窗口，最多 32K 字
    let ns = text as NSString
    let total = ns.length
    var windowLen = min(2048, total)
    let maxLen = min(32768, total)

    var lastResult: String = ""
    while true {
        let start = max(0, total - windowLen)
        let range = NSRange(location: start, length: total - start)
        let chunk = ns.substring(with: range) as NSString

        // CoreText 断行（使用 chunk 作为排版对象）
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font.ctFont
        ]
        let attrStr = CFAttributedStringCreate(nil, chunk as CFString, attrs as CFDictionary)!
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)

        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: width, height: 10_000))
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let linesCF = CTFrameGetLines(frame)
        let count = CFArrayGetCount(linesCF)

        if count == 0 {
            // 没断出行（极端情况），返回空
            return ""
        }

        // 取最后 N 行在 chunk 中的字符串范围
        let take = min(lines, count)
        var firstLoc = Int.max
        var lastMax = 0
        for i in (count - take)..<count {
            let unmanaged = CFArrayGetValueAtIndex(linesCF, i)
            let line = unsafeBitCast(unmanaged, to: CTLine.self)
            let r = CTLineGetStringRange(line) // 相对于 chunk
            let loc = r.location
            let len = r.length
            firstLoc = min(firstLoc, loc)
            lastMax = max(lastMax, loc + len)
        }
        let tailRange = NSRange(location: firstLoc == Int.max ? 0 : firstLoc,
                                length: max(0, lastMax - (firstLoc == Int.max ? 0 : firstLoc)))
        let tail = chunk.substring(with: NSIntersectionRange(tailRange, NSRange(location: 0, length: chunk.length)))

        lastResult = tail

        // 如果已经覆盖到 N 行，或窗口已到上限，就结束
        if count >= lines || windowLen >= maxLen || windowLen >= total {
            break
        }

        // 否则扩大窗口再试（倍增）
        windowLen = min(maxLen, min(total, windowLen * 2))
    }

    return lastResult
}

// MARK: - ─────────── 仅当“视觉上多了一行”才触发自动滚动 ────────────

private struct LineHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 18 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct HeightMeasurer: View {
    let font: Font
    @Binding var lineHeight: CGFloat
    var body: some View {
        Text("A")
            .font(font)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: LineHeightKey.self, value: geo.size.height)
                }
            )
            .hidden()
            .onPreferenceChange(LineHeightKey.self) { h in
                lineHeight = max(1, h)
            }
    }
}

private struct MessageHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - ─────────── 视图模型 & 主要视图 ────────────

struct ChatView: View {
    @EnvironmentObject var chatSessionsViewModel: ChatSessionsViewModel
    @EnvironmentObject var audioManager: GlobalAudioManager
    @StateObject private var viewModel: ChatViewModel
    @State private var textFieldHeight: CGFloat = 44
    @FocusState private var isInputFocused: Bool

    @State private var isShowingTextSelectionSheet = false
    @State private var textSelectionContent = ""

    @State private var isAtBottom: Bool = true
    @State private var lastMeasuredLastMessageHeight: CGFloat = 0
    @State private var bodyLineHeight: CGFloat = 19
    @State private var lastMessageID: UUID?

    @State private var lastThinkClosedForLastMessage: Bool?
    @State private var lastBodyLenForLastMessage: Int = 0

    var onMessagesCountChange: (Int) -> Void = { _ in }

    init(chatSession: ChatSession, onMessagesCountChange: @escaping (Int) -> Void = { _ in }) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(chatSession: chatSession))
        self.onMessagesCountChange = onMessagesCountChange
    }

    var body: some View {
        ZStack(alignment: .top) {
            ChatTheme.bgGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                Divider().overlay(ChatTheme.separator).opacity(0)

                ScrollViewReader { scrollView in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.chatSession.messages) { message in
                                VoiceMessageView(
                                    message: message,
                                    onSelectText: { showSelectTextSheet(with: $0) },
                                    onRegenerate: { viewModel.regenerateSystemMessage($0) },
                                    onEditUserMessage: { viewModel.editUserMessage($0) }
                                )
                                .id(message.id)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .preference(key: MessageHeightKey.self,
                                                        value: [message.id.uuidString: geo.size.height])
                                    }
                                )
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.chatSession.messages)
                            }

                            if viewModel.isLoading { LoadingBubble() }

                            BottomSentinel(
                                onAppearAtBottom: { isAtBottom = true },
                                onDisappearFromBottom: { isAtBottom = false }
                            )
                            .id("BOTTOM_SENTINEL")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .onChange(of: viewModel.chatSession.messages.count) { _, newCount in
                            onMessagesCountChange(newCount)
                            chatSessionsViewModel.objectWillChange.send()
                            if let last = viewModel.chatSession.messages.last, last.isUser {
                                scrollToBottom(scrollView: scrollView)
                            }
                        }
                        .onChange(of: viewModel.chatSession.messages.last?.id) { _, newID in
                            guard let newID else { return }
                            lastMessageID = newID
                            let content = viewModel.chatSession.messages.last?.content ?? ""
                            let parts = content.extractThinkParts()
                            lastThinkClosedForLastMessage = parts.isClosed
                            lastBodyLenForLastMessage = parts.body.count
                            if isAtBottom {
                                scrollToBottom(scrollView: scrollView, animated: true)
                                lastMeasuredLastMessageHeight = 0
                            }
                        }
                        .onChange(of: viewModel.chatSession.messages.last?.content) { _, newContent in
                            guard let newContent else { return }
                            let parts = newContent.extractThinkParts()
                            let nowClosed = parts.isClosed
                            let nowBodyLen = parts.body.count
                            let wasClosed = lastThinkClosedForLastMessage
                            let wasBodyLen = lastBodyLenForLastMessage
                            defer {
                                lastThinkClosedForLastMessage = nowClosed
                                lastBodyLenForLastMessage = nowBodyLen
                            }
                            guard isAtBottom else { return }
                            if wasClosed == false && nowClosed == true {
                                scrollToBottom(scrollView: scrollView, animated: true)
                                lastMeasuredLastMessageHeight = 0
                                return
                            }
                            if (wasBodyLen == 0) && (nowBodyLen > 0) {
                                scrollToBottom(scrollView: scrollView, animated: true)
                                lastMeasuredLastMessageHeight = 0
                                return
                            }
                        }
                        .onPreferenceChange(MessageHeightKey.self) { heights in
                            guard let last = viewModel.chatSession.messages.last else { return }
                            let key = last.id.uuidString
                            guard let newHeight = heights[key] else { return }
                            let delta = newHeight - lastMeasuredLastMessageHeight

                            if isAtBottom, delta >= (bodyLineHeight - 0.5) {
                                lastMeasuredLastMessageHeight = newHeight
                                scrollToBottom(scrollView: scrollView, animated: true)
                            } else {
                                lastMeasuredLastMessageHeight = max(lastMeasuredLastMessageHeight, newHeight)
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture { isInputFocused = false }
                }

                // 输入区域
                VStack(spacing: 10) {
                    HStack(alignment: .bottom, spacing: 10) {
                        AutoSizingTextEditor(
                            text: $viewModel.userMessage,
                            height: $textFieldHeight,
                            onCommit: {
                                #if os(macOS)
                                viewModel.sendMessage()
                                #endif
                            }
                        )
                        .focused($isInputFocused)
                        .frame(height: textFieldHeight)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(ChatTheme.inputBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ChatTheme.subtleStroke, lineWidth: 1)
                        )

                        Button {
                            viewModel.sendMessage()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(
                                    viewModel.userMessage.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                                    ? Color.gray.opacity(0.4)
                                    : ChatTheme.accent
                                )
                                .shadow(color: ChatTheme.bubbleShadow, radius: 4, x: 0, y: 2)
                                .accessibilityLabel("发送")
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.userMessage.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 12)

                    Rectangle()
                        .fill(LinearGradient(colors: [ChatTheme.separator, .clear], startPoint: .top, endPoint: .bottom))
                        .frame(height: 1)
                        .opacity(0.6)
                        .padding(.horizontal, 12)
                }
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .overlay(
                    VStack(spacing: 0) {
                        Divider().overlay(ChatTheme.separator)
                        Spacer(minLength: 0)
                    }
                )
            }

            if audioManager.isShowingAudioPlayer {
                VStack {
                    AudioPlayerView()
                        .environmentObject(audioManager)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: audioManager.isShowingAudioPlayer)
            }
        }
        #if os(macOS)
        .navigationTitle(viewModel.chatSession.title)
        #endif
        .onAppear {
            onMessagesCountChange(viewModel.chatSession.messages.count)
            lastMessageID = viewModel.chatSession.messages.last?.id
            if let content = viewModel.chatSession.messages.last?.content {
                let parts = content.extractThinkParts()
                lastThinkClosedForLastMessage = parts.isClosed
                lastBodyLenForLastMessage = parts.body.count
            }

            viewModel.onUpdate = { [weak viewModel, weak chatSessionsViewModel] in
                DispatchQueue.main.async {
                    guard let vm = viewModel, let store = chatSessionsViewModel else { return }
                    if !store.chatSessions.contains(vm.chatSession) {
                        store.addSession(vm.chatSession)
                    } else {
                        store.saveChatSessions()
                    }
                    store.objectWillChange.send()
                    onMessagesCountChange(vm.chatSession.messages.count)
                }
            }
        }
        // 与正文 16pt 对齐用于“多一行”阈值
        .overlay(HeightMeasurer(font: .system(size: 16), lineHeight: $bodyLineHeight))
        .sheet(isPresented: $isShowingTextSelectionSheet) {
            NavigationView {
                ScrollView {
                    Text(textSelectionContent)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ChatTheme.bgGradient)
                }
                .navigationTitle("选择文本")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { isShowingTextSelectionSheet = false }
                    }
                }
            }
        }
    }

    private func scrollToBottom(scrollView: ScrollViewProxy, animated: Bool = true) {
        withAnimation(animated ? .easeIn(duration: 0.12) : nil) {
            scrollView.scrollTo("BOTTOM_SENTINEL", anchor: .bottom)
        }
    }

    private func showSelectTextSheet(with text: String) {
        textSelectionContent = text
        isShowingTextSelectionSheet = true
    }
}

// MARK: - ─────────── 底部哨兵视图 ────────────

private struct BottomSentinel: View {
    var onAppearAtBottom: () -> Void
    var onDisappearFromBottom: () -> Void

    var body: some View {
        Color.clear
            .frame(height: 1)
            .onAppear { onAppearAtBottom() }
            .onDisappear { onDisappearFromBottom() }
            .accessibilityHidden(true)
    }
}

// MARK: - ─────────── 气泡视图等 ────────────

struct VoiceMessageView: View {
    @ObservedObject var message: ChatMessage
    @EnvironmentObject var audioManager: GlobalAudioManager

    let onSelectText: (String) -> Void
    let onRegenerate: (ChatMessage) -> Void
    let onEditUserMessage: (ChatMessage) -> Void

    private let thinkPreviewLines: Int = 4
    private let thinkFontSize: CGFloat = 14
    private let thinkFont: Font = .system(size: 14, design: .monospaced)

    var body: some View {
        HStack(alignment: .top) {
            if message.isUser { Spacer(minLength: 40) } else { Spacer(minLength: 0) }

            if message.isUser {
                UserTextBubble(text: message.content)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                SystemTextBubble(message: message,
                                 thinkPreviewLines: thinkPreviewLines,
                                 thinkFontSize: thinkFontSize,
                                 thinkFont: thinkFont)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if message.isUser { Spacer(minLength: 0) } else { Spacer(minLength: 40) }
        }
        .padding(.vertical, 4)
        .contextMenu {
            let parts = message.content.extractThinkParts()
            let bodyText = parts.body
            Button { copyToClipboard(bodyText) } label: { Label("复制", systemImage: "doc.on.doc") }
            Button { onSelectText(bodyText) } label: { Label("选择文本", systemImage: "text.cursor") }

            if message.isUser {
                Button { onEditUserMessage(message) } label: { Label("编辑", systemImage: "pencil") }
            } else {
                Button { onRegenerate(message) } label: { Label("重新生成", systemImage: "arrow.clockwise") }
                Button { audioManager.startProcessing(text: bodyText) } label: { Label("朗读", systemImage: "speaker.wave.2.fill") }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS) || os(tvOS) || os(watchOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

private struct SystemTextBubble: View {
    @ObservedObject var message: ChatMessage
    @State private var showThink = false
    private let horizontalMargin: CGFloat = 40
    private let preferredMaxWidth: CGFloat = 525

    let thinkPreviewLines: Int
    let thinkFontSize: CGFloat
    let thinkFont: Font

    var body: some View {
        let parts = message.content.extractThinkParts()

        let thinkView = Group {
            if let think = parts.think {
                if parts.isClosed {
                    // 思考完毕：默认只显示状态，可展开查看完整思考
                    DisclosureGroup(isExpanded: $showThink) {
                        Text(think)
                            .font(thinkFont)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: bubbleWidth, alignment: .leading)
                            .padding(.top, 4)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                            Text("思考完毕")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .contentShape(Rectangle())
                    }
                    .padding(10)
                    .frame(maxWidth: bubbleWidth, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous)
                            .stroke(ChatTheme.subtleStroke, lineWidth: 1)
                    )
                } else {
                    // 思考中：折叠时仅绘制“最后 N 行”，展开才渲染完整文本
                    VStack(alignment: .leading, spacing: 6) {
                        DisclosureGroup(isExpanded: $showThink) {
                            Text(think)
                                .font(thinkFont)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: bubbleWidth, alignment: .leading)
                                .padding(.top, 4)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "brain.head.profile")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                                Text("思考中")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .contentShape(Rectangle())
                        }

                        if !showThink {
                            TailLinesText(
                                text: think,
                                lines: thinkPreviewLines,
                                font: PlatformFontSpec(size: thinkFontSize, isMonospaced: true)
                            )
                            .frame(maxWidth: bubbleWidth, alignment: .leading)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous)
                            .stroke(ChatTheme.subtleStroke, lineWidth: 1)
                    )
                    .frame(maxWidth: bubbleWidth)
                }
            }
        }

        let bodyView = Group {
            if !parts.body.isEmpty {
                RichMarkdownView(markdown: parts.body)
                    .frame(maxWidth: bubbleWidth, alignment: .leading)
                    .bubbleStyle(isUser: false)
            }
        }

        return VStack(alignment: .leading, spacing: 8) {
            thinkView
            bodyView
        }
        .tint(ChatTheme.accent)
        .frame(maxWidth: bubbleWidth, alignment: .leading)
    }

    private var bubbleWidth: CGFloat {
        #if os(iOS) || os(tvOS) || os(watchOS)
        min(UIScreen.main.bounds.width - horizontalMargin, preferredMaxWidth)
        #elseif os(macOS)
        min((NSScreen.main?.frame.width ?? 800) - horizontalMargin, preferredMaxWidth)
        #else
        preferredMaxWidth
        #endif
    }
}

private struct UserTextBubble: View {
    let text: String
    @State private var expanded = false
    private let maxCharacters = 1000
    private let horizontalMargin: CGFloat = 40
    private let preferredMaxWidth: CGFloat = 525

    var body: some View {
        let display = (expanded || text.count <= maxCharacters) ? text : (String(text.prefix(maxCharacters)) + "…")

        VStack(alignment: .trailing, spacing: 6) {
            Text(display)
                .foregroundColor(.white)
                .font(.system(size: 16))
                .frame(maxWidth: bubbleWidth, alignment: .trailing)
                .bubbleStyle(isUser: true)

            if text.count > maxCharacters {
                Button(expanded ? "收起" : "显示完整信息") {
                    withAnimation(.easeInOut) { expanded.toggle() }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)
                .frame(maxWidth: bubbleWidth, alignment: .trailing)
            }
        }
        .frame(maxWidth: bubbleWidth, alignment: .trailing)
    }

    private var bubbleWidth: CGFloat {
        #if os(iOS) || os(tvOS) || os(watchOS)
        min(UIScreen.main.bounds.width - horizontalMargin, preferredMaxWidth)
        #elseif os(macOS)
        min((NSScreen.main?.frame.width ?? 800) - horizontalMargin, preferredMaxWidth)
        #else
        preferredMaxWidth
        #endif
    }
}

// MARK: - ─────────── 输入框自适应 ────────────

#if os(macOS)
private struct AutoSizingTextEditor: NSViewRepresentable {
    typealias NSViewType = NSTextView

    @Binding var text: String
    @Binding var height: CGFloat
    var onCommit: () -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textView = CommitTextView()
        textView.isEditable = true
        textView.font = .systemFont(ofSize: 17)
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 6, height: 10)
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        textView.onCommit = onCommit
        textView.isRichText = false
        textView.isAutomaticDataDetectionEnabled = true
        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        if nsView.string != text { nsView.string = text }
        if let used = nsView.layoutManager?.usedRect(for: nsView.textContainer ?? NSTextContainer(size: .zero)) {
            height = max(44, used.height + 18)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoSizingTextEditor
        init(parent: AutoSizingTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            let used = tv.layoutManager?.usedRect(for: tv.textContainer!) ?? .zero
            parent.height = max(44, used.height + 18)
        }
    }

    final class CommitTextView: NSTextView {
        var onCommit: () -> Void = {}
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 { // Return
                if event.modifierFlags.contains(.shift) {
                    super.keyDown(with: event)
                } else {
                    self.window?.makeFirstResponder(nil)
                    onCommit()
                }
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
#else
private struct AutoSizingTextEditor: View {
    @Binding var text: String
    @Binding var height: CGFloat
    var onCommit: () -> Void = {}

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("在这里输入消息…")
                    .foregroundColor(.secondary)
                    .padding(.top, 12)
                    .padding(.leading, 10)
                    .font(.system(size: 17))
                    .accessibilityHint("输入框占位提示")
            }

            Text(text + " ")
                .font(.system(size: 17))
                .foregroundColor(.clear)
                .padding(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
                .background(
                    GeometryReader { geo in
                        Color.clear.onChange(of: text) { _, _ in
                            DispatchQueue.main.async { height = max(44, geo.size.height) }
                        }
                    }
                )

            TextEditor(text: $text)
                .font(.system(size: 17))
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .background(Color.clear)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 44)
                .onSubmit { onCommit() }
                .accessibilityLabel("消息输入框")
        }
        .frame(height: max(height, 44))
    }
}
#endif

// MARK: - ─────────── Loading 指示 ────────────

private struct LoadingIndicatorView: View {
    @State private var phase: CGFloat = 0
    var body: some View {
        HStack(spacing: 6) {
            Circle().frame(width: 8, height: 8).opacity(dotOpacity(0))
            Circle().frame(width: 8, height: 8).opacity(dotOpacity(0.2))
            Circle().frame(width: 8, height: 8).opacity(dotOpacity(0.4))
        }
        .foregroundColor(.secondary)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
    private func dotOpacity(_ delay: CGFloat) -> Double {
        let value = sin((phase + delay) * .pi)
        return Double(0.35 + 0.65 * max(0, value))
    }
}

private struct LoadingBubble: View {
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            LoadingIndicatorView()
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous)
                        .stroke(ChatTheme.subtleStroke, lineWidth: 1)
                )
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
    }
}

// MARK: - ─────────── 预览 ────────────

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        let session = ChatSession()
        ChatView(chatSession: session)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(ChatSessionsViewModel())
            .preferredColorScheme(.light)

        ChatView(chatSession: session)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(ChatSessionsViewModel())
            .preferredColorScheme(.dark)
    }
}
