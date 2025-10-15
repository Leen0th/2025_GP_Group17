import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Simple color helper (local to this file — no extension)
private func colorHex(_ hex: String) -> Color {
    let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
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
    default:(a, r, g, b) = (255, 0, 0, 0)
    }
    return Color(.sRGB,
                 red:   Double(r)/255,
                 green: Double(g)/255,
                 blue:  Double(b)/255,
                 opacity: Double(a)/255)
}

// MARK: - User Role Enum
enum UserRole: String { case player = "Player", coach = "Coach" }

// MARK: - Sign Up Screen
struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss

    // Page colors
    private let primary = colorHex("#36796C")
    private let bg = colorHex("#EFF5EC")

    // Must match Firebase email template "Action URL"
    private let emailActionURL = "https://haddaf-db.firebaseapp.com/__/auth/action"

    // Fields
    @State private var role: UserRole = .player
    @State private var fullName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var isHidden = true
    @State private var dob: Date? = nil
    @State private var showDOBPicker = false
    @State private var tempDOB = Date()

    // Navigation
    @State private var goToPlayerSetup = false

    // Verification UI/logic
    @State private var showVerifyPrompt = false
    @State private var verifyTask: Task<Void, Never>? = nil
    @State private var inlineVerifyError: String? = nil

    // Resend cooldown (30s)
    @State private var resendCooldown = 0
    @State private var resendTimerTask: Task<Void, Never>? = nil
    private let resendCooldownSeconds = 30
    private let lastSentKey = "last_verification_email_sent_at"

    // Validation
    private var isNameValid: Bool { isValidFullName(fullName) }
    private var isPasswordValid: Bool { isValidPassword(password) }
    private var isFormValid: Bool {
        isNameValid
        && isPasswordValid
        && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && dob != nil
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    Text("Sign Up")
                        .font(.custom("Poppins", size: 34))
                        .fontWeight(.medium)
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    HStack(spacing: 28) { rolePill(.player); rolePill(.coach) }
                        .frame(maxWidth: .infinity, alignment: .center)

                    fieldLabel("Full Name")
                    roundedField {
                        TextField("", text: $fullName)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                            .textInputAutocapitalization(.words)
                    }
                    if !fullName.isEmpty && !isNameValid {
                        Text("Please enter a real name (letters only). Numbers are not allowed.")
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }

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
                            Image(systemName: "calendar").foregroundColor(primary.opacity(0.85))
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

                    fieldLabel("Phone Number")
                    roundedField {
                        TextField("", text: $phone)
                            .keyboardType(.phonePad)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                    }

                    fieldLabel("Password")
                    roundedField {
                        ZStack(alignment: .trailing) {
                            if isHidden {
                                SecureField("", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .font(.custom("Poppins", size: 16))
                                    .foregroundColor(primary)
                                    .padding(.trailing, 44)
                            } else {
                                TextField("", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .font(.custom("Poppins", size: 16))
                                    .foregroundColor(primary)
                                    .padding(.trailing, 44)
                            }
                            Button { withAnimation { isHidden.toggle() } } label: {
                                Image(systemName: isHidden ? "eye.slash" : "eye").foregroundColor(.gray)
                            }
                        }
                    }
                    if !password.isEmpty && !isPasswordValid {
                        Text("Password must be at least 8 characters and include uppercase and lowercase letters, a number, and a special symbol.")
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button { Task { await handleSignUp() } } label: {
                        Text("Sign Up")
                            .font(.custom("Poppins", size: 18))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(primary)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 8)
                    .disabled(!isFormValid)
                    .opacity(isFormValid ? 1.0 : 0.5)

                    HStack(spacing: 6) {
                        Text("Already have an account?")
                            .font(.custom("Poppins", size: 15))
                            .foregroundColor(.gray)
                        NavigationLink { SignInView() } label: {
                            Text("Sign in")
                                .font(.custom("Poppins", size: 15))
                                .fontWeight(.semibold)
                                .foregroundColor(primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

            if showVerifyPrompt {
                Color.black.opacity(0.35).ignoresSafeArea()
                VerifyEmailModal(
                    title: "Verify your email",
                    message: "We’ve sent a verification link to \(email).",
                    leftTitle: resendCooldown > 0 ? "Resend (\(resendCooldown)s)" : "Resend",
                    rightTitle: "I’ve Verified",
                    onLeft: { guard resendCooldown == 0 else { return }; Task { await resendVerification() } },
                    onRight: { Task { await checkVerificationNow() } },
                    onDismiss: { withAnimation { showVerifyPrompt = false } },
                    leftDisabled: resendCooldown > 0,
                    errorText: inlineVerifyError
                )
                .transition(.opacity.combined(with: .scale))
                .zIndex(1)
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
        .navigationDestination(isPresented: $goToPlayerSetup) { PlayerSetupView() }
        .onDisappear { verifyTask?.cancel(); resendTimerTask?.cancel() }
    }

    // MARK: - Actions
    private func handleSignUp() async {
        guard isFormValid else { return }

        do {
            let authResult = try await Auth.auth().createUser(withEmail: email.lowercased(), password: password)

            // Optional: put name in email template
            let changeReq = authResult.user.createProfileChangeRequest()
            changeReq.displayName = fullName
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                changeReq.commitChanges { err in
                    if let err = err { cont.resume(throwing: err) } else { cont.resume() }
                }
            }

            // Save local draft (no Firestore yet)
            let draft = ProfileDraft(fullName: fullName, phone: phone, role: role.rawValue.lowercased(), dob: dob, email: email.lowercased())
            DraftStore.save(draft)

            // Send verification + UI
            try await sendVerificationEmail(to: authResult.user)
            markVerificationSentNow()
            startResendCooldown(seconds: resendCooldownSeconds)
            inlineVerifyError = nil
            showVerifyPrompt = true
            startVerificationWatcher()

        } catch {
            inlineVerifyError = (error as NSError).localizedDescription
            showVerifyPrompt = true
        }
    }

    private func startVerificationWatcher() {
        verifyTask?.cancel()
        verifyTask = Task {
            let deadline = Date().addingTimeInterval(600)
            while !Task.isCancelled && Date() < deadline {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let user = Auth.auth().currentUser else { break }
                try? await user.reload()
                if user.isEmailVerified {
                    await finalizeProfileAndNavigate(for: user)
                    break
                }
            }
        }
    }

    private func checkVerificationNow() async {
        guard let user = Auth.auth().currentUser else { return }
        do {
            try await user.reload()
            if user.isEmailVerified {
                await finalizeProfileAndNavigate(for: user)
            } else {
                inlineVerifyError = "Your email is not verified yet. Please check your inbox."
            }
        } catch {
            inlineVerifyError = error.localizedDescription
        }
    }

    @MainActor
    private func finalizeProfileAndNavigate(for user: User) async {
        if let draft = DraftStore.load() {
            let (first, lastOpt) = splitName(draft.fullName)
            var data: [String: Any] = [
                "email": user.email ?? draft.email,
                "firstName": first,
                "lastName": lastOpt ?? NSNull(),
                "role": draft.role,
                "phone": draft.phone,
                "emailVerified": true,
                "createdAt": FieldValue.serverTimestamp()
            ]
            if let d = draft.dob { data["dob"] = Timestamp(date: d) }
            try? await Firestore.firestore().collection("users").document(user.uid).setData(data, merge: true)
            DraftStore.clear()
        }
        inlineVerifyError = nil
        showVerifyPrompt = false
        goToPlayerSetup = true
    }

    private func resendVerification() async {
        guard let user = Auth.auth().currentUser else { return }
        guard canSendVerificationNow(), resendCooldown == 0 else {
            inlineVerifyError = "Please wait \(max(0, resendCooldown))s before resending the link."
            return
        }
        do {
            try await sendVerificationEmail(to: user)
            markVerificationSentNow()
            startResendCooldown(seconds: resendCooldownSeconds)
            inlineVerifyError = nil
        } catch {
            let ns = error as NSError
            inlineVerifyError = (ns.code == AuthErrorCode.tooManyRequests.rawValue)
                ? "Too many requests from this device. Please try again later."
                : ns.localizedDescription
        }
    }

    private func sendVerificationEmail(to user: User) async throws {
        let acs = ActionCodeSettings()
        acs.handleCodeInApp = true
        acs.url = URL(string: emailActionURL)
        if let bundleID = Bundle.main.bundleIdentifier { acs.setIOSBundleID(bundleID) }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            user.sendEmailVerification(with: acs) { err in
                if let err = err { cont.resume(throwing: err) } else { cont.resume() }
            }
        }
    }

    // MARK: - Cooldown helpers
    private func startResendCooldown(seconds: Int) {
        resendTimerTask?.cancel()
        resendCooldown = seconds
        resendTimerTask = Task {
            while !Task.isCancelled && resendCooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { resendCooldown -= 1 }
            }
        }
    }
    private func canSendVerificationNow() -> Bool {
        let last = UserDefaults.standard.integer(forKey: lastSentKey)
        let now  = Int(Date().timeIntervalSince1970)
        return (now - last) >= resendCooldownSeconds
    }
    private func markVerificationSentNow() {
        let now = Int(Date().timeIntervalSince1970)
        UserDefaults.standard.set(now, forKey: lastSentKey)
    }

    // MARK: - Validation helpers
    private func isValidFullName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = #"^[\p{L}][\p{L}\s.'-]*$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
    private func isValidPassword(_ pass: String) -> Bool {
        guard pass.count >= 8 else { return false }
        let hasUpper   = pass.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasLower   = pass.range(of: "[a-z]", options: .regularExpression) != nil
        let hasDigit   = pass.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSpecial = pass.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil
        return hasUpper && hasLower && hasDigit && hasSpecial
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
    private func buttonLikeField<Content: View>(action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
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
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; return f.string(from: date)
    }
    private func splitName(_ full: String) -> (first: String, last: String?) {
        let parts = full.split(separator: " ").map { String($0) }
        guard let first = parts.first else { return ("", nil) }
        return parts.count > 1 ? (first, parts.dropFirst().joined(separator: " ")) : (first, nil)
    }
}

// MARK: - Date Wheel Sheet
private struct DateWheelPickerSheet: View {
    @Binding var selection: Date?
    @Binding var tempSelection: Date
    @Binding var showSheet: Bool

    private let primary = colorHex("#36796C")

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
