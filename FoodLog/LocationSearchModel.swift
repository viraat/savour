import Combine
import CoreLocation
import MapKit

struct LocationSelection: Equatable {
    let displayName: String
    let city: String
    let latitude: Double
    let longitude: Double
}

enum PlaceFormatting {
    static func city(from placemark: MKPlacemark) -> String {
        placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea ?? ""
    }

    static func conciseName(place: String, city: String) -> String {
        let trimmedPlace = place.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeName = trimmedPlace
            .split(separator: ",", omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmedPlace

        guard !trimmedCity.isEmpty,
              placeName.caseInsensitiveCompare(trimmedCity) != .orderedSame
        else { return placeName }
        return "\(placeName), \(trimmedCity)"
    }
}

final class LocationSearchModel: NSObject, ObservableObject {
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []
    @Published private(set) var isLocating = false
    @Published private(set) var isEnabled = false
    @Published private(set) var message: String?
    @Published private(set) var resolvedSelection: LocationSelection?

    private let completer = MKLocalSearchCompleter()
    private let locationManager = CLLocationManager()
    private var localSearch: MKLocalSearch?
    private var acceptedPlace: String?
    private var waitingForAuthorization = false

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .pointOfInterest
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
        let temporaryName = completion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        acceptedPlace = temporaryName
        suggestions = []
        completer.cancel()
        localSearch?.cancel()
        message = nil

        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        localSearch = search
        search.start { [weak self, weak search] response, error in
            DispatchQueue.main.async {
                guard let self, self.localSearch === search else { return }
                self.localSearch = nil

                guard error == nil, let item = response?.mapItems.first else {
                    self.message = "More details for this place could not be loaded."
                    return
                }

                let city = PlaceFormatting.city(from: item.placemark)
                let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayName = PlaceFormatting.conciseName(
                    place: name?.isEmpty == false ? name! : temporaryName,
                    city: city
                )
                self.acceptedPlace = displayName
                self.resolvedSelection = LocationSelection(
                    displayName: displayName,
                    city: city,
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
            }
        }

        return temporaryName
    }

    func requestNearbyRegion() {
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
            message = "Location access is disabled in Settings. Search still works."
        case .restricted:
            waitingForAuthorization = false
            message = "Location access is unavailable. Search still works."
        @unknown default:
            waitingForAuthorization = false
            message = "Location access is unavailable. Search still works."
        }
    }

    func stop() {
        completer.cancel()
        localSearch?.cancel()
        localSearch = nil
        locationManager.stopUpdatingLocation()
    }

    private func requestLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            waitingForAuthorization = false
            message = "Location Services are off. Search still works."
            return
        }
        isLocating = true
        locationManager.requestLocation()
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
            message = "Location access is disabled in Settings. Search still works."
        case .restricted:
            waitingForAuthorization = false
            message = "Location access is unavailable. Search still works."
        case .notDetermined:
            break
        @unknown default:
            waitingForAuthorization = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        waitingForAuthorization = false
        isLocating = false
        guard isEnabled, let location = locations.last else { return }
        completer.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 20_000,
            longitudinalMeters: 20_000
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        waitingForAuthorization = false
        isLocating = false
        guard isEnabled else { return }
        message = "Nearby results are unavailable. Search still works."
    }
}
