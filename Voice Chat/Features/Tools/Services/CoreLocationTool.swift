//
//  CoreLocationTool.swift
//  Voice Chat
//
//  Created by Codex on 2026.06.22.
//

import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

protocol LocationToolServing: Sendable {
    func currentLocation(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload
}

struct CoreLocationTool: LocationToolServing {
    func currentLocation(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        #if canImport(CoreLocation)
        let provider = await LocationSnapshotProvider()
        let location = try await provider.currentLocation()
        let roundedLatitude = (location.coordinate.latitude * 100_000).rounded() / 100_000
        let roundedLongitude = (location.coordinate.longitude * 100_000).rounded() / 100_000
        return ChatToolExecutionPayload(
            payload: [
                "latitude": .number(roundedLatitude),
                "longitude": .number(roundedLongitude),
                "horizontal_accuracy_meters": .number(location.horizontalAccuracy),
                "timestamp": .string(ISO8601DateFormatter().string(from: location.timestamp))
            ],
            summary: NSLocalizedString("Current location was read.", comment: "Tool summary")
        )
        #else
        throw ChatToolError.unsupported(NSLocalizedString("Location access is not available on this platform.", comment: "Tool-use error"))
        #endif
    }
}

#if canImport(CoreLocation)
@MainActor
private final class LocationSnapshotProvider: NSObject, @preconcurrency CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var didStartUpdating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw ChatToolError.unsupported(NSLocalizedString("Location services are disabled.", comment: "Tool-use error"))
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                self?.finish(.failure(ChatToolError.failed(NSLocalizedString("Location request timed out.", comment: "Tool-use error"))))
            }

            handleAuthorizationStatus(manager.authorizationStatus)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorizationStatus(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError,
           locationError.code == .locationUnknown,
           didStartUpdating {
            return
        }
        finish(.failure(ChatToolError.failed(error.localizedDescription)))
    }

    private func handleAuthorizationStatus(_ status: CLAuthorizationStatus) {
        guard continuation != nil else { return }

        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(.failure(ChatToolError.denied(NSLocalizedString("Location permission was denied.", comment: "Tool-use error"))))
        default:
            guard Self.isAuthorized(status) else {
                finish(.failure(ChatToolError.denied(NSLocalizedString("Location permission was denied.", comment: "Tool-use error"))))
                return
            }
            requestSnapshot()
        }
    }

    private func requestSnapshot() {
        guard continuation != nil else { return }

        if let cached = manager.location,
           cached.horizontalAccuracy >= 0,
           abs(cached.timestamp.timeIntervalSinceNow) < 120 {
            finish(.success(cached))
            return
        }

        manager.requestLocation()
        if !didStartUpdating {
            didStartUpdating = true
            manager.startUpdatingLocation()
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if didStartUpdating {
            manager.stopUpdatingLocation()
            didStartUpdating = false
        }
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    private static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        #if os(macOS)
        status == .authorizedAlways || status == .authorized
        #else
        status == .authorizedAlways || status == .authorizedWhenInUse
        #endif
    }
}
#endif
