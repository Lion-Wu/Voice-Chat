//
//  VoiceModeView.swift
//  Voice Chat
//
//  Created by Lion Wu on 2025/3/9.
//

import SwiftUI
import Speech
import AVFoundation

struct VoiceModeView: View {
    // 识别完成后把结果回调给外部
    let onRecognized: (String) -> Void
    let onClose: () -> Void

    @StateObject private var speechRecognizer = SpeechRecognizerHelper()
    @State private var isMicMuted = false

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack {
                Spacer()

                // 中间的圆形波纹（此处简化为一个静态圆）
                Circle()
                    .strokeBorder(Color.white, lineWidth: 3)
                    .frame(width: 150, height: 150)

                Spacer()

                HStack {
                    // 静音/启用按钮
                    Button(action: {
                        isMicMuted.toggle()
                        speechRecognizer.toggleMute(isMicMuted)
                    }) {
                        Image(systemName: isMicMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                    }

                    Spacer()

                    // 关闭按钮
                    Button(action: {
                        // 若已经识别到一些内容，或想要在关闭前提交，可以在这里处理
                        speechRecognizer.stopRecording()
                        onClose()
                    }) {
                        Text("关闭")
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            // 请求权限并开始录音
            speechRecognizer.startRecording { recognizedText in
                // 当识别到一段后，如果要立即提交：
                // 不过本例子里是把全部说完之后的一次性结果返回
                // 这里留作演示
                // print("partial recognized: \(recognizedText)")
            } onComplete: { finalText in
                // 用户停止说话，或者系统检测到长时间静音
                onRecognized(finalText)
                onClose()
            }
        }
        .onDisappear {
            // 确保离开界面时停止录音
            speechRecognizer.stopRecording()
        }
    }
}

/// 辅助类，使用苹果 Speech 框架进行语音识别
class SpeechRecognizerHelper: NSObject, ObservableObject {
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) // 可改成选定语言
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var partialResultHandler: ((String) -> Void)?
    private var completionHandler: ((String) -> Void)?

    private var isMuted = false

    /// 开始录音并实时识别
    func startRecording(onPartial: @escaping (String) -> Void,
                        onComplete: @escaping (String) -> Void) {
        partialResultHandler = onPartial
        completionHandler = onComplete

        // 请求语音识别权限
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    onComplete("")
                    return
                }
                self.internalStartRecording()
            }
        }
    }

    private func internalStartRecording() {
        // 如果之前有task，先取消
        recognitionTask?.cancel()
        recognitionTask = nil

        // 音频会话
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // .playAndRecord 以便边播边录，这里仅演示
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Audio session error: \(error)")
            completionHandler?("")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            completionHandler?("")
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, when in
            if !self.isMuted {
                recognitionRequest.append(buffer)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("audioEngine couldn't start: \(error)")
            completionHandler?("")
            return
        }

        // 开始识别任务
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest, resultHandler: { result, error in
            if let result = result {
                let bestString = result.bestTranscription.formattedString
                self.partialResultHandler?(bestString)

                if result.isFinal {
                    // 识别到最终结果
                    DispatchQueue.main.async {
                        self.completionHandler?(bestString)
                    }
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                // 结束
                self.stopRecording()
            }
        })
    }

    /// 切换静音/启用
    func toggleMute(_ mute: Bool) {
        isMuted = mute
    }

    /// 停止录音和识别
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
    }
}
