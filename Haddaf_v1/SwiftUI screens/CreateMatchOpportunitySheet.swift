import SwiftUI
import FirebaseFirestore
import MapKit

struct CreateMatchOpportunitySheet: View {
    @EnvironmentObject var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var dateTime = Date().addingTimeInterval(3600)
    @State private var locationSearch = ""
    @State private var selectedPlace: MatchPlace? = nil
    @StateObject private var places = GooglePlacesService.shared

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 24.7136, longitude: 46.6753),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )

    @State private var attackerCount = 0
    @State private var midfielderCount = 0
    @State private var defenderCount = 0

    @State private var isSaving = false
    @State private var errorText: String? = nil

    private let accent = BrandColors.darkTeal

    private var totalPositions: Int {
        attackerCount + midfielderCount + defenderCount
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // DATE
                    Text("Date and time")
                        .font(.system(size: 14, weight: .semibold))

                    DatePicker("", selection: $dateTime, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))

                    // LOCATION
                    Text("Location")
                        .font(.system(size: 14, weight: .semibold))

                    ZStack(alignment: .top) {

                        Map(
                            coordinateRegion: $region,
                            annotationItems: selectedPlace != nil ? [selectedPlace!] : []
                        ) { place in
                            MapMarker(
                                coordinate: CLLocationCoordinate2D(
                                    latitude: place.latitude ?? region.center.latitude,
                                    longitude: place.longitude ?? region.center.longitude
                                )
                            )
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(spacing: 0) {

                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 13))

                                TextField("Search place...", text: $locationSearch)
                                    .font(.system(size: 13))
                                    .onChange(of: locationSearch) { _, newValue in
                                        places.search(query: newValue)
                                    }
                            }
                            .padding(11)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            if !places.suggestions.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(places.suggestions, id: \.id) { place in
                                        Button {
                                            selectedPlace = place
                                            locationSearch = place.name
                                            places.suggestions = []

                                            if let lat = place.latitude,
                                               let lng = place.longitude {
                                                region = MKCoordinateRegion(
                                                    center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                                                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                                )
                                            }
                                        } label: {
                                            Text(place.name)
                                                .font(.system(size: 13))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 10)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }

                                        Divider()
                                    }
                                }
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(10)
                        .zIndex(1)
                    }

                    // POSITIONS
                    Text("Open Positions")
                        .font(.system(size: 14, weight: .semibold))

                    VStack(spacing: 10) {
                        StepperRow(title: "Attackers", count: $attackerCount)
                        StepperRow(title: "Midfielders", count: $midfielderCount)
                        StepperRow(title: "Defenders", count: $defenderCount)
                    }

                    // ERROR
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }

                    // POST BUTTON
                    Button {
                        Task { await saveMatch() }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView().tint(.white)
                            }
                            Text("POST MATCH")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(totalPositions == 0 ? Color.gray.opacity(0.4) : accent)
                        .clipShape(Capsule())
                    }
                    .disabled(isSaving || totalPositions == 0 || locationSearch.isEmpty)
                }
                .padding(18)
                .background(BrandColors.backgroundGradientEnd)
            }
            .navigationTitle("Add New Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 14))
                }
            }
            .task {
                places.startSession()
            }
        }
    }

    private func saveMatch() async {
        guard let uid = session.user?.uid else { return }

        isSaving = true

        let name = await fetchUserDisplayName(uid: uid)
        let resolvedPlace = await places.resolveCoordinates(for: locationSearch)

        try? await MatchService.shared.createMatch(
            organizerId: uid,
            organizerName: name,
            organizerRole: session.role ?? "player",
            dateTime: dateTime,
            place: resolvedPlace,
            positions: [
                MatchPosition.attacker.rawValue: attackerCount,
                MatchPosition.midfielder.rawValue: midfielderCount,
                MatchPosition.defender.rawValue: defenderCount
            ]
        )

        isSaving = false
        dismiss()
    }

    private func fetchUserDisplayName(uid: String) async -> String {
        let doc = try? await Firestore.firestore()
            .collection("users")
            .document(uid)
            .getDocument()

        let fn = doc?.data()?["firstName"] as? String ?? ""
        let ln = doc?.data()?["lastName"] as? String ?? ""
        let name = "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Match Organizer" : name
    }
}

struct StepperRow: View {
    let title: String
    @Binding var count: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))

            Spacer()

            Button {
                if count > 0 { count -= 1 }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
            }

            Text("\(count)")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28)

            Button {
                count += 1
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
            }
            .foregroundColor(BrandColors.darkTeal)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
    }
}
