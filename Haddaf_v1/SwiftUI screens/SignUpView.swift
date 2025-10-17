import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Foundation

// MARK: - Local color helper
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

    // Theme
    private let primary = colorHex("#36796C")
    private let bg = colorHex("#EFF5EC")

    // Must match Firebase Auth email action URL
    private let emailActionURL = "https://haddaf-db.web.app/__/auth/action"

    // Fields
    @State private var role: UserRole = .player
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isHidden = true
    @State private var dob: Date? = nil
    @State private var showDOBPicker = false
    @State private var tempDOB = Date()

    // Navigation
    @State private var goToPlayerSetup = false

    // Email verification UI/logic
    @State private var showVerifyPrompt = false
    @State private var verifyTask: Task<Void, Never>? = nil
    @State private var inlineVerifyError: String? = nil

    // Resend cooldown
    @State private var resendCooldown = 0
    @State private var resendTimerTask: Task<Void, Never>? = nil
    private let resendCooldownSeconds = 30
    private let lastSentKey = "last_verification_email_sent_at"

    // Loading state
    @State private var isSubmitting = false

    // Email-exists inline check (no spinner)
    @State private var emailExists = false
    @State private var emailCheckError: String? = nil
    @State private var emailCheckTask: Task<Void, Never>? = nil

    // Validation
    private var isNameValid: Bool { isValidFullName(fullName) }
    private var isPasswordValid: Bool { isValidPassword(password) }
    private var isEmailValid: Bool { isValidEmail(email) }   // متغيّر محسوب للـ UI فقط
    private var isFormValid: Bool {
        isNameValid && isPasswordValid && isEmailValid && dob != nil && !emailExists
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

                    // Full Name
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
                            .onChange(of: email) { _ in debouncedEmailCheck() } // يتحقق بدون سبينر
                    }

                    // Inline email state (بدون "Checking email…")
                    Group {
                        if !email.isEmpty && !isEmailValid {
                            Text("Please enter a valid email address.")
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        } else if emailExists {
                            Text("This email is already registered. Please sign in.")
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        } else if let err = emailCheckError, !err.isEmpty {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        }
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

                    // Submit
                    Button { Task { await handleSignUp() } } label: {
                        HStack(spacing: 10) {
                            Text("Sign Up")
                                .font(.custom("Poppins", size: 18))
                                .foregroundColor(.white)
                            if isSubmitting { ProgressView().scaleEffect(0.9) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(primary)
                        .clipShape(Capsule())
                    }
                    .padding(.top, 8)
                    .disabled(!isFormValid || isSubmitting)
                    .opacity((isFormValid && !isSubmitting) ? 1.0 : 0.5)

                    // Bottom link
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

            // Verify popup
            if showVerifyPrompt {
                Color.black.opacity(0.35).ignoresSafeArea()
                SimpleVerifySheet(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    primary: primary,
                    resendCooldown: $resendCooldown,
                    errorText: $inlineVerifyError,
                    onResend: { Task { await resendVerification() } },
                    onClose: { withAnimation { showVerifyPrompt = false } }
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
        .onDisappear { verifyTask?.cancel(); resendTimerTask?.cancel(); emailCheckTask?.cancel() }
    }

    // MARK: - Email existence check (debounced, no spinner)
    private func debouncedEmailCheck() {
        emailCheckTask?.cancel()
        emailExists = false
        emailCheckError = nil

        // ✅ استخدم الدالة الصحيحة بدلاً من المتغيّر المحسوب
        guard isValidEmail(email) else { return }

        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        emailCheckTask = Task {
            // تهدئة بسيطة لتقليل الطلبات أثناء الكتابة
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
            do {
                let methods = try await fetchSignInMethods(for: mail)
                await MainActor.run {
                    emailExists = !methods.isEmpty
                }
            } catch {
                await MainActor.run {
                    emailCheckError = "Couldn't check this email. Please try again."
                }
            }
        }
    }

    private func fetchSignInMethods(for email: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String], Error>) in
            Auth.auth().fetchSignInMethods(forEmail: email) { methods, error in
                if let error = error { cont.resume(throwing: error) }
                else { cont.resume(returning: methods ?? []) }
            }
        }
    }

    // MARK: - Actions
    private func handleSignUp() async {
        if emailExists { return }
        guard isFormValid else { return }
        isSubmitting = true
        inlineVerifyError = nil

        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        do {
            // 1) Create user
            let authResult = try await Auth.auth().createUser(withEmail: mail, password: password)

            // 2) Optional displayName
            let changeReq = authResult.user.createProfileChangeRequest()
            changeReq.displayName = name
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                changeReq.commitChanges { err in
                    if let err = err { cont.resume(throwing: err) } else { cont.resume() }
                }
            }

            // 3) Save local draft
            let draft = ProfileDraft(fullName: name,
                                     phone: "",
                                     role: role.rawValue.lowercased(),
                                     dob: dob,
                                     email: mail)
            DraftStore.save(draft)

            // 4) Send verification email
            try await sendVerificationEmail(to: authResult.user)
            markVerificationSentNow()
            startResendCooldown(seconds: resendCooldownSeconds)

            // 5) Show popup + start watcher
            await MainActor.run { showVerifyPrompt = true }
            startVerificationWatcher()

        } catch {
            let ns = error as NSError
            if ns.code == AuthErrorCode.emailAlreadyInUse.rawValue {
                emailExists = true
                showVerifyPrompt = false
                inlineVerifyError = nil
            } else {
                inlineVerifyError = ns.localizedDescription
                showVerifyPrompt = true
            }
        }

        isSubmitting = false
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
                    await finalizeAndGo(for: user)
                    break
                }
            }
        }
    }

    @MainActor
    private func finalizeAndGo(for user: User) async {
        if let draft = DraftStore.load() {
            let (first, lastOpt) = splitName(draft.fullName)
            var data: [String: Any] = [
                "email": user.email ?? draft.email,
                "firstName": first,
                "lastName": lastOpt ?? NSNull(),
                "role": draft.role,
                "emailVerified": true,
                "createdAt": FieldValue.serverTimestamp()
            ]
            if let d = draft.dob { data["dob"] = Timestamp(date: d) }
            try? await Firestore.firestore().collection("users").document(user.uid).setData(data, merge: true)
            DraftStore.clear()
        } else {
            try? await Firestore.firestore().collection("users").document(user.uid).setData([
                "email": user.email ?? "",
                "emailVerified": true,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        }
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

    // MARK: - Cooldown / helpers
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
    private func isValidEmail(_ value: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
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

// MARK: - Simple Verify Sheet (Resend only, smaller)
struct SimpleVerifySheet: View {
    let email: String
    let primary: Color
    @Binding var resendCooldown: Int
    @Binding var errorText: String?
    var onResend: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)

                Text("Verify your email")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)

                Text("We’ve sent a verification link to \(email).\n")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                Button(action: { if resendCooldown == 0 { onResend() } }) {
                    Text(resendCooldown > 0 ? "Resend (\(resendCooldown)s)" : "Resend")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(resendCooldown > 0)

                if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                }

                Spacer().frame(height: 8)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 10)
            )
            Spacer()
        }
        .padding()
        .background(Color.clear)
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
