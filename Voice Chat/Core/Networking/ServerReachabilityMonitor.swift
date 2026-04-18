//
//  ServerReachabilityMonitor.swift
//  Voice Chat
//
//  Created by OpenAI Codex on 2025/03/10.
//

import Foundation
import Network

/// Performs lightweight reachability checks for the text-generation and TTS servers.
@MainActor
final class ServerReachabilityMonitor: ObservableObject {
    static let shared = ServerReachabilityMonitor()

    private let errorCenter = AppErrorCenter.shared
    @Published private(set) var isChatReachable: Bool?
    @Published private(set) var isTTSReachable: Bool?

    private var monitorTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 5

    private init() {}

    /// Starts periodic reachability checks (immediately, then on an interval).
    func startMonitoring(settings: SettingsManager) {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            // Immediate check without waiting.
            await self.checkAll(settings: settings)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                await self.checkAll(settings: settings)
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    /// Checks both chat and TTS endpoints and surfaces banners when unreachable.
    func checkAll(settings: SettingsManager) async {
        let chatBase = settings.chatSettings.apiURL
        let ttsBase  = settings.serverSettings.serverAddress

        await check(chatBase: chatBase)
        await checkTTS(ttsBase: ttsBase)
    }

    /// Clears existing notices for the given category when connectivity is restored.
    private func clear(_ category: AppErrorNotice.Category) async {
        await MainActor.run {
            self.errorCenter.clear(category: category)
        }
    }

    private func check(chatBase: String) async {
        guard let endpoint = hostPort(from: chatBase, defaultPort: 80) else {
            await MainActor.run { self.isChatReachable = nil }
            return
        }
        do {
            try await tcpProbe(host: endpoint.host, port: endpoint.port)
            await MainActor.run { self.isChatReachable = true }
            await clear(.textModel)
        } catch {
            await MainActor.run {
                self.isChatReachable = false
                if self.shouldPublishNotice(for: .textModel) {
                    self.errorCenter.publishCritical(
                        title: NSLocalizedString("Text server unreachable", comment: "Shown when the LLM endpoint cannot be reached"),
                        message: friendlyMessage(for: error, base: chatBase),
                        category: .textModel
                    )
                }
            }
        }
    }

    private func checkTTS(ttsBase: String) async {
        guard let endpoint = hostPort(from: ttsBase, defaultPort: 9880) else {
            await MainActor.run { self.isTTSReachable = nil }
            return
        }
        do {
            try await tcpProbe(host: endpoint.host, port: endpoint.port)
            await MainActor.run { self.isTTSReachable = true }
            await clear(.tts)
        } catch {
            await MainActor.run {
                self.isTTSReachable = false
                if self.shouldPublishNotice(for: .tts) {
                    self.errorCenter.publishCritical(
                        title: NSLocalizedString("TTS server unreachable", comment: "Shown when the TTS endpoint cannot be reached"),
                        message: friendlyMessage(for: error, base: ttsBase),
                        category: .tts
                    )
                }
            }
        }
    }

    private func hostPort(from base: String, defaultPort: UInt16) -> (host: String, port: UInt16)? {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Ensure we have a scheme so URLComponents can parse host/port reliably.
        let normalized: String
        if trimmed.contains("://") {
            normalized = trimmed
        } else {
            normalized = "http://\(trimmed)"
        }

        guard let comps = URLComponents(string: normalized) else { return nil }
        let pathHost = comps.path.split(separator: "/").first.map(String.init)
        guard let resolvedHost = comps.host ?? pathHost, !resolvedHost.isEmpty else { return nil }

        let resolvedPort: UInt16 = {
            if let p = comps.port {
                return UInt16(p)
            }
            if let scheme = comps.scheme?.lowercased() {
                switch scheme {
                case "https": return 443
                case "http": return 80
                default: break
                }
            }
            return defaultPort
        }()

        return (resolvedHost, resolvedPort)
    }

    private func tcpProbe(host: String, port: UInt16, timeout: TimeInterval = 5) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let endpointHost = NWEndpoint.Host(host)
            guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(throwing: URLError(.badURL))
                return
            }

            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let connection = NWConnection(host: endpointHost, port: endpointPort, using: params)

            let queue = DispatchQueue(label: "VoiceChat.TCPProbe.\(host):\(port)")

            actor ResumeGate {
                private var fired = false
                func fire(_ result: Result<Void, Error>, connection: NWConnection, continuation: CheckedContinuation<Void, Error>) {
                    guard !fired else { return }
                    fired = true
                    connection.cancel()
                    continuation.resume(with: result)
                }
            }

            let gate = ResumeGate()

            connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Task { await gate.fire(.success(()), connection: connection, continuation: continuation) }
            case .failed(let error):
                Task { await gate.fire(.failure(error), connection: connection, continuation: continuation) }
            case .cancelled:
                Task { await gate.fire(.failure(URLError(.cancelled)), connection: connection, continuation: continuation) }
            default:
                break
            }
        }

        connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                Task { await gate.fire(.failure(URLError(.timedOut)), connection: connection, continuation: continuation) }
            }
        }
    }

    private func friendlyMessage(for error: Error, base: String) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .cannotConnectToHost:
                return String(format: NSLocalizedString("Could not connect to %@", comment: "Shown when a server host is unreachable"), base)
            case .notConnectedToInternet:
                return NSLocalizedString("You appear to be offline. Please check your internet connection.", comment: "Shown when the device is offline")
            case .networkConnectionLost:
                return NSLocalizedString("The network connection was lost.", comment: "Shown when the connection drops")
            case .timedOut:
                return NSLocalizedString("The request timed out. The server may be offline or busy.", comment: "Shown when a server request times out")
            default:
                return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private func shouldPublishNotice(for category: AppErrorNotice.Category) -> Bool {
        // Avoid re-publishing if the same category is already displayed or was dismissed and not yet resolved.
        guard !errorCenter.isDismissed(for: category) else { return false }
        return !errorCenter.notices.contains(where: { $0.category == category })
    }
}
