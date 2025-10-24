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
    // MODIFIED: Uses the Color(hex:) extension from AppModels.swift
    private let primary = Color(hex: "#36796C")
    private let bg = Color(hex: "#EFF5EC")

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

    // --- MODIFIED: Renamed to clearly indicate validation ---
    /// Checks if all mandatory fields have valid input.
    private var allFieldsValidAndFilled: Bool {
        !position.isEmpty &&
        !location.isEmpty &&
        isWeightValid && // Implicitly checks if not empty via Int conversion
        isHeightValid // Implicitly checks if not empty via Int conversion
    }

    // --- MODIFIED: Updated logic for clarity ---
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
                                Image("profile_placeholder") // Make sure this image exists in your assets
                                    .resizable().scaledToFill()
                                    .frame(width: 110, height: 110)
                                    .clipShape(Circle())
                                    .foregroundColor(.gray.opacity(0.5)) // Added fallback color
                            }
                            // Small plus icon overlay
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

                    // ========= Position (Mandatory) =========
                    // --- MODIFIED: Added required: true ---
                    fieldLabel("Position", required: true)
                    buttonLikeField(action: {
                        showPositionPicker = true
                    }) {
                        HStack {
                            Text(position.isEmpty ? "Select position" : position)
                                .font(.custom("Poppins", size: 16))
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
                        .presentationBackground(.white)
                        .presentationCornerRadius(28)
                    }

                    // ========= Weight (Mandatory & Validated) =========
                    // --- MODIFIED: Added required: true ---
                    fieldLabel("Weight (kg)", required: true)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Enter weight", text: $weight) // Added placeholder
                            .keyboardType(.numberPad)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .onChange(of: weight) { _, new in // Use new syntax
                                let filtered = new.filter(\.isNumber)
                                // Allow up to 3 digits for weight
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
                            .overlay( // Show red border if invalid and not empty
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(!weight.isEmpty && !isWeightValid ? Color.red : Color.clear, lineWidth: 1)
                            )

                        // Validation message
                        if !weight.isEmpty && !isWeightValid {
                            Text("Enter a realistic weight between 15–200 kg.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    // ========= Height (Mandatory & Validated) =========
                    // --- MODIFIED: Added required: true ---
                    fieldLabel("Height (cm)", required: true)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Enter height", text: $height) // Added placeholder
                            .keyboardType(.numberPad)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .onChange(of: height) { _, new in // Use new syntax
                                let filtered = new.filter(\.isNumber)
                                // Allow up to 3 digits for height
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
                            .overlay( // Show red border if invalid and not empty
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(!height.isEmpty && !isHeightValid ? Color.red : Color.clear, lineWidth: 1)
                            )

                        // Validation message
                        if !height.isEmpty && !isHeightValid {
                            Text("Enter a realistic height between 100–230 cm.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    // ========= Residence (Mandatory) =========
                    // --- MODIFIED: Added required: true ---
                    fieldLabel("Residence", required: true)
                    buttonLikeField(action: {
                        locationSearch = ""
                        showLocationPicker = true
                    }) {
                        HStack {
                            Text(location.isEmpty ? "Select city" : location)
                                .font(.custom("Poppins", size: 16))
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
                        .presentationBackground(.white)
                        .presentationCornerRadius(28)
                    }

                    // ========= Done Button (Activation logic handled by canSubmit) =========
                    Button {
                        Task {
                            // No need to re-check canSubmit here, disabled state handles it
                            do {
                                try await savePlayerSetupData()
                                goToProfile = true // Trigger navigation on success
                            } catch {
                                alertMsg = error.localizedDescription
                                showAlert = true
                            }
                        }
                    } label: {
                        HStack { // Added HStack for potential spinner
                            Text("Done")
                                .font(.custom("Poppins", size: 18))
                                .foregroundColor(.white)
                            // Optional: Add ProgressView if needed during save operation
                            // if isSaving { ProgressView().colorInvert().scaleEffect(0.8) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(primary)
                        .clipShape(Capsule())
                    }
                    .disabled(!canSubmit) // Button is disabled if canSubmit is false
                    .opacity(canSubmit ? 1 : 0.5) // Visual cue for disabled state
                    .padding(.top) // Add some space before the button

                    Spacer(minLength: 24) // Ensure content pushes button up if needed
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .onChange(of: selectedItem) { _, newItem in // Use new syntax
            // Reset upload state when a new item is picked
            selectedImageData = nil
            profileImage = nil
            downloadURL = nil
            isUploading = false
            alertMsg = ""
            
            Task {
                guard let item = newItem else { return }
                
                // Load image data
                if let data = try? await item.loadTransferable(type: Data.self) {
                    selectedImageData = data
                    // Try to determine file extension
                    fileExt = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    // Display the selected image immediately
                    if let uiImage = UIImage(data: data) {
                        profileImage = Image(uiImage: uiImage)
                    }
                    
                    // Start the upload automatically
                    do {
                        try await uploadProfilePhoto()
                        // Upload successful, downloadURL is set
                    } catch {
                        // Handle upload error
                        alertMsg = "Photo upload failed: \(error.localizedDescription)"
                        showAlert = true
                        // Clear image data so user isn't stuck waiting for a failed upload
                        selectedImageData = nil
                        profileImage = nil
                        downloadURL = nil
                        isUploading = false // Ensure uploading state is reset
                    }
                } else {
                    // Handle error loading data from PhotosPickerItem
                    alertMsg = "Could not load image data."
                    showAlert = true
                }
            }
        }
        .fullScreenCover(isPresented: $goToProfile) {
            // Navigate to the main profile view (ensure PlayerProfileView exists)
             PlayerProfileView() // Assuming this is your destination view
        }
        .navigationBarBackButtonHidden(true)
        .alert("Notice", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMsg) }
    }

    // MARK: - Upload profile photo
    private func uploadProfilePhoto() async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        guard let data = selectedImageData else {
            // This case should ideally not happen if called correctly
             print("Upload attempt with no image data.")
            return
        }

        isUploading = true // Start uploading state

        let filename = "\(UUID().uuidString).\(fileExt)"
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
            
            // Save the URL to Firestore (optional here, could be done in savePlayerSetupData)
             try await Firestore.firestore().collection("users").document(uid)
                 .setData(["profilePic": url.absoluteString], merge: true)
            
        } catch {
            // Handle errors during upload or URL retrieval
             await MainActor.run {
                 isUploading = false // Finish uploading state on error
                 downloadURL = nil // Ensure URL is nil on error
             }
            print("Error uploading photo or getting URL: \(error)")
            throw error // Re-throw the error to be caught by the caller
        }
    }

    // MARK: - Save Player Setup Data
    private func savePlayerSetupData() async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        // No need to check canSubmit here, button state handles it

        let db = Firestore.firestore()

        // --- Prepare Payload ---
        var payload: [String: Any] = [
            "position": position,
            "weight": weightInt ?? NSNull(), // Use NSNull for optional Ints
            "height": heightInt ?? NSNull(), // Use NSNull for optional Ints
            "location": location,
            "contactVisibility": false, // Default value
            "isEmailVisible": false,   // Default value
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        // --- Save to Sub-collection ---
        let profileRef = db.collection("users")
            .document(uid)
            .collection("player")
            .document("profile")
            
        try await profileRef.setData(payload, merge: true) // Use merge to avoid overwriting other fields if they exist
        
        // --- Update Main User Doc Timestamp (Optional but good practice) ---
         try await db.collection("users").document(uid).setData([
             "updatedAt": FieldValue.serverTimestamp()
             // Ensure profilePic is already saved if upload happened
         ], merge: true)
    }

    // MARK: - UI Helpers

    // --- MODIFIED: Added required parameter ---
    /// Creates a standard field label with an optional red asterisk for mandatory fields.
    private func fieldLabel(_ title: String, required: Bool = false) -> some View {
        HStack(spacing: 2) { // Reduced spacing
            Text(title)
                .font(.custom("Poppins", size: 14))
                .foregroundColor(.gray)
            if required {
                Text("*")
                    .font(.custom("Poppins", size: 14)) // Match size
                    .fontWeight(.bold) // Make star bold
                    .foregroundColor(.red)
            }
        }
    }

    /// Creates a button styled like a text field.
    private func buttonLikeField<Content: View>(
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading) // Ensure text aligns left
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white)
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                )
        }
    }
}
