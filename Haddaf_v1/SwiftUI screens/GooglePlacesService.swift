import Foundation
import GooglePlaces
import GoogleMaps  
@MainActor
final class GooglePlacesService: NSObject, ObservableObject {
    static let shared = GooglePlacesService()

    @Published var suggestions: [MatchPlace] = []
    @Published var isLoading = false

    private let placesClient = GMSPlacesClient.shared()
    private var currentToken: GMSAutocompleteSessionToken?

    func startSession() {
        currentToken = GMSAutocompleteSessionToken()
    }

    func reset() {
        suggestions = []
        isLoading = false
        currentToken = nil
    }

    func search(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            suggestions = []
            isLoading = false
            return
        }

        if currentToken == nil {
            startSession()
        }

        isLoading = true

        let filter = GMSAutocompleteFilter()
        filter.types = []   // 🔥 مهم
        filter.country = "SA"

        placesClient.findAutocompletePredictions(
            fromQuery: trimmed,
            filter: filter,
            sessionToken: currentToken
        ) { [weak self] results, error in
            guard let self else { return }

            Task { @MainActor in
                self.isLoading = false

                guard error == nil, let results else {
                    self.suggestions = []
                    return
                }

                self.suggestions = results.map { prediction in
                    MatchPlace(
                        name: prediction.attributedPrimaryText.string,
                        address: prediction.attributedFullText.string,
                        latitude: nil,
                        longitude: nil,
                        placeID: prediction.placeID
                    )
                }
            }
        }
    }
    

    func resolveCoordinates(for place: MatchPlace) async -> MatchPlace {
        await withCheckedContinuation { continuation in
            guard let placeID = place.placeID else {
                continuation.resume(returning: place)
                return
            }

            let fields: GMSPlaceField = [.name, .formattedAddress, .coordinate]

            placesClient.fetchPlace(
                fromPlaceID: placeID,
                placeFields: fields,
                sessionToken: currentToken
            ) { fetchedPlace, error in
                let resolved = MatchPlace(
                    name: place.name, // نحافظ على النص اللي اختاره المستخدم
                    address: fetchedPlace?.formattedAddress ?? place.address,
                    latitude: fetchedPlace?.coordinate.latitude,
                    longitude: fetchedPlace?.coordinate.longitude,
                    placeID: placeID
                )

                continuation.resume(returning: resolved)
            }
        }
    }
    func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> MatchPlace {

        await withCheckedContinuation { continuation in

            let geocoder = GMSGeocoder()

            geocoder.reverseGeocodeCoordinate(coordinate) { response, _ in

                let first = response?.firstResult()

                let place = MatchPlace(
                    name: first?.lines?.first ?? "Selected Location",
                    address: first?.lines?.joined(separator: ", ") ?? "Custom location",
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    placeID: nil
                )

                continuation.resume(returning: place)
            }
        }
    }
}
