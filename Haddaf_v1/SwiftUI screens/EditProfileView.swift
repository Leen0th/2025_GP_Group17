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
    
    // MARK: - Age Warning State
    @State private var ageWarning: String? = nil
    
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
    
    // MARK: - Re-authentication State
    @State private var showReauthPrompt = false
    @State private var reauthPassword = ""
    @State private var reauthError: String? = nil
    @State private var isReauthing = false
    
    // MARK: - Validation Computed Properties
    
    // 1. Name Validation (Uses helper)
    private var isNameValid: Bool {
        return fullNameValidationError(name) == nil
    }
    
    // 2. Email Validation
    private var isEmailFieldValid: Bool { isValidEmail(email) }
    
    // 3. Phone Validation
    private var isPhoneNumberValid: Bool {
        isValidPhone(code: selectedDialCode.code, local: phoneLocal)
    }
    
    private var isWeightValid: Bool {
        guard let w = Int(weight) else { return false }
        return (15...200).contains(w)
    }
    
    private var isHeightValid: Bool {
        guard let h = Int(height) else { return false }
        return (100...200).contains(h)
    }
    
    private var isLocationValid: Bool {
        return !location.isEmpty
    }
    
    // Valid only if standard fields are valid AND email is not taken AND we aren't currently checking
    private var isFormValid: Bool {
        isNameValid && isEmailFieldValid && isPhoneNumberValid &&
        isWeightValid && isHeightValid && isLocationValid && !position.isEmpty &&
        !emailExists && !isCheckingEmail && dob != nil
    }
    
    // MARK: - Date Range Properties (From SignUp)
    /// The latest date a user can select (7 years ago).
    private var minAgeDate: Date {
        Calendar.current.date(byAdding: .year, value: -7, to: Date())!
    }
    /// The earliest date a user can select (100 years ago).
    private var maxAgeDate: Date {
        Calendar.current.date(byAdding: .year, value: -100, to: Date())!
    }
    
    init(userProfile: UserProfile) {
        self.userProfile = userProfile
        _name = State(initialValue: userProfile.name)
        _position = State(initialValue: userProfile.position)
        _weight = State(initialValue: userProfile.weight.replacingOccurrences(of: "kg", with: ""))
        _height = State(initialValue: userProfile.height.replacingOccurrences(of: "cm", with: ""))
        _location = State(initialValue: userProfile.location)
        
        let authEmail = Auth.auth().currentUser?.email ?? userProfile.email
        _email = State(initialValue: authEmail)
        
        _isEmailVisible = State(initialValue: userProfile.isEmailVisible)
        _profileImage = State(initialValue: userProfile.profileImage)
        _dob = State(initialValue: userProfile.dob)
        
        let (_, parsedLocal) = parsePhoneNumber(userProfile.phoneNumber)
        _phoneLocal = State(initialValue: parsedLocal)
        
        _isPhoneNumberVisible = State(initialValue: userProfile.isPhoneNumberVisible)
    }
    private func confirmEmailUpdateWithPassword() {
        guard let user = Auth.auth().currentUser, let userEmail = user.email else { return }
        guard !reauthPassword.isEmpty else { return }
        
        // 1. Use the NEW variable
        reauthError = nil
        isReauthing = true
        
        let credential = EmailAuthProvider.credential(withEmail: userEmail, password: reauthPassword)
        
        Task {
            do {
                try await user.reauthenticate(with: credential)
                
                await MainActor.run {
                    // 2. Stop the local spinner
                    isReauthing = false
                    showReauthPrompt = false
                    reauthPassword = ""
                    
                    // 3. Start the actual update (which uses 'isSaving')
                    Task { await executeEmailUpdate() }
                }
            } catch {
                await MainActor.run {
                    // 4. Handle Error
                    isReauthing = false
                    reauthPassword = ""
                    reauthError = "Incorrect password. Please try again."
                }
            }
        }
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
            // Custom Re-auth Overlay
            if showReauthPrompt {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture {
                        // Optional: Tap background to dismiss
                        isReauthing = false
                        showReauthPrompt = false
                    }
                
                ReauthPromptSheet(
                    password: $reauthPassword,
                    errorText: $reauthError,
                    isLoading: $isReauthing,
                    onCancel: {
                        isReauthing = false
                        showReauthPrompt = false
                        reauthPassword = ""
                        reauthError = nil
                    },
                    onConfirm: {
                        confirmEmailUpdateWithPassword()
                    }
                )
                .transition(.scale.combined(with: .opacity))
                .zIndex(4) // Ensure it sits on top
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
                        // 1. Stop the loading spinner
                        isSaving = false
                        // 2. Stop checking for verification in the background
                        verifyTask?.cancel()
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
        // Calculate initial age warning if needed
        .onAppear {
            if let d = dob {
                let age = calculateAge(from: d)
                if (7...12).contains(age) {
                    ageWarning = "You are recommended to use this app with parental supervision."
                }
            }
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
            
            // MARK: - Name Field
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Name")
                roundedField {
                    TextField("", text: $name)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(primary)
                        .tint(primary)
                        .textInputAutocapitalization(.words)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        // Border turns red if invalid (including if > 35 chars)
                        .stroke(!name.isEmpty && !isNameValid ? Color.red : Color.gray.opacity(0.1), lineWidth: 1)
                )
                
                // Error message appears underneath
                if let error = fullNameValidationError(name), !name.isEmpty {
                    Text(error)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.red)
                }
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
            
            // MARK: - Height Field
            fieldLabel("Height (cm)")
            VStack(alignment: .leading, spacing: 6) {
                roundedField {
                    TextField("Enter height", text: $height)
                        .keyboardType(.numberPad)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(primary)
                        .onChange(of: height) { _, new in
                            let filtered = new.filter(\.isNumber)
                            height = String(filtered.prefix(3))
                        }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(!height.isEmpty && !isHeightValid ? Color.red : Color.clear, lineWidth: 1)
                )
                
                if !height.isEmpty && !isHeightValid {
                    Text("Enter a realistic height between 100–200 cm.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.red)
                }
            }
            // MARK: - Weight Field
            fieldLabel("Weight (kg)")
            VStack(alignment: .leading, spacing: 6) {
                roundedField {
                    TextField("Enter weight", text: $weight)
                        .keyboardType(.numberPad)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(primary)
                        .onChange(of: weight) { _, new in
                            let filtered = new.filter(\.isNumber)
                            weight = String(filtered.prefix(3))
                        }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(!weight.isEmpty && !isWeightValid ? Color.red : Color.clear, lineWidth: 1)
                )
                
                if !weight.isEmpty && !isWeightValid {
                    Text("Enter a realistic weight between 15–200 kg.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.red)
                }
            }
            
            // MARK: - DOB (Fixed with Age Limit & Warning)
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Date of birth")
                buttonLikeField {
                    HStack {
                        Text(dob.map { formatDate($0) } ?? "Select date")
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(dob == nil ? .gray : primary)
                        Spacer()
                        Image(systemName: "calendar").foregroundColor(primary.opacity(0.85))
                    }
                } onTap: {
                    tempDOB = dob ?? minAgeDate
                    showDOBPicker = true
                }
                .sheet(isPresented: $showDOBPicker) {
                    // Restrict range: 100 years ago ... 7 years ago
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
                .onChange(of: dob) { _, newDOB in
                    guard let newDOB = newDOB else {
                        ageWarning = nil
                        return
                    }
                    let age = calculateAge(from: newDOB)
                    if (7...12).contains(age) {
                        ageWarning = "You are recommended to use this app with parental supervision."
                    } else {
                        ageWarning = nil
                    }
                }
                
                // WARNING TEXT
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
                    .padding(.top, 2)
                }
            }
            
            // Residence
            // MARK: - Residence Field (Matched PlayerSetup)
            fieldLabel("City of Residence")
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
            
            // MARK: - Email Field
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
                        .onSubmit { checkEmailImmediately() }
                    
                    if isCheckingEmail {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(!email.isEmpty && (emailExists || !isEmailFieldValid) ? Color.red : Color.clear, lineWidth: 1)
            )
            .onChange(of: emailFocused) { focused in
                if !focused { checkEmailImmediately() }
            }
            .onChange(of: email) { _, newValue in
                if newValue.isEmpty {
                    emailExists = false
                    emailCheckError = nil
                }
            }
            
            // EMAIL ERRORS
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
            
            // MARK: - Phone Field (Fixed)
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
            if phoneNonDigitError {
                Text("Numbers only (0–9).").font(.system(size: 13, design: .rounded)).foregroundColor(.red)
            } else if !phoneLocal.isEmpty && !isPhoneNumberValid {
                // EXACT SIGNUP ERROR MESSAGE
                Text("Enter a valid Saudi number (starts with 5, 9 digits).")
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
    // MARK: - Helper Functions (Logic from SignUpView)
    // MARK: - Auth Display Name Update Helper
    private func updateAuthDisplayNameIfNeeded() async {
        guard let authUser = Auth.auth().currentUser else { return }
        do {
            let changeRequest = authUser.createProfileChangeRequest()
            changeRequest.displayName = name   // use the new name
            try await changeRequest.commitChanges()
            print("displayName updated to:", authUser.displayName ?? "nil")
        } catch {
            print("Failed to update displayName:", error)
        }
    }

    
    // 1. Full Name Validation
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
    
    // 2. Strict Email Regex
    private func isValidEmail(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        if value.contains("..") { return false }
        let pattern = #"^(?![.])([A-Za-z0-9._%+-]{1,64})(?<![.])@([A-Za-z0-9-]{1,63}\.)+[A-Za-z]{2,63}$"#
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: value)
    }
    
    // 3. Strict Phone Logic
    private func isValidPhone(code: String, local: String) -> Bool {
        guard !local.isEmpty else { return false }
        let len = local.count
        var ok = (6...15).contains(len)
        if code == "+966" { ok = (len == 9) && local.first == "5" } // KSA rule
        return ok
    }
    
    // 4. Age Calculation
    private func calculateAge(from dob: Date) -> Int {
        return Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
    }
    // MARK: - Email Availability Logic
    private func checkEmailImmediately() {
        emailCheckTask?.cancel(); emailExists = false; emailCheckError = nil; isCheckingEmail = false
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip check if the email matches your CURRENT Auth email
        let currentAuthEmail = Auth.auth().currentUser?.email
        if trimmed.isEmpty || trimmed == userProfile.email || trimmed == currentAuthEmail { return }
        
        guard isValidEmail(trimmed) else { return }
        let mail = trimmed.lowercased()
        isCheckingEmail = true
        emailCheckTask = Task {
            let testPassword = UUID().uuidString + "Aa1!"
            do {
                let result = try await Auth.auth().createUser(withEmail: mail, password: testPassword)
                try? await result.user.delete()
                await MainActor.run { if !Task.isCancelled { emailExists = false; isCheckingEmail = false } }
            } catch {
                let ns = error as NSError
                await MainActor.run {
                    if !Task.isCancelled { emailExists = (ns.code == AuthErrorCode.emailAlreadyInUse.rawValue); isCheckingEmail = false }
                }
            }
        }
    }
    
    // MARK: - Save Logic
    // MODIFIED: saveChanges
    private func saveChanges() async {
        guard let user = Auth.auth().currentUser else {
            overlayMessage = "User not authenticated"; overlayIsError = true; showInfoOverlay = true; return
        }
        isSaving = true
        
        let currentAuthEmail = user.email ?? ""
        
        if email != currentAuthEmail {
            // Always ask for password first
            showReauthPrompt = true
            return
        } else {
            await updateAuthDisplayNameIfNeeded()
            // Email matched, just update profile details
            await saveProfileToFirestore(updateEmailInDB: true)
            await MainActor.run {
                overlayMessage = "Profile updated successfully"; overlayIsError = false; showInfoOverlay = true; isSaving = false
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
    
    private func executeEmailUpdate() async {
        guard let user = Auth.auth().currentUser else { return }
        
        // Start loading again for the main screen
        await MainActor.run { isSaving = true }
        
        do {
            await updateAuthDisplayNameIfNeeded()
            
            // 1. Update Email on Firebase Auth
            try await user.updateEmail(to: email)
            
            // 2. Send Verification
            try await sendVerificationEmail(to: user)
            markVerificationSentNow()
            startResendCooldown(seconds: 60)
            
            // 3. Success: Stop loading, Show Verification Sheet
            await MainActor.run {
                isSaving = false
                withAnimation { showVerifyPrompt = true }
            }
            
            // 4. Background tasks
            await saveProfileToFirestore(updateEmailInDB: false)
            startVerificationWatcher()
           
            
        } catch {
            // 5. Failure: Stop loading and show error
            await MainActor.run {
                isSaving = false
                let ns = error as NSError
                if ns.code == AuthErrorCode.emailAlreadyInUse.rawValue {
                    emailExists = true
                } else {
                    overlayMessage = "Failed to update email: \(error.localizedDescription)"
                    overlayIsError = true
                    showInfoOverlay = true
                }
            }
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
        try? await user.getIDToken(forcingRefresh: true) // Force refresh token
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
struct ReauthPromptSheet: View {
    @Binding var password: String
    @Binding var errorText: String?
    @Binding var isLoading: Bool
    
    var onCancel: () -> Void
    var onConfirm: () -> Void
    
    private let primary = BrandColors.darkTeal
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 20) {
                // Header
                Text("Verify it's you")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(primary)
                    .padding(.top, 10)
                
                Text("For security, please enter your password to change your email.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Password Field (Custom Styling)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SecureField("Password", text: $password)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(primary)
                            .tint(primary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(BrandColors.background)
                            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                    )
                    
                    if let error = errorText {
                        Text(error)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.red)
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal)
                
                // Buttons
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(UIColor.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    
                    Button(action: onConfirm) {
                        HStack {
                            if isLoading {
                                ProgressView().colorInvert().scaleEffect(0.8)
                            } else {
                                Text("Confirm")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(password.isEmpty || isLoading)
                    .opacity((password.isEmpty || isLoading) ? 0.6 : 1.0)
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(BrandColors.background)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            )
            .padding()
            
            Spacer()
        }
        .background(Color.clear)
    }
}
