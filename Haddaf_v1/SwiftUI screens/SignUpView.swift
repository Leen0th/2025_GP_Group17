import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Foundation

// MARK: - User Role
enum UserRole: String { case player = "Player", coach = "Coach" }

// MARK: - Sign Up
struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AppSession
    
    // Theme
    private let primary = BrandColors.darkTeal
    private let bg = BrandColors.backgroundGradientEnd
    private let emailActionURL = "https://haddaf-db.web.app/__/auth/action"
    
    // Coach Fields
    @State private var coachLocation = ""
    @State private var hasTeam = true
    @State private var verificationFile: URL? = nil
    @State private var verificationFileName = ""
    @State private var showVerificationInfo = false
    @State private var showFileImporter = false
    @State private var isUploadingVerification = false
    @State private var showCoachLocationPicker = false
    
    // Navigation for Coach
    @State private var goToCoachTeamSetup = false
    @State private var goToDiscovery = false
    
    // Fields
    @State private var role: UserRole = .player
    @State private var fullName = ""
    @State private var email = ""
    private let selectedDialCode = "+966"
    @State private var phoneLocal = ""
    @State private var phoneNonDigitError = false
    @State private var password = ""
    @State private var isHidden = true
    @State private var dob: Date? = nil
    @State private var showDOBPicker = false
    @State private var tempDOB = Date()
    @State private var ageWarning: String? = nil
    
    // NEW: Parent/Guardian email for minors
    @State private var parentEmail = ""
    @State private var requiresParentConsent = false
    @FocusState private var parentEmailFocused: Bool
    
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
    
    // NEW: Parent email validation
    @State private var parentEmailExists = false
    @State private var parentEmailCheckError: String? = nil
    @State private var parentEmailCheckTask: Task<Void, Never>? = nil
    
    // Track if user attempted to submit
    @State private var attemptedSubmit = false
    
    // Password criteria
    private var pHasLen: Bool { password.count >= 8 && password.count <= 30 }
    private var isPasswordTooLong: Bool { password.count > 30 }
    private var pHasUpper: Bool { password.range(of: "[A-Z]", options: .regularExpression) != nil }
    private var pHasLower: Bool { password.range(of: "[a-z]", options: .regularExpression) != nil }
    private var pHasDigit: Bool { password.range(of: "[0-9]", options: .regularExpression) != nil }
    private var pHasSpec: Bool { password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil }
    
    // Full name validation/error (last name optional)
    private var nameError: String? { fullNameValidationError(fullName) }
    
    // Validation
    private var isNameValid: Bool { nameError == nil && !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isPasswordValid: Bool { pHasLen && pHasUpper && pHasLower && pHasDigit && pHasSpec }
    private var isEmailValid: Bool { !requiresParentConsent || isValidEmail(email) }
    private var isPhoneValid: Bool { isValidPhone(code: selectedDialCode, local: phoneLocal) }
    private var isParentEmailValid: Bool {
        !requiresParentConsent || isValidEmail(parentEmail)
    }
    
    private var isFormValid: Bool {
        if role == .player {
            return isPlayerFormValid
        } else {
            return isCoachFormValid
        }
    }
    
    private var isPlayerFormValid: Bool {
        isNameValid && isPasswordValid && (requiresParentConsent ? isParentEmailValid : isEmailValid) && isPhoneValid && dob != nil && !emailExists && !parentEmailExists
    }
    
    private var isCoachFormValid: Bool {
        isNameValid && isPasswordValid && isEmailValid && !coachLocation.isEmpty && verificationFile != nil && !emailExists
    }
    
    // Computed property to get missing required fields
    private var missingFields: [String] {
        var missing: [String] = []
        if !isNameValid { missing.append("Full Name") }
        if !isPasswordValid { missing.append("Password") }
        
        if role == .player {
            if requiresParentConsent {
                if !isParentEmailValid { missing.append("Parent/Guardian Email") }
            } else {
                if !isEmailValid { missing.append("Email") }
            }
            if !isPhoneValid { missing.append("Phone number") }
            if dob == nil { missing.append("Date of birth") }
        } else { // Coach
            if emailExists { missing.append("Email (already in use)") }
            if !isEmailValid { missing.append("Email") }
            if coachLocation.isEmpty { missing.append("Location") }
            if verificationFile == nil { missing.append("Verification File") }
        }
        
        return missing
    }
    
    // Date range properties
    private var minAgeDate: Date {
        Calendar.current.date(byAdding: .year, value: -7, to: Date())!
    }
    private var maxAgeDate: Date {
        Calendar.current.date(byAdding: .year, value: -100, to: Date())!
    }
    
    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Sign Up")
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                    
                    // Role
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Profile Category", required: true)
                        HStack(spacing: 0) {
                            roleSegmentPill(.player)
                            roleSegmentPill(.coach)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(BrandColors.lightGray.opacity(0.7))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    
                    if role == .player {
                        // Full Name
                        fieldLabel("Full Name", required: true)
                        roundedField {
                            TextField("", text: $fullName)
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(primary)
                                .tint(primary)
                                .textInputAutocapitalization(.words)
                        }
                        if let err = nameError, !fullName.isEmpty {
                            Text(err)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.red)
                        }
                        
                        // Email
                        if !requiresParentConsent {
                            fieldLabel("Email", required: true)
                            roundedField {
                                TextField("", text: $email)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundColor(primary)
                                    .tint(primary)
                                    .focused($emailFocused)
                                    .onSubmit { checkEmailImmediately() }
                            }
                            .onChange(of: emailFocused) { focused in
                                if !focused {
                                    checkEmailImmediately()
                                }
                            }
                            Group {
                                if !email.isEmpty && !isValidEmail(email) {
                                    Text("Please enter a valid email address (name@domain).")
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundColor(.red)
                                } else if emailExists {
                                    Text("You already have an account. Please sign in.")
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundColor(.red)
                                } else if let err = emailCheckError, !err.isEmpty {
                                    Text(err)
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        // PHONE
                        fieldLabel("Phone number", required: true)
                        roundedField {
                            HStack(spacing: 10) {
                                Text(selectedDialCode)
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundColor(primary)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(primary.opacity(0.08))
                                    )
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
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(primary)
                                .tint(primary)
                            }
                        }
                        if phoneNonDigitError {
                            Text("Numbers only (0–9).")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.red)
                        } else if !phoneLocal.isEmpty && !isValidPhone(code: selectedDialCode, local: phoneLocal) {
                            Text("Enter a valid Saudi number (starts with 5, 9 digits).")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.red)
                        }
                        
                        // DOB
                        fieldLabel("Date of birth", required: true)
                        buttonLikeField(action: {
                            tempDOB = dob ?? minAgeDate
                            showDOBPicker = true
                        }) {
                            HStack {
                                Text(dob.map { formatDate($0) } ?? "")
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundColor(primary)
                                Spacer()
                                Image(systemName: "calendar").foregroundColor(primary.opacity(0.85))
                            }
                            .frame(height: 22)
                        }
                        .sheet(isPresented: $showDOBPicker) {
                            DateWheelPickerSheet(
                                selection: $dob,
                                tempSelection: $tempDOB,
                                showSheet: $showDOBPicker,
                                in: maxAgeDate...minAgeDate
                            )
                            .presentationDetents([.height(300)])
                            .presentationBackground(BrandColors.background)
                            .presentationCornerRadius(28)
                        }
                        
                        // Show age warning
                        if let ageWarning = ageWarning {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(Color.orange)
                                    .font(.system(size: 14))
                                    .padding(.top, 2)
                                Text(ageWarning)
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(Color.orange.opacity(0.9))
                            }
                            .padding(.top, -10)
                        }
                        
                        // NEW: Parent/Guardian Email (shown only for ages 7-12)
                        if requiresParentConsent {
                            VStack(alignment: .leading, spacing: 8) {
                                fieldLabel("Parent/Guardian Email", required: true)
                                roundedField {
                                    TextField("", text: $parentEmail)
                                        .keyboardType(.emailAddress)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .font(.system(size: 16, design: .rounded))
                                        .foregroundColor(primary)
                                        .tint(primary)
                                        .focused($parentEmailFocused)
                                        .onSubmit { checkParentEmailImmediately() }
                                }
                                .onChange(of: parentEmailFocused) { focused in
                                    if !focused {
                                        checkParentEmailImmediately()
                                    }
                                }
                                
                                // Important notice for children
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(Color.orange)
                                        .font(.system(size: 14))
                                        .padding(.top, 2)
                                    Text("Your account will be created using your parent/guardian's email address. When signing in later, you will need to use their email and the password you set below.")
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundColor(Color.orange.opacity(0.9))
                                }
                                .padding(.top, -4)
                                
                                // Validation errors
                                Group {
                                    if !parentEmail.isEmpty && !isValidEmail(parentEmail) {
                                        Text("Please enter a valid email address (name@domain).")
                                            .font(.system(size: 13, design: .rounded))
                                            .foregroundColor(.red)
                                    } else if parentEmailExists {
                                        Text("This email is already registered. Please use a different email.")
                                            .font(.system(size: 13, design: .rounded))
                                            .foregroundColor(.red)
                                    } else if let err = parentEmailCheckError, !err.isEmpty {
                                        Text(err)
                                            .font(.system(size: 13, design: .rounded))
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                        
                        // Password
                        fieldLabel("Password", required: true)
                        roundedField {
                            ZStack(alignment: .trailing) {
                                if isHidden {
                                    SecureField("", text: $password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .font(.system(size: 16, design: .rounded))
                                        .foregroundColor(primary)
                                        .padding(.trailing, 44)
                                } else {
                                    TextField("", text: $password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .font(.system(size: 16, design: .rounded))
                                        .foregroundColor(primary)
                                        .padding(.trailing, 44)
                                }
                                Button { withAnimation { isHidden.toggle() } } label: {
                                    Image(systemName: isHidden ? "eye.slash" : "eye")
                                        .foregroundColor(primary.opacity(0.6))
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            passwordRuleRow("At least 8 characters, max 30", satisfied: pHasLen)
                            passwordRuleRow("At least one uppercase letter (A–Z)", satisfied: pHasUpper)
                            passwordRuleRow("At least one lowercase letter (a–z)", satisfied: pHasLower)
                            passwordRuleRow("At least one number (0–9)", satisfied: pHasDigit)
                            passwordRuleRow("At least one special symbol", satisfied: pHasSpec)
                        }
                        .padding(.top, -8)
                        if isPasswordTooLong {
                            Text("Password must be 30 characters or less.")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.red)
                                .padding(.top, 4)
                        }
                        
                        // Show missing fields warning if user tried to submit
                        if attemptedSubmit && !isFormValid {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 16))
                                    Text("Please complete the following required fields:")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(.orange.opacity(0.9))
                                }
                                ForEach(missingFields, id: \.self) { field in
                                    HStack(spacing: 6) {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 6))
                                            .foregroundColor(.orange.opacity(0.7))
                                        Text(field)
                                            .font(.system(size: 13, design: .rounded))
                                            .foregroundColor(.orange.opacity(0.8))
                                    }
                                    .padding(.leading, 24)
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.orange.opacity(0.1))
                            )
                            .padding(.top, 4)
                        }
                        
                        // Submit
                        Button {
                            attemptedSubmit = true
                            if isFormValid {
                                Task { await handleSignUp() }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text("Sign Up")
                                    .font(.system(size: 18, weight: .medium, design: .rounded))
                                    .foregroundColor(.white)
                                if isSubmitting { ProgressView().colorInvert().scaleEffect(0.9) }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isFormValid && !isSubmitting ? primary : primary.opacity(0.5))
                            .clipShape(Capsule())
                            .shadow(color: (isFormValid && !isSubmitting) ? primary.opacity(0.3) : .clear, radius: 10, y: 5)
                        }
                        .padding(.top, 8)
                        .disabled(isSubmitting)
                        
                        // Bottom link
                        HStack(spacing: 6) {
                            Text("Already have an account?")
                                .font(.system(size: 15, design: .rounded))
                                .foregroundColor(primary.opacity(0.7))
                            NavigationLink { SignInView() } label: {
                                Text("Sign in")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(primary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 6)
                    } else {
                        coachSignupForm
                    }
                }
                .onChange(of: role) { _ in
                    fullName = ""
                    email = ""
                    phoneLocal = ""
                    password = ""
                    dob = nil
                    parentEmail = ""
                    requiresParentConsent = false
                    ageWarning = nil
                    phoneNonDigitError = false
                    emailExists = false
                    parentEmailExists = false
                    coachLocation = ""
                    hasTeam = true
                    verificationFile = nil
                    verificationFileName = ""
                    showVerificationInfo = false
                    attemptedSubmit = false
                    inlineVerifyError = nil
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            
            // Overlay verify popup
            if showVerifyPrompt {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                SimpleVerifySheet(
                    email: requiresParentConsent ?
                        parentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() :
                        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    primary: primary,
                    resendCooldown: $resendCooldown,
                    errorText: $inlineVerifyError,
                    isParentVerification: requiresParentConsent,
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
        .navigationDestination(isPresented: $goToCoachTeamSetup) { CoachTeamSetupView(hasTeam: hasTeam) }
        .navigationDestination(isPresented: $goToDiscovery) { PlayerProfileView() }
        .onDisappear {
            verifyTask?.cancel()
            resendTimerTask?.cancel()
            emailCheckTask?.cancel()
            parentEmailCheckTask?.cancel()
        }
        .onChange(of: dob) { _, newDOB in
            guard let newDOB = newDOB else {
                ageWarning = nil
                requiresParentConsent = false
                return
            }
            let age = calculateAge(from: newDOB)
            if (7...12).contains(age) {
                ageWarning = "You are recommended to use this app with parental supervision."
                requiresParentConsent = true
                // Clear child email when parent consent is required
                email = ""
            } else {
                ageWarning = nil
                requiresParentConsent = false
                parentEmail = ""
            }
        }
    }
    
    // Helper function to calculate age
    private func calculateAge(from dob: Date) -> Int {
        return Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
    }
    
    private func fetchRole(for uid: String) async -> String? {
        do {
            let doc = try await Firestore.firestore().collection("users").document(uid).getDocument()
            return doc.data()?["role"] as? String
        } catch {
            print("Error fetching role: \(error)")
            return nil
        }
    }
    
    // MARK: - Full name validation
    private func fullNameValidationError(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Please enter your name." }
        let parts = trimmed.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
        let unitRegex = try! NSRegularExpression(pattern: #"^[\p{L}.'-]+$"#, options: [])
        for p in parts {
            let range = NSRange(location: 0, length: (p as NSString).length)
            if unitRegex.firstMatch(in: p, options: [], range: range) == nil {
                return "Letters only for your first/last name."
            }
        }
        if parts.count >= 3 { return "Please enter only your first and last name." }
        if trimmed.replacingOccurrences(of: " ", with: "").count > 35 {
            return "Full name must not exceed 35 characters"
        }
        return nil
    }
    
    // MARK: - Email check (child email) - فقط لو ما كان طفل
    private func checkEmailImmediately() {
        guard !requiresParentConsent else { return }
        
        emailCheckTask?.cancel()
        emailExists = false
        emailCheckError = nil
        
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(trimmed) else { return }
        
        let mail = trimmed.lowercased()
        
        emailCheckTask = Task {
            do {
                let methods = try await Auth.auth().fetchSignInMethods(forEmail: mail)
                await MainActor.run {
                    if !Task.isCancelled {
                        self.emailExists = !methods.isEmpty
                    }
                }
            } catch {
                let ns = error as NSError
                await MainActor.run {
                    if !Task.isCancelled {
                        self.emailCheckError = ns.localizedDescription
                    }
                }
            }
        }
    }
    
    // MARK: - Parent email check
    private func checkParentEmailImmediately() {
        parentEmailCheckTask?.cancel()
        parentEmailExists = false
        parentEmailCheckError = nil
        
        let trimmed = parentEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(trimmed) else { return }
        
        let mail = trimmed.lowercased()
        
        parentEmailCheckTask = Task {
            do {
                let methods = try await Auth.auth().fetchSignInMethods(forEmail: mail)
                await MainActor.run {
                    if !Task.isCancelled {
                        self.parentEmailExists = !methods.isEmpty
                    }
                }
            } catch {
                let ns = error as NSError
                await MainActor.run {
                    if !Task.isCancelled {
                        self.parentEmailCheckError = ns.localizedDescription
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    private func handleSignUp() async {
        if emailExists || (requiresParentConsent && parentEmailExists) { return }
        guard isFormValid else { return }
        isSubmitting = true
        inlineVerifyError = nil
        
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let childEmail = requiresParentConsent ? "" : email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fullPhone = selectedDialCode + phoneLocal
        
        let accountEmail = requiresParentConsent ?
        parentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() :
        childEmail
        
        do {
            // 1) Create account with parent's email if child needs consent
            let authResult = try await Auth.auth().createUser(withEmail: accountEmail, password: password)
            let uid = authResult.user.uid
            
            // 2) Set the display name
            let changeReq = authResult.user.createProfileChangeRequest()
            changeReq.displayName = name
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                changeReq.commitChanges { err in
                    if let err = err { cont.resume(throwing: err) }
                    else { cont.resume() }
                }
            }
            
            var finalVerificationURL = ""

            // If it is a coach, upload the file now
            if role == .coach, let localFileURL = verificationFile {
                // Call the helper we added above
                finalVerificationURL = try await uploadVerificationToStorage(userId: uid, fileURL: localFileURL)
            }
            
            // 3) Store draft
            var draftData: [String: Any] = [
                "fullName": name,
                "phone": fullPhone,
                "role": role.rawValue.lowercased(),
                "accountEmail": accountEmail
            ]
            
            if role == .player {
                let fullPhone = selectedDialCode + phoneLocal
                draftData["phone"] = fullPhone
                if let d = dob {
                    draftData["dob"] = d.timeIntervalSince1970
                }
                if requiresParentConsent {
                    draftData["parentEmail"] = accountEmail
                    draftData["requiresParentConsent"] = true
                }
            } else { // Coach
                draftData["location"] = coachLocation
                draftData["hasTeam"] = hasTeam
                draftData["verificationFile"] = finalVerificationURL
            }
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: draftData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                UserDefaults.standard.set(jsonString, forKey: "profile_draft")
            }
            
            // 4) Send verification email
            try await sendVerificationEmail(to: authResult.user)
            markVerificationSentNow()
            startResendCooldown(seconds: resendCooldownSeconds)
            
            // 5) Show verification sheet
            await MainActor.run { showVerifyPrompt = true }
            startVerificationWatcher()
            
        } catch {
            let ns = error as NSError
            if ns.code == AuthErrorCode.emailAlreadyInUse.rawValue {
                if requiresParentConsent {
                    parentEmailExists = true
                } else {
                    emailExists = true
                }
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
        do {
            try await user.reload()
            _ = try await user.getIDTokenResult(forcingRefresh: true)
        } catch { }
        
        // Load draft and save to Firestore
        if let jsonString = UserDefaults.standard.string(forKey: "profile_draft"),
           let jsonData = jsonString.data(using: .utf8),
           let draft = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            
            let db = Firestore.firestore()
            
            let fullName = draft["fullName"] as? String ?? ""
            let parts = fullName.split(separator: " ").map(String.init)
            let first = parts.first ?? ""
            let last = parts.count >= 2 ? parts[1] : ""
            
            let accountEmail = draft["accountEmail"] as? String ?? user.email ?? ""
            let roleString = draft["role"] as? String ?? "player"
            
            var data: [String: Any] = [
                "email": accountEmail,
                "firstName": first,
                "lastName": last.isEmpty ? NSNull() : last,
                "role": roleString,
                "emailVerified": true,
                "isActive": true,
                "createdAt": FieldValue.serverTimestamp()
            ]
            if roleString == "player" {
                data["phone"] = draft["phone"] as? String ?? ""
                if let dobTimestamp = draft["dob"] as? TimeInterval {
                    data["dob"] = Timestamp(date: Date(timeIntervalSince1970: dobTimestamp))
                }
                if let parentEmail = draft["parentEmail"] as? String {
                    data["parentEmail"] = parentEmail
                    data["requiresParentConsent"] = true
                }
            } else { // Coach
                data["location"] = draft["location"] as? String ?? ""
                data["verificationFile"] = draft["verificationFile"] as? String ?? ""
                data["hasTeam"] = draft["hasTeam"] as? Bool ?? false
            }
            
            try? await Firestore.firestore().collection("users").document(user.uid).setData(data, merge: true)
            
            // Admin Approval Request for Coaches
            if roleString == "coach" {
                let requestData: [String: Any] = [
                    "uid": user.uid,
                    "fullName": fullName,
                    "email": accountEmail,
                    "status": "pending",
                    "submittedAt": FieldValue.serverTimestamp(),
                    "verificationFile": draft["verificationFile"] as? String ?? ""
                ]
                
                // We use user.uid as the document ID so we can find it easily later
                try? await db.collection("coachRequests").document(user.uid).setData(requestData)
            }
            
            UserDefaults.standard.removeObject(forKey: "profile_draft")
            
            session.user = user
            session.isGuest = false
            showVerifyPrompt = false
            session.role = roleString
            // Coaches start unverified until admin clicks approve
            session.isVerifiedCoach = (roleString == "admin")
            
            
            // Post notification (keeps app state in sync)
            NotificationCenter.default.post(
                name: .userSignedIn,
                object: nil,
                userInfo: [
                    "role": roleString,
                    "hasTeam": draft["hasTeam"] as? Bool ?? false
                ]
            )
            
            // MARK: - Navigation Logic
            if roleString == "coach" {
                let coachHasTeam = draft["hasTeam"] as? Bool ?? false
                if coachHasTeam {
                    // Redirect to Team Setup
                    goToCoachTeamSetup = true
                } else {
                    // No team, go directly to Discovery
                    goToDiscovery = true
                }
            } else {
                // For players, proceed to Player Setup
                goToPlayerSetup = true
            }
        }
    }
    
    private func resendVerification() async {
        guard let user = Auth.auth().currentUser else { return }
        guard resendCooldown == 0 else {
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
        if let bundleID = Bundle.main.bundleIdentifier {
            acs.setIOSBundleID(bundleID)
        }
        
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            user.sendEmailVerification(with: acs) { err in
                if let err = err { cont.resume(throwing: err) }
                else { cont.resume() }
            }
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
        if code == "+966" { ok = (len == 9) && local.first == "5" }
        return ok
    }
    
    // MARK: - Helpers
    private func roleSegmentPill(_ r: UserRole) -> some View {
        let isSelected = role == r
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { role = r }
        } label: {
            Text(r.rawValue)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundColor(isSelected ? .white : primary.opacity(0.8))
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? primary : Color.clear)
                        .shadow(color: isSelected ? primary.opacity(0.3) : .clear, radius: 8, y: 4)
                )
                .padding(2)
        }
    }
    
    // MARK: - Storage Helper
    private func uploadVerificationToStorage(userId: String, fileURL: URL) async throws -> String {
        let storage = Storage.storage()
        // Create a reference: coach_verifications/USER_ID/filename
        let ref = storage.reference().child("coach_verifications/\(userId)/\(fileURL.lastPathComponent)")
        
        // We must access the security scoped resource to read the file
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { fileURL.stopAccessingSecurityScopedResource() }
        }
        
        let data = try Data(contentsOf: fileURL)
        
        // Upload
        _ = try await ref.putDataAsync(data)
        
        // Get the download URL (The http link the admin can click)
        let downloadURL = try await ref.downloadURL()
        return downloadURL.absoluteString
    }
    
    private func fieldLabel(_ title: String, required: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(primary.opacity(0.75))
            if required {
                Text("*")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.red).padding(.top, -2)
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
                    .fill(BrandColors.background)
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
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
                        .fill(BrandColors.background)
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                )
        }
    }
    
    private func passwordRuleRow(_ text: String, satisfied: Bool) -> some View {
        let color = satisfied ? primary : Color.gray.opacity(0.7)
        let icon  = satisfied ? "checkmark.circle.fill" : "circle"
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon).foregroundColor(color)
            Text(text)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(color)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: date)
    }
    
    
    private var coachSignupForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Full Name
            fieldLabel("Full Name", required: true)
            roundedField {
                TextField("", text: $fullName)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(primary)
                    .tint(primary)
                    .textInputAutocapitalization(.words)
            }
            if let err = nameError, !fullName.isEmpty {
                Text(err)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.red)
            }
            
            // Email
            fieldLabel("Email", required: true)
            roundedField {
                TextField("", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(primary)
                    .tint(primary)
                    .focused($emailFocused)
                    .onSubmit { checkEmailImmediately() }
                    .onChange(of: emailFocused) { focused in
                        if !focused {
                            checkEmailImmediately()
                        }
                    }
            }
            Group {
                if !email.isEmpty && !isValidEmail(email) {
                    Text("Please enter a valid email address (name@domain).")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.red)
                } else if emailExists {
                    Text("You already have an account. Please sign in.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.red)
                } else if let err = emailCheckError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.red)
                }
            }
            
            // Password
            fieldLabel("Password", required: true)
            roundedField {
                ZStack(alignment: .trailing) {
                    if isHidden {
                        SecureField("", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(primary)
                            .padding(.trailing, 44)
                    } else {
                        TextField("", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(primary)
                            .padding(.trailing, 44)
                    }
                    Button { withAnimation { isHidden.toggle() } } label: {
                        Image(systemName: isHidden ? "eye.slash" : "eye")
                            .foregroundColor(primary.opacity(0.6))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                passwordRuleRow("At least 8 characters, max 30", satisfied: pHasLen)
                passwordRuleRow("At least one uppercase letter (A–Z)", satisfied: pHasUpper)
                passwordRuleRow("At least one lowercase letter (a–z)", satisfied: pHasLower)
                passwordRuleRow("At least one number (0–9)", satisfied: pHasDigit)
                passwordRuleRow("At least one special symbol", satisfied: pHasSpec)
            }
            .padding(.top, -8)
            if isPasswordTooLong {
                Text("Password must be 30 characters or less.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
            
            // Location
            fieldLabel("Location", required: true)
            buttonLikeField(action: { showCoachLocationPicker = true }) {
                HStack {
                    Text(coachLocation.isEmpty ? "Select city" : coachLocation)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(coachLocation.isEmpty ? .gray : primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(primary.opacity(0.85))
                }
            }
            .sheet(isPresented: $showCoachLocationPicker) {
                LocationPickerSheet(
                    title: "Select your city",
                    allCities: SAUDI_CITIES,
                    selection: $coachLocation,
                    searchText: .constant(""),
                    showSheet: $showCoachLocationPicker,
                    accent: primary
                )
            }
            
            // Verification File
            VStack(alignment: .leading, spacing: 8) {
                // Label with (i) icon
                HStack(spacing: 4) {
                    Text("Verification Document")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(primary.opacity(0.75))
                    
                    Text("*")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                        .padding(.top, -2)
                    
                    // The Info Button
                    Button {
                        showVerificationInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 15))
                            .foregroundColor(primary)
                    }
                }
                .alert("Verification Help", isPresented: $showVerificationInfo) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Upload a file (PDF or Image) to verify you are a coach.")
                }

                // The Upload Button
                buttonLikeField(action: { showFileImporter = true }) {
                    HStack {
                        Image(systemName: verificationFile == nil ? "doc.badge.plus" : "doc.fill")
                            .foregroundColor(primary)
                        
                        Text(verificationFileName.isEmpty ? "Upload Document" : verificationFileName)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(verificationFile == nil ? .gray : primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        if verificationFile != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(BrandColors.actionGreen)
                        } else {
                            Image(systemName: "arrow.up.doc")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [.pdf, .image],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let selectedURL = urls.first else { return }
                        // Optionally, start accessing the file securely
                        if selectedURL.startAccessingSecurityScopedResource() {
                            defer { selectedURL.stopAccessingSecurityScopedResource() }
                            verificationFile = selectedURL
                            verificationFileName = selectedURL.lastPathComponent
                        }
                    case .failure(let error):
                        print("File import error: \(error.localizedDescription)")
                        // Optionally, show an alert or set an error state
                    }
                }
            }
            
            // Has Team Toggle
            Toggle(isOn: $hasTeam) {
                Text("I have a team I am coaching")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(primary)
            }
            .tint(primary)
            
            // Show missing fields warning if user tried to submit
            if attemptedSubmit && !missingFields.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 16))
                        Text("Please complete the following required fields:")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.orange.opacity(0.9))
                    }
                    ForEach(missingFields, id: \.self) { field in
                        HStack(spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundColor(.orange.opacity(0.7))
                            Text(field)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.orange.opacity(0.8))
                        }
                        .padding(.leading, 24)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                )
                .padding(.top, 4)
            }

            // Submit
            Button {
                attemptedSubmit = true
                if isFormValid {
                    Task { await handleSignUp() }
                }
            } label: {
                HStack(spacing: 10) {
                    Text("Sign Up")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                    if isSubmitting { ProgressView().colorInvert().scaleEffect(0.9) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isFormValid && !isSubmitting ? primary : primary.opacity(0.5))
                .clipShape(Capsule())
                .shadow(color: (isFormValid && !isSubmitting) ? primary.opacity(0.3) : .clear, radius: 10, y: 5)
            }
            .padding(.top, 8)
            .disabled(isSubmitting)

            // Bottom link
            HStack(spacing: 6) {
                Text("Already have an account?")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(primary.opacity(0.7))
                NavigationLink { SignInView() } label: {
                    Text("Sign in")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
        }
        
    }
}


// MARK: - Verify sheet
struct SimpleVerifySheet: View {
    let email: String
    let primary: Color
    @Binding var resendCooldown: Int
    @Binding var errorText: String?
    var isParentVerification: Bool = false
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
                
                Text(isParentVerification ? "Parent/Guardian Verification" : "Verify your email")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(isParentVerification ?
                    "We've sent a verification link to \(email) (your parent/guardian's email).\n\nOnce they open the link and verify, your account will be automatically activated." :
                    "We've sent a verification link to \(email).\n\nOpen the link to verify your email so you can continue sign-up and complete your profile.")
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
                        .padding(.horizontal, 16).padding(.top, 2)
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
