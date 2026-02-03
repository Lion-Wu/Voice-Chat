//
//  Models.swift
//  Voice Chat
//
//  Created by Lion Wu on 2024.09.22.
//

import Foundation

struct ModelListResponse: Codable {
    let object: String
    let data: [ModelInfo]
}

struct ModelInfo: Codable {
    let id: String
    let object: String
    let created: Int?
    let owned_by: String?
}

// MARK: - Network Retry

struct NetworkRetryPolicy: Sendable {
    /// Total number of attempts including the initial try. `nil` means retry forever until cancelled.
    let maxAttempts: Int?
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let backoffFactor: Double
    let jitterRatio: Double

    init(
        maxAttempts: Int? = 6,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        backoffFactor: Double = 1.6,
        jitterRatio: Double = 0.2
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = max(0, baseDelay)
        self.maxDelay = max(self.baseDelay, maxDelay)
        self.backoffFactor = max(1.0, backoffFactor)
        self.jitterRatio = max(0, min(1, jitterRatio))
    }

    func shouldContinue(afterAttempt attempt: Int) -> Bool {
        guard let maxAttempts else { return true }
        return attempt < maxAttempts
    }

    /// `retryCount` is 1 for the first retry after the initial failure.
    func delay(forRetryCount retryCount: Int) -> TimeInterval {
        guard retryCount > 0 else { return 0 }
        let exponent = Double(max(0, retryCount - 1))
        let raw = baseDelay * pow(backoffFactor, exponent)
        let clamped = min(maxDelay, max(0, raw))
        guard jitterRatio > 0, clamped > 0 else { return clamped }
        let delta = clamped * jitterRatio
        return Double.random(in: max(0, clamped - delta)...(clamped + delta))
    }
}

struct HTTPStatusError: LocalizedError, Sendable {
    let statusCode: Int
    let bodyPreview: String?

    var errorDescription: String? {
        if let bodyPreview, !bodyPreview.isEmpty {
            return "HTTP \(statusCode): \(bodyPreview)"
        }
        return "HTTP \(statusCode)"
    }
}

enum NetworkRetryability {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    static func shouldRetry(_ error: Error) -> Bool {
        if isCancellation(error) { return false }

        if let status = error as? HTTPStatusError {
            return shouldRetry(statusCode: status.statusCode)
        }

        if let url = error as? URLError {
            return shouldRetry(urlCode: url.code)
        }

        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return shouldRetry(urlCode: URLError.Code(rawValue: ns.code))
        }

        return false
    }

    static func shouldRetry(statusCode: Int) -> Bool {
        switch statusCode {
        case 408, 425, 429, 500, 502, 503, 504:
            return true
        default:
            return false
        }
    }

    private static func shouldRetry(urlCode: URLError.Code) -> Bool {
        switch urlCode {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }
}

enum NetworkRetry {
    static func sleep(seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        do {
            try await Task.sleep(for: .seconds(seconds))
        } catch {
            // Cancellation or sleep failure should stop the retry loop naturally.
        }
    }

    static func run<T>(
        policy: NetworkRetryPolicy,
        shouldRetry: @escaping @Sendable (Error) -> Bool = NetworkRetryability.shouldRetry(_:),
        onRetry: (@Sendable (_ nextAttempt: Int, _ delay: TimeInterval, _ error: Error) async -> Void)? = nil,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            attempt += 1
            do {
                try Task.checkCancellation()
                return try await operation()
            } catch {
                if NetworkRetryability.isCancellation(error) { throw error }
                guard shouldRetry(error) else { throw error }
                guard policy.shouldContinue(afterAttempt: attempt) else { throw error }

                let retryCount = attempt
                let delay = policy.delay(forRetryCount: retryCount)
                await onRetry?(attempt + 1, delay, error)
                await sleep(seconds: delay)
                continue
            }
        }
    }
}
