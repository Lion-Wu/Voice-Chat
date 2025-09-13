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

// MARK: - 平台类型别名

#if os(iOS) || os(tvOS) || os(watchOS)
private typealias PlatformNativeFont = UIFont
#elseif os(macOS)
private typealias PlatformNativeFont = NSFont
#endif

// MARK: - 平台颜色映射

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

// MARK: - 主题与辅助样式

private enum ChatTheme {
    static let inputBG: Material = .thin
    static let bubbleRadius: CGFloat = 24
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

// MARK: - 输入区间距常量
private enum InputMetrics {
    static let outerV: CGFloat = 8     // outer vertical padding applied around the text editor
    static let outerH: CGFloat = 12    // outer horizontal padding applied around the text editor
    static let innerTop: CGFloat = 10  // text container top inset
    static let innerBottom: CGFloat = 10 // text container bottom inset
    static let innerLeading: CGFloat = 6  // text container leading inset
    static let innerTrailing: CGFloat = 6 // text container trailing inset
}

private struct BubbleBackground: ViewModifier {
    let isUser: Bool
    let contentPadding: EdgeInsets

    init(isUser: Bool, contentPadding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) {
        self.isUser = isUser
        self.contentPadding = contentPadding
    }

    func body(content: Content) -> some View {
        content
            .padding(contentPadding)
            .background(isUser ? AnyView(ChatTheme.userBubbleGradient) : AnyView(ChatTheme.systemBubbleFill))
            .overlay(
                RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous)
                    .stroke(ChatTheme.subtleStroke, lineWidth: isUser ? 0 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous))
            .shadow(color: ChatTheme.bubbleShadow, radius: 8, x: 0, y: 4)
    }
}
private extension View {
    func bubbleStyle(isUser: Bool, contentPadding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) -> some View {
        modifier(BubbleBackground(isUser: isUser, contentPadding: contentPadding))
    }
}

// MARK: - Markdown 渲染

fileprivate struct RichMarkdownView: View {
    let markdown: String
    var body: some View {
        Markdown(markdown)
            .markdownImageProvider(.default)
            .textSelection(.enabled)
            .tint(ChatTheme.accent)
    }
}

// MARK: - <think> 提取

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

// MARK: - 仅渲染“最后 N 条视觉行”

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

private struct TailLinesText: View {
    let text: String
    let lines: Int
    let font: PlatformFontSpec
    private var fixedHeight: CGFloat { font.lineHeight * CGFloat(max(1, lines)) }

    @State private var displayTail: String = ""
    @State private var lastComputedForTextCount: Int = -1
    @State private var lastWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = max(1, floor(geo.size.width))

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
        .accessibilityLabel("思考预览")
    }

    private func recomputeIfNeeded(width: CGFloat) {
        let tcount = text.utf16.count
        let needs = (tcount != lastComputedForTextCount) || abs(width - lastWidth) > 0.5
        guard needs, width > 1 else { return }

        displayTail = computeTailVisualLines(text: text, width: width, lines: lines, font: font)
        lastComputedForTextCount = tcount
        lastWidth = width
    }
}

private func computeTailVisualLines(text: String, width: CGFloat, lines: Int, font: PlatformFontSpec) -> String {
    guard !text.isEmpty, width > 1, lines > 0 else { return "" }

    let ns = text as NSString
    let total = ns.length
    var windowLen = min(2048, total)
    let maxLen = min(32768, total)

    var lastResult: String = ""
    while true {
        let start = max(0, total - windowLen)
        let range = NSRange(location: start, length: total - start)
        let chunk = ns.substring(with: range) as NSString

        let attrs: [CFString: Any] = [kCTFontAttributeName: font.ctFont]
        let attrStr = CFAttributedStringCreate(nil, chunk as CFString, attrs as CFDictionary)!
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)

        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: width, height: 10_000))
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let linesCF = CTFrameGetLines(frame)
        let count = CFArrayGetCount(linesCF)

        if count == 0 { return "" }

        let take = min(lines, count)
        var firstLoc = Int.max
        var lastMax = 0
        for i in (count - take)..<count {
            let unmanaged = CFArrayGetValueAtIndex(linesCF, i)
            let line = unsafeBitCast(unmanaged, to: CTLine.self)
            let r = CTLineGetStringRange(line)
            let loc = r.location
            let len = r.length
            firstLoc = min(firstLoc, loc)
            lastMax = max(lastMax, loc + len)
        }
        let tailRange = NSRange(location: firstLoc == Int.max ? 0 : firstLoc,
                                length: max(0, lastMax - (firstLoc == Int.max ? 0 : firstLoc)))
        let tail = chunk.substring(with: NSIntersectionRange(tailRange, NSRange(location: 0, length: chunk.length)))

        lastResult = tail

        if count >= lines || windowLen >= maxLen || windowLen >= total {
            break
        }

        windowLen = min(maxLen, min(total, windowLen * 2))
    }

    return lastResult
}

// MARK: - 自动滚动的辅助键

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

// MARK: - ChatView

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

    // 输入框溢出 -> 显示“全屏编辑”按钮（仅 iPhone）
    @State private var inputOverflow: Bool = false
    @State private var showFullScreenComposer: Bool = false

    var onMessagesCountChange: (Int) -> Void = { _ in }

    init(chatSession: ChatSession, onMessagesCountChange: @escaping (Int) -> Void = { _ in }) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(chatSession: chatSession))
        self.onMessagesCountChange = onMessagesCountChange
    }

    // ★ 统一的排序视图（按 createdAt），避免关系数组顺序不稳定
    private var orderedMessages: [ChatMessage] {
        viewModel.chatSession.messages.sorted { $0.createdAt < $1.createdAt }
    }

    /// 处于编辑模式时，仅展示“到被编辑消息为止”的可见消息
    private var visibleMessages: [ChatMessage] {
        guard let baseID = viewModel.editingBaseMessageID,
              let idx = orderedMessages.firstIndex(where: { $0.id == baseID }) else {
            return orderedMessages
        }
        return Array(orderedMessages.prefix(idx + 1))
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 移除渐变背景，使用平台默认背景
            PlatformColor.systemBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Divider().overlay(ChatTheme.separator).opacity(0)

                ScrollViewReader { scrollView in
                    ScrollView {
                        VStack(spacing: 0) {
                            LazyVStack(spacing: 12) {
                                ForEach(visibleMessages) { message in
                                    VoiceMessageView(
                                        message: message,
                                        onSelectText: { showSelectTextSheet(with: $0) },
                                        onRegenerate: { viewModel.regenerateSystemMessage($0) },
                                        onEditUserMessage: { msg in
                                            viewModel.beginEditUserMessage(msg)
                                            isInputFocused = true
                                        },
                                        onRetry: { errMsg in
                                            viewModel.retry(afterErrorMessage: errMsg)
                                        }
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
                                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: visibleMessages.map(\.id))
                                }

                                // 仅在“首个令牌到达之前”显示的加载中（对齐系统文本区域）
                                if viewModel.isPriming {
                                    AssistantAlignedLoadingBubble()
                                }

                                BottomSentinel(
                                    onAppearAtBottom: { isAtBottom = true },
                                    onDisappearFromBottom: { isAtBottom = false }
                                )
                                .id("BOTTOM_SENTINEL")
                            }
                            #if os(macOS)
                            .padding(.horizontal)
                            #else
                            .padding(.horizontal, 8)
                            #endif
                            .padding(.vertical, 12)
                        }
                        // Center the entire message column within the available width
                        .frame(maxWidth: contentColumnMaxWidth())
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture { isInputFocused = false }
                }

                // 编辑提示条（仅 UI 隐藏尾部；发送后才真正删除）
                if viewModel.isEditing, let _ = visibleMessages.last {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                            .foregroundStyle(.orange)
                        Text("正在编辑")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            viewModel.cancelEditing()
                            isInputFocused = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("取消编辑并恢复显示")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PlatformColor.secondaryBackground.opacity(0.6))
                }

                // 输入区域
                VStack(spacing: 10) {
                    HStack(alignment: .bottom, spacing: 10) {
                        // 自适应输入框 +（iPhone 溢出）全屏按钮
                        ZStack(alignment: .topLeading) {
                            if viewModel.userMessage.isEmpty {
                                Text("在这里输入消息…")
                                    .font(.system(size: 17))
                                    .foregroundColor(.secondary)
                                    .padding(.top, InputMetrics.outerV + InputMetrics.innerTop)
                                    .padding(.leading, InputMetrics.outerH + InputMetrics.innerLeading)
                                    .accessibilityHint("输入框占位提示")
                            }

#if os(macOS)
                            AutoSizingTextEditor(
                                text: $viewModel.userMessage,
                                height: $textFieldHeight,
                                maxLines: platformMaxLines(),
                                onOverflowChange: { _ in },
                                onCommit: {
                                    let trimmed = viewModel.userMessage.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                    guard !viewModel.isLoading, !trimmed.isEmpty else { return }
                                    viewModel.sendMessage()
                                }
                            )
                            .focused($isInputFocused)
                            .frame(height: textFieldHeight)
                            .padding(.vertical, InputMetrics.outerV)
                            .padding(.horizontal, InputMetrics.outerH)
#else
                            AutoSizingTextEditor(
                                text: $viewModel.userMessage,
                                height: $textFieldHeight,
                                maxLines: platformMaxLines(),
                                onOverflowChange: { overflow in
                                    self.inputOverflow = overflow && isPhone()
                                }
                            )
                            .focused($isInputFocused)
                            .frame(height: textFieldHeight)
                            .padding(.vertical, InputMetrics.outerV)
                            .padding(.horizontal, InputMetrics.outerH)
#endif

#if os(iOS) || os(tvOS)
                            if inputOverflow && isPhone() {
                                Button {
                                    showFullScreenComposer = true
                                } label: {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 6)
                                .padding(.trailing, 8)
                                .accessibilityLabel("全屏编辑")
                                .frame(maxWidth: .infinity, alignment: .topTrailing)
                            }
#endif
                        }
                        .background(ChatTheme.inputBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(ChatTheme.subtleStroke, lineWidth: 1)
                        )

                        if viewModel.isLoading {
                            Button {
                                viewModel.cancelCurrentRequest()
                            } label: {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 32, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.red)
                                    .shadow(color: ChatTheme.bubbleShadow, radius: 4, x: 0, y: 2)
                                    .accessibilityLabel("停止")
                            }
                            .buttonStyle(.plain)
                        } else {
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
            onMessagesCountChange(visibleMessages.count)
            lastMessageID = visibleMessages.last?.id
            if let content = visibleMessages.last?.content {
                let parts = content.extractThinkParts()
                lastThinkClosedForLastMessage = parts.isClosed
                lastBodyLenForLastMessage = parts.body.count
            }

            // 存储节流：交由外层 VM 节流保存（SwiftData）
            viewModel.onUpdate = { [weak viewModel, weak chatSessionsViewModel] in
                guard let vm = viewModel, let store = chatSessionsViewModel else { return }
                if !store.chatSessions.contains(where: { $0.id == vm.chatSession.id }) {
                    store.addSession(vm.chatSession)
                } else {
                    store.persist(session: vm.chatSession, reason: .throttled)
                }
                // ❗️不要同步触发 objectWillChange，以免“视图更新期间修改状态”警告
                // 如确需强制刷新侧边栏，可异步派发（下一 runloop）：
                // DispatchQueue.main.async { store.objectWillChange.send() }

                onMessagesCountChange(vm.chatSession.messages.count)
            }
        }
        .overlay(HeightMeasurer(font: .system(size: 16), lineHeight: $bodyLineHeight))
#if os(iOS) || os(tvOS)
        .fullScreenCover(isPresented: $showFullScreenComposer) {
            FullScreenComposer(text: $viewModel.userMessage) {
                showFullScreenComposer = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    inputOverflow = false
                }
            }
        }
#endif
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

// MARK: - 辅助：平台内容最大宽度与设备判断

@MainActor
private func contentMaxWidthForAssistant() -> CGFloat {
    #if os(iOS) || os(tvOS) || os(watchOS)
    return min(UIScreen.main.bounds.width - 16, 680) // 减小左右外边距（约 8pt/侧）
    #elseif os(macOS)
    return min((NSScreen.main?.frame.width ?? 1200) - 80, 900) // macOS 扩大最大宽度
    #else
    return 680
    #endif
}

@MainActor
private func contentMaxWidthForUser() -> CGFloat {
    #if os(iOS) || os(tvOS) || os(watchOS)
    return min(UIScreen.main.bounds.width - 16, 680)
    #elseif os(macOS)
    return min((NSScreen.main?.frame.width ?? 1200) - 80, 900)
    #else
    return 680
    #endif
}

@MainActor
private func contentColumnMaxWidth() -> CGFloat {
    return max(contentMaxWidthForAssistant(), contentMaxWidthForUser())
}

@MainActor
private func platformMaxLines() -> Int {
    #if os(macOS)
    return 10
    #else
    return 6
    #endif
}

#if os(iOS) || os(tvOS)
@MainActor
private func isPhone() -> Bool {
    return UIDevice.current.userInterfaceIdiom == .phone
}
#endif

// MARK: - 底部哨兵视图

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

// MARK: - 气泡及子视图

struct VoiceMessageView: View {
    @Bindable var message: ChatMessage
    @EnvironmentObject var audioManager: GlobalAudioManager

    let onSelectText: (String) -> Void
    let onRegenerate: (ChatMessage) -> Void
    let onEditUserMessage: (ChatMessage) -> Void
    let onRetry: (ChatMessage) -> Void

    private let thinkPreviewLines: Int = 6
    private let thinkFontSize: CGFloat = 14
    private let thinkFont: Font = .system(size: 14, design: .monospaced)

    var body: some View {
        // 错误气泡特殊处理
        if message.content.hasPrefix("!error:") {
            return AnyView(
                HStack {
                    // 系统消息区域（左对齐居中呈现）
                    ErrorBubbleView(text: String(message.content.dropFirst("!error:".count)).trimmingCharacters(in: .whitespacesAndNewlines)) {
                        onRetry(message)
                    }
                    .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            )
        }

        return AnyView(
            HStack(alignment: .top) {
                if message.isUser { Spacer(minLength: 40) } else { Spacer(minLength: 0) }

                if message.isUser {
                    UserTextBubble(text: message.content)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    SystemTextBubble(
                        message: message,
                        thinkPreviewLines: thinkPreviewLines,
                        thinkFontSize: thinkFontSize,
                        thinkFont: thinkFont
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                Spacer(minLength: 0)    // Ensure system messages are centered, so no more spacer necessary
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
        )
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

private struct ErrorBubbleView: View {
    let text: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                Text("发生错误")
                    .foregroundStyle(.white)
                    .font(.headline)
            }
            .padding(.bottom, 2)

            Text(text.isEmpty ? "未知错误" : text)
                .foregroundStyle(.white.opacity(0.95))
                .font(.subheadline)

            HStack {
                Spacer()
                Button {
                    onRetry()
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.white.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.95), in: RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous))
        .shadow(color: ChatTheme.bubbleShadow, radius: 8, x: 0, y: 4)
    }
}

private struct SystemTextBubble: View {
    @Bindable var message: ChatMessage
    @State private var showThink = false

    let thinkPreviewLines: Int
    let thinkFontSize: CGFloat
    let thinkFont: Font

    var body: some View {
        let parts = message.content.extractThinkParts()

        let thinkView = Group {
            if let think = parts.think {
                if parts.isClosed {
                    DisclosureGroup(isExpanded: $showThink) {
                        Text(think)
                            .font(thinkFont)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .leading)
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
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .leading)
                    .bubbleStyle(
                        isUser: false,
                        contentPadding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
                    )
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        DisclosureGroup(isExpanded: $showThink) {
                            Text(think)
                                .font(thinkFont)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .leading)
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
                            .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .leading)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: contentMaxWidthForAssistant())
                    .bubbleStyle(
                        isUser: false,
                        contentPadding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
                    )
                }
            }
        }

        let bodyView = Group {
            if !parts.body.isEmpty {
                RichMarkdownView(markdown: parts.body)
                    // 系统消息：去掉消息气泡背景，文字居中展示
                    .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }

        return VStack(alignment: .center, spacing: 8) {
            thinkView
            bodyView
        }
        .tint(ChatTheme.accent)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct UserTextBubble: View {
    let text: String
    @State private var expanded = false
    private let maxCharacters = 1000

    var body: some View {
        let display = (expanded || text.count <= maxCharacters) ? text : (String(text.prefix(maxCharacters)) + "…")

        // 右侧对齐，但不强制拉满；限定最大宽度，自适应文本长度
        VStack(alignment: .trailing, spacing: 6) {
            Text(display)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .bubbleStyle(isUser: true)
                .frame(maxWidth: contentMaxWidthForUser(), alignment: .trailing)

            if text.count > maxCharacters {
                Button(expanded ? "收起" : "显示完整信息") {
                    withAnimation(.easeInOut) { expanded.toggle() }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)
                .frame(maxWidth: contentMaxWidthForUser(), alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - 输入框自适应

#if os(macOS)
private struct AutoSizingTextEditor: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    @Binding var text: String
    @Binding var height: CGFloat
    var maxLines: Int = 10
    var onOverflowChange: (Bool) -> Void = { _ in }
    var onCommit: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = CommitTextView()
        textView.isEditable = true
        textView.font = .systemFont(ofSize: 17)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: InputMetrics.innerLeading, height: InputMetrics.innerTop)
        textView.isRichText = false
        textView.isAutomaticDataDetectionEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        textView.onCommit = onCommit

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        if tv.string != text { tv.string = text }
        let used = tv.layoutManager?.usedRect(for: tv.textContainer!) ?? .zero
        let lineH = tv.layoutManager?.defaultLineHeight(for: tv.font ?? .systemFont(ofSize: 17)) ?? 18
        let maxH = CGFloat(maxLines) * lineH + 18 // 额外内边距
        let newH = min(maxH, max(44, used.height + 18))
        height = newH
        onOverflowChange((used.height + 18) > (maxH - 1))

        // 始终让插入点可见（当溢出时滚动）
        if let selected = tv.selectedRanges.first as? NSRange {
            tv.scrollRangeToVisible(selected)
        } else {
            let end = NSRange(location: (tv.string as NSString).length, length: 0)
            tv.scrollRangeToVisible(end)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoSizingTextEditor
        weak var textView: NSTextView?

        init(parent: AutoSizingTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            let used = tv.layoutManager?.usedRect(for: tv.textContainer!) ?? .zero
            let lineH = tv.layoutManager?.defaultLineHeight(for: tv.font ?? .systemFont(ofSize: 17)) ?? 18
            let maxH = CGFloat(parent.maxLines) * lineH + 18
            let newH = min(maxH, max(44, used.height + 18))
            parent.height = newH
            parent.onOverflowChange((used.height + 18) > (maxH - 1))

            // 输入时自动滚动到底部
            let end = NSRange(location: (tv.string as NSString).length, length: 0)
            tv.scrollRangeToVisible(end)
        }
    }

    final class CommitTextView: NSTextView {
        var onCommit: () -> Void = {}
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 {
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
private struct AutoSizingTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var maxLines: Int = 6
    var onOverflowChange: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: 17)
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(
            top: InputMetrics.innerTop,
            left: InputMetrics.innerLeading,
            bottom: InputMetrics.innerBottom,
            right: InputMetrics.innerTrailing
        )
        tv.isScrollEnabled = false
        tv.alwaysBounceVertical = true
        tv.showsVerticalScrollIndicator = true
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        recalcHeight(uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func recalcHeight(_ tv: UITextView) {
        let lineH = tv.font?.lineHeight ?? 18
        let maxH = CGFloat(maxLines) * lineH + tv.textContainerInset.top + tv.textContainerInset.bottom
        let fitting = tv.sizeThatFits(CGSize(width: tv.bounds.width, height: .greatestFiniteMagnitude)).height
        let newH = min(maxH, max(44, fitting))

        // 当超过最大高度时，开启内部滚动，避免内容溢出外框
        let shouldScroll = fitting > (maxH - 1)
        if tv.isScrollEnabled != shouldScroll {
            tv.isScrollEnabled = shouldScroll
        }

        if abs(newH - height) > 0.5 {
            DispatchQueue.main.async { height = newH }
        }
        onOverflowChange(shouldScroll)

        // 保证光标可见（在可滚动时）
        if shouldScroll {
            let end = NSRange(location: (tv.text as NSString).length, length: 0)
            tv.scrollRangeToVisible(end)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoSizingTextEditor
        init(_ parent: AutoSizingTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            parent.recalcHeight(textView)
            if textView.isScrollEnabled {
                let end = NSRange(location: (textView.text as NSString).length, length: 0)
                textView.scrollRangeToVisible(end)
            }
        }
    }
}
#endif

// MARK: - Loading 指示（对齐系统气泡的版本，仅在首 token 前展示）

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

private struct AssistantAlignedLoadingBubble: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack {
                    LoadingIndicatorView()
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(PlatformColor.secondaryBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: ChatTheme.bubbleRadius, style: .continuous))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: contentMaxWidthForAssistant(), alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 6)
#if os(macOS)
        .padding(.horizontal)
#else
        .padding(.horizontal, 2)
#endif
    }
}

// MARK: - iOS 全屏编辑器（保持原实现）

#if os(iOS) || os(tvOS)
private struct FullScreenComposer: View {
    @Binding var text: String
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            TextEditor(text: $text)
                .font(.system(size: 17))
                .padding()
                .navigationTitle("全屏编辑")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
                            dismiss()
                            onDone()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            dismiss()
                            onDone()
                        }
                    }
                }
        }
        .ignoresSafeArea()
    }
}
#endif

// MARK: - 预览

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        let session = ChatSession()
        ChatView(chatSession: session)
            .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(ChatSessionsViewModel())
            .preferredColorScheme(.light)

        ChatView(chatSession: session)
            .modelContainer(for: [ChatSession.self, ChatMessage.self, AppSettings.self], inMemory: true)
            .environmentObject(GlobalAudioManager.shared)
            .environmentObject(ChatSessionsViewModel())
            .preferredColorScheme(.dark)
    }
}
