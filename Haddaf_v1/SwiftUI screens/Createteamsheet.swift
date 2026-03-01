import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore

// MARK: - Create Team Page (Full Page)
struct CreateTeamSheet: View {
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss

    // Academy selection
    @State private var academySearch = ""
    @State private var selectedAcademy: String = ""
    @State private var showAcademyPicker = false

    // City selection (filtered by academy)
    @State private var citySearch = ""
    @State private var selectedCity: String = ""
    @State private var showCityPicker = false

    // Street selection (filtered by academy + city)
    @State private var streetSearch = ""
    @State private var selectedStreet: String = ""
    @State private var showStreetPicker = false

    // Logo
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var teamLogoImage: Image?
    @State private var fileExt = "jpg"
    @State private var downloadURL: URL?
    @State private var isUploading = false
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMsg = ""

    private let primary = BrandColors.darkTeal

    // Filtered lists
    private var filteredAcademies: [String] {
        let all = SAUDI_ACADEMY_NAMES
        if academySearch.isEmpty { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(academySearch) }
    }

    private var availableCities: [String] {
        guard !selectedAcademy.isEmpty else { return SAUDI_ACADEMY_CITIES }
        return citiesForAcademy(selectedAcademy)
    }

    private var filteredCities: [String] {
        if citySearch.isEmpty { return availableCities }
        return availableCities.filter { $0.localizedCaseInsensitiveContains(citySearch) }
    }

    private var availableStreets: [String] {
        if selectedAcademy.isEmpty && selectedCity.isEmpty { return [] }
        if !selectedAcademy.isEmpty && !selectedCity.isEmpty {
            return Array(Set(SAUDI_ACADEMIES.filter {
                $0.name == selectedAcademy && $0.city == selectedCity
            }.map { $0.street })).sorted()
        }
        if !selectedAcademy.isEmpty {
            return streetsForAcademy(selectedAcademy)
        }
        return streetsForCity(selectedCity)
    }

    private var filteredStreets: [String] {
        if streetSearch.isEmpty { return availableStreets }
        return availableStreets.filter { $0.localizedCaseInsensitiveContains(streetSearch) }
    }

    private var teamName: String { selectedAcademy }

    private var canSubmit: Bool {
        !selectedAcademy.isEmpty && !selectedCity.isEmpty && !selectedStreet.isEmpty
            && !isUploading && !isSaving
    }

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Custom Header ────────────────────────────────────
                    ZStack {
                        Text("Create Team")
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .foregroundColor(primary)
                        HStack {
                            Button { dismiss() } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(primary)
                                    .padding(10)
                                    .background(Circle().fill(BrandColors.lightGray.opacity(0.7)))
                            }
                            Spacer()
                        }
                    }
                    .padding(.top, 8)

                    // Logo Picker
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        VStack(spacing: 8) {
                            ZStack(alignment: .bottomTrailing) {
                                if let image = teamLogoImage {
                                    image.resizable().scaledToFill()
                                        .frame(width: 110, height: 110).clipShape(Circle())
                                } else {
                                    Image(systemName: "shield.lefthalf.filled")
                                        .resizable().scaledToFit()
                                        .frame(width: 60, height: 60)
                                        .foregroundColor(primary.opacity(0.7))
                                        .frame(width: 110, height: 110)
                                        .background(Color.gray.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                Circle().fill(primary).frame(width: 32, height: 32)
                                    .overlay(Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold)).foregroundColor(.white))
                                    .shadow(color: primary.opacity(0.3), radius: 8, y: 4)
                            }
                            Text("Team Logo (Optional)")
                                .font(.system(size: 14, design: .rounded)).foregroundColor(primary.opacity(0.75))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 6)

                    // ── Academy Picker ──────────────────────────────────
                    fieldLabel("Academy Name", required: true)
                    pickerButton(
                        value: selectedAcademy,
                        placeholder: "Select academy",
                        action: { showAcademyPicker = true }
                    )

                    // ── City Picker ─────────────────────────────────────
                    fieldLabel("City", required: true)
                    pickerButton(
                        value: selectedCity,
                        placeholder: "Select city",
                        action: { showCityPicker = true }
                    )
                    .disabled(selectedAcademy.isEmpty)
                    .opacity(selectedAcademy.isEmpty ? 0.5 : 1)

                    // ── Street Picker ───────────────────────────────────
                    fieldLabel("Street", required: true)
                    pickerButton(
                        value: selectedStreet,
                        placeholder: "Select street",
                        action: { showStreetPicker = true }
                    )
                    .disabled(selectedCity.isEmpty)
                    .opacity(selectedCity.isEmpty ? 0.5 : 1)

                    // Create Button
                    Button {
                        Task { await saveTeam() }
                    } label: {
                        HStack(spacing: 10) {
                            Text("Create Team")
                                .font(.system(size: 18, weight: .medium, design: .rounded)).foregroundColor(.white)
                            if isUploading || isSaving { ProgressView().colorInvert().scaleEffect(0.9) }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                    .background(canSubmit ? primary : primary.opacity(0.4))
                    .clipShape(Capsule())
                    .shadow(color: canSubmit ? primary.opacity(0.3) : .clear, radius: 10, y: 5)
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.6)
                    .padding(.top)
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Notice", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMsg) }
        // ── Academy Sheet ────────────────────────────────────────────────
        .sheet(isPresented: $showAcademyPicker) {
            SearchablePickerSheet(
                title: "Select Academy",
                items: filteredAcademies,
                searchText: $academySearch,
                onSelect: { name in
                    selectedAcademy = name
                    selectedCity = ""
                    selectedStreet = ""
                    showAcademyPicker = false
                }
            )
        }
        // ── City Sheet ───────────────────────────────────────────────────
        .sheet(isPresented: $showCityPicker) {
            SearchablePickerSheet(
                title: "Select City",
                items: filteredCities,
                searchText: $citySearch,
                onSelect: { city in
                    selectedCity = city
                    selectedStreet = ""
                    showCityPicker = false
                }
            )
        }
        // ── Street Sheet ─────────────────────────────────────────────────
        .sheet(isPresented: $showStreetPicker) {
            SearchablePickerSheet(
                title: "Select Street",
                items: filteredStreets,
                searchText: $streetSearch,
                onSelect: { street in
                    selectedStreet = street
                    showStreetPicker = false
                }
            )
        }
        .onChange(of: selectedItem) { _, newItem in
            selectedImageData = nil; teamLogoImage = nil; downloadURL = nil; isUploading = false
            Task {
                guard let item = newItem else { return }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    selectedImageData = data
                    fileExt = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    if let uiImg = UIImage(data: data) { teamLogoImage = Image(uiImage: uiImg) }
                    do { try await uploadLogo() } catch {
                        alertMsg = "Logo upload failed: \(error.localizedDescription)"; showAlert = true
                        selectedImageData = nil; teamLogoImage = nil; downloadURL = nil; isUploading = false
                    }
                }
            }
        }
    }

    // ── Helper Views ─────────────────────────────────────────────────────

    @ViewBuilder
    private func fieldLabel(_ text: String, required: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text(text)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(primary)
            if required {
                Text("*")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.red)
            }
        }
    }

    @ViewBuilder
    private func pickerButton(value: String, placeholder: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(value.isEmpty ? placeholder : value)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(value.isEmpty ? Color(.placeholderText) : primary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(BrandColors.background)
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
            )
        }
    }

    // ── Firebase ──────────────────────────────────────────────────────────

    private func uploadLogo() async throws {
        guard let uid = Auth.auth().currentUser?.uid, let data = selectedImageData else { return }
        isUploading = true
        let filename = "\(UUID().uuidString).\(fileExt)"
        let ref = Storage.storage().reference().child("teams").child(uid).child("logo").child(filename)
        let meta = StorageMetadata(); meta.contentType = "image/\(fileExt == "jpg" ? "jpeg" : fileExt)"
        _ = try await ref.putDataAsync(data, metadata: meta)
        let url = try await ref.downloadURL()
        await MainActor.run { downloadURL = url; isUploading = false }
    }

    private func saveTeam() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSaving = true
        let db = Firestore.firestore()

        var payload: [String: Any] = [
            "coachUid": uid,
            "teamName": selectedAcademy,
            "city": selectedCity,
            "street": selectedStreet,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let logo = downloadURL?.absoluteString { payload["logoURL"] = logo }

        do {
            let teamDocRef = db.collection("teams").document()  // ✅ unique ID per team
            try await teamDocRef.setData(payload)
            try await db.collection("users").document(uid).setData([
                "teamId": teamDocRef.documentID,
                "teamName": selectedAcademy,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            await MainActor.run { isSaving = false; onCreated() }
        } catch {
            await MainActor.run { isSaving = false; alertMsg = error.localizedDescription; showAlert = true }
        }
    }
}

// MARK: - Searchable Picker Sheet
struct SearchablePickerSheet: View {
    let title: String
    let items: [String]
    @Binding var searchText: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    private let primary = BrandColors.darkTeal

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search...", text: $searchText)
                            .font(.system(size: 16, design: .rounded))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                    .padding(.horizontal, 16).padding(.vertical, 12)

                    if items.isEmpty {
                        Spacer()
                        Text("No results found")
                            .foregroundColor(.secondary)
                            .font(.system(size: 15, design: .rounded))
                        Spacer()
                    } else {
                        List(items, id: \.self) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                Text(item)
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .listRowBackground(BrandColors.backgroundGradientEnd)
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { searchText = ""; dismiss() }
                        .foregroundColor(primary)
                }
            }
        }
    }
}
