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
#if canImport(Contacts)
import Contacts
#endif

protocol LocationToolServing: Sendable {
    func currentLocation(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload
}

struct CoreLocationTool: LocationToolServing {
    func currentLocation(arguments: ChatToolArgumentReader) async throws -> ChatToolExecutionPayload {
        #if canImport(CoreLocation)
        let provider = await LocationSnapshotProvider()
        let location = try await provider.currentLocation()
        let place = await reverseGeocodedPlace(for: location)
        let roundedLatitude = (location.coordinate.latitude * 100_000).rounded() / 100_000
        let roundedLongitude = (location.coordinate.longitude * 100_000).rounded() / 100_000
        var payload: [String: JSONValue] = [
            "latitude": .number(roundedLatitude),
            "longitude": .number(roundedLongitude),
            "horizontal_accuracy_meters": .number(location.horizontalAccuracy),
            "timestamp": .string(ChatToolTimeFormatter.localISO8601String(from: location.timestamp)),
            "timestamp_utc": .string(ChatToolTimeFormatter.utcISO8601String(from: location.timestamp)),
            "timezone": .string(TimeZone.autoupdatingCurrent.identifier),
            "timezone_offset": .string(ChatToolTimeFormatter.timeZoneOffsetString(for: location.timestamp))
        ]
        payload["place"] = place?.jsonValue ?? .null

        let summary: String
        if let displayName = place?.displayName {
            summary = String(
                format: NSLocalizedString("Current location was read: %@.", comment: "Tool summary"),
                displayName
            )
        } else {
            summary = NSLocalizedString("Current location was read.", comment: "Tool summary")
        }
        return ChatToolExecutionPayload(
            payload: payload,
            summary: summary
        )
        #else
        throw ChatToolError.unsupported(NSLocalizedString("Location access is not available on this platform.", comment: "Tool-use error"))
        #endif
    }

    #if canImport(CoreLocation)
    private func reverseGeocodedPlace(for location: CLLocation) async -> LocationPlaceDescription? {
        let geocoder = CLGeocoder()
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return nil
        }
        return LocationPlaceDescription(placemark: placemark)
    }
    #endif
}

#if canImport(CoreLocation)
struct LocationPlaceDescription: Sendable {
    let formattedAddress: String?
    let name: String?
    let country: String?
    let countryCode: String?
    let administrativeArea: String?
    let subAdministrativeArea: String?
    let locality: String?
    let subLocality: String?
    let postalCode: String?
    let thoroughfare: String?
    let subThoroughfare: String?
    let areasOfInterest: [String]
    let inlandWater: String?
    let ocean: String?

    init(placemark: CLPlacemark) {
        #if canImport(Contacts)
        if let postalAddress = placemark.postalAddress {
            formattedAddress = CNPostalAddressFormatter
                .string(from: postalAddress, style: .mailingAddress)
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        } else {
            formattedAddress = nil
        }
        #else
        formattedAddress = nil
        #endif
        name = placemark.name
        country = placemark.country
        countryCode = placemark.isoCountryCode
        administrativeArea = placemark.administrativeArea
        subAdministrativeArea = placemark.subAdministrativeArea
        locality = placemark.locality
        subLocality = placemark.subLocality
        postalCode = placemark.postalCode
        thoroughfare = placemark.thoroughfare
        subThoroughfare = placemark.subThoroughfare
        areasOfInterest = placemark.areasOfInterest ?? []
        inlandWater = placemark.inlandWater
        ocean = placemark.ocean
    }

    var jsonValue: JSONValue {
        var fields: [String: JSONValue] = [:]
        insert(formattedAddress, as: "formatted_address", into: &fields)
        insert(name, as: "name", into: &fields)
        insert(country, as: "country", into: &fields)
        insert(countryCode, as: "country_code", into: &fields)
        insert(administrativeArea, as: "administrative_area", into: &fields)
        insert(subAdministrativeArea, as: "sub_administrative_area", into: &fields)
        insert(locality, as: "locality", into: &fields)
        insert(subLocality, as: "sub_locality", into: &fields)
        insert(postalCode, as: "postal_code", into: &fields)
        insert(thoroughfare, as: "thoroughfare", into: &fields)
        insert(subThoroughfare, as: "sub_thoroughfare", into: &fields)
        insert(inlandWater, as: "inland_water", into: &fields)
        insert(ocean, as: "ocean", into: &fields)
        if !areasOfInterest.isEmpty {
            fields["areas_of_interest"] = .array(areasOfInterest.map(JSONValue.string))
        }
        return .object(fields)
    }

    var displayName: String? {
        formattedAddress ?? name ?? firstNonempty([
            subLocality,
            locality,
            subAdministrativeArea,
            administrativeArea,
            country
        ])
    }

    private func insert(
        _ value: String?,
        as key: String,
        into fields: inout [String: JSONValue]
    ) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return
        }
        fields[key] = .string(value)
    }

    private func firstNonempty(_ values: [String?]) -> String? {
        values.lazy.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }
}
#endif

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
        #if os(visionOS)
        status == .authorizedWhenInUse
        #elseif os(macOS)
        status == .authorizedAlways || status == .authorized
        #else
        status == .authorizedAlways || status == .authorizedWhenInUse
        #endif
    }
}
#endif
