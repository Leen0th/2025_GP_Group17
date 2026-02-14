import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AppSession

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
    @State private var goToAdmin = false

    // Resend cooldown/backoff (email verification only)
    @State private var resendBackoff = 60
    private let resendBackoffMax = 15 * 60
    private let resendCooldownSeconds = 30
    private let lastSentKey = "signin_last_verification_email_sent_at"

    // Theme
    private let primary = BrandColors.darkTeal
    private let bg = BrandColors.backgroundGradientEnd
    private let emailActionURL = "https://haddaf-db.web.app/__/auth/action"

    // Returns true only when email and password are non-empty and the email format is valid.
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
                        HStack(spacing: 3) {
                            Text("Email")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(.gray)

                            Text("*")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(.red)
                        }
                        
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
                        HStack(spacing: 3) {
                              Text("Password")
                                  .font(.system(size: 14, design: .rounded))
                                  .foregroundColor(.gray)

                              Text("*")
                                  .font(.system(size: 14, design: .rounded))
                                  .foregroundColor(.red)
                          }
                        
                        
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
                        Text("Sign in")
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

            // Overlay-only verify popup with transparent background (no sheet)
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
        .fullScreenCover(isPresented: $goToAdmin) {
            AdminTabView()
        }


        .fullScreenCover(isPresented: $goToProfile) {
            PlayerProfileView()
                .toolbar(.hidden, for: .navigationBar)
        }

        .fullScreenCover(isPresented: $goToPlayerSetup) {
            NavigationStack { PlayerSetupView() }
        }
        .onAppear { restoreCooldownIfAny() }
        .onDisappear { cleanupTasks() }
        .toolbar {
                   ToolbarItem(placement: .topBarLeading) {
                       Button {
                           dismiss()
                       } label: {
                           Image(systemName: "chevron.left")
                               .font(.system(size: 20, weight: .semibold))
                               .foregroundColor(primary)
                       }
                   }
               }
        .navigationBarBackButtonHidden(true)
           }
    

    // MARK: - Sign In Logic
    private func handleSignIn() async {
        // Ensure form is valid before attempting sign-in
        guard isFormValid else { return }
        
        signInError = nil
        inlineVerifyError = nil
        
        do {
            // Sign in with Firebase Auth
            let result = try await Auth.auth().signIn(withEmail: email.lowercased(), password: password)
            let user = result.user
            
            // Reload to get the latest auth state (email verification, token, etc.)
            try await user.reload()
            
            // Fetch role + isActive from Firestore
            let doc = try await Firestore.firestore()
                .collection("users")
                .document(user.uid)
                .getDocument()
            
            let data = doc.data() ?? [:]
            let role = (data["role"] as? String ?? "player").lowercased()
            let isActive = data["isActive"] as? Bool ?? true
            
            // CHECK VERIFICATION:
            var coachIsVerified = false
            if role == "coach" {
                // We check the coachRequests collection for this user's approval status
                let reqSnap = try await Firestore.firestore()
                    .collection("coachRequests")
                    .whereField("uid", isEqualTo: user.uid)
                    .getDocuments()
                
                if let status = reqSnap.documents.first?.data()["status"] as? String {
                    coachIsVerified = (status == "approved")
                }
            }
            
            // ✅ Admin: allow direct access WITHOUT email verification
            if role == "admin" {
                _ = try? await user.getIDTokenResult(forcingRefresh: true)
                
                await MainActor.run {
                    session.user = user
                    session.isGuest = false
                    goToAdmin = true
                }
                return
            }
            
            // Non-admin flow: keep your current email verification logic
            if user.isEmailVerified {
                _ = try? await user.getIDTokenResult(forcingRefresh: true)
                await promoteSignupDraftIfNeeded(for: user)
                
                await MainActor.run {
                    session.user = user
                    session.role = role // Set the specific role (player or coach)
                    session.isVerifiedCoach = coachIsVerified // SAVE TO SESSION
                    session.isGuest = false
                }
                
                if role == "coach" {
                    // ✅ COACH FLOW: Skip player setup and go directly to profile/discovery
                    await MainActor.run { goToProfile = true }
                } else {
                    // ✅ PLAYER FLOW: Check for profile completion
                    do {
                        let complete = try await isPlayerProfileComplete(uid: user.uid)
                        await MainActor.run {
                            if complete {
                                goToProfile = true
                            } else {
                                goToPlayerSetup = true
                            }
                        }
                    } catch {
                        await MainActor.run { goToPlayerSetup = true }
                    }
                }
                
            } else {
                // Email not verified (players/coaches): show verification prompt
                try await sendVerificationEmail(to: user)
                markVerificationSentNow()
                startResendCooldown(seconds: max(resendCooldownSeconds, resendBackoff))
                
                await MainActor.run { showVerifyPrompt = true }
                startVerificationWatcher()
            }
            
        } catch {
            // Firebase Auth error mapping
            let ns = error as NSError
            if let authErr = AuthErrorCode(rawValue: ns.code) {
                switch authErr {
                case .wrongPassword, .userNotFound, .invalidEmail, .invalidCredential:
                    signInError = "Email or password is incorrect. Please make sure you entered them correctly."
                case .invalidUserToken, .userTokenExpired:
                    signInError = "Your session has expired. Please try again later."
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

    private func promoteSignupDraftIfNeeded(for user: User) async {
        let usersRef = Firestore.firestore().collection("users").document(user.uid)
        if let snap = try? await usersRef.getDocument(),
           let data = snap.data(),
           (data["firstName"] as? String).map({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) == true {
            return
        }
        // Try to load the locally saved sign-up draft (from DraftStore).
        if let localDraft = DraftStore.load() {
            let (first, last) = splitName(localDraft.fullName)
            var base: [String: Any] = [
                "email": user.email ?? localDraft.email,
                "firstName": first,
                "lastName": last ?? NSNull(),
                "role": localDraft.role,
                "phone": localDraft.phone,
                "emailVerified": true,
                "createdAt": FieldValue.serverTimestamp()
            ]
            if let d = localDraft.dob { base["dob"] = Timestamp(date: d) }
            try? await usersRef.setData(base, merge: true)
            DraftStore.clear()
        } else {
            try? await usersRef.setData([
                "email": user.email ?? "",
                "emailVerified": true,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        }
    }

    // MARK: - Player profile completion check
    // Checks if the player's profile document (users/{uid}/player/profile) is complete.
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
                        
                        _ = try? await user.getIDTokenResult(forcingRefresh: true)
                        await promoteSignupDraftIfNeeded(for: user)
                        await MainActor.run {
                            session.user = user
                            session.isGuest = false
                            showVerifyPrompt = false
                            goToPlayerSetup = true
                        }
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

    // MARK: - Resend verification email with backoff (UI only)
    private func resendVerification() async {
        guard let user = Auth.auth().currentUser else { return }
        guard resendCooldown == 0 else { return }
        do {
            try await sendVerificationEmail(to: user)
            markVerificationSentNow()
            resendBackoff = 60
            startResendCooldown(seconds: resendBackoff)
            await MainActor.run { inlineVerifyError = nil }
        } catch {
            let ns = error as NSError
            if let code = AuthErrorCode(rawValue: ns.code), code == .tooManyRequests {
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
    
    // Sends an email verification link using Firebase's ActionCodeSettings.

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

// MARK: - Unified Verify Sheet (Sign-In)
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
        .background(Color.clear)
        .allowsHitTesting(true)
    }
}
