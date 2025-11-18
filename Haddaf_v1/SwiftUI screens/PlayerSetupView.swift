import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore
import UIKit

struct PlayerSetupView: View {

    // MARK: - Fields (this screen only)
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
    @State private var downloadURL: URL? // The URL after successful upload

    // MARK: - Upload & flow state
    @State private var isUploading = false // Tracks if photo upload is in progress
    @State private var showAlert = false
    @State private var alertMsg = ""
    @State private var goToProfile = false // Navigation trigger

    // MARK: - Theme
    // MODIFIED:new BrandColors
    private let primary = BrandColors.darkTeal
    private let bg = BrandColors.backgroundGradientEnd

    // MARK: - Validation (realistic ranges)
    private var weightInt: Int? { Int(weight) }
    private var heightInt: Int? { Int(height) }

    private var isWeightValid: Bool {
        guard let w = weightInt else { return false }
        return (15...200).contains(w)
    }
    private var isHeightValid: Bool {
        guard let h = heightInt else { return false }
        return (100...230).contains(h)
    }

    /// Checks if all mandatory fields have valid input.
    private var allFieldsValidAndFilled: Bool {
        !position.isEmpty &&
        !location.isEmpty &&
        isWeightValid &&
        isHeightValid
    }

    /// Determines if the "Done" button should be enabled.
    private var canSubmit: Bool {
        // 1. All fields must be validly filled.
        guard allFieldsValidAndFilled else { return false }

        // 2. If an image was selected...
        if selectedImageData != nil {
            // ... the upload must NOT be in progress AND we must have received the download URL.
            return !isUploading && downloadURL != nil
        } else {
            // 3. If no image was selected, we just need to ensure no upload is (erroneously) in progress.
            return !isUploading
        }
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Set up your profile")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

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
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                            Circle().fill(primary)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                )
                                .shadow(color: primary.opacity(0.3), radius: 8, y: 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)

                    // ========= Position =========
                    fieldLabel("Position", required: true)
                    buttonLikeField(action: {
                        showPositionPicker = true
                    }) {
                        HStack {
                            Text(position.isEmpty ? "Select position" : position)
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(position.isEmpty ? .gray : primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(primary.opacity(0.85))
                        }
                    }
                    .sheet(isPresented: $showPositionPicker) {
                        PositionWheelPickerSheet(
                            positions: positions,
                            selection: $position,
                            showSheet: $showPositionPicker
                        )
                        .presentationDetents([.height(300)])
                        .presentationBackground(BrandColors.background)
                        .presentationCornerRadius(28)
                    }

                    // ========= Weight =========
                    fieldLabel("Weight (kg)", required: true)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Enter weight", text: $weight)
                            .keyboardType(.numberPad)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(primary)
                            .onChange(of: weight) { _, new in
                                let filtered = new.filter(\.isNumber)
                                weight = String(filtered.prefix(3))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(BrandColors.background)
                                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(!weight.isEmpty && !isWeightValid ? Color.red : Color.clear, lineWidth: 1)
                            )

                        if !weight.isEmpty && !isWeightValid {
                            Text("Enter a realistic weight between 15–200 kg.")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.red)
                        }
                    }

                    // ========= Height =========
                    fieldLabel("Height (cm)", required: true)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Enter height", text: $height)
                            .keyboardType(.numberPad)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(primary)
                            .onChange(of: height) { _, new in
                                let filtered = new.filter(\.isNumber)
                                height = String(filtered.prefix(3))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(BrandColors.background)
                                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(!height.isEmpty && !isHeightValid ? Color.red : Color.clear, lineWidth: 1)
                            )

                        if !height.isEmpty && !isHeightValid {
                            Text("Enter a realistic height between 100–230 cm.")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.red)
                        }
                    }

                    // ========= City =========
                    fieldLabel("City of Residence", required: true)
                    buttonLikeField(action: {
                        locationSearch = ""
                        showLocationPicker = true
                    }) {
                        HStack {
                            Text(location.isEmpty ? "Select city" : location)
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(location.isEmpty ? .gray : primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(primary.opacity(0.85))
                        }
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
                        .presentationBackground(BrandColors.background)
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
                        HStack {
                            Text("Done")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(primary)
                        .clipShape(Capsule())
                        .shadow(color: primary.opacity(0.3), radius: 10, y: 5)
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.5)
                    .padding(.top)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            selectedImageData = nil
            profileImage = nil
            downloadURL = nil
            isUploading = false
            alertMsg = ""
            Task {
                guard let item = newItem else { return }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    selectedImageData = data
                    fileExt = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    if let uiImage = UIImage(data: data) {
                        profileImage = Image(uiImage: uiImage)
                    }
                    do {
                        try await uploadProfilePhoto()
                    } catch {
                        alertMsg = "Photo upload failed: \(error.localizedDescription)"
                        showAlert = true
                        selectedImageData = nil
                        profileImage = nil
                        downloadURL = nil
                        isUploading = false
                    }
                } else {
                    alertMsg = "Could not load image data."
                    showAlert = true
                }
            }
        }
        .task {
                   // 🔄 نحدّث الـ token بعد التفعيل أول ما تفتح الشاشة
                   if let u = Auth.auth().currentUser {
                       try? await u.reload()
                       _ = try? await u.getIDTokenResult(forcingRefresh: true)
                   }
               }
        .fullScreenCover(isPresented: $goToProfile) {
             PlayerProfileView()
        }
        .navigationBarBackButtonHidden(true)
        .alert("Notice", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMsg) }
    }

    // MARK: - Upload profile photo
    private func uploadProfilePhoto() async throws {
            if let u = Auth.auth().currentUser {
                try? await u.reload()
                _ = try? await u.getIDTokenResult(forcingRefresh: true)
            }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        guard let data = selectedImageData else {
            // This case should ideally not happen if called correctly
            print("Upload attempt with no image data.")
            return
        }

        isUploading = true // Start uploading state
        // Creates a unique file name.
        let filename = "\(UUID().uuidString).\(fileExt)"
        // Builds the Storage path structure.
        let storageRef = Storage.storage().reference()
            .child("profile")
            .child(uid)
            .child(filename)

        let metadata = StorageMetadata()
        metadata.contentType = "image/\(fileExt == "jpg" ? "jpeg" : fileExt)"

        do {
            // Perform the upload
            _ = try await storageRef.putDataAsync(data, metadata: metadata)
            // Get the download URL upon successful upload
            let url = try await storageRef.downloadURL()
            
            // Update the state on the main thread
            await MainActor.run {
                self.downloadURL = url
                self.isUploading = false // Finish uploading state
            }
            
            // Save the URL To Firestore
            try await Firestore.firestore().collection("users").document(uid)
                .setData(["profilePic": url.absoluteString], merge: true)
            
        } catch {
            await MainActor.run {
                isUploading = false
                downloadURL = nil
            }
            print("Error uploading photo or getting URL: \(error)")
            throw error
        }
    }

    // MARK: - Save Player Setup Data
    private func savePlayerSetupData() async throws {
          if let u = Auth.auth().currentUser {
              // Reload the user object to ensure we have the latest server-side auth state.
              try? await u.reload()
              // Force-refresh the ID token so any recent auth changes are applied to the session.
              _ = try? await u.getIDTokenResult(forcingRefresh: true)
          }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        let db = Firestore.firestore()

        var payload: [String: Any] = [
            "position": position,
            "weight": weightInt ?? NSNull(),
            "height": heightInt ?? NSNull(),
            "location": location,
            "isPhoneNumberVisible": false,
            "isEmailVisible": false,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        let profileRef = db.collection("users")
            .document(uid)
            .collection("player")
            .document("profile")
            
        try await profileRef.setData(payload, merge: true)
        
        try await db.collection("users").document(uid).setData([
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    // MARK: - UI Helpers
    private func fieldLabel(_ title: String, required: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.gray)
            if required {
                Text("*")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.red)
            }
        }
    }

    private func buttonLikeField<Content: View>(
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(BrandColors.background)
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                )
        }
    }
}
