import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - Edit Profile View
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var userProfile: UserProfile
    
    // MARK: - Local Form State
    @State private var name: String
    @State private var position: String
    @State private var weight: String
    @State private var height: String
    @State private var location: String
    @State private var email: String
    @State private var isEmailVisible: Bool
    @State private var profileImage: UIImage?
    @State private var dob: Date?
    
    // Phone
    private let selectedDialCode = CountryDialCode.saudi
    @State private var phoneLocal: String
    @State private var phoneNonDigitError = false
    @State private var isPhoneNumberVisible: Bool
    
    // MARK: - Sheets & Pickers
    @State private var showDOBPicker = false
    @State private var tempDOB = Date()
    @State private var showPositionPicker = false
    @State private var showLocationPicker = false
    @State private var locationSearch = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    // MARK: - Email Validation State
    @FocusState private var emailFocused: Bool
    @State private var emailExists = false
    @State private var emailCheckError: String? = nil
    @State private var emailCheckTask: Task<Void, Never>? = nil
    @State private var isCheckingEmail = false
    
    // MARK: - Verification Flow State
    @State private var showVerifyPrompt = false
    @State private var verifyTask: Task<Void, Never>? = nil
    @State private var resendCooldown = 0
    @State private var resendTimerTask: Task<Void, Never>? = nil
    @State private var inlineVerifyError: String? = nil
    private let resendCooldownSeconds = 60
    
    private let emailActionURL = "https://haddaf-db.web.app/__/auth/action"
    
    // MARK: - View Operation State
    @State private var isSaving = false
    @State private var showInfoOverlay = false
    @State private var overlayMessage = ""
    @State private var overlayIsError = false
    
    private let primary = BrandColors.darkTeal
    private let db = Firestore.firestore()
    private let positions = ["Attacker", "Midfielder", "Defender"]
    
    // MARK: - Validation Logic
    private var isEmailFieldValid: Bool { isValidEmail(email) }
    
    private var isPhoneNumberValid: Bool {
        isValidPhone(code: selectedDialCode.code, local: phoneLocal)
    }
    
    private var isNameValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = #"^[\p{L}][\p{L}\s.'-]*$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
    
    private var isWeightValid: Bool {
        guard let w = Int(weight) else { return false }
        return (15...200).contains(w)
    }
    
    private var isHeightValid: Bool {
        guard let h = Int(height) else { return false }
        return (100...230).contains(h)
    }
    
    // Valid only if standard fields are valid AND email is not taken AND we aren't currently checking
    private var isFormValid: Bool {
        isNameValid && isEmailFieldValid && isPhoneNumberValid &&
        isWeightValid && isHeightValid && !position.isEmpty &&
        !emailExists && !isCheckingEmail
    }
    
    init(userProfile: UserProfile) {
        self.userProfile = userProfile
        _name = State(initialValue: userProfile.name)
        _position = State(initialValue: userProfile.position)
        _weight = State(initialValue: userProfile.weight.replacingOccurrences(of: "kg", with: ""))
        _height = State(initialValue: userProfile.height.replacingOccurrences(of: "cm", with: ""))
        _location = State(initialValue: userProfile.location)
        _email = State(initialValue: userProfile.email)
        _isEmailVisible = State(initialValue: userProfile.isEmailVisible)
        _profileImage = State(initialValue: userProfile.profileImage)
        _dob = State(initialValue: userProfile.dob)
        
        let (parsedCode, parsedLocal) = parsePhoneNumber(userProfile.phoneNumber)
        _phoneLocal = State(initialValue: parsedLocal)
        
        _isPhoneNumberVisible = State(initialValue: userProfile.isPhoneNumberVisible)
    }

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    profilePictureSection
                    Divider()
                    formFields
                    togglesSection
                    updateButton
                        .padding(.top, 20)
                        .padding(.bottom)
                }
                .padding(.horizontal)
            }
            .opacity(showVerifyPrompt ? 0.2 : 1.0)
            
            // Success/Error Overlay
            if showInfoOverlay {
                InfoOverlay(primary: primary, title: overlayMessage, isError: overlayIsError, onOk: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showInfoOverlay = false }
                    if !overlayIsError { dismiss() }
                })
                .transition(.scale.combined(with: .opacity)).zIndex(2)
            }
            
            // Email Verification Overlay
            if showVerifyPrompt {
                Color.black.opacity(0.4).ignoresSafeArea()
                
                EditProfileVerifySheet(
                    email: email,
                    primary: primary,
                    resendCooldown: $resendCooldown,
                    errorText: $inlineVerifyError,
                    onResend: { Task { await resendVerification() } },
                    onClose: {
                        withAnimation { showVerifyPrompt = false }
                    }
                )
                .transition(.scale)
                .zIndex(3)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let newImage = UIImage(data: data) {
                    await MainActor.run { self.profileImage = newImage }
                }
            }
        }
        .onDisappear {
            verifyTask?.cancel()
            resendTimerTask?.cancel()
            emailCheckTask?.cancel()
        }
    }

    // MARK: - View Builders
    private var header: some View {
        ZStack {
            Text("Edit Profile")
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundColor(primary)
            
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                        .foregroundColor(primary).padding(10).background(Circle().fill(BrandColors.lightGray.opacity(0.7)))
                }
                Spacer()
            }
        }
        .padding(.top)
    }

    private var profilePictureSection: some View {
        VStack {
            Image(uiImage: profileImage ?? UIImage(systemName: "person.circle.fill")!)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100).clipShape(Circle())
                .foregroundColor(.gray.opacity(0.5))
            
            HStack(spacing: 20) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    Text("Change Picture")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(primary)
                }
                
                if profileImage != nil {
                    Button(role: .destructive) {
                        withAnimation { self.profileImage = nil; self.selectedPhotoItem = nil }
                    } label: {
                        Text("Remove Picture")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Name
            field(label: "Name", text: $name, isValid: isNameValid)
            if !name.isEmpty && !isNameValid {
                Text("Please enter a valid name (letters and spaces only).").font(.system(size: 13, design: .rounded)).foregroundColor(.red)
            }
            
            // Position
            fieldLabel("Position")
            buttonLikeField {
                HStack {
                    Text(position.isEmpty ? "Select position" : position)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(position.isEmpty ? .gray : primary)
                    Spacer()
                    Image(systemName: "chevron.down").foregroundColor(primary.opacity(0.85))
                }
            } onTap: { showPositionPicker = true }
            .sheet(isPresented: $showPositionPicker) {
                PositionWheelPickerSheet(positions: positions, selection: $position, showSheet: $showPositionPicker)
                    .presentationDetents([.height(300)]).presentationBackground(BrandColors.background).presentationCornerRadius(28)
            }
            
            // Height & Weight
            field(label: "Height (cm)", text: $height, keyboardType: .numberPad, isValid: isHeightValid)
            field(label: "Weight (kg)", text: $weight, keyboardType: .numberPad, isValid: isWeightValid)
            
            // DOB
            fieldLabel("Date of birth")
            buttonLikeField {
                HStack {
                    Text(dob.map { formatDate($0) } ?? "Select date")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(dob == nil ? .gray : primary)
                    Spacer()
                    Image(systemName: "calendar").foregroundColor(primary.opacity(0.85))
                }
            } onTap: { tempDOB = dob ?? Date(); showDOBPicker = true }
            .sheet(isPresented: $showDOBPicker) {
                DateWheelPickerSheet(selection: $dob, tempSelection: $tempDOB, showSheet: $showDOBPicker)
                    .presentationDetents([.height(300)]).presentationBackground(BrandColors.background).presentationCornerRadius(28)
            }
            
            // Residence
            fieldLabel("Residence")
            buttonLikeField {
                HStack {
                    Text(location.isEmpty ? "Select city" : location)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(location.isEmpty ? .gray : primary)
                    Spacer()
                    Image(systemName: "chevron.down").foregroundColor(primary.opacity(0.85))
                }
            } onTap: { locationSearch = ""; showLocationPicker = true }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerSheet(title: "Select your city", allCities: SAUDI_CITIES, selection: $location, searchText: $locationSearch, showSheet: $showLocationPicker, accent: primary)
                    .presentationDetents([.large]).presentationBackground(BrandColors.background).presentationCornerRadius(28)
            }
            
            // MARK: - Email Field (Matched to SignUp)
            fieldLabel("Email")
            roundedField {
                HStack {
                    TextField("", text: $email)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(primary)
                        .tint(primary)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .focused($emailFocused)
                        .onSubmit { checkEmailImmediately() } // Check on return
                    
                    if isCheckingEmail {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    // STRICT CHECK: Border is RED only if email is NOT empty AND (exists OR format is invalid)
                    .stroke(!email.isEmpty && (emailExists || !isEmailFieldValid) ? Color.red : Color.clear, lineWidth: 1)
            )
            .onChange(of: emailFocused) { focused in
                if !focused { checkEmailImmediately() }
            }
            // Also clear errors immediately when typing
            .onChange(of: email) { _, newValue in
                if newValue.isEmpty {
                    emailExists = false
                    emailCheckError = nil
                }
            }
            
            // EMAIL ERRORS (Only show if not empty)
            if !email.isEmpty {
                if !isEmailFieldValid {
                    Text("Please enter a valid email address (name@domain).")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.red)
                } else if emailExists {
                    Text("This email is already in use by another account.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.red)
                } else if let err = emailCheckError {
                    Text(err)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.red)
                }
            }
            
            // Phone
            fieldLabel("Phone number")
            roundedField {
                HStack(spacing: 10) {
                    Text(selectedDialCode.code).font(.system(size: 16, design: .rounded)).foregroundColor(primary)
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(primary.opacity(0.08)))
                    TextField("", text: Binding(
                        get: { phoneLocal },
                        set: { val in phoneNonDigitError = val.contains { !$0.isNumber }; phoneLocal = val.filter { $0.isNumber } }
                    ))
                    .keyboardType(.numberPad).font(.system(size: 16, design: .rounded)).foregroundColor(primary).tint(primary)
                }
            }
            if phoneNonDigitError { Text("Numbers only (0–9).").font(.system(size: 13, design: .rounded)).foregroundColor(.red) }
            else if !phoneLocal.isEmpty && !isPhoneNumberValid {
                Text(selectedDialCode.code == "+966" ? "Must be 9 digits and start with 5." : "Enter a valid phone number.")
                    .font(.system(size: 13, design: .rounded)).foregroundColor(.red)
            }
        }
    }

    // MARK: - Toggles Section
    private var togglesSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Make my email visible")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)
                Spacer()
                Toggle("", isOn: $isEmailVisible)
                    .labelsHidden()
                    .tint(primary)
            }
            
            HStack {
                Text("Make my phone visible")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)
                Spacer()
                Toggle("", isOn: $isPhoneNumberVisible)
                    .labelsHidden()
                    .tint(primary)
            }
        }
        .padding(.top, 10)
    }

    private var updateButton: some View {
        Button { Task { await saveChanges() } } label: {
            HStack {
                Text("Update")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                if isSaving { ProgressView().colorInvert().scaleEffect(0.9) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16).background(primary).clipShape(Capsule())
        }
        .disabled(!isFormValid || isSaving || isCheckingEmail)
        .opacity((!isFormValid || isSaving || isCheckingEmail) ? 0.6 : 1.0)
    }

    // MARK: - Email Availability Logic (Matches SignUp)
    // Checks immediately when called (on blur or submit)
    private func checkEmailImmediately() {
        // Reset
        emailCheckTask?.cancel()
        emailExists = false
        emailCheckError = nil
        isCheckingEmail = false
        
        // If empty, stop here (errors are hidden by UI logic anyway)
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        
        // If email hasn't changed from current profile, consider it valid
        if email == userProfile.email {
            return
        }
        
        guard isValidEmail(trimmed) else { return }
        
        let mail = trimmed.lowercased()
        isCheckingEmail = true
        
        emailCheckTask = Task {
            let testPassword = UUID().uuidString + "Aa1!"
            do {
                // Try creating dummy user
                let result = try await Auth.auth().createUser(withEmail: mail, password: testPassword)
                // If successful, delete immediately
                try? await result.user.delete()
                
                await MainActor.run {
                    if !Task.isCancelled {
                        emailExists = false
                        isCheckingEmail = false
                    }
                }
            } catch {
                let ns = error as NSError
                await MainActor.run {
                    if !Task.isCancelled {
                        // If taken, set emailExists = true
                        emailExists = (ns.code == AuthErrorCode.emailAlreadyInUse.rawValue)
                        isCheckingEmail = false
                    }
                }
            }
        }
    }

    // MARK: - Save Logic
    private func saveChanges() async {
        guard let user = Auth.auth().currentUser else {
            overlayMessage = "User not authenticated"; overlayIsError = true; showInfoOverlay = true; return
        }
        
        isSaving = true
        
        if email != userProfile.email {
            do {
                // A. Update Auth Email
                try await user.updateEmail(to: email)
                
                // B. Send Verification Email (Using helper)
                try await sendVerificationEmail(to: user)
                
                // C. Show Verification Prompt
                markVerificationSentNow()
                startResendCooldown(seconds: 60)
                
                withAnimation {
                    showVerifyPrompt = true
                }
                
                startVerificationWatcher()
                
                await saveProfileToFirestore(updateEmailInDB: false)
                
            } catch {
                isSaving = false
                let ns = error as NSError
                
                if ns.code == AuthErrorCode.requiresRecentLogin.rawValue {
                    overlayMessage = "For security, please log out and log back in to change your email."
                } else if ns.code == AuthErrorCode.emailAlreadyInUse.rawValue {
                    // Silent fail (error shown under field)
                    emailExists = true
                    return
                } else {
                    overlayMessage = "Failed to update email: \(error.localizedDescription)"
                }
                overlayIsError = true
                showInfoOverlay = true
                return
            }
        } else {
            // Email didn't change
            await saveProfileToFirestore(updateEmailInDB: true)
            
            await MainActor.run {
                overlayMessage = "Profile updated successfully"
                overlayIsError = false
                showInfoOverlay = true
                isSaving = false
            }
        }
    }
    
    // Updates Firestore
    private func saveProfileToFirestore(updateEmailInDB: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        do {
            let fullPhone = selectedDialCode.code + phoneLocal
            
            // 1. /users/{uid}
            var userUpdates: [String: Any] = [
                "firstName": name.split(separator: " ").first.map(String.init) ?? name,
                "lastName": name.split(separator: " ").dropFirst().joined(separator: " "),
                "phone": fullPhone,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            if updateEmailInDB {
                userUpdates["email"] = email
            }
            
            if let dob = dob { userUpdates["dob"] = Timestamp(date: dob) }
            else { userUpdates["dob"] = NSNull() }
            
            // Profile Pic
            let oldImage = userProfile.profileImage
            if let newImage = profileImage, newImage != oldImage {
                if let imageData = newImage.jpegData(compressionQuality: 0.8) {
                    let fileName = "\(UUID().uuidString).jpg"
                    let ref = Storage.storage().reference().child("profile/\(uid)/\(fileName)")
                    _ = try await ref.putDataAsync(imageData)
                    let url = try await ref.downloadURL()
                    userUpdates["profilePic"] = url.absoluteString
                }
            } else if profileImage == nil, oldImage != nil {
                userUpdates["profilePic"] = ""
            }
            
            try await db.collection("users").document(uid).setData(userUpdates, merge: true)
            
            // 2. /player/profile
            let profileUpdates: [String: Any] = [
                "position": position,
                "weight": Int(weight) ?? 0,
                "height": Int(height) ?? 0,
                "location": location,
                "isEmailVisible": isEmailVisible,
                "isPhoneNumberVisible": isPhoneNumberVisible,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try await db.collection("users").document(uid)
                .collection("player").document("profile")
                .setData(profileUpdates, merge: true)
            
            // Update Local Object
            await MainActor.run {
                userProfile.name = name
                userProfile.position = position
                userProfile.weight = "\(weight)kg"
                userProfile.height = "\(height)cm"
                userProfile.location = location
                if updateEmailInDB { userProfile.email = email }
                userProfile.phoneNumber = fullPhone
                userProfile.isEmailVisible = isEmailVisible
                userProfile.isPhoneNumberVisible = isPhoneNumberVisible
                userProfile.dob = dob
                if let dob = dob {
                    let comps = Calendar.current.dateComponents([.year], from: dob, to: Date())
                    userProfile.age = "\(comps.year ?? 0)"
                }
                
                NotificationCenter.default.post(name: .profileUpdated, object: nil)
            }
            
        } catch {
            print("Error saving profile: \(error)")
        }
    }
    
    // MARK: - Email Sending Logic
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
    
    // MARK: - Verification Watcher
    private func startVerificationWatcher() {
        verifyTask?.cancel()
        verifyTask = Task {
            let deadline = Date().addingTimeInterval(600)
            while !Task.isCancelled && Date() < deadline {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let user = Auth.auth().currentUser else { break }
                try? await user.reload()
                
                if user.isEmailVerified {
                    await finalizeEmailUpdate(for: user)
                    break
                }
            }
        }
    }
    
    @MainActor
    private func finalizeEmailUpdate(for user: User) async {
        try? await db.collection("users").document(user.uid).updateData([
            "email": user.email ?? email,
            "emailVerified": true
        ])
        
        userProfile.email = user.email ?? email
        showVerifyPrompt = false
        isSaving = false
        
        overlayMessage = "Email verified and updated successfully!"
        overlayIsError = false
        showInfoOverlay = true
    }
    
    private func resendVerification() async {
        guard let user = Auth.auth().currentUser else { return }
        if resendCooldown > 0 { return }
        
        do {
            try await sendVerificationEmail(to: user)
            markVerificationSentNow()
            startResendCooldown(seconds: 60)
            inlineVerifyError = nil
        } catch {
            inlineVerifyError = error.localizedDescription
        }
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
        UserDefaults.standard.set(Int(Date().timeIntervalSince1970), forKey: "edit_profile_last_sent")
    }

    // MARK: - View Helpers
    private func field(label: String, text: Binding<String>, keyboardType: UIKeyboardType = .default, isValid: Bool) -> some View {
        VStack(alignment: .leading) {
            fieldLabel(label)
            roundedField {
                TextField("", text: text)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(primary)
                    .tint(primary).keyboardType(keyboardType)
                    .onChange(of: text.wrappedValue) { oldValue, newValue in
                        if keyboardType == .numberPad {
                            text.wrappedValue = newValue.filter(\.isNumber)
                        }
                    }
            }
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isValid || text.wrappedValue.isEmpty ? Color.clear : Color.red, lineWidth: 1))
        }
    }
    
    private func fieldLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 14, design: .rounded)).foregroundColor(.gray)
    }
    
    private func roundedField<Content: View>(@ViewBuilder c: () -> Content) -> some View {
        c()
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background).shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1)))
    }
    
    private func buttonLikeField<Content: View>(@ViewBuilder content: () -> Content, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            content()
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background).shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1)))
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; return f.string(from: date)
    }
}

// MARK: - Verification Sheet for Edit Profile
struct EditProfileVerifySheet: View {
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
                
                Text("Verify new email")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Text("We've sent a verification link to \(email).\nPlease check your inbox and verify the link to complete the update.")
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
                
                // Add a spinner to show it's waiting
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting for verification...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                
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
    }
}
