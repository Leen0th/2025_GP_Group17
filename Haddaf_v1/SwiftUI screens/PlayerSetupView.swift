import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore
import UIKit

struct PlayerSetupView: View {

    // MARK: - Fields (this screen only)
    @State private var phone: String = ""           // phone goes here (no OTP)
    @State private var position: String = ""
    @State private var weight: String = ""
    @State private var height: String = ""
    @State private var location: String = ""

    // MARK: - Position list (wheel)
    @State private var showPositionPicker = false
    private let positions = ["Attacker", "Midfielder", "Defender"]

    // MARK: - Location (dropdown with search)
    @State private var showLocationPicker = false
    @State private var locationSearch = ""

    // MARK: - Profile Picture
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var profileImage: Image?
    @State private var fileExt: String = "jpg"
    @State private var downloadURL: URL?    // gets a value after upload completes

    // MARK: - Upload & flow state
    @State private var isUploading = false
    @State private var showAlert = false
    @State private var alertMsg = ""
    @State private var goToProfile = false

    // MARK: - Theme
    private let primary = Color(hexV: "#36796C")
    private let bg = Color(hexV: "#EFF5EC")

    // MARK: - Validation (realistic ranges)
    private var weightInt: Int? { Int(weight) }
    private var heightInt: Int? { Int(height) }

    private var isWeightValid: Bool {
        guard let w = weightInt else { return false }
        return (15...200).contains(w)   // ✅ الآن يبدأ من 15
    }
    private var isHeightValid: Bool {
        guard let h = heightInt else { return false }
        return (100...230).contains(h)
    }
    private var isPhoneValid: Bool {
        !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var fieldsFilled: Bool {
        isPhoneValid &&
        !position.isEmpty &&
        !location.isEmpty &&
        isWeightValid &&
        isHeightValid
    }
    private var canSubmit: Bool {
        guard fieldsFilled else { return false }
        if selectedImageData != nil {
            return !isUploading && downloadURL != nil
        } else {
            return !isUploading
        }
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    Text("Set up your profile")
                        .font(.custom("Poppins", size: 28))
                        .fontWeight(.medium)
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    // Profile photo (silent upload once selected)
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            if let image = profileImage {
                                image.resizable().scaledToFill()
                                    .frame(width: 110, height: 110)
                                    .clipShape(Circle())
                            } else {
                                Image("profile_placeholder")
                                    .resizable().scaledToFill()
                                    .frame(width: 110, height: 110)
                                    .clipShape(Circle())
                            }
                            Circle().fill(primary)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)

                    // ========= Phone (before Position) =========
                    fieldLabel("Phone Number")
                    // 👇 صندوق فارغ بدون Placeholder
                    TextField("", text: $phone)
                        .keyboardType(.phonePad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.custom("Poppins", size: 16))
                        .foregroundColor(primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.white)
                                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                        )

                    // ========= Position =========
                    fieldLabel("Position")
                    buttonLikeField {
                        HStack {
                            Text(position.isEmpty ? "Select position" : position)
                                .font(.custom("Poppins", size: 16))
                                .foregroundColor(position.isEmpty ? .gray : primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(primary.opacity(0.85))
                        }
                    } onTap: {
                        showPositionPicker = true
                    }
                    .sheet(isPresented: $showPositionPicker) {
                        PositionWheelPickerSheet(
                            positions: positions,
                            selection: $position,
                            showSheet: $showPositionPicker
                        )
                        .presentationDetents([.height(300)])
                        .presentationBackground(.white)
                        .presentationCornerRadius(28)
                    }

                    // ========= Weight (validated) =========
                    fieldLabel("Weight (kg)")
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("", text: $weight)
                            .keyboardType(.numberPad)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .onChange(of: weight) { new in
                                // keep digits only, max 3
                                let filtered = new.filter(\.isNumber)
                                weight = String(filtered.prefix(3))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.white)
                                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(isWeightValid || weight.isEmpty ? Color.clear : .red, lineWidth: 1)
                            )

                        if !weight.isEmpty && !isWeightValid {
                            Text("Enter a realistic weight between 15–200 kg.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    // ========= Height (validated) =========
                    fieldLabel("Height (cm)")
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("", text: $height)
                            .keyboardType(.numberPad)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .onChange(of: height) { new in
                                // keep digits only, max 3
                                let filtered = new.filter(\.isNumber)
                                height = String(filtered.prefix(3))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.white)
                                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(isHeightValid || height.isEmpty ? Color.clear : .red, lineWidth: 1)
                            )

                        if !height.isEmpty && !isHeightValid {
                            Text("Enter a realistic height between 100–230 cm.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    // ========= Location (dropdown with search) =========
                    fieldLabel("Location")
                    buttonLikeField {
                        HStack {
                            Text(location.isEmpty ? "Select city" : location)
                                .font(.custom("Poppins", size: 16))
                                .foregroundColor(location.isEmpty ? .gray : primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(primary.opacity(0.85))
                        }
                    } onTap: {
                        locationSearch = ""
                        showLocationPicker = true
                    }
                    .sheet(isPresented: $showLocationPicker) {
                        LocationPickerSheet(
                            title: "Select your city",
                            allCities: SAUDI_CITIES,
                            selection: $location,
                            searchText: $locationSearch,
                            showSheet: $showLocationPicker,
                            accent: primary
                        )
                        .presentationDetents([.large])
                        .presentationBackground(.white)
                        .presentationCornerRadius(28)
                    }

                    // ========= Done =========
                    Button {
                        Task {
                            do {
                                try await savePlayerSetupData()
                                goToProfile = true
                            } catch {
                                alertMsg = error.localizedDescription
                                showAlert = true
                            }
                        }
                    } label: {
                        Text("Done")
                            .font(.custom("Poppins", size: 18))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(primary)
                            .clipShape(Capsule())
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.5)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        // When an image gets picked: preview then upload silently
        .onChange(of: selectedItem) { newItem in
            Task {
                guard let item = newItem else { return }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    selectedImageData = data
                    fileExt = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    if let ui = UIImage(data: data) { profileImage = Image(uiImage: ui) }
                    do { try await uploadProfilePhoto() }
                    catch {
                        alertMsg = error.localizedDescription
                        showAlert = true
                    }
                }
            }
        }
        // Navigate to profile
        .navigationDestination(isPresented: $goToProfile) {
            PlayerProfileView()
        }
        .alert("Notice", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMsg) }
    }

    // MARK: - Upload profile photo (silent) + users/{uid}.profilePic
    private func uploadProfilePhoto() async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "No user id"])
        }
        guard let data = selectedImageData else {
            throw NSError(domain: "Upload", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "No image selected"])
        }

        isUploading = true
        defer { isUploading = false }

        let filename = "\(UUID().uuidString).\(fileExt)"
        let ref = Storage.storage().reference()
            .child("profile")
            .child(uid)
            .child(filename)

        let meta = StorageMetadata()
        meta.contentType = "image/\(fileExt == "jpg" ? "jpeg" : fileExt)"

        let task = ref.putData(data, metadata: meta) { _, _ in }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.observe(.success) { _ in continuation.resume() }
            task.observe(.failure) { snap in
                let err = snap.error ?? NSError(domain: "Upload", code: -1,
                                                userInfo: [NSLocalizedDescriptionKey: "Unknown upload error"])
                continuation.resume(throwing: err)
            }
        }

        let url = try await ref.downloadURL()
        self.downloadURL = url

        try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .setData(["profilePic": url.absoluteString], merge: true)
    }

    // MARK: - Save Player Setup
    private func savePlayerSetupData() async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "No user id"])
        }

        let db = Firestore.firestore()

        // Update root user doc with phone + timestamp
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        try await db.collection("users").document(uid).setData([
            "phone": trimmedPhone,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        // Player-specific data under users/{uid}/player/profile
        let profileRef = db.collection("users")
            .document(uid)
            .collection("player")
            .document("profile")

        let payload: [String: Any] = [
            "position": position,
            "weight": weightInt ?? NSNull(),
            "height": heightInt ?? NSNull(),
            "location": location,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await profileRef.setData(payload, merge: true)
    }

    // MARK: - UI Helpers
    private func fieldLabel(_ title: String) -> some View {
        Text(title).font(.custom("Poppins", size: 14)).foregroundColor(.gray)
    }

    private func buttonLikeField<Content: View>(
        @ViewBuilder content: () -> Content,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white)
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                )
        }
    }
}

// MARK: - Wheel sheet for Position
private struct PositionWheelPickerSheet: View {
    let positions: [String]
    @Binding var selection: String
    @Binding var showSheet: Bool
    @State private var tempSelection: String = ""
    private let primary = Color(hexV: "#36796C")

    var body: some View {
        VStack(spacing: 16) {
            Text("Select your position")
                .font(.custom("Poppins", size: 18))
                .foregroundColor(primary)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)

            Picker("", selection: $tempSelection) {
                ForEach(positions, id: \.self) { pos in
                    Text(pos).tag(pos)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 180)

            Button("Done") {
                selection = tempSelection
                showSheet = false
            }
            .font(.custom("Poppins", size: 18))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(primary)
            .clipShape(Capsule())
            .padding(.bottom, 16)
        }
        .onAppear { tempSelection = selection.isEmpty ? (positions.first ?? "") : selection }
        .padding(.horizontal, 20)
    }
}

// MARK: - Location Picker (dropdown with search)
private struct LocationPickerSheet: View {
    let title: String
    let allCities: [String]
    @Binding var selection: String
    @Binding var searchText: String
    @Binding var showSheet: Bool
    let accent: Color

    var filtered: [String] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return allCities }
        return allCities.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered, id: \.self) { city in
                    Button {
                        selection = city
                        showSheet = false
                    } label: {
                        HStack {
                            Text(city).foregroundColor(.black) // 👈 أسود بدل الأزرق
                            Spacer()
                            if city == selection {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain) // يمنع تلوين كنص رابط
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search city")
            .navigationTitle(Text(title))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSheet = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Saudi cities (English)
private let SAUDI_CITIES: [String] = [
    "Riyadh", "Jeddah", "Mecca", "Medina", "Dammam", "Khobar", "Dhahran", "Taif",
    "Tabuk", "Abha", "Khamis Mushait", "Jizan", "Najran", "Hail", "Buraydah", "Unaizah",
    "Al Hofuf", "Al Mubarraz", "Jubail", "Yanbu", "Rabigh", "Al Baha", "Bisha", "Al Majmaah",
    "Al Zulfi", "Sakaka", "Arar", "Qurayyat", "Rafha", "Turaif", "Tarut", "Qatif", "Safwa",
    "Saihat", "Al Khafji", "Al Ahsa", "Al Qassim", "Al Qaisumah", "Sharurah", "Tendaha",
    "Wadi ad-Dawasir", "Al Qurayyat", "Tayma", "Umluj", "Haql", "Al Wajh",
    "Al Lith", "Al Qunfudhah", "Sabya", "Abu Arish", "Samtah",
    "Baljurashi", "Al Mandaq", "Qilwah", "Al Namas", "Tanomah",
    "Mahd adh Dhahab", "Badr", "Al Ula", "Khaybar",
    "Al Bukayriyah", "Riyadh Al Khabra", "Al Rass",
    "Diriyah", "Al Kharj", "Hotat Bani Tamim", "Al Hariq", "Wadi Al Dawasir",
    "Afif", "Dawadmi", "Shaqra", "Thadig", "Muzahmiyah", "Rumah",
    "Ad Dilam", "Al Quwayiyah",
    "Duba", "Turaif", "Ar Ruwais", "Farasan", "Al Dayer", "Fifa", "Al Aridhah",
    "Al Bahah City", "King Abdullah Economic City", "Al Uyaynah", "Al Badayea",
    "Al Uwayqilah", "Bathaa", "Al Jafr", "Thuqbah", "Buqayq (Abqaiq)", "Ain Dar",
    "Nairyah", "Al Hassa", "Salwa", "Ras Tanura", "Khafji", "Manfouha", "Al Muzahmiyah"
].sorted()

// MARK: - Color hex init
extension Color {
    init(hexV: String) {
        let s = hexV.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: s).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch s.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17,
                                (int >> 4 & 0xF) * 17,
                                (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16,
                                int >> 8 & 0xFF,
                                int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24,
                                int >> 16 & 0xFF,
                                int >> 8 & 0xFF,
                                int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}
