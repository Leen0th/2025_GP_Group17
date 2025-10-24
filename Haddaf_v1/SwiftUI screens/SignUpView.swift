import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Foundation

// MARK: - Color helper (REMOVED)
// This is now handled by the extension in AppModels.swift

// MARK: - User Role
enum UserRole: String { case player = "Player", coach = "Coach" }

// MARK: - Country code model/data (REMOVED)
// These are now defined in PlayerProfileContentView.swift

// MARK: - Sign Up
struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss

    // MODIFIED: Use Color(hex:) extension
    private let primary = Color(hex: "#36796C")
    private let bg = Color(hex: "#EFF5EC")
    private let emailActionURL = "https://haddaf-db.web.app/__/auth/action"

    // Fields
    @State private var role: UserRole = .player
    @State private var fullName = ""
    @State private var email = ""
    @State private var selectedDialCode: CountryDialCode = countryCodes.first { $0.code == "+966" } ?? countryCodes[0]
    @State private var showDialPicker = false
    @State private var phoneLocal = "" // digits only
    @State private var phoneNonDigitError = false
    @State private var password = ""
    @State private var isHidden = true
    @State private var dob: Date? = nil
    @State private var showDOBPicker = false
    @State private var tempDOB = Date()

    // Focus
    @FocusState private var emailFocused: Bool

    // Navigation
    @State private var goToPlayerSetup = false

    // Verify email UI/logic
    @State private var showVerifyPrompt = false
    @State private var verifyTask: Task<Void, Never>? = nil
    @State private var inlineVerifyError: String? = nil

    // Resend cooldown
    @State private var resendCooldown = 0
    @State private var resendTimerTask: Task<Void, Never>? = nil
    private let resendCooldownSeconds = 60
    private let lastSentKey = "last_verification_email_sent_at"

    // Loading / email-exists
    @State private var isSubmitting = false
    @State private var emailExists = false
    @State private var emailCheckError: String? = nil
    @State private var emailCheckTask: Task<Void, Never>? = nil

    // Password criteria
    private var pHasLen: Bool { password.count >= 8 }
    private var pHasUpper: Bool { password.range(of: "[A-Z]", options: .regularExpression) != nil }
    private var pHasLower: Bool { password.range(of: "[a-z]", options: .regularExpression) != nil }
    private var pHasDigit: Bool { password.range(of: "[0-9]", options: .regularExpression) != nil }
    private var pHasSpec: Bool { password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil }

    // Full name validation/error (last name optional)
    private var nameError: String? { fullNameValidationError(fullName) }

    // Validation
    private var isNameValid: Bool { nameError == nil && !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isPasswordValid: Bool { pHasLen && pHasUpper && pHasLower && pHasDigit && pHasSpec }
    private var isEmailValid: Bool { isValidEmail(email) }
    private var isPhoneValid: Bool { isValidPhone(code: selectedDialCode.code, local: phoneLocal) }
    private var isFormValid: Bool {
        isNameValid && isPasswordValid && isEmailValid && isPhoneValid && dob != nil && !emailExists
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    Text("Sign Up")
                        .font(.custom("Poppins", size: 34)).fontWeight(.medium)
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    // --- ADJUSTED ROLE SELECTION (Pill Segmented Control Style) ---
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Profile Category", required: true)
                        
                        // Role Selection: Player and Coach as segmented buttons
                        HStack(spacing: 0) {
                            roleSegmentPill(.player)
                            roleSegmentPill(.coach)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.gray.opacity(0.1)) // Light background for the control itself
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    // -------------------------------------------------------------

                    // Full Name
                    fieldLabel("Full Name", required: true)
                    roundedField {
                        TextField("", text: $fullName)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                            .textInputAutocapitalization(.words)
                    }
                    if let err = nameError, !fullName.isEmpty {
                        Text(err).font(.system(size: 13)).foregroundColor(.red)
                    }

                    // Email
                    fieldLabel("Email", required: true)
                    roundedField {
                        TextField("", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                            .focused($emailFocused)
                            .onChange(of: email) { _ in debouncedEmailCheck() }
                            .onSubmit { checkEmailImmediately() }
                    }
                    .onChange(of: emailFocused) { focused in if !focused { checkEmailImmediately() } }

                    Group {
                        if !email.isEmpty && !isEmailValid {
                            Text("Please enter a valid email address.")
                                .font(.system(size: 13)).foregroundColor(.red)
                        } else if emailExists {
                            Text("You already have an account. Please sign in.")
                                .font(.system(size: 13)).foregroundColor(.red)
                        } else if let err = emailCheckError, !err.isEmpty {
                            Text(err).font(.system(size: 13)).foregroundColor(.red)
                        }
                    }

                    // PHONE
                    fieldLabel("Phone number", required: true)
                    roundedField {
                        HStack(spacing: 10) {
                            Button { showDialPicker = true } label: {
                                HStack(spacing: 6) {
                                    Text(selectedDialCode.code)
                                        .font(.custom("Poppins", size: 16))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(primary)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(primary.opacity(0.08))
                                )
                            }

                            TextField("", text: Binding(
                                get: { phoneLocal },
                                set: { val in
                                    phoneNonDigitError = val.contains { !$0.isNumber }
                                    phoneLocal = val.filter { $0.isNumber }
                                }
                            ))
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                        }
                    }
                    if phoneNonDigitError {
                        Text("Numbers only (0–9).").font(.system(size: 13)).foregroundColor(.red)
                    } else if !phoneLocal.isEmpty && !isPhoneValid {
                        Text("Enter a valid phone number.").font(.system(size: 13)).foregroundColor(.red)
                    }

                    // DOB
                    fieldLabel("Date of birth", required: true)
                    buttonLikeField(action: {
                        tempDOB = dob ?? Date()
                        showDOBPicker = true
                    }) {
                        HStack {
                            Text(dob.map { formatDate($0) } ?? "")
                                .font(.custom("Poppins", size: 16))
                                .foregroundColor(primary)
                            Spacer()
                            Image(systemName: "calendar")
                                .foregroundColor(primary.opacity(0.85))
                        }
                        .frame(height: 22)
                    }
                    .sheet(isPresented: $showDOBPicker) {
                        DateWheelPickerSheet(selection: $dob, tempSelection: $tempDOB, showSheet: $showDOBPicker)
                            .presentationDetents([.height(300)])
                            .presentationBackground(.white)
                            .presentationCornerRadius(28)
                    }

                    // Password
                    fieldLabel("Password", required: true)
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
                                Image(systemName: isHidden ? "eye.slash" : "eye")
                                    .foregroundColor(primary.opacity(0.6))
                            }
                        }
                    }

                    // Password criteria bullets (gray → green)
                    VStack(alignment: .leading, spacing: 6) {
                        passwordRuleRow("At least 8 characters", satisfied: pHasLen)
                        passwordRuleRow("At least one uppercase letter (A–Z)", satisfied: pHasUpper)
                        passwordRuleRow("At least one lowercase letter (a–z)", satisfied: pHasLower)
                        passwordRuleRow("At least one number (0–9)", satisfied: pHasDigit)
                        passwordRuleRow("At least one special symbol", satisfied: pHasSpec)
                    }
                    .padding(.top, -8)

                    // Submit
                    Button { Task { await handleSignUp() } } label: {
                        HStack(spacing: 10) {
                            Text("Sign Up").font(.custom("Poppins", size: 18)).foregroundColor(.white)
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
                            .foregroundColor(primary.opacity(0.7))
                        NavigationLink { EmptyView() /*SignInView()*/ } label: {
                            Text("Sign in")
                                .font(.custom("Poppins", size: 15)).fontWeight(.semibold).foregroundColor(primary)
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
        .navigationDestination(isPresented: $goToPlayerSetup) {PlayerSetupView() }
        .onDisappear { verifyTask?.cancel(); resendTimerTask?.cancel(); emailCheckTask?.cancel() }
        .sheet(isPresented: $showDialPicker) {
            CountryCodePickerSheet(selected: $selectedDialCode, primary: primary)
        }
    }

    // MARK: - Full name validation (last name optional)
    private func fullNameValidationError(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Please enter your name." }

        let parts = trimmed.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }

        // Only letters (allow . ' -)
        let unitRegex = try! NSRegularExpression(pattern: #"^[\p{L}.'-]+$"#, options: [])
        for p in parts {
            let range = NSRange(location: 0, length: (p as NSString).length)
            if unitRegex.firstMatch(in: p, options: [], range: range) == nil {
                return "Letters only for your first/last name."
            }
        }

        // Allow 1 or 2 parts, but not 3+
        if parts.count >= 3 { return "Please enter only your first and last name." }

        // Total length without spaces ≤ 60
        if trimmed.replacingOccurrences(of: " ", with: "").count > 60 {
            return "Full name must be ≤ 60 characters."
        }
        return nil
    }

    // MARK: - Email check (using Firebase Auth dummy user attempt)
    private func debouncedEmailCheck() {
        emailCheckTask?.cancel(); emailExists = false; emailCheckError = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(email) else { return }
        let mail = trimmed.lowercased()
        emailCheckTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            let testPassword = UUID().uuidString + "Aa1!"
            do {
                let result = try await Auth.auth().createUser(withEmail: mail, password: testPassword)
                try? await result.user.delete()
                await MainActor.run { if !Task.isCancelled { emailExists = false } }
            } catch {
                let ns = error as NSError
                await MainActor.run { if !Task.isCancelled { emailExists = (ns.code == AuthErrorCode.emailAlreadyInUse.rawValue) } }
            }
        }
    }
    private func checkEmailImmediately() {
        emailCheckTask?.cancel(); emailExists = false; emailCheckError = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(email) else { return }
        let mail = trimmed.lowercased()
        emailCheckTask = Task {
            let testPassword = UUID().uuidString + "Aa1!"
            do {
                let result = try await Auth.auth().createUser(withEmail: mail, password: testPassword)
                try? await result.user.delete()
                await MainActor.run { if !Task.isCancelled { emailExists = false } }
            } catch {
                let ns = error as NSError
                await MainActor.run { if !Task.isCancelled { emailExists = (ns.code == AuthErrorCode.emailAlreadyInUse.rawValue) } }
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
        let fullPhone = selectedDialCode.code + phoneLocal

        do {
            // 1) Create user
            let authResult = try await Auth.auth().createUser(withEmail: mail, password: password)

            // 2) Optional displayName
            let changeReq = authResult.user.createProfileChangeRequest()
            changeReq.displayName = name
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                changeReq.commitChanges { err in if let err = err { cont.resume(throwing: err) } else { cont.resume() } }
            }

            // 3) Save local draft (includes phone)
            let draft = ProfileDraft(fullName: name, phone: fullPhone, role: role.rawValue.lowercased(), dob: dob, email: mail)
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
            let (first, last) = firstLast(from: draft.fullName) // last can be nil
            var data: [String: Any] = [
                "email": user.email ?? draft.email,
                "firstName": first,
                "lastName": last ?? NSNull(),
                "role": draft.role,
                "emailVerified": true,
                "phone": draft.phone,
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
            inlineVerifyError = "Please wait \(max(0, resendCooldown)) seconds before resending."
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
            user.sendEmailVerification(with: acs) { err in if let err = err { cont.resume(throwing: err) } else { cont.resume() } }
        }
    }

    // MARK: - Resend cooldown
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
        let now  = Int(Date().timeIntervalSince1970)
        return (now - last) >= resendCooldownSeconds
    }
    private func markVerificationSentNow() {
        let now = Int(Date().timeIntervalSince1970)
        UserDefaults.standard.set(now, forKey: lastSentKey)
    }

    // MARK: - Validators
    private func isValidEmail(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        if value.contains("..") { return false }
        let pattern = #"^(?![.])([A-Za-z0-9._%+-]{1,64})(?<![.])@([A-Za-z0-9-]{1,63}\.)+[A-Za-z]{2,63}$"#
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: value)
    }
    private func isValidPhone(code: String, local: String) -> Bool {
        guard !local.isEmpty else { return false }
        let len = local.count
        var ok = (6...15).contains(len)
        if code == "+966" { ok = (len == 9) && local.first == "5" } // KSA rule
        return ok
    }

    // MARK: - Helpers

    // --- NEW roleSegmentPill Helper ---
    private func roleSegmentPill(_ r: UserRole) -> some View {
        let isSelected = role == r
        
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                role = r
            }
        } label: {
            Text(r.rawValue)
                .font(.custom("Poppins", size: 16))
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundColor(isSelected ? .white : primary.opacity(0.8))
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? primary : Color.clear)
                )
                .padding(2) // Inner padding to show the gray background of the main HStacK
        }
    }
    // -----------------------------------
    
    // Original rolePill is now removed/replaced

    private func fieldLabel(_ title: String, required: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.custom("Poppins", size: 14)).foregroundColor(primary.opacity(0.75))
            if required {
                Text("*").font(.system(size: 12, weight: .bold)).foregroundColor(.red).padding(.top, -2)
            }
        }
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
    private func passwordRuleRow(_ text: String, satisfied: Bool) -> some View {
        let color = satisfied ? primary : Color.gray.opacity(0.7)
        let icon  = satisfied ? "checkmark.circle.fill" : "circle"
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon).foregroundColor(color)
            Text(text).font(.system(size: 13)).foregroundColor(color)
        }
    }
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; return f.string(from: date)
    }
    private func firstLast(from full: String) -> (String, String?) {
        let parts = full.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
        let first = parts.first ?? ""
        let last  = parts.count >= 2 ? parts[1] : nil
        return (first, last)
    }
}


// MARK: - Verify sheet
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
                .padding(.horizontal, 8).padding(.top, 6)

                Text("Verify your email")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)

                Text("We’ve sent a verification link to \(email).\nOpen the link to verify your email so you can continue sign-up and complete your profile.")
                    .font(.system(size: 14)).foregroundColor(.secondary)
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
                        .padding(.horizontal, 16).padding(.top, 2)
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
        .padding().background(Color.clear)
    }
}
