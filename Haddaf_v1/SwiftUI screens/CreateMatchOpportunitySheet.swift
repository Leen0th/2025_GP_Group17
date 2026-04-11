import SwiftUI
import FirebaseFirestore
import MapKit
import GoogleMaps

struct CreateMatchOpportunitySheet: View {
    @EnvironmentObject var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var dateTime = Date().addingTimeInterval(3600)
    @State private var locationSearch = ""
    @State private var selectedPlace: MatchPlace? = nil
    @StateObject private var places = GooglePlacesService.shared

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

                    Text("Date and time")
                        .font(.system(size: 14, weight: .semibold))

                    DatePicker("", selection: $dateTime, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))

                    Text("Location")
                        .font(.system(size: 14, weight: .semibold))

                    ZStack(alignment: .top) {

                        // ✅ Map
                        let lat = selectedPlace?.latitude ?? 24.7136
                        let lng = selectedPlace?.longitude ?? 46.6753

                        GoogleMapView(
                            latitude: lat,
                            longitude: lng
                        ) { coordinate in

                            // 🔥 Reverse Geocode (اسم المكان الحقيقي)
                            Task {
                                let place = await places.reverseGeocode(coordinate: coordinate)

                                selectedPlace = place
                                locationSearch = place.name
                            }
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // 🔍 Search
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
                                            Task {
                                                let resolved = await places.resolveCoordinates(for: place)

                                                selectedPlace = resolved
                                                locationSearch = resolved.name
                                                places.suggestions = []
                                            }
                                        } label: {

                                            // 🔥 اسم + عنوان
                                            VStack(alignment: .leading, spacing: 2) {

                                                Text(place.name)
                                                    .font(.system(size: 13, weight: .medium))

                                                Text(place.address)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.gray)
                                                    .lineLimit(1)
                                            }
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

                    Text("Open Positions")
                        .font(.system(size: 14, weight: .semibold))

                    VStack(spacing: 10) {
                        StepperRow(title: "Attackers", count: $attackerCount)
                        StepperRow(title: "Midfielders", count: $midfielderCount)
                        StepperRow(title: "Defenders", count: $defenderCount)
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }

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

        let resolvedPlace = selectedPlace ?? MatchPlace(
            name: locationSearch,
            address: locationSearch,
            latitude: nil,
            longitude: nil,
            placeID: nil
        )

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

// ✅ نفس لون زر POST
struct StepperRow: View {
    let title: String
    @Binding var count: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()

            Button {
                if count > 0 { count -= 1 }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundColor(BrandColors.darkTeal)
            }

            Text("\(count)")
                .frame(width: 30)

            Button {
                count += 1
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(BrandColors.darkTeal)
            }
        }
        .padding(10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
