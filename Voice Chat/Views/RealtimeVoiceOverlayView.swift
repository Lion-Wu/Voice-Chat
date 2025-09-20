//
//  RealtimeVoiceOverlayView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/9/21.
//

import SwiftUI

struct RealtimeVoiceOverlayView: View {
    @EnvironmentObject var speechInputManager: SpeechInputManager
    @EnvironmentObject var audioManager: GlobalAudioManager
    @Environment(\.colorScheme) private var colorScheme

    /// 关闭回调（外部可用来收起 fullScreenCover 等）
    var onClose: () -> Void = {}

    /// 识别完成将文本回传给宿主（宿主可把文本发到当前聊天会话）
    var onTextFinal: (String) -> Void = { _ in }

    // 播放/加载时的占位脉冲相位
    @State private var pulsePhase: Double = 0
    @State private var showErrorToast: Bool = false

    private enum OverlayState: Equatable {
        case listening
        case loading
        case speaking
        case error(String)
    }
    @State private var state: OverlayState = .listening

    // 更平滑的统一动画
    private let stateAnim = Animation.spring(response: 0.28, dampingFraction: 0.85, blendDuration: 0.2)

    // 根据系统外观切换圆圈底色（深色=白圈，浅色=黑圈）
    private var circleBaseColor: Color { colorScheme == .dark ? .white : .black }

    // —— 平滑过渡用的内部状态（低通 + 目标/显示缩放）
    @State private var smoothedInputLevel: CGFloat = 0.0   // 录音输入音量（聆听用）
    @State private var smoothedOutputLevel: CGFloat = 0.0  // 输出音量（播放用）
    @State private var targetScale: CGFloat = 1.0
    @State private var displayedScale: CGFloat = 1.0
    @State private var pulseTimer: Timer?

    // 圆圈基准尺寸：默认与“聆听”区分
    private let defaultBaseSize: CGFloat = 200
    private let listeningBaseSize: CGFloat = 280    // ★ “聆听中”更大一些，和原来区分明显

    // MARK: - Body
    var body: some View {
        ZStack {
            // ★ 改：背景改为“完全不透明”，避免看到后面的内容
            PlatformColor.systemBackground
                .ignoresSafeArea()

            VStack(spacing: 28) {

                // 关闭按钮（右上角）
                HStack {
                    Spacer()
                    Button {
                        stopIfNeeded()
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.95))
                            .shadow(radius: 6)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // 中心圆圈
            ZStack {
                let baseSize: CGFloat = (state == .listening) ? listeningBaseSize : defaultBaseSize
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                circleBaseColor.opacity(0.95),
                            circleBaseColor.opacity(0.78)
                            ],
                            center: .center, startRadius: 2, endRadius: baseSize * 0.8
                        )
                    )
                    .frame(width: baseSize, height: baseSize)
                    .scaleEffect(displayedScale) // 使用平滑后的缩放值
                    .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 6)
            }
            .animation(stateAnim, value: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            // 初始化缩放，避免初次出现的跳变
            targetScale = circleTargetScale()
            displayedScale = targetScale
            startListening()
            startPulse()
            syncStateWithEngines()
        }
        .onDisappear {
            stopPulse()
            speechInputManager.stopRecording()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 16) {
                Picker("", selection: Binding(
                    get: { speechInputManager.currentLanguage },
                    set: { speechInputManager.currentLanguage = $0 }
                )) {
                    ForEach(SpeechInputManager.DictationLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
        }
        // —— 跟随录音/播放状态动态更新 Overlay 状态，并在播放完毕后自动回到“聆听”
        .onChange(of: speechInputManager.isRecording) { _, recording in
            if recording {
                withAnimation(stateAnim) { state = .listening }
            }
        }
        .onChange(of: audioManager.isAudioPlaying) { _, playing in
            if playing {
                withAnimation(stateAnim) { state = .speaking }
            } else {
                autoResumeListeningIfIdle()
            }
        }
        .onChange(of: audioManager.isLoading) { _, loading in
            if loading && !audioManager.isAudioPlaying {
                withAnimation(stateAnim) { state = .loading }
            } else {
                autoResumeListeningIfIdle()
            }
        }
        .alert(isPresented: $showErrorToast) {
            Alert(
                title: Text("语音错误"),
                message: Text(speechInputManager.lastError ?? "未知错误"),
                dismissButton: .default(Text("确定"))
            )
        }
    }

    // MARK: - Helpers

    private func startListening() {
        // 避免重复启动
        if speechInputManager.isRecording { return }
        withAnimation(stateAnim) { state = .listening }
        Task { @MainActor in
            await speechInputManager.startRecording(
                language: speechInputManager.currentLanguage,
                onPartial: { _ in },
                onFinal: { text in
                    // 收到最终文本 -> 回传给宿主，随后进入“加载/说话”状态由宿主控制
                    onTextFinal(text)
                    withAnimation(stateAnim) { state = .loading }
                }
            )
            if let err = speechInputManager.lastError, !err.isEmpty {
                withAnimation(stateAnim) { state = .error(err) }
                showErrorToast = true
            }
        }
    }

    private func autoResumeListeningIfIdle() {
        // 若未在录音、未在播放且未加载中，则自动恢复聆听并重新开启识别
        if !speechInputManager.isRecording,
           !audioManager.isAudioPlaying,
           !audioManager.isLoading {
            startListening()
        }
    }

    private func stopIfNeeded() {
        if speechInputManager.isRecording { speechInputManager.stopRecording() }
    }

    // —— 目标缩放：按照需求重做各状态规则
    private func circleTargetScale() -> CGFloat {
        switch state {
        case .listening:
            // ★ 聆听中：基于“输入音量”动态缩放；基准尺寸已增大，这里只做 1.0~1.25 的动态
            return 1.0 + 0.32 * smoothedInputLevel
        case .speaking:
            // ★ 正在播放：改为“跟聆听类似”的新动画——根据“输出音量”动态缩放（基准尺寸保持默认）
            return 1.0 + 0.32 * smoothedOutputLevel
        case .loading:
            // ★ 处理中：使用“原来正在播报”的动画（沿用旧 speaking 的脉冲幅度/节奏）
            return 0.95 + 0.10 * CGFloat((sin(pulsePhase) + 1) * 0.5)
        case .error:
            return 1.0
        }
    }

    private func startPulse() {
        stopPulse()
        // 使用计时器推进相位 + 平滑缩放
        let timer = Timer.scheduledTimer(withTimeInterval: 1/60.0, repeats: true) { _ in
            Task { @MainActor in
                // 相位推进：loading 使用旧 speaking 的节奏；其他保持既有流畅度
                let step: Double = (state == .loading) ? 0.06 : 0.12
                pulsePhase += step
                if pulsePhase > .pi * 2 { pulsePhase -= .pi * 2 }

                // 输入电平低通（聆听）
                let inRaw = CGFloat(min(1.0, max(0.0, speechInputManager.inputLevel)))
                let inAlpha: CGFloat = 0.20
                smoothedInputLevel += (inRaw - smoothedInputLevel) * inAlpha

                // 输出电平低通（播放）
                let outRaw = CGFloat(min(1.0, max(0.0, audioManager.outputLevel)))
                let outAlpha: CGFloat = 0.20
                smoothedOutputLevel += (outRaw - smoothedOutputLevel) * outAlpha

                // 计算目标缩放并做一次指数平滑过渡
                targetScale = circleTargetScale()
                let k: CGFloat = 0.20
                displayedScale += (targetScale - displayedScale) * k
            }
        }
        timer.tolerance = 0.005
        pulseTimer = timer
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulsePhase = 0
    }

    private func syncStateWithEngines() {
        if audioManager.isAudioPlaying {
            withAnimation(stateAnim) { state = .speaking }
        } else if audioManager.isLoading {
            withAnimation(stateAnim) { state = .loading }
        } else if speechInputManager.isRecording {
            withAnimation(stateAnim) { state = .listening }
        } else {
            withAnimation(stateAnim) { state = .listening }
        }
        // 同步一次缩放，避免状态同步瞬间产生跳变
        targetScale = circleTargetScale()
        displayedScale = targetScale
    }
}
