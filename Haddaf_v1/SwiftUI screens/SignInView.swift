import SwiftUI
import FirebaseAuth
import FirebaseFirestore

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
    default: (a, r, g, b) = (255, 0, 0, 0)
    }
    return Color(.sRGB,
                 red: Double(r)/255,
                 green: Double(g)/255,
                 blue: Double(b)/255,
                 opacity: Double(a)/255)
}

struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isHidden = true

    @State private var signInError: String?
    @State private var inlineVerifyError: String?
    @State private var showVerifyPrompt = false

    @State private var verifyTask: Task<Void, Never>?
    @State private var resendTimerTask: Task<Void, Never>?
    @State private var resendCooldown = 0

    @State private var goToProfile = false
    @State private var goToPlayerSetup = false

    private let resendCooldownSeconds = 30
    private let lastSentKey = "signin_last_verification_email_sent_at"

    private let primary = colorHex("#36796C")
    private let bg = colorHex("#EFF5EC")
    private let emailActionURL = "https://haddaf-db.firebaseapp.com/__/auth/action"

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidEmail(email)
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Text("Sign In")
                        .font(.custom("Poppins", size: 34))
                        .foregroundColor(primary)
                        .fontWeight(.medium)
                        .padding(.top, 12)

                    // Email
                    VStack(alignment: .leading) {
                        Text("Email")
                            .font(.custom("Poppins", size: 14))
                            .foregroundColor(.gray)
                        TextField("", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.custom("Poppins", size: 16))
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                    }

                    // Password
                    VStack(alignment: .leading) {
                        Text("Password")
                            .font(.custom("Poppins", size: 14))
                            .foregroundColor(.gray)
                        HStack {
                            if isHidden {
                                SecureField("", text: $password)
                            } else {
                                TextField("", text: $password)
                            }
                            Button { isHidden.toggle() } label: {
                                Image(systemName: isHidden ? "eye.slash" : "eye")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                    }

                    // Forgot
                    HStack {
                        Spacer()
                        NavigationLink { ForgotPasswordView() } label: {
                            Text("Forgot password?")
                                .foregroundColor(primary)
                                .font(.custom("Poppins", size: 15))
                        }
                    }

                    // Button
                    Button { Task { await handleSignIn() } } label: {
                        Text("Log in")
                            .foregroundColor(.white)
                            .font(.custom("Poppins", size: 18))
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(primary)
                            .clipShape(Capsule())
                    }
                    .disabled(!isFormValid)
                    .opacity(isFormValid ? 1 : 0.5)

                    if let signInError {
                        Text(signInError)
                            .foregroundColor(.red)
                            .font(.system(size: 13))
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 22)
            }
        }
        .navigationDestination(isPresented: $goToProfile) { PlayerProfileView() }
        .navigationDestination(isPresented: $goToPlayerSetup) { PlayerSetupView() }
    }

    // MARK: Sign In Logic
    private func handleSignIn() async {
        guard isFormValid else { return }
        do {
            let result = try await Auth.auth().signIn(withEmail: email.lowercased(), password: password)
            let user = result.user
            try await user.reload()

            if user.isEmailVerified {
                goToProfile = true
            } else {
                try await sendVerificationEmail(to: user)
                markVerificationSentNow()
                startResendCooldown(seconds: resendCooldownSeconds)
                showVerifyPrompt = true
                startVerificationWatcher()
            }
        } catch {
            let ns = error as NSError
            if let authErr = AuthErrorCode(rawValue: ns.code) {
                switch authErr {
                case .invalidEmail:
                    signInError = "Invalid email format."
                case .userNotFound:
                    signInError = "No user found for this email."
                case .wrongPassword:
                    signInError = "Wrong password. Try again."
                case .tooManyRequests:
                    signInError = "Too many attempts. Try again later."
                case .networkError:
                    signInError = "Network error. Check your connection."
                default:
                    signInError = ns.localizedDescription
                }
            } else {
                signInError = ns.localizedDescription
            }
        }
    }

    // MARK: Verify watcher
    private func startVerificationWatcher() {
        verifyTask?.cancel()
        verifyTask = Task {
            let end = Date().addingTimeInterval(600)
            while !Task.isCancelled && Date() < end {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let user = Auth.auth().currentUser else { break }
                try? await user.reload()
                if user.isEmailVerified {
                    await finalizeAfterVerification(for: user)
                    break
                }
            }
        }
    }

    // MARK: finalizeAfterVerification
    @MainActor
    private func finalizeAfterVerification(for user: User) async {
        // Example only — you can customize as needed
        let db = Firestore.firestore()
        try? await db.collection("users").document(user.uid).setData([
            "email": user.email ?? "",
            "emailVerified": true,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        showVerifyPrompt = false
        goToPlayerSetup = true
    }

    // MARK: Resend verification
    private func resendVerification() async {
        guard let user = Auth.auth().currentUser else { return }
        do {
            try await sendVerificationEmail(to: user)
            markVerificationSentNow()
            startResendCooldown(seconds: resendCooldownSeconds)
        } catch {
            let ns = error as NSError
            if let code = AuthErrorCode(rawValue: ns.code) {
                inlineVerifyError = (code == .tooManyRequests)
                ? "Too many requests from this device. Try again later."
                : ns.localizedDescription
            } else {
                inlineVerifyError = ns.localizedDescription
            }
        }
    }

    private func sendVerificationEmail(to user: User) async throws {
        let acs = ActionCodeSettings()
        acs.handleCodeInApp = true
        acs.url = URL(string: emailActionURL)
        if let bundleID = Bundle.main.bundleIdentifier {
            acs.setIOSBundleID(bundleID)
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            user.sendEmailVerification(with: acs) { err in
                if let err { cont.resume(throwing: err) } else { cont.resume() }
            }
        }
    }

    // MARK: Helpers
    private func isValidEmail(_ value: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

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

    private func markVerificationSentNow() {
        let now = Int(Date().timeIntervalSince1970)
        UserDefaults.standard.set(now, forKey: lastSentKey)
    }
}
