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
    @Published var phone: String = ""
    @Published var isEmailVisible: Bool = false
    @Published var isPhoneNumberVisible: Bool = false
    @Published var profileImage: UIImage? = nil
    @Published var coachStatus: String = ""
    @Published var rejectionReason: String = ""

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
            
            // Fetch first team name BEFORE entering MainActor.run
            let teamSnap = try? await self.db.collection("teams")
                .whereField("coachUid", isEqualTo: userID)
                .getDocuments()
            // Sort client-side by createdAt (handles docs without the field)
            let sortedDocs = (teamSnap?.documents ?? []).sorted {
                let a = ($0.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
                let b = ($1.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
                return a < b
            }
            let hasTeam = !sortedDocs.isEmpty
            let firstTeamName = hasTeam ? (sortedDocs.first!.data()["teamName"] as? String ?? "") : ""

            await MainActor.run {
                // 1. Map basic info immediately
                self.coachProfile.name = (data["firstName"] as? String ?? "") + " " + (data["lastName"] as? String ?? "")
                self.coachProfile.location = data["location"] as? String ?? ""
                self.coachProfile.email = data["email"] as? String ?? ""
                self.coachProfile.phone = data["phone"] as? String ?? ""
                self.coachProfile.isEmailVisible = data["isEmailVisible"] as? Bool ?? false
                self.coachProfile.isPhoneNumberVisible = data["isPhoneNumberVisible"] as? Bool ?? false
                self.coachProfile.team = firstTeamName
                self.coachProfile.coachStatus = data["coachStatus"] as? String ?? ""
                self.coachProfile.rejectionReason = data["rejectionReason"] as? String ?? ""
                
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
    @EnvironmentObject var session: AppSession
    @StateObject private var viewModel: CoachProfileViewModel
    @State private var selectedContent: ContentType = .currentTeam
    @State private var goToSettings = false
    @State private var showNotificationsList = false

    private var isCurrentUser: Bool
    private var isRootProfileView: Bool = true // Adjust if needed

    var isAdminViewing: Bool
    var onAdminApprove: (() -> Void)?
    var onAdminReject: (() -> Void)?

    enum ContentType: String, CaseIterable {
        case currentTeam = "Current Teams"
        case matchSchedule = "Match Schedule"
    }

    init() {
        _viewModel = StateObject(wrappedValue: CoachProfileViewModel(userID: nil))
        self.isCurrentUser = true
        self.isAdminViewing = false
        self.onAdminApprove = nil
        self.onAdminReject = nil
    }

    init(userID: String, isAdminViewing: Bool = false, onAdminApprove: (() -> Void)? = nil, onAdminReject: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: CoachProfileViewModel(userID: userID))
        self.isCurrentUser = (userID == Auth.auth().currentUser?.uid)
        self.isRootProfileView = false
        self.isAdminViewing = isAdminViewing
        self.onAdminApprove = onAdminApprove
        self.onAdminReject = onAdminReject
    }

    var body: some View {
        NavigationStack {
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
                            onReport: {},
                            reportService: ReportStateService.shared,
                            reportedID: viewModel.coachProfile.email,
                            isAdminViewing: isAdminViewing,
                            onAdminApprove: onAdminApprove,
                            onAdminReject: onAdminReject
                        )
                        ProfileHeaderViewCoach(coachProfile: viewModel.coachProfile)
                        InfoGridViewCoach(coachProfile: viewModel.coachProfile)
                        ContentTabViewCoach(selectedContent: $selectedContent)
                        switch selectedContent {
                        case .currentTeam:
                            CurrentTeamView()
                                .padding(.top, 10)
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
            .navigationDestination(isPresented: $goToSettings) {
                SettingsViewCoach(coachProfile: viewModel.coachProfile)
            }
            .navigationDestination(isPresented: $showNotificationsList) {
                NotificationsView()
                    .environmentObject(session)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileUpdated)) { _ in
            Task {
                await viewModel.fetchProfile(userID: Auth.auth().currentUser?.uid ?? "")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .teamDeleted)) { _ in
            // Refresh coach header (TEAM field) immediately after deletion
            Task {
                await viewModel.fetchProfile(userID: Auth.auth().currentUser?.uid ?? "")
            }
        }
        .navigationBarBackButtonHidden(true)
        } // end NavigationStack
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
    var isAdminViewing: Bool = false
    var onAdminApprove: (() -> Void)? = nil
    var onAdminReject: (() -> Void)? = nil

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
            if isAdminViewing {
                // Admin viewing - show approve/reject buttons (same style as in coach cards)
                HStack(spacing: 8) {
                    if let onApprove = onAdminApprove {
                        Button(action: onApprove) {
                            Text("Approve")
                                .foregroundColor(.white)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(BrandColors.darkTeal)
                                .clipShape(Capsule())
                        }
                    }
                    
                    if let onReject = onAdminReject {
                        Button(action: onReject) {
                            Text("Reject")
                                .foregroundColor(.red)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color(UIColor.systemGray6))
                                .clipShape(Capsule())
                        }
                    }
                }
            } else if isCurrentUser {
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
            } else if !isAdminViewing {
                // Only show report flag if not admin
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
    @State private var allTeamNames: [String] = []
    @State private var showAllTeamNames = false

    // TEAMS stat — first team default, arrow shows remaining teams only
    @ViewBuilder private func TeamsStatItem(coachProfile: CoachProfile) -> some View {
        VStack(spacing: 6) {
            Text("TEAMS")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(accentColor.opacity(0.8))

            if allTeamNames.isEmpty {
                Text("-")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
            } else {
                // Default: first team name (bold, black)
                Text(allTeamNames.first ?? "-")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)

                // Arrow — only show if there are more teams beyond first
                if allTeamNames.count > 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAllTeamNames.toggle() }
                    } label: {
                        Image(systemName: showAllTeamNames ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                    .buttonStyle(.plain)

                    // Expanded: show ONLY the other teams (not the first one again)
                    if showAllTeamNames {
                        VStack(spacing: 4) {
                            ForEach(allTeamNames.dropFirst(), id: \.self) { name in
                                Text(name)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(.black.opacity(0.7))
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .onAppear { loadAllTeamNames() }
        .onReceive(NotificationCenter.default.publisher(for: .teamDeleted)) { _ in loadAllTeamNames() }
        .onReceive(NotificationCenter.default.publisher(for: .profileUpdated)) { _ in loadAllTeamNames() }
    }

    private func loadAllTeamNames() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            let snap = try? await Firestore.firestore().collection("teams")
                .whereField("coachUid", isEqualTo: uid)
                .getDocuments()
            // Sort client-side by createdAt
            let sorted = (snap?.documents ?? []).sorted {
                let a = ($0.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
                let b = ($1.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
                return a < b
            }
            let names = sorted.compactMap { $0.data()["teamName"] as? String }
            await MainActor.run { allTeamNames = names }
        }
    }

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
                TeamsStatItem(coachProfile: coachProfile)
                Spacer()
                UserStatItem(title: "LOCATION", value: coachProfile.location)
                Spacer()
            }

            // Row 2: Contact Info (if visible)
            HStack {
                if coachProfile.isEmailVisible {
                    Spacer()
                    UserStatItem(title: "EMAIL", value: coachProfile.email)
                    Spacer()
                }
                
                if coachProfile.isPhoneNumberVisible {
                    Spacer()
                    UserStatItem(title: "PHONE", value: coachProfile.phone)
                    Spacer()
                }
            }
            .opacity((coachProfile.isEmailVisible || coachProfile.isPhoneNumberVisible) ? 1 : 0)
            .frame(height: (coachProfile.isEmailVisible || coachProfile.isPhoneNumberVisible) ? nil : 0)


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
            ContentTabButton(title: "Current Teams", type: .currentTeam, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
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
    @State private var showImageSourcePicker = false
    @State private var showCameraOrLibrary = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var showUIImagePicker = false

    // Email Validation State
    @FocusState private var emailFocused: Bool
    @State private var emailExists = false
    @State private var emailCheckError: String? = nil
    @State private var emailCheckTask: Task<Void, Never>? = nil
    @State private var isCheckingEmail = false
    
    // Phone State
    @State private var phone: String
    @State private var isPhoneNumberVisible: Bool
    @State private var phoneNonDigitError = false
    private let selectedDialCode = "+966"

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
        isNameValid && isEmailFieldValid && isLocationValid && isPhoneValid &&
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
        
        // Initialize phone - Extract local phone part (remove +966)
        let storedPhone = coachProfile.phone
        let localPart = storedPhone.hasPrefix("+966") ? String(storedPhone.dropFirst(4)) : storedPhone
        _phone = State(initialValue: localPart)
        _isPhoneNumberVisible = State(initialValue: coachProfile.isPhoneNumberVisible)
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
                        .padding(.bottom, 100)
                }
                .padding(.horizontal)
            }
            .opacity(showVerifyPrompt || showInfoOverlay ? 0.2 : 1.0)

            if showInfoOverlay {
                InfoOverlay(primary: primary, title: overlayMessage, isError: overlayIsError, onOk: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showInfoOverlay = false }
                    if !overlayIsError { dismiss() }
                })
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
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
        .sheet(isPresented: $showUIImagePicker) {
            UIImagePickerWrapper(sourceType: imagePickerSource) { image in
                self.profileImage = image
            }
            .ignoresSafeArea()
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
                Button {
                    imagePickerSource = .photoLibrary
                    showUIImagePicker = true
                } label: {
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
            
            // Phone Field
            fieldLabel("Phone number")
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
                        get: { phone },
                        set: { val in
                            phoneNonDigitError = val.contains { !$0.isNumber }
                            phone = val.filter { $0.isNumber }
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
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(!phone.isEmpty && !isPhoneValid ? Color.red : Color.clear, lineWidth: 1)
            )

            if phoneNonDigitError {
                Text("Numbers only (0–9).")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.red)
            } else if !phone.isEmpty && !isPhoneValid {
                Text("Enter a valid Saudi number (starts with 5, 9 digits).")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.red)
            }
        }
    }
    
    private var isPhoneValid: Bool {
        isValidPhone(code: selectedDialCode, local: phone)
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
            
            HStack {
                Text("Make my phone number visible")
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
            overlayMessage = "User not authenticated"; overlayIsError = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showInfoOverlay = true }
            return
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
                overlayMessage = "Profile updated successfully"
                overlayIsError = false
                isSaving = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showInfoOverlay = true }
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
            let fullPhone = selectedDialCode + phone
            
            var userUpdates: [String: Any] = [
                "firstName": name.split(separator: " ").first.map(String.init) ?? name,
                "lastName": name.split(separator: " ").dropFirst().joined(separator: " "),
                "location": location,
                "phone": fullPhone,
                "isEmailVisible": isEmailVisible,
                "isPhoneNumberVisible": isPhoneNumberVisible,
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
    
    private func isValidPhone(code: String, local: String) -> Bool {
        guard !local.isEmpty else { return false }
        let len = local.count
        var ok = (6...15).contains(len)
        if code == "+966" { ok = (len == 9) && local.first == "5" }
        return ok
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
    @State private var showEditProfile = false

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
                    Button {
                        showEditProfile = true
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
        .navigationDestination(isPresented: $showEditProfile) {
            EditCoachProfileView(coachProfile: coachProfile)
        }
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

// MARK: - CurrentTeamView for Coach Profile
struct CurrentTeamView: View {
    @EnvironmentObject var session: AppSession
    @State private var teams: [SaudiTeam] = []
    @State private var team: SaudiTeam? = nil
    @State private var isLoading = true
    @State private var navigateToTeamDetail = false
    @State private var selectedTeamForDetail: SaudiTeam? = nil
    @State private var showAllTeams = false
    @State private var showCreateTeam = false
    @State private var coachStatusApproved = false
    @State private var showNotApprovedAlert = false
    private let accentColor = BrandColors.darkTeal

    var body: some View {
        VStack(spacing: 14) {
            if isLoading {
                ProgressView().tint(accentColor).padding()
            } else {
                // ── All teams stacked — all highlighted equally ──
                ForEach(teams) { t in
                    TeamCard(team: t, isHighlighted: true)
                        .padding(.horizontal, 20)
                        .onTapGesture { selectedTeamForDetail = t }
                }

                // ── Create Team button — always visible ───────────────
                Button {
                    if coachStatusApproved { showCreateTeam = true }
                    else { showNotApprovedAlert = true }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(accentColor.opacity(0.1)).frame(width: 56, height: 56)
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(accentColor.opacity(0.8))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Create New Team")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(accentColor)
                            Text("Set up another academy team")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(accentColor.opacity(0.5))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(BrandColors.background)
                            .shadow(color: accentColor.opacity(0.12), radius: 8, y: 3)
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(accentColor.opacity(0.25), lineWidth: 1.2))
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
        .navigationDestination(item: $selectedTeamForDetail) { t in
            TeamDetailView(team: t)
        }
        .navigationDestination(isPresented: $showCreateTeam) {
            CreateTeamSheet(onCreated: {
                showCreateTeam = false
                loadTeam()
                // Refresh coach profile header (TEAM field) immediately
                NotificationCenter.default.post(name: .profileUpdated, object: nil)
            })
        }
        .onReceive(NotificationCenter.default.publisher(for: .teamDeleted)) { _ in
            loadTeam()  // reload all teams after deletion
        }
        .overlay {
            if showNotApprovedAlert {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                        .onTapGesture { withAnimation { showNotApprovedAlert = false } }
                    VStack(spacing: 0) {
                        VStack(spacing: 12) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .font(.system(size: 40)).foregroundColor(accentColor)
                            Text("Pending Approval")
                                .font(.system(size: 18, weight: .bold))
                            Text("Your account is pending admin approval. You'll be able to create a team once approved.")
                                .font(.system(size: 14)).foregroundColor(.secondary).multilineTextAlignment(.center)
                        }
                        .padding(.top, 24).padding(.horizontal, 20).padding(.bottom, 20)
                        Divider()
                        Button { withAnimation { showNotApprovedAlert = false } } label: {
                            Text("OK").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(accentColor).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 16)
                    }
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)))
                    .padding(.horizontal, 30)
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                    .transition(.scale.combined(with: .opacity))
                }
                .animation(.spring(response: 0.3), value: showNotApprovedAlert)
            }
        }
        .onAppear { loadTeam(); loadCoachStatus() }
    }

    private func loadCoachStatus() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            let doc = try? await Firestore.firestore().collection("users").document(uid).getDocument()
            let status = doc?.data()?["coachStatus"] as? String
            await MainActor.run { coachStatusApproved = (status == "approved") }
        }
    }

    private func loadTeam() {
        guard let uid = Auth.auth().currentUser?.uid else { isLoading = false; return }
        Task {
            let db = Firestore.firestore()
            let snap = try? await db.collection("teams")
                .whereField("coachUid", isEqualTo: uid)
                .getDocuments()
            // Sort client-side by createdAt (oldest first = default shown)
            let docs = (snap?.documents ?? []).sorted {
                let a = ($0.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
                let b = ($1.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
                return a < b
            }
            guard !docs.isEmpty else {
                await MainActor.run { self.teams = []; self.team = nil; self.isLoading = false }
                return
            }
            var coachName: String? = nil
            if let cd = try? await db.collection("users").document(uid).getDocument(),
               let cdata = cd.data() {
                let fn = cdata["firstName"] as? String ?? ""
                let ln = cdata["lastName"]  as? String ?? ""
                coachName = "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)
            }
            var loaded: [SaudiTeam] = []
            for doc in docs {
                let data = doc.data()
                let playersSnap = try? await db.collection("teams").document(doc.documentID)
                    .collection("players").getDocuments()
                loaded.append(SaudiTeam(
                    id: doc.documentID,
                    teamName: data["teamName"] as? String ?? "",
                    logoURL:  data["logoURL"]  as? String,
                    coachUID: uid,
                    coachName: coachName,
                    playerCount: playersSnap?.documents.count ?? 0,
                    city:   data["city"]   as? String ?? "",
                    street: data["street"] as? String ?? ""
                ))
            }
            await MainActor.run {
                self.teams = loaded
                self.team  = loaded.first  // default = oldest (first created)
                self.isLoading = false
            }
        }
    }
}

// MARK: - UIImagePickerWrapper (avoids NavigationLink dismiss bug with PhotosPicker)
struct UIImagePickerWrapper: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImagePicked: onImagePicked) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImagePicked: (UIImage) -> Void
        init(onImagePicked: @escaping (UIImage) -> Void) { self.onImagePicked = onImagePicked }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let img = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            picker.dismiss(animated: true)
            if let img { onImagePicked(img) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
