import SwiftUI
import FirebaseAuth
import FirebaseFirestore
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
    // Resend cooldown/backoff (email verification only)
    @State private var resendBackoff = 60
    private let resendBackoffMax = 15 * 60
    private let resendCooldownSeconds = 30
    private let lastSentKey = "signin_last_verification_email_sent_at"
    // MODIFIED: Use new BrandColors
    private let primary = BrandColors.darkTeal
    private let bg = BrandColors.backgroundGradientEnd
    
    private let emailActionURL = "https://haddaf-db.web.app/__/auth/action"
    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isValidEmail(email)
    }
    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    Text("Sign In")
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .foregroundColor(primary)
                        .padding(.top, 12)
                    VStack(alignment: .leading) {
                        Text("Email")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.gray)
                        
                        TextField("", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(primary)
                            .tint(primary)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(BrandColors.background)
                                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                            )
                    }
                    if !email.isEmpty && !isValidEmail(email) {
                        Text("Please enter a valid email address.")
                            .foregroundColor(.red)
                            .font(.system(size: 13, design: .rounded))
                    }
                    VStack(alignment: .leading) {
                        Text("Password")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.gray)
                        
                        HStack {
                            if isHidden {
                                SecureField("", text: $password)
                                    .foregroundColor(primary)
                                    .tint(primary)
                                    .font(.system(size: 16, design: .rounded))
                            } else {
                                TextField("", text: $password)
                                    .foregroundColor(primary)
                                    .tint(primary)
                                    .font(.system(size: 16, design: .rounded))
                            }
                            Button { isHidden.toggle() } label: {
                                Image(systemName: "eye\(isHidden ? ".slash" : "")")
                                    .foregroundColor(.gray)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(BrandColors.background)
                                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                        )
                    }
                    HStack {
                        Spacer()
                        NavigationLink { ForgotPasswordView() } label: {
                            Text("Forgot password?")
                                .foregroundColor(primary)
                                .font(.system(size: 15, design: .rounded))
                        }
                    }
                    Button { Task { await handleSignIn() } } label: {
                        Text("Log in")
                            .foregroundColor(.white)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(primary)
                            .clipShape(Capsule())
                            .shadow(color: primary.opacity(0.3), radius: 10, y: 5)
                    }
                    .disabled(!isFormValid)
                    .opacity(isFormValid ? 1 : 0.5)
                    if let signInError {
                        Text(signInError)
                            .foregroundColor(.red)
                            .font(.system(size: 13, design: .rounded))
                            .multilineTextAlignment(.center)
                    }
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 22)
            }
            // ✅ Overlay-only verify popup with transparent background (no sheet)
            if showVerifyPrompt {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                UnifiedVerifySheetSI(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    primary: primary,
                    resendCooldown: $resendCooldown,
                    errorText: $inlineVerifyError,
                    onResend: { Task { await resendVerification() } },
                    onClose: {
                        withAnimation {
                            stopVerificationWatcher()
                            showVerifyPrompt = false
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale))
                .zIndex(1)
            }
        }
        .fullScreenCover(isPresented: $goToProfile) {
            PlayerProfileView()
                .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $goToPlayerSetup) {
            NavigationStack {
                PlayerSetupView()
            }
        }
        .onAppear { restoreCooldownIfAny() }
        .onDisappear { cleanupTasks() }
    }
    // MARK: - Sign In Logic
    private func handleSignIn() async {
        guard isFormValid else { return }
        signInError = nil
        inlineVerifyError = nil
        do {
            let result = try await Auth.auth().signIn(withEmail: email.lowercased(), password: password)
            let user = result.user
            try await user.reload()
            if user.isEmailVerified {
                // Check if player profile is complete
                do {
                    let complete = try await isPlayerProfileComplete(uid: user.uid)
                    await MainActor.run {
                        if complete { goToProfile = true }
                        else { goToPlayerSetup = true }
                    }
                } catch {
                    await MainActor.run { goToPlayerSetup = true }
                }
            } else {
                // Not verified → send verification email
                try await sendVerificationEmail(to: user)
                markVerificationSentNow()
                startResendCooldown(seconds: max(resendCooldownSeconds, resendBackoff))
                await MainActor.run { showVerifyPrompt = true }
                startVerificationWatcher()
            }
        } catch {
            let ns = error as NSError
            if let authErr = AuthErrorCode(rawValue: ns.code) {
                switch authErr {
                case .wrongPassword, .userNotFound, .invalidEmail, .invalidCredential:
                    signInError = "Email or password is incorrect. Please make sure you entered them correctly."
                case .invalidUserToken, .userTokenExpired:
                    signInError = "Your session has expired. Please try again or reset your password."
                case .tooManyRequests:
                    signInError = "Too many attempts. Try again later."
                default:
                    signInError = ns.localizedDescription
                }
            } else {
                signInError = ns.localizedDescription
            }
        }
    }
    // MARK: - Player profile completion check
    private func isPlayerProfileComplete(uid: String) async throws -> Bool {
        let snap = try await Firestore.firestore()
            .collection("users").document(uid)
            .collection("player").document("profile")
            .getDocument()
        guard snap.exists, let data = snap.data() else { return false }
        let position = data["position"] as? String ?? ""
        let weight   = data["weight"] as? Int ?? -1
        let height   = data["height"] as? Int ?? -1
        let location = data["location"] as? String ?? ""
        let hasPosition = !position.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasLocation = !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let weightOK = (15...200).contains(weight)
        let heightOK = (100...230).contains(height)
        return hasPosition && hasLocation && weightOK && heightOK
    }
    // MARK: - Email verification watcher
    private func startVerificationWatcher() {
        verifyTask?.cancel()
        verifyTask = Task {
            let end = Date().addingTimeInterval(600)
            while !Task.isCancelled && Date() < end {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let user = Auth.auth().currentUser else { break }
                do {
                    try await user.reload()
                    if user.isEmailVerified {
                        await finalizeAfterVerification(for: user)
                        break
                    }
                } catch { /* ignore polling errors */ }
            }
        }
    }
    private func stopVerificationWatcher() {
        verifyTask?.cancel()
        verifyTask = nil
    }
    // MARK: - Finalize after verification
    @MainActor
    private func finalizeAfterVerification(for user: User) async {
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
            try? await Firestore.firestore()
                .collection("users")
                .document(user.uid)
                .setData(data, merge: true)
            DraftStore.clear()
        } else {
            try? await Firestore.firestore()
                .collection("users")
                .document(user.uid)
                .setData([
                    "email": user.email ?? "",
                    "emailVerified": true,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
        }
        inlineVerifyError = nil
        showVerifyPrompt = false
        Task {
            do {
                let complete = try await isPlayerProfileComplete(uid: user.uid)
                await MainActor.run {
                    if complete { goToProfile = true } else { goToPlayerSetup = true }
                }
            } catch {
                await MainActor.run { goToPlayerSetup = true }
            }
        }
        stopVerificationWatcher()
    }
    // MARK: - Resend verification email with backoff (UI only)
    private func resendVerification() async {
        guard let user = Auth.auth().currentUser else { return }
        guard resendCooldown == 0 else { return }
        do {
            try await sendVerificationEmail(to: user)
            markVerificationSentNow()
            // reset backoff on success
            resendBackoff = 60
            startResendCooldown(seconds: resendBackoff)
            await MainActor.run { inlineVerifyError = nil }
        } catch {
            let ns = error as NSError
            if let code = AuthErrorCode(rawValue: ns.code), code == .tooManyRequests {
                // exponential backoff + small jitter
                resendBackoff = min(resendBackoff * 2, resendBackoffMax)
                let jitter = Int.random(in: 5...15)
                startResendCooldown(seconds: resendBackoff + jitter)
                await MainActor.run {
                    inlineVerifyError = "Too many requests. Try again in ~\(resendBackoff + jitter)s."
                }
            } else {
                await MainActor.run { inlineVerifyError = ns.localizedDescription }
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
    // MARK: - Helpers
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
    private func restoreCooldownIfAny() {
        let now = Int(Date().timeIntervalSince1970)
        let last = UserDefaults.standard.integer(forKey: lastSentKey)
        let diff = max(0, resendCooldownSeconds - (now - last))
        if diff > 0 { startResendCooldown(seconds: diff) }
    }
    private func cleanupTasks() {
        stopVerificationWatcher()
        resendTimerTask?.cancel()
        resendTimerTask = nil
    }
    private func splitName(_ full: String) -> (first: String, last: String?) {
        let parts = full.split(separator: " ").map { String($0) }
        guard let first = parts.first else { return ("", nil) }
        return parts.count > 1 ? (first, parts.dropFirst().joined(separator: " ")) : (first, nil)
    }
}
// MARK: - Unified Verify Sheet
struct UnifiedVerifySheetSI: View {
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
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text("We've sent a verification link to \(email).\nOpen the link to verify your email so you can complete your profile.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                Button(action: { if resendCooldown == 0 { onResend() } }) {
                    Text(resendCooldown > 0 ? "Resend (\(resendCooldown)s)" : "Resend")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(resendCooldown > 0)
                if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .font(.system(size: 13, design: .rounded))
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
                    .fill(BrandColors.background)
                    .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 10)
            )
            Spacer()
        }
        .padding()
        .background(Color.clear) // fully transparent backdrop
        .allowsHitTesting(true)
    }
}
