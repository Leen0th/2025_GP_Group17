import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore

// MARK: - Create Team Sheet
struct CreateTeamSheet: View {
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var teamName = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var teamLogoImage: Image?
    @State private var fileExt = "jpg"
    @State private var downloadURL: URL?
    @State private var isUploading = false
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMsg = ""

    private let maxTeamNameLength = 30
    private let primary = BrandColors.darkTeal

    private var isTeamNameValid: Bool {
        let trimmed = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxTeamNameLength
            && trimmed.allSatisfy { $0.isLetter || $0 == " " }
    }

    private var canSubmit: Bool {
        guard isTeamNameValid else { return false }
        if selectedImageData != nil { return !isUploading && !isSaving && downloadURL != nil }
        return !isUploading && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
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
                                        .overlay(Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundColor(.white))
                                        .shadow(color: primary.opacity(0.3), radius: 8, y: 4)
                                }
                                Text("Team Logo (Optional)")
                                    .font(.system(size: 14, design: .rounded)).foregroundColor(primary.opacity(0.75))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 6)

                        // Team Name
                        Text("Team Name *")
                            .font(.system(size: 14, design: .rounded)).foregroundColor(.gray)
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Enter team name", text: $teamName)
                                .font(.system(size: 16, design: .rounded)).foregroundColor(primary)
                                .textInputAutocapitalization(.words)
                                .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background)
                                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1)))
                                .onChange(of: teamName) { _, val in
                                    var f = val.filter { $0.isLetter || $0 == " " }
                                    if f.count > maxTeamNameLength { f = String(f.prefix(maxTeamNameLength)) }
                                    if f != teamName { teamName = f }
                                }
                            HStack {
                                Spacer()
                                Text("\(teamName.count)/\(maxTeamNameLength)")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundColor(teamName.count == maxTeamNameLength ? .red : .gray)
                            }
                        }

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
                        .background(canSubmit ? primary : primary.opacity(0.5))
                        .clipShape(Capsule())
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.5)
                        .padding(.top)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 24)
                }
            }
            .navigationTitle("Create Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(primary)
                }
            }
            .alert("Notice", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: { Text(alertMsg) }
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

    private func uploadLogo() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let data = selectedImageData else { return }
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
            "teamName": teamName.trimmingCharacters(in: .whitespacesAndNewlines),
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let logo = downloadURL?.absoluteString { payload["logoURL"] = logo }

        do {
            try await db.collection("teams").document(uid).setData(payload, merge: true)
            try await db.collection("users").document(uid).setData([
                "teamId": uid,
                "teamName": teamName.trimmingCharacters(in: .whitespacesAndNewlines),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            await MainActor.run { isSaving = false; onCreated() }
        } catch {
            await MainActor.run { isSaving = false; alertMsg = error.localizedDescription; showAlert = true }
        }
    }
}
