import SwiftUI
import FirebaseAuth
import FirebaseFirestore

enum UserRole: String { case player = "Player", coach = "Coach" }

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss

    // Colors
    private let primary = Color(hexv: "#36796C")
    private let bg = Color(hexv: "#EFF5EC")

    // Role
    @State private var role: UserRole = .player

    // Fields
    @State private var fullName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var isHidden = true

    // DOB
    @State private var dob: Date? = nil
    @State private var showDOBPicker = false
    @State private var tempDOB = Date()

    // Nav
    @State private var goToPlayerSetup = false

    // UX
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMsg = ""

    // Validation
    private var isFormValid: Bool {
        let nameOK = !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let emailOK = !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let phoneOK = !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let passOK  = password.count >= 6
        let dobOK   = dob != nil
        return nameOK && emailOK && phoneOK && passOK && dobOK
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Title
                    Text("Sign Up")
                        .font(.custom("Poppins", size: 34))
                        .fontWeight(.medium)
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    // Role
                    HStack(spacing: 28) {
                        rolePill(.player); rolePill(.coach)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    // Full name
                    fieldLabel("Full Name")
                    roundedField {
                        TextField("", text: $fullName)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                    }

                    // Email
                    fieldLabel("Email")
                    roundedField {
                        TextField("", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                    }

                    // DOB
                    fieldLabel("Date of birth")
                    buttonLikeField(action: {
                        tempDOB = dob ?? Date()
                        showDOBPicker = true
                    }) {
                        HStack {
                            Text(dob.map { formatDate($0) } ?? "Select date")
                                .font(.custom("Poppins", size: 16))
                                .foregroundColor(dob == nil ? .gray : primary)
                            Spacer()
                            Image(systemName: "calendar")
                                .foregroundColor(primary.opacity(0.85))
                        }
                    }
                    .sheet(isPresented: $showDOBPicker) {
                        DateWheelPickerSheet(
                            selection: $dob,
                            tempSelection: $tempDOB,
                            showSheet: $showDOBPicker
                        )
                        .presentationDetents([.height(300)])
                        .presentationBackground(.white)
                        .presentationCornerRadius(28)
                    }

                    // Phone
                    fieldLabel("Phone Number")
                    roundedField {
                        TextField("", text: $phone)
                            .keyboardType(.phonePad)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                    }

                    // Password
                    fieldLabel("Password")
                    roundedField {
                        ZStack(alignment: .trailing) {
                            if isHidden {
                                SecureField("", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .font(.custom("Poppins", size: 16))
                                    .foregroundColor(primary)
                                    .tint(primary)
                                    .textContentType(.password)
                                    .padding(.trailing, 44)
                            } else {
                                TextField("", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .font(.custom("Poppins", size: 16))
                                    .foregroundColor(primary)
                                    .tint(primary)
                                    .textContentType(.password)
                                    .padding(.trailing, 44)
                            }

                            Button { withAnimation { isHidden.toggle() } } label: {
                                Image(systemName: isHidden ? "eye.slash" : "eye")
                                    .foregroundColor(.gray)
                            }
                        }
                    }

                    // Sign Up
                    Button {
                        Task { await handleSignUp() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView().tint(.white) }
                            Text("Sign Up")
                        }
                        .font(.custom("Poppins", size: 18))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(primary)
                        .clipShape(Capsule())
                    }
                    .padding(.top, 8)
                    .disabled(!isFormValid || isLoading)
                    .opacity(isFormValid ? 1.0 : 0.5)

                    // Footer
                    HStack(spacing: 6) {
                        Text("Already have an account?")
                            .font(.custom("Poppins", size: 15))
                            .foregroundColor(.gray)
                        NavigationLink { /* SignInView() */ } label: {
                            Text("Sign in")
                                .font(.custom("Poppins", size: 15))
                                .fontWeight(.semibold)
                                .foregroundColor(primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(primary)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $goToPlayerSetup) {
            PlayerSetupView() // انتقلي لإعداد الملف الشخصي
        }
        .alert("Error", isPresented: $showAlert) { Button("OK", role: .cancel) {} } message: { Text(alertMsg) }
    }

    // MARK: - Actions
    private func handleSignUp() async {
        guard isFormValid else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // 1) إنشاء المستخدم في Auth
            let authResult = try await Auth.auth().createUser(withEmail: email.lowercased(), password: password)
            let uid = authResult.user.uid

            // 2) تفكيك الاسم الكامل
            let (first, lastOpt) = splitName(fullName)

            // 3) بناء البيانات للتخزين
            var data: [String: Any] = [
                "email": email.lowercased(),
                "firstName": first,
                "role": role == .player ? "player" : "coach",
                "phone": phone,
                "createdAt": FieldValue.serverTimestamp()
            ]

            if let dob = dob {
                data["dob"] = Timestamp(date: dob)
            }

            // lastName: إمّا قيمة نصية أو null لو ما كتبه المستخدم
            data["lastName"] = lastOpt ?? NSNull()

            // 4) الكتابة إلى Firestore
            try await Firestore.firestore().collection("users").document(uid).setData(data, merge: true)

            // 5) نجاح → الانتقال لصفحة الإعداد
            goToPlayerSetup = true

        } catch {
            print("🔥 SIGNUP ERROR:", error)
            alertMsg = error.localizedDescription
            showAlert = true
        }
    }

    /// تفكيك الاسم الكامل إلى first و last (لو فيه أكثر من كلمة ناخذ الأولى first والباقي last)
    private func splitName(_ full: String) -> (first: String, last: String?) {
        let parts = full
            .split(separator: " ")
            .map { String($0) }
            .filter { !$0.isEmpty }

        guard let first = parts.first else { return ("", nil) }
        if parts.count >= 2 {
            let last = parts.dropFirst().joined(separator: " ")
            return (first, last)
        } else {
            return (first, nil) // نخليه null في Firestore
        }
    }

    // MARK: - UI helpers
    private func rolePill(_ r: UserRole) -> some View {
        Button { role = r } label: {
            HStack(spacing: 8) {
                Image(systemName: role == r ? "circle.inset.filled" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                Text(r.rawValue)
                    .font(.custom("Poppins", size: 16))
            }
            .foregroundColor(primary)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.custom("Poppins", size: 14))
            .foregroundColor(.gray)
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
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
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

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: date)
    }
}

// MARK: - Wheel sheet for DOB
private struct DateWheelPickerSheet: View {
    @Binding var selection: Date?
    @Binding var tempSelection: Date
    @Binding var showSheet: Bool

    private let primary = Color(hexv: "#36796C")

    var body: some View {
        VStack(spacing: 16) {
            Text("Select your birth date")
                .font(.custom("Poppins", size: 18))
                .foregroundColor(primary)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)

            DatePicker("", selection: $tempSelection, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .tint(primary)
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
        .padding(.horizontal, 20)
    }
}

// Hex color
extension Color {
    init(hexv: String) {
        let hexv = hexv.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexv).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexv.count {
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
