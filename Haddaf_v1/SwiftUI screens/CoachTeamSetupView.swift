import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore
import UIKit

struct CoachTeamSetupView: View {
    // Passed from SignUpView
    let hasTeam: Bool
    
    @Environment(\.dismiss) private var dismiss
    
    
    // MARK: - Fields
    @State private var teamName: String = ""
    
    // MARK: - Team Logo Picture
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var teamLogoImage: Image?
    @State private var fileExt: String = "jpg"
    @State private var downloadURL: URL? // The URL after successful upload
    
    // MARK: - Upload & flow state
    @State private var isUploading = false // Tracks if photo upload is in progress
    @State private var showAlert = false
    @State private var alertMsg = ""
    @State private var goToDiscovery = false // Navigation trigger
    
    // MARK: - Theme
    private let primary = BrandColors.darkTeal
    private let bg = BrandColors.backgroundGradientEnd
    
    // MARK: - Validation
    private let maxTeamNameLength = 30
    private let teamNameRegex = "^[A-Za-z ]+$"

    private var isTeamNameLengthValid: Bool {
        teamName.count <= maxTeamNameLength
    }
    
    private var isTeamNameCharactersValid: Bool {
        teamName.allSatisfy { char in
            char.isLetter || char == " "
        }
    }

    private var isTeamNameValid: Bool {
        let trimmed = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty &&
               isTeamNameLengthValid &&
               isTeamNameCharactersValid
    }
    
    /// Determines if the "Done" button should be enabled.
    private var canSubmit: Bool {
        // 1. Team name is mandatory.
        guard isTeamNameValid else { return false }
        
        // 2. If an image was selected, ensure upload is complete.
        if selectedImageData != nil {
            return !isUploading && downloadURL != nil
        } else {
            // 3. If no image was selected, we just need to ensure no upload is in progress.
            return !isUploading
        }
    }
    
    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Set up your team")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                    
                    // Team Logo
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        VStack(spacing: 8) {
                            ZStack(alignment: .bottomTrailing) {
                                if let image = teamLogoImage {
                                    image.resizable().scaledToFill()
                                        .frame(width: 110, height: 110)
                                        .clipShape(Circle())
                                } else {
                                    // Default logo placeholder
                                    Image(systemName: "shield.lefthalf.filled")
                                        .resizable().scaledToFit()
                                        .frame(width: 60, height: 60)
                                        .foregroundColor(primary.opacity(0.7))
                                        .frame(width: 110, height: 110)
                                        .background(Color.gray.opacity(0.1))
                                        .clipShape(Circle())
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
                            Text("Team Logo (Optional)")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(primary.opacity(0.75))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                    
                    // ========= Team Name =========
                    fieldLabel("Team Name", required: true)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Enter team name", text: $teamName)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(primary)
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(BrandColors.background)
                                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                            ).onChange(of: teamName) { _, newValue in
                                // Allow only letters (Arabic + English) and spaces
                                var filtered = newValue.filter { $0.isLetter || $0 == " " }
                                
                                // Enforce max length
                                if filtered.count > maxTeamNameLength {
                                    filtered = String(filtered.prefix(maxTeamNameLength))
                                }

                                // Apply correction only if needed
                                if filtered != teamName {
                                    teamName = filtered
                                }
                            }
                        HStack {
                            if !teamName.isEmpty && !isTeamNameCharactersValid {
                                Text("Only letters and spaces are allowed.")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.red)
                            } else if !teamName.isEmpty && !isTeamNameLengthValid {
                                Text("Team name must be 30 characters or less.")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.red)
                            }

                            Spacer()

                            Text("\(teamName.count)/\(maxTeamNameLength)")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(teamName.count == maxTeamNameLength ? .red : .gray)
                        }
                    }
                    
                    // ========= Done =========
                    Button {
                        Task {
                            do {
                                try await saveTeamSetupData()
                                NotificationCenter.default.post(
                                    name: .userSignedIn,
                                    object: nil,
                                    userInfo: [
                                        "role": "coach",
                                        "hasTeam": hasTeam
                                    ]
                                )
                                goToDiscovery = true
                            } catch {
                                alertMsg = error.localizedDescription
                                showAlert = true
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text("Done")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                            if isUploading { ProgressView().colorInvert().scaleEffect(0.9) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .background(canSubmit ? primary : primary.opacity(0.5))
                    .clipShape(Capsule())
                    .shadow(color: canSubmit ? primary.opacity(0.3) : .clear, radius: 10, y: 5)
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
            teamLogoImage = nil
            downloadURL = nil
            isUploading = false
            alertMsg = ""
            Task {
                guard let item = newItem else { return }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    selectedImageData = data
                    fileExt = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    if let uiImage = UIImage(data: data) {
                        teamLogoImage = Image(uiImage: uiImage)
                    }
                    do {
                        try await uploadTeamLogo()
                    } catch {
                        alertMsg = "Logo upload failed: \(error.localizedDescription)"
                        showAlert = true
                        selectedImageData = nil
                        teamLogoImage = nil
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
            if let u = Auth.auth().currentUser {
                try? await u.reload()
                _ = try? await u.getIDTokenResult(forcingRefresh: true)
            }
        }
        .navigationDestination(isPresented: $goToDiscovery) {
            PlayerProfileView()
        }
        .navigationBarBackButtonHidden(true)
        .alert("Notice", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMsg) }
    }
    
    // MARK: - Upload Team Logo
    private func uploadTeamLogo() async throws {
        if let u = Auth.auth().currentUser {
            try? await u.reload()
            _ = try? await u.getIDTokenResult(forcingRefresh: true)
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        guard let data = selectedImageData else {
            print("Upload attempt with no image data.")
            return
        }
        isUploading = true
        
        let filename = "\(UUID().uuidString).\(fileExt)"
        // Builds the Storage path structure: teams/{coach_uid}/logo/{filename}
        let storageRef = Storage.storage().reference()
            .child("teams")
            .child(uid)
            .child("logo")
            .child(filename)
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/\(fileExt == "jpg" ? "jpeg" : fileExt)"
        
        do {
            _ = try await storageRef.putDataAsync(data, metadata: metadata)
            let url = try await storageRef.downloadURL()
            
            await MainActor.run {
                self.downloadURL = url
                self.isUploading = false
            }
            
        } catch {
            await MainActor.run {
                isUploading = false
                downloadURL = nil
            }
            print("Error uploading photo or getting URL: \(error)")
            throw error
        }
    }
    
    // MARK: - Save Team Setup Data
    private func saveTeamSetupData() async throws {
        if let u = Auth.auth().currentUser {
            try? await u.reload()
            _ = try? await u.getIDTokenResult(forcingRefresh: true)
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 0, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        let db = Firestore.firestore()
        
        var teamPayload: [String: Any] = [
            "coachUid": uid,
            "teamName": teamName,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        if let logoURL = downloadURL?.absoluteString {
            teamPayload["logoURL"] = logoURL
        }
        
        // 1. Create a new document in the 'teams' collection with the coach's UID as the ID
        try await db.collection("teams").document(uid).setData(teamPayload, merge: true)
        
        // 2. Update the coach's user document to link the team
        try await db.collection("users").document(uid).setData([
            "teamId": uid, // teamId is the coach's UID
            "teamName": teamName,
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
}
