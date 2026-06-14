//
//  TTSPresetApplyService.swift
//  Voice Chat
//
//  Created by Codex on 2026/6/13.
//

import Foundation

struct TTSPresetApplyRequest: Equatable, Sendable {
    let serverAddress: String
    let gptWeightsPath: String
    let sovitsWeightsPath: String
}

struct TTSPresetApplyRetryStatus: Equatable, Sendable {
    let retryAttempt: Int
    let lastErrorDescription: String

    init(nextAttempt: Int, errorDescription: String) {
        self.retryAttempt = max(1, nextAttempt - 1)
        self.lastErrorDescription = errorDescription
    }
}

enum TTSPresetApplyStage: Equatable, Sendable {
    case gptWeights
    case sovitsWeights

    var endpointPath: String {
        switch self {
        case .gptWeights:
            return "/set_gpt_weights"
        case .sovitsWeights:
            return "/set_sovits_weights"
        }
    }

    func weightsPath(from request: TTSPresetApplyRequest) -> String {
        switch self {
        case .gptWeights:
            return request.gptWeightsPath
        case .sovitsWeights:
            return request.sovitsWeightsPath
        }
    }
}

enum TTSPresetApplyError: LocalizedError, Sendable {
    case invalidServerAddress(stage: TTSPresetApplyStage)
    case requestFailed(stage: TTSPresetApplyStage, statusCode: Int?, errorDescription: String)

    var settingsMessage: String {
        switch self {
        case .invalidServerAddress(.gptWeights):
            return NSLocalizedString(
                "Invalid server address for GPT weights",
                comment: "Shown when the GPT weights endpoint cannot be constructed"
            )
        case .invalidServerAddress(.sovitsWeights):
            return NSLocalizedString(
                "Invalid server address for SoVITS weights",
                comment: "Shown when the SoVITS weights endpoint cannot be constructed"
            )
        case let .requestFailed(.gptWeights, statusCode?, _):
            return String(
                format: NSLocalizedString(
                    "Set GPT weights failed (HTTP %d)",
                    comment: "Shown when setting GPT weights fails with an HTTP status."
                ),
                statusCode
            )
        case let .requestFailed(.sovitsWeights, statusCode?, _):
            return String(
                format: NSLocalizedString(
                    "Set SoVITS weights failed (HTTP %d)",
                    comment: "Shown when setting SoVITS weights fails with an HTTP status."
                ),
                statusCode
            )
        case let .requestFailed(.gptWeights, nil, errorDescription):
            return String(
                format: NSLocalizedString(
                    "Set GPT weights failed: %@",
                    comment: "Shown when setting GPT weights fails with an error."
                ),
                errorDescription
            )
        case let .requestFailed(.sovitsWeights, nil, errorDescription):
            return String(
                format: NSLocalizedString(
                    "Set SoVITS weights failed: %@",
                    comment: "Shown when setting SoVITS weights fails with an error."
                ),
                errorDescription
            )
        }
    }

    var errorDescription: String? {
        settingsMessage
    }
}

struct TTSPresetApplyService: Sendable {
    typealias RetryStateHandler = @Sendable (TTSPresetApplyRetryStatus?) async -> Void

    static let defaultRetryPolicy = NetworkRetryPolicy(
        maxAttempts: 4,
        baseDelay: 0.5,
        maxDelay: 4.0,
        backoffFactor: 1.6,
        jitterRatio: 0.2
    )

    let retryPolicy: NetworkRetryPolicy

    init(retryPolicy: NetworkRetryPolicy = Self.defaultRetryPolicy) {
        self.retryPolicy = retryPolicy
    }

    static func endpointURL(
        serverAddress: String,
        endpointPath: String,
        weightsPath: String
    ) -> URL? {
        let raw = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let normalized = raw.contains("://") ? raw : "http://\(raw)"
        let base = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var comps = URLComponents(string: base + endpointPath)
        comps?.queryItems = [URLQueryItem(name: "weights_path", value: weightsPath)]
        return comps?.url
    }

    func endpointURL(for request: TTSPresetApplyRequest, stage: TTSPresetApplyStage) -> URL? {
        Self.endpointURL(
            serverAddress: request.serverAddress,
            endpointPath: stage.endpointPath,
            weightsPath: stage.weightsPath(from: request)
        )
    }

    func apply(
        _ request: TTSPresetApplyRequest,
        onRetryStateChange: RetryStateHandler? = nil
    ) async throws {
        try await applyStage(.gptWeights, request: request, onRetryStateChange: onRetryStateChange)
        try await applyStage(.sovitsWeights, request: request, onRetryStateChange: onRetryStateChange)
    }

    private func applyStage(
        _ stage: TTSPresetApplyStage,
        request: TTSPresetApplyRequest,
        onRetryStateChange: RetryStateHandler?
    ) async throws {
        guard let url = endpointURL(for: request, stage: stage) else {
            throw TTSPresetApplyError.invalidServerAddress(stage: stage)
        }

        do {
            _ = try await fetchWithRetry(url, onRetryStateChange: onRetryStateChange)
            await onRetryStateChange?(nil)
        } catch let statusError as HTTPStatusError {
            throw TTSPresetApplyError.requestFailed(
                stage: stage,
                statusCode: statusError.statusCode,
                errorDescription: statusError.localizedDescription
            )
        } catch {
            throw TTSPresetApplyError.requestFailed(
                stage: stage,
                statusCode: nil,
                errorDescription: error.localizedDescription
            )
        }
    }

    private func fetchWithRetry(
        _ url: URL,
        onRetryStateChange: RetryStateHandler?
    ) async throws -> Data {
        try await NetworkRetry.run(
            policy: retryPolicy,
            onRetry: { nextAttempt, _, error in
                await onRetryStateChange?(TTSPresetApplyRetryStatus(
                    nextAttempt: nextAttempt,
                    errorDescription: error.localizedDescription
                ))
            },
            operation: {
                let (data, resp) = try await URLSession.shared.data(from: url)
                if let http = resp as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    let preview = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let snippet = preview.isEmpty ? nil : String(preview.prefix(180))
                    throw HTTPStatusError(statusCode: http.statusCode, bodyPreview: snippet)
                }
                return data
            }
        )
    }
}
