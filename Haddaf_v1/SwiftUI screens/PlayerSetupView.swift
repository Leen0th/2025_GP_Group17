import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore
import UIKit

struct PlayerSetupView: View {
    // MARK: - Model (حقول هذه الشاشة فقط)
    @State private var position: String = ""
    @State private var weight: String = ""
    @State private var height: String = ""
    @State private var location: String = ""

    // MARK: - Position list (wheel)
    @State private var showPositionPicker = false
    private let positions = ["Attacker", "Midfielder", "Defender"]

    // MARK: - Profile Picture
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var profileImage: Image?
    @State private var fileExt: String = "jpg"
    @State private var downloadURL: URL?    // يصير له قيمة بعد اكتمال رفع الصورة

    // MARK: - حالة الرفع (صامت)
    @State private var isUploading = false
    @State private var showAlert = false
    @State private var alertMsg = ""
    @State private var goToProfile = false

    // MARK: - Theme
    private let primary = Color(hexV: "#36796C")
    private let bg = Color(hexV: "#EFF5EC")

    // لازم كل الحقول تتعبّى
    private var fieldsFilled: Bool {
        !position.isEmpty && !weight.isEmpty && !height.isEmpty && !location.isEmpty
    }

    // زر Done يتفعّل فقط إذا: كل الحقول متعبّاة + (لو اليوزر اختار صورة لازم يكون رفعها خلص)
    private var canSubmit: Bool {
        guard fieldsFilled else { return false }
        if selectedImageData != nil {
            // إذا اختار صورة، ما نسمح إلا بعد اكتمال الرفع ووجود رابط
            return !isUploading && downloadURL != nil
        } else {
            // ما اختار صورة -> يكفي تعبئة الحقول
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

                    // صورة البروفايل (رفع صامت بمجرد الاختيار)
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

                    // Position (زر يفتح Wheel Sheet)
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

                    // Weight
                    fieldLabel("Weight")
                    roundedField {
                        TextField("", text: $weight)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                    }

                    // Height
                    fieldLabel("Height")
                    roundedField {
                        TextField("", text: $height)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                    }

                    // Location
                    fieldLabel("Location")
                    roundedField {
                        TextField("", text: $location)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                    }

                    // Done
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
        // بمجرد اختيار صورة: اعرض المعاينة ثم ارفعها بصمت
        .onChange(of: selectedItem) { newItem in
            Task {
                guard let item = newItem else { return }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    selectedImageData = data
                    fileExt = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    if let ui = UIImage(data: data) { profileImage = Image(uiImage: ui) }
                    // ارفع مباشرة بدون ما نبيّن أي مؤشر للمستخدم
                    do { try await uploadProfilePhoto() }
                    catch {
                        alertMsg = error.localizedDescription
                        showAlert = true
                    }
                }
            }
        }
        // الانتقال لصفحة البروفايل
        .navigationDestination(isPresented: $goToProfile) {
            PlayerProfileView()
        }
        .alert("Notice", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMsg) }
    }

    // MARK: - رفع الصورة (صامت) وتحديث users/{uid}.profilePic
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

    // MARK: - تخزين بيانات السيت أب فقط
    private func savePlayerSetupData() async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "No user id"])
        }

        let db = Firestore.firestore()
        let profileRef = db.collection("users")
            .document(uid)
            .collection("player")
            .document("profile")

        let weightInt = Int(weight.filter { "0123456789".contains($0) })
        let heightInt = Int(height.filter { "0123456789".contains($0) })

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

    private func roundedField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
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

// MARK: - Color hex init
extension Color {
    init(hexV: String) {
        let hexV = hexV.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexV).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexV.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}
