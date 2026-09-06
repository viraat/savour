import CoreLocation
import MapKit
import Combine

final class LocationSearchModel: NSObject, ObservableObject {
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []
    @Published private(set) var isLocating = false
    @Published private(set) var isEnabled = false
    @Published private(set) var message: String?
    @Published private(set) var resolvedPlace: String?

    private let completer = MKLocalSearchCompleter()
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var acceptedPlace: String?
    private var waitingForAuthorization = false

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func updateQuery(_ query: String) {
        guard isEnabled else {
            suggestions = []
            completer.cancel()
            return
        }

        if query == acceptedPlace {
            acceptedPlace = nil
            return
        }

        message = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            completer.cancel()
            return
        }
        completer.queryFragment = trimmed
    }

    func setEnabled(_ enabled: Bool, query: String) {
        isEnabled = enabled
        message = nil

        if enabled {
            updateQuery(query)
        } else {
            waitingForAuthorization = false
            isLocating = false
            suggestions = []
            stop()
        }
    }

    func select(_ completion: MKLocalSearchCompletion) -> String {
        let value = [completion.title, completion.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        acceptedPlace = value
        suggestions = []
        completer.cancel()
        return value
    }

    func requestCurrentPlace() {
        guard isEnabled else { return }
        message = nil
        waitingForAuthorization = true

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocation()
        case .denied:
            waitingForAuthorization = false
            message = "Location access is disabled in Settings."
        case .restricted:
            waitingForAuthorization = false
            message = "Location access is unavailable."
        @unknown default:
            waitingForAuthorization = false
            message = "Location access is unavailable."
        }
    }

    func stop() {
        completer.cancel()
        geocoder.cancelGeocode()
        locationManager.stopUpdatingLocation()
    }

    private func requestLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            waitingForAuthorization = false
            message = "Location Services are turned off."
            return
        }
        isLocating = true
        locationManager.requestLocation()
    }

    private func resolve(_ location: CLLocation) {
        guard isEnabled else { return }
        completer.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 20_000,
            longitudinalMeters: 20_000
        )

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLocating = false

                guard error == nil, let placemark = placemarks?.first else {
                    self.message = "The current place could not be found."
                    return
                }

                let pieces = [
                    placemark.name,
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.country
                ].compactMap { $0 }.reduce(into: [String]()) { result, piece in
                    if !result.contains(where: { $0.caseInsensitiveCompare(piece) == .orderedSame }) {
                        result.append(piece)
                    }
                }

                guard !pieces.isEmpty else {
                    self.message = "The current place could not be found."
                    return
                }
                let place = pieces.joined(separator: ", ")
                self.suggestions = []
                self.completer.cancel()
                self.acceptedPlace = place
                self.resolvedPlace = place
            }
        }
    }
}

extension LocationSearchModel: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = isEnabled ? Array(completer.results.prefix(5)) : []
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}

extension LocationSearchModel: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard waitingForAuthorization else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocation()
        case .denied:
            waitingForAuthorization = false
            message = "Location access is disabled in Settings."
        case .restricted:
            waitingForAuthorization = false
            message = "Location access is unavailable."
        case .notDetermined:
            break
        @unknown default:
            waitingForAuthorization = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        waitingForAuthorization = false
        guard isEnabled else { return }
        guard let location = locations.last else {
            isLocating = false
            message = "The current location could not be found."
            return
        }
        resolve(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        waitingForAuthorization = false
        isLocating = false
        guard isEnabled else { return }
        message = "The current location could not be found."
    }
}
