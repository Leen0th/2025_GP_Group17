import SwiftUI
import FirebaseMessaging
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - Coach Profile Model
class CoachProfile: ObservableObject {
    @Published var name: String = ""
    @Published var team: String = ""
    @Published var location: String = ""
    @Published var email: String = ""
    @Published var isEmailVisible: Bool = false
    @Published var profileImage: UIImage? = nil

    init() {}
}

// MARK: - Coach Profile View Model
class CoachProfileViewModel: ObservableObject {
    @Published var coachProfile = CoachProfile()
    @Published var isLoading = true

    private let db = Firestore.firestore()

    init(userID: String?) {
        Task {
            await fetchProfile(userID: userID ?? Auth.auth().currentUser?.uid ?? "")
        }
    }

    func fetchProfile(userID: String) async {
        do {
            let userDoc = try await db.collection("users").document(userID).getDocument()
            guard let data = userDoc.data() else {
                await MainActor.run { self.isLoading = false }
                return
            }
            
            await MainActor.run {
                // 1. Map basic info immediately
                self.coachProfile.name = (data["firstName"] as? String ?? "") + " " + (data["lastName"] as? String ?? "")
                self.coachProfile.location = data["location"] as? String ?? ""
                self.coachProfile.email = data["email"] as? String ?? ""
                self.coachProfile.isEmailVisible = data["isEmailVisible"] as? Bool ?? false
                self.coachProfile.team = data["teamName"] as? String ?? ""
                
                // 2. Handle Profile Picture asynchronously
                if let urlString = data["profilePic"] as? String,
                   !urlString.isEmpty,
                   let url = URL(string: urlString) {
                    
                    // Start background download immediately without delay
                    Task(priority: .userInitiated) {
                        do {
                            let (imageData, _) = try await URLSession.shared.data(from: url)
                            if let image = UIImage(data: imageData) {
                                await MainActor.run {
                                    self.coachProfile.profileImage = image
                                }
                            }
                        } catch {
                            print("Error downloading profile image: \(error)")
                        }
                    }
                }
                
                self.isLoading = false
            }
        } catch {
            print("Error fetching coach profile: \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }

}

// MARK: - Coach Profile Content View
struct CoachProfileContentView: View {
    @StateObject private var viewModel: CoachProfileViewModel
    @State private var selectedContent: ContentType = .currentTeam
    @State private var goToSettings = false
    @State private var showNotificationsList = false // If needed, else remove

    private var isCurrentUser: Bool
    private var isRootProfileView: Bool = true // Adjust if needed

    enum ContentType: String, CaseIterable {
        case currentTeam = "Current Team"
        case matchSchedule = "Match Schedule"
    }

    init() {
        _viewModel = StateObject(wrappedValue: CoachProfileViewModel(userID: nil))
        self.isCurrentUser = true
    }

    init(userID: String) {
        _viewModel = StateObject(wrappedValue: CoachProfileViewModel(userID: userID))
        self.isCurrentUser = (userID == Auth.auth().currentUser?.uid)
        self.isRootProfileView = false
    }

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            ScrollView {
                if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 50)
                        .tint(BrandColors.darkTeal)
                } else {
                    VStack(spacing: 24) {
                        TopNavigationBarCoach(
                            coachProfile: viewModel.coachProfile,
                            goToSettings: $goToSettings,
                            showNotifications: $showNotificationsList,
                            isCurrentUser: isCurrentUser,
                            isRootProfileView: isRootProfileView,
                            onReport: {}, // No report for now
                            reportService: ReportStateService.shared,
                            reportedID: viewModel.coachProfile.email
                        )
                        ProfileHeaderViewCoach(coachProfile: viewModel.coachProfile)
                        InfoGridViewCoach(coachProfile: viewModel.coachProfile)
                        ContentTabViewCoach(selectedContent: $selectedContent)
                        switch selectedContent {
                        case .currentTeam:
                            EmptyStateView(
                                imageName: "person.3",
                                message: "To be developed in the next sprint"
                            )
                            .padding(.top, 40)
                        case .matchSchedule:
                            EmptyStateView(
                                imageName: "calendar",
                                message: "To be developed in the next sprint"
                            )
                            .padding(.top, 40)
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
            .fullScreenCover(isPresented: $goToSettings) {
                NavigationStack { SettingsViewCoach(coachProfile: viewModel.coachProfile) }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

// Adapt TopNavigationBar for coach
struct TopNavigationBarCoach: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var coachProfile: CoachProfile
    @Binding var goToSettings: Bool
    @Binding var showNotifications: Bool
    var isCurrentUser: Bool
    var isRootProfileView: Bool
    var onReport: () -> Void
    @ObservedObject var reportService: ReportStateService
    var reportedID: String

    var body: some View {
        HStack(spacing: 16) {
            if !isRootProfileView {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(BrandColors.darkTeal)
                        .padding(10)
                        .background(Circle().fill(BrandColors.lightGray.opacity(0.7)))
                }
            }
            Spacer()
            if isCurrentUser {
                Button { showNotifications = true } label: {
                    Image(systemName: "bell")
                        .font(.title2)
                        .foregroundColor(BrandColors.darkTeal)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                Button { goToSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .foregroundColor(BrandColors.darkTeal)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            } else {
                let isReported = reportService.reportedProfileIDs.contains(reportedID)
                Button(action: onReport) {
                    Image(systemName: isReported ? "flag.fill" : "flag")
                        .font(.title2)
                        .foregroundColor(.red)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(isReported)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}

// Profile Header for Coach
struct ProfileHeaderViewCoach: View {
    @ObservedObject var coachProfile: CoachProfile

    var body: some View {
        VStack(spacing: 12) {
            Image(uiImage: coachProfile.profileImage ?? UIImage(systemName: "person.circle.fill")!)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100).clipShape(Circle())
                .overlay(Circle().stroke(BrandColors.background, lineWidth: 4))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
                .foregroundColor(.gray.opacity(0.5))
            Text(coachProfile.name)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(BrandColors.darkTeal)
        }
    }
}

// Info Grid for Coach
struct InfoGridViewCoach: View {
    @ObservedObject var coachProfile: CoachProfile
    let accentColor = BrandColors.darkTeal

    @ViewBuilder private func UserStatItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(accentColor.opacity(0.8))
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(BrandColors.darkGray)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        VStack(spacing: 18) {

            // Row 1: Team & Location
            HStack {
                Spacer()
                UserStatItem(title: "TEAM", value: coachProfile.team)
                Spacer()
                UserStatItem(title: "LOCATION", value: coachProfile.location)
                Spacer()
            }

            // Row 2: Email (only if visible)
            if coachProfile.isEmailVisible {
                UserStatItem(title: "EMAIL", value: coachProfile.email)
            }

        }
        .padding(.vertical, 25)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(BrandColors.background)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        )
        .padding(.horizontal)
    }

}

// Content Tab for Coach
struct ContentTabViewCoach: View {
    @Binding var selectedContent: CoachProfileContentView.ContentType
    @Namespace private var animation
    let accentColor = BrandColors.darkTeal

    var body: some View {
        HStack(spacing: 12) {
            ContentTabButton(title: "Current Team", type: .currentTeam, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
            ContentTabButton(title: "Match Schedule", type: .matchSchedule, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
        }
        .font(.system(size: 16, weight: .medium, design: .rounded))
    }
}

fileprivate struct ContentTabButton: View {
    let title: String, type: CoachProfileContentView.ContentType
    @Binding var selectedContent: CoachProfileContentView.ContentType
    let accentColor: Color, animation: Namespace.ID

    var body: some View {
        Button(action: { withAnimation(.easeInOut) { selectedContent = type } }) {
            VStack(spacing: 8) {
                Text(title)
                    .foregroundColor(selectedContent == type ? accentColor : .secondary)
                if selectedContent == type {
                    Rectangle().frame(height: 2).foregroundColor(accentColor)
                        .matchedGeometryEffect(id: "underline", in: animation)
                } else { Color.clear.frame(height: 2) }
            }
        }.frame(maxWidth: .infinity)
    }
}
// MARK: - Edit Coach Profile View
struct EditCoachProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var coachProfile: CoachProfile

    // Local Form State
    @State private var name: String
    @State private var location: String
    @State private var email: String
    @State private var isEmailVisible: Bool
    @State private var profileImage: UIImage?

    // Sheets & Pickers
    @State private var showLocationPicker = false
    @State private var locationSearch = ""
    @State private var selectedPhotoItem: PhotosPickerItem?

    // Email Validation State
    @FocusState private var emailFocused: Bool
    @State private var emailExists = false
    @State private var emailCheckError: String? = nil
    @State private var emailCheckTask: Task<Void, Never>? = nil
    @State private var isCheckingEmail = false

    // Verification Flow State
    @State private var showVerifyPrompt = false
    @State private var verifyTask: Task<Void, Never>? = nil
    @State private var resendCooldown = 0
    @State private var resendTimerTask: Task<Void, Never>? = nil
    @State private var inlineVerifyError: String? = nil
    private let resendCooldownSeconds = 60
    private let emailActionURL = "https://haddaf-db.web.app/__/auth/action"

    // View Operation State
    @State private var isSaving = false
    @State private var showInfoOverlay = false
    @State private var overlayMessage = ""
    @State private var overlayIsError = false

    private let primary = BrandColors.darkTeal
    private let db = Firestore.firestore()

    // Re-authentication State
    @State private var showReauthPrompt = false
    @State private var reauthPassword = ""
    @State private var reauthError: String? = nil
    @State private var isReauthing = false

    // Validation Computed Properties
    private var isNameValid: Bool {
        fullNameValidationError(name) == nil
    }

    private var isEmailFieldValid: Bool { isValidEmail(email) }

    private var isLocationValid: Bool {
        !location.isEmpty
    }

    private var isFormValid: Bool {
        isNameValid && isEmailFieldValid && isLocationValid &&
        !emailExists && !isCheckingEmail
    }

    init(coachProfile: CoachProfile) {
        self.coachProfile = coachProfile
        _name = State(initialValue: coachProfile.name)
        _location = State(initialValue: coachProfile.location)
        let authEmail = Auth.auth().currentUser?.email ?? coachProfile.email
        _email = State(initialValue: authEmail)
        _isEmailVisible = State(initialValue: coachProfile.isEmailVisible)
        _profileImage = State(initialValue: coachProfile.profileImage)
    }

    private func confirmEmailUpdateWithPassword() {
        guard let user = Auth.auth().currentUser, let userEmail = user.email else { return }
        guard !reauthPassword.isEmpty else { return }

        reauthError = nil
        isReauthing = true

        let credential = EmailAuthProvider.credential(withEmail: userEmail, password: reauthPassword)

        Task {
            do {
                try await user.reauthenticate(with: credential)
                await MainActor.run {
                    isReauthing = false
                    showReauthPrompt = false
                    reauthPassword = ""
                    Task { await executeEmailUpdate() }
                }
            } catch {
                await MainActor.run {
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

            if showInfoOverlay {
                InfoOverlay(primary: primary, title: overlayMessage, isError: overlayIsError, onOk: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showInfoOverlay = false }
                    if !overlayIsError { dismiss() }
                })
                .transition(.scale.combined(with: .opacity)).zIndex(2)
            }
            if showReauthPrompt {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture {
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
                .zIndex(4)
            }

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
                        isSaving = false
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
    }

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
            // Name Field
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
                        .stroke(!name.isEmpty && !isNameValid ? Color.red : Color.gray.opacity(0.1), lineWidth: 1)
                )

                if let error = fullNameValidationError(name), !name.isEmpty {
                    Text(error)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.red)
                }
            }

            // Location
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

            // Email Field
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
        }
    }

    // Toggles Section (Reused)
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
        }
        .padding(.top, 10)
    }

    // Update Button (Reused)
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

    // MARK: - Helper Functions (Reused from EditProfileView)
    private func checkEmailImmediately() {
        emailCheckTask?.cancel(); emailExists = false; emailCheckError = nil; isCheckingEmail = false
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)

        let currentAuthEmail = Auth.auth().currentUser?.email
        if trimmed.isEmpty || trimmed == coachProfile.email || trimmed == currentAuthEmail { return }

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

    private func saveChanges() async {
        guard let user = Auth.auth().currentUser else {
            overlayMessage = "User not authenticated"; overlayIsError = true; showInfoOverlay = true; return
        }
        isSaving = true

        let currentAuthEmail = user.email ?? ""

        if email != currentAuthEmail {
            showReauthPrompt = true
            return
        } else {
            await updateAuthDisplayNameIfNeeded()
            await saveProfileToFirestore(updateEmailInDB: true)
            await MainActor.run {
                overlayMessage = "Profile updated successfully"; overlayIsError = false; showInfoOverlay = true; isSaving = false
            }
        }
    }

    private func updateAuthDisplayNameIfNeeded() async {
        guard let authUser = Auth.auth().currentUser else { return }
        do {
            let changeRequest = authUser.createProfileChangeRequest()
            changeRequest.displayName = name
            try await changeRequest.commitChanges()
        } catch {
            print("Failed to update displayName:", error)
        }
    }

    private func saveProfileToFirestore(updateEmailInDB: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            var userUpdates: [String: Any] = [
                "firstName": name.split(separator: " ").first.map(String.init) ?? name,
                "lastName": name.split(separator: " ").dropFirst().joined(separator: " "),
                "location": location,
                "isEmailVisible": isEmailVisible,
                "updatedAt": FieldValue.serverTimestamp()
            ]

            if updateEmailInDB {
                userUpdates["email"] = email
            }

            // Profile Pic
            let oldImage = coachProfile.profileImage
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

            // Update Local Object
            await MainActor.run {
                coachProfile.name = name
                coachProfile.location = location
                if updateEmailInDB { coachProfile.email = email }
                coachProfile.isEmailVisible = isEmailVisible
                NotificationCenter.default.post(name: .profileUpdated, object: nil)
            }

        } catch {
            print("Error saving profile: \(error)")
        }
    }

    private func executeEmailUpdate() async {
        guard let user = Auth.auth().currentUser else { return }

        await MainActor.run { isSaving = true }

        do {
            await updateAuthDisplayNameIfNeeded()

            try await user.updateEmail(to: email)

            try await sendVerificationEmail(to: user)
            markVerificationSentNow()
            startResendCooldown(seconds: 60)

            await MainActor.run {
                isSaving = false
                withAnimation { showVerifyPrompt = true }
            }

            await saveProfileToFirestore(updateEmailInDB: false)
            startVerificationWatcher()

        } catch {
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
        try? await user.getIDToken(forcingRefresh: true)
        try? await db.collection("users").document(user.uid).updateData([
            "email": user.email ?? email,
            "emailVerified": true
        ])

        coachProfile.email = user.email ?? email
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

    private func isValidEmail(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        if value.contains("..") { return false }
        let pattern = #"^(?![.])([A-Za-z0-9._%+-]{1,64})(?<![.])@([A-Za-z0-9-]{1,63}\.)+[A-Za-z]{2,63}$"#
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: value)
    }
}
// MARK: - Settings View for Coach
struct SettingsViewCoach: View {
    @EnvironmentObject var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var coachProfile: CoachProfile  // Changed from UserProfile to CoachProfile
    
    private let primary = BrandColors.darkTeal
    private let dividerColor = Color.black.opacity(0.15)
    
    @State private var showLogoutPopup = false
    @State private var isSigningOut = false
    @State private var signOutError: String?

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    Text("Settings")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(primary)
                                .padding(10)
                                .background(Circle().fill(BrandColors.lightGray.opacity(0.7)))
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)

                // MARK: - Settings List
                VStack(spacing: 0) {
                    NavigationLink {
                        EditCoachProfileView(coachProfile: coachProfile)  // Now passes the correct type
                    } label: {
                        settingsRow(icon: "person", title: "Edit Profile",
                                    iconColor: primary, showChevron: true, showDivider: true)
                    }
                    
                    NavigationLink {
                        NotificationsView()
                    } label: {
                        settingsRow(icon: "bell", title: "Notifications",
                                    iconColor: primary, showChevron: true, showDivider: true)
                    }

                    NavigationLink {
                        ChangePasswordView()
                    } label: {
                        settingsRow(icon: "lock", title: "Change Password",
                                    iconColor: primary, showChevron: true, showDivider: true)
                    }

                    Button {
                        showLogoutPopup = true
                    } label: {
                        settingsRow(icon: "rectangle.portrait.and.arrow.right", title: "Logout",
                                    iconColor: primary, showChevron: false, showDivider: false)
                    }
                }
                .background(BrandColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
                .padding(.horizontal, 16)

                Spacer()
            }

            // MARK: - Logout Popup (identical to player version)
            if showLogoutPopup {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)

                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        VStack(spacing: 20) {
                            Text("Logout?")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)

                            Text("Are you sure you want to log out from this device?")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            if isSigningOut {
                                ProgressView().tint(primary).padding(.top, 4)
                            }

                            if let signOutError {
                                Text(signOutError)
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                            }

                            HStack(spacing: 16) {
                                Button("No") {
                                    withAnimation { showLogoutPopup = false }
                                }
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundColor(BrandColors.darkGray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(BrandColors.lightGray)
                                .cornerRadius(12)

                                Button("Yes") {
                                    performLogout()
                                }
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.red)
                                .cornerRadius(12)
                                .disabled(isSigningOut)
                            }
                            .padding(.top, 4)
                        }
                        .padding(EdgeInsets(top: 24, leading: 24, bottom: 20, trailing: 24))
                        .frame(width: 320)
                        .background(BrandColors.background)
                        .cornerRadius(20)
                        .shadow(radius: 12)
                        Spacer()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .transition(.scale)
            }
        }
        .animation(.easeInOut, value: showLogoutPopup)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Logout Logic
    private func performLogout() {
        isSigningOut = true
        signOutError = nil

        clearLocalCaches()

        Messaging.messaging().deleteToken { _ in
            self.signOutFirebase()
        }
    }

    private func signOutFirebase() {
        do {
            // 1. أرسل notification فوراً لإغلاق fullScreenCover
            NotificationCenter.default.post(name: .forceLogout, object: nil)
            
            // 2. امسح session
            session.user = nil
            session.role = nil
            session.isVerifiedCoach = false
            session.coachStatus = nil
            session.isGuest = false
            session.userListener?.remove()
            
            // 3. سجل خروج من Firebase
            try Auth.auth().signOut()
            
            // 4. اطلع من Settings
            DispatchQueue.main.async {
                self.presentationMode.wrappedValue.dismiss()
            }
            
            isSigningOut = false
            showLogoutPopup = false
            
        } catch {
            isSigningOut = false
            signOutError = "Failed to sign out: \(error.localizedDescription)"
        }
    }

    private func clearLocalCaches() {
        UserDefaults.standard.removeObject(forKey: "signup_profile_draft")
        UserDefaults.standard.removeObject(forKey: "current_user_profile")
        UserDefaults.standard.synchronize()
        ReportStateService.shared.reset()
    }

    // MARK: - View Builders (identical to player version)
    private func settingsRow(icon: String, title: String,
                             iconColor: Color, showChevron: Bool, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(.system(size: 17, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if showDivider {
                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)
                    .padding(.leading, 60)
            }
        }
    }
}
