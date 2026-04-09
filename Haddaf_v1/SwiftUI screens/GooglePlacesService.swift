import Foundation
import GooglePlaces

@MainActor
final class GooglePlacesService: NSObject, ObservableObject {
    static let shared = GooglePlacesService()

    @Published var suggestions: [MatchPlace] = []
    @Published var isLoading = false

    private var placesClient = GMSPlacesClient.shared()
    private var currentToken: GMSAutocompleteSessionToken?

    func startSession() {
        currentToken = GMSAutocompleteSessionToken()
    }

    func reset() {
        suggestions = []
        isLoading = false
        currentToken = nil
    }

    // 🔍 SEARCH (FIXED)
    func search(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            return
        }

        if currentToken == nil { startSession() }
        isLoading = true

        let filter = GMSAutocompleteFilter()
        filter.types = ["establishment", "geocode"]
        filter.country = "SA"

        placesClient.findAutocompletePredictions(
            fromQuery: trimmed,
            filter: filter,
            sessionToken: currentToken
        ) { [weak self] results, error in
            guard let self else { return }
            self.isLoading = false

            guard let results else {
                self.suggestions = []
                return
            }

            // 🔥 نحفظ placeID عشان نجيب الإحداثيات
            self.suggestions = results.map {
                MatchPlace(
                    name: $0.attributedPrimaryText.string,
                    address: $0.attributedFullText.string,
                    latitude: nil,
                    longitude: nil
                )
            }
        }
    }

    // 📍 GET COORDINATES (IMPORTANT)
    func resolveCoordinates(for placeName: String) async -> MatchPlace {
        await withCheckedContinuation { continuation in

            placesClient.findAutocompletePredictions(
                fromQuery: placeName,
                filter: nil,
                sessionToken: currentToken
            ) { [weak self] results, _ in

                guard let self,
                      let placeID = results?.first?.placeID else {

                    continuation.resume(returning:
                        MatchPlace(name: placeName, address: placeName, latitude: nil, longitude: nil)
                    )
                    return
                }

                let fields: GMSPlaceField = [.name, .formattedAddress, .coordinate]

                self.placesClient.fetchPlace(
                    fromPlaceID: placeID,
                    placeFields: fields,
                    sessionToken: self.currentToken
                ) { place, _ in

                    let resolved = MatchPlace(
                        name: place?.name ?? placeName,
                        address: place?.formattedAddress ?? placeName,
                        latitude: place?.coordinate.latitude,
                        longitude: place?.coordinate.longitude
                    )

                    continuation.resume(returning: resolved)
                }
            }
        }
    }
}
