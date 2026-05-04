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
    // Academy
    @Published var currentAcademy: String = ""
    @Published var pendingAcademy: String = ""
    // DOB / Age
    @Published var dob: Date? = nil

    init() {}

    var age: Int? {
        guard let dob = dob else { return nil }
        return Calendar.current.dateComponents([.year], from: dob, to: Date()).year
    }
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

            // Read currentAcademy from users doc directly
            let currentAcademy = data["currentAcademy"] as? String ?? ""
            let hasTeam = !currentAcademy.isEmpty

            await MainActor.run {
                // 1. Map basic info immediately
                self.coachProfile.name = (data["firstName"] as? String ?? "") + " " + (data["lastName"] as? String ?? "")
                self.coachProfile.location = data["location"] as? String ?? ""
                self.coachProfile.email = data["email"] as? String ?? ""
                self.coachProfile.phone = data["phone"] as? String ?? ""
                self.coachProfile.isEmailVisible = data["isEmailVisible"] as? Bool ?? false
                self.coachProfile.isPhoneNumberVisible = data["isPhoneNumberVisible"] as? Bool ?? false
                self.coachProfile.team = currentAcademy
                self.coachProfile.coachStatus = data["coachStatus"] as? String ?? ""
                self.coachProfile.rejectionReason = data["rejectionReason"] as? String ?? ""
                self.coachProfile.currentAcademy = data["currentAcademy"] as? String ?? ""
                self.coachProfile.pendingAcademy = data["pendingAcademy"] as? String ?? ""
                if let dobTS = data["dob"] as? Timestamp {
                    self.coachProfile.dob = dobTS.dateValue()
                }

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
    @State private var goToSettings = false
    @State private var showNotificationsList = false
    @State private var showLeaveAcademyConfirm = false

    // Navigation state lifted up from CurrentAcademyView so that
    // .navigationDestination sits directly inside the NavigationStack owner,
    // which is the only reliable way to trigger push navigation in SwiftUI.
    @State private var navigateToAcademyDetail = false
    @State private var navigateToCreatedAcademy = false
    @State private var destinationAcademy: HaddafAcademy? = nil

    private var isCurrentUser: Bool
    private var isRootProfileView: Bool = true

    var isAdminViewing: Bool
    var onAdminApprove: (() -> Void)?
    var onAdminReject: (() -> Void)?

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

                            // ── Current Academy title ──
                            HStack {
                                Text("Current Academy")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(BrandColors.darkTeal)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                            CurrentAcademyView(
                                    coachProfile: viewModel.coachProfile,
                                    isCurrentUser: isCurrentUser,
                                    showLeaveConfirm: $showLeaveAcademyConfirm,
                                    navigateToAcademyDetail: $navigateToAcademyDetail,
                                    navigateToCreated: $navigateToCreatedAcademy,
                                    destinationAcademy: $destinationAcademy
                                )
                                .padding(.horizontal, 20)
                                .padding(.top, 10)
                        }
                        .padding(.bottom, 100)
                    }
                }
                .navigationDestination(isPresented: $goToSettings) {
                    SettingsViewCoach(coachProfile: viewModel.coachProfile)
                }
                .navigationDestination(isPresented: $showNotificationsList) {
                    NotificationsView(isCoach: true)
                        .environmentObject(session)
                }
                // These two are lifted from CurrentAcademyView so they live
                // directly inside the NavigationStack — the only place SwiftUI
                // reliably handles push navigation.
                .navigationDestination(isPresented: $navigateToAcademyDetail) {
                    if let academy = destinationAcademy {
                        AcademyDetailView(academy: academy)
                            .environmentObject(session)
                    }
                }
                .navigationDestination(isPresented: $navigateToCreatedAcademy) {
                    if let academy = destinationAcademy {
                        AcademyDetailView(academy: academy)
                            .environmentObject(session)
                    }
                }

                // Full-screen Leave Academy confirmation popup
                if showLeaveAcademyConfirm {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    GeometryReader { geometry in
                        VStack {
                            Spacer()
                            VStack(spacing: 20) {
                                Text("Leave Academy?")
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)

                                Text("Are you sure you want to leave \(viewModel.coachProfile.currentAcademy)?")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 24)

                                HStack(spacing: 16) {
                                    Button("No") {
                                        withAnimation { showLeaveAcademyConfirm = false }
                                    }
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundColor(BrandColors.darkGray)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(BrandColors.lightGray)
                                    .cornerRadius(12)

                                    Button("Yes") {
                                        withAnimation { showLeaveAcademyConfirm = false }
                                        Task { await leaveAcademy() }
                                    }
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.red)
                                    .cornerRadius(12)
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
            .animation(.easeInOut, value: showLeaveAcademyConfirm)
            .onReceive(NotificationCenter.default.publisher(for: .profileUpdated)) { _ in
                Task {
                    await viewModel.fetchProfile(userID: Auth.auth().currentUser?.uid ?? "")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .teamDeleted)) { _ in
                Task {
                    await viewModel.fetchProfile(userID: Auth.auth().currentUser?.uid ?? "")
                }
            }
            .navigationBarBackButtonHidden(true)
        } // end NavigationStack
    }

    private func leaveAcademy() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        do {
            // 1. Remove coach from all categories' coaches array in the academy
            let userDoc = try? await db.collection("users").document(uid).getDocument()
            let academyId = userDoc?.data()?["academyId"] as? String ?? ""
            if !academyId.isEmpty {
                let catsSnap = try? await db.collection("academies").document(academyId)
                    .collection("categories").getDocuments()
                for catDoc in catsSnap?.documents ?? [] {
                    try? await db.collection("academies").document(academyId)
                        .collection("categories").document(catDoc.documentID)
                        .updateData(["coaches": FieldValue.arrayRemove([uid])])
                }
            }

            // 2. Clear academy fields from users doc
            try await db.collection("users").document(uid).updateData([
                "currentAcademy": FieldValue.delete(),
                "academyId": FieldValue.delete(),
                "isInAcademy": false
            ])
            await MainActor.run {
                viewModel.coachProfile.currentAcademy = ""
                viewModel.coachProfile.pendingAcademy = ""
            }
        } catch {
            print("Error leaving academy: \(error)")
        }
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
                // Admin viewing — show approve/reject buttons
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
                NotificationBellButton(
                    showNotifications: $showNotifications,
                    userId: Auth.auth().currentUser?.uid ?? ""
                )
                Button { goToSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .foregroundColor(BrandColors.darkTeal)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            } else if !isAdminViewing {
                // Show report flag only when not admin
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

    @ViewBuilder private func StatItem(title: String, value: String, isPending: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(accentColor.opacity(0.8))
            if isPending {
                VStack(spacing: 2) {
                    Text(value.isEmpty ? "-" : value)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(BrandColors.darkGray)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pending")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(BrandColors.gold)
                }
            } else {
                Text(value.isEmpty ? "-" : value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            // Row 1: Academy Name · Age · Location
            HStack(spacing: 0) {
                // If coach has a pending *change* request, show "-" until admin approves
                let hasPendingChange = !coachProfile.pendingAcademy.isEmpty && !coachProfile.currentAcademy.isEmpty
                let isPendingJoin    = !coachProfile.pendingAcademy.isEmpty && coachProfile.currentAcademy.isEmpty
                let academyDisplay: String = {
                    if hasPendingChange { return "-" }
                    if !coachProfile.currentAcademy.isEmpty { return coachProfile.currentAcademy }
                    if isPendingJoin { return coachProfile.pendingAcademy }
                    return "-"
                }()
                StatItem(title: "ACADEMY NAME", value: academyDisplay, isPending: isPendingJoin)
                    .frame(maxWidth: .infinity)
                Divider().frame(height: 36)
                StatItem(title: "AGE", value: coachProfile.age.map { "\($0)" } ?? "-")
                    .frame(maxWidth: .infinity)
                Divider().frame(height: 36)
                StatItem(title: "LOCATION", value: coachProfile.location)
                    .frame(maxWidth: .infinity)
            }

            // Row 2: Contact Info (if visible)
            if coachProfile.isEmailVisible || coachProfile.isPhoneNumberVisible {
                HStack {
                    if coachProfile.isEmailVisible {
                        Spacer()
                        StatItem(title: "EMAIL", value: coachProfile.email)
                        Spacer()
                    }
                    if coachProfile.isPhoneNumberVisible {
                        Spacer()
                        StatItem(title: "PHONE", value: coachProfile.phone)
                        Spacer()
                    }
                }
            }
        }
        .padding(.vertical, 25)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(BrandColors.background)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        )
        .padding(.horizontal)
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

        // Initialize phone — extract local part (remove +966 prefix)
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

            // Email error messages
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

    // Toggles Section
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

    // Update Button
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

    // MARK: - Helper Functions
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

            // Upload profile picture if changed
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

            // Update local model
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
    @ObservedObject var coachProfile: CoachProfile

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

            // MARK: - Logout Popup
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
            // 1. Post notification immediately to close any fullScreenCover
            NotificationCenter.default.post(name: .forceLogout, object: nil)

            // 2. Clear session
            session.user = nil
            session.role = nil
            session.isVerifiedCoach = false
            session.coachStatus = nil
            session.isGuest = false
            session.userListener?.remove()

            // 3. Sign out from Firebase
            try Auth.auth().signOut()

            // 4. Dismiss settings screen
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

    // MARK: - View Builders
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

// MARK: - Current Academy View
struct CurrentAcademyView: View {
    @ObservedObject var coachProfile: CoachProfile
    var isCurrentUser: Bool = true
    @Binding var showLeaveConfirm: Bool

    // Navigation state is owned by CoachProfileContentView (the NavigationStack owner)
    // and passed down as bindings, so .navigationDestination works reliably.
    @Binding var navigateToAcademyDetail: Bool
    @Binding var navigateToCreated: Bool
    @Binding var destinationAcademy: HaddafAcademy?

    private let accent = BrandColors.darkTeal

    @State private var showChangeAcademySheet = false
    @State private var isProcessing = false
    @State private var errorText: String? = nil
    @State private var showAcademySetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Show the appropriate row based on academy/pending state
            if coachProfile.pendingAcademy.isEmpty && coachProfile.currentAcademy.isEmpty {
                // No academy at all
                noAcademyRow
            } else if !coachProfile.pendingAcademy.isEmpty && coachProfile.currentAcademy.isEmpty {
                // Pending join — first time joining
                pendingAcademyRow
            } else if !coachProfile.pendingAcademy.isEmpty && !coachProfile.currentAcademy.isEmpty {
                // Has current academy + a pending change request
                pendingChangeRow
            } else {
                // Has an approved academy, no pending change
                approvedAcademyRow
            }

            if let err = errorText {
                Text(err)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.red)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BrandColors.background)
                .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
        )
        // Change Academy Sheet
        .sheet(isPresented: $showChangeAcademySheet) {
            ChangeAcademySheet(
                currentAcademy: coachProfile.currentAcademy,
                onSubmit: { newAcademy, fileURL in
                    Task { await submitAcademyChangeRequest(newAcademy: newAcademy, fileURL: fileURL) }
                }
            )
            .presentationDetents([.large])
            .presentationBackground(BrandColors.background)
            .presentationCornerRadius(28)
        }
        // Pre-load academy data on appear so logo is visible immediately
        .task {
            if !coachProfile.currentAcademy.isEmpty && destinationAcademy == nil {
                await loadCurrentAcademy()
            }
        }
    }

    // MARK: - Sub-views

    private var noAcademyRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.gray.opacity(0.1)).frame(width: 48, height: 48)
                Image(systemName: "building.2")
                    .font(.system(size: 20))
                    .foregroundColor(.gray.opacity(0.6))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("No Academy")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                if isCurrentUser {
                    Text("Tap Join to join an academy")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            Spacer()
            if isCurrentUser {
                Button { showChangeAcademySheet = true } label: {
                    Text("Join")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pendingAcademyRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(BrandColors.gold.opacity(0.12)).frame(width: 48, height: 48)
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 20))
                    .foregroundColor(BrandColors.gold)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(coachProfile.pendingAcademy)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Text("Pending admin approval")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(BrandColors.gold)
            }
            Spacer()
        }
    }

    // Current academy exists but a *change* request is pending
    private var pendingChangeRow: some View {
        VStack(spacing: 10) {
            // ── Current academy row — still tappable (coach is still a member) ──
            Button {
                Task {
                    await loadCurrentAcademy()
                    await MainActor.run { navigateToAcademyDetail = true }
                }
            } label: {
                HStack(spacing: 12) {
                    if let logoURL = destinationAcademy?.logoURL, !logoURL.isEmpty {
                        AcademyLogoView(logoURL: logoURL, size: 48)
                    } else {
                        ZStack {
                            Circle().fill(accent.opacity(0.1)).frame(width: 48, height: 48)
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 20))
                                .foregroundColor(accent)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(coachProfile.currentAcademy)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        if let city = destinationAcademy?.city, !city.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(accent.opacity(0.6))
                                Text(city)
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(accent.opacity(0.4))
                }
            }
            .buttonStyle(.plain)

            // ── Pending change banner ──
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 12))
                    .foregroundColor(BrandColors.gold)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Change request pending approval")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(BrandColors.gold)
                    Text("Requested: \(coachProfile.pendingAcademy)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(BrandColors.gold.opacity(0.8))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(BrandColors.gold.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(BrandColors.gold.opacity(0.25), lineWidth: 1))
            )
            // No Change/Leave buttons while a change request is pending
        }
    }

    // MARK: - FIX: Navigation state is lifted to CoachProfileContentView (NavigationStack owner).
    // Tapping the academy row loads the academy data then sets the parent binding,
    // which triggers .navigationDestination defined at the NavigationStack level.
    private var approvedAcademyRow: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    await loadCurrentAcademy()
                    await MainActor.run { navigateToAcademyDetail = true }
                }
            } label: {
                HStack(spacing: 12) {
                    // Show actual academy logo if loaded, otherwise fallback icon
                    if let logoURL = destinationAcademy?.logoURL, !logoURL.isEmpty {
                        AcademyLogoView(logoURL: logoURL, size: 48)
                    } else {
                        ZStack {
                            Circle().fill(accent.opacity(0.1)).frame(width: 48, height: 48)
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 20))
                                .foregroundColor(accent)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(coachProfile.currentAcademy)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        if let city = destinationAcademy?.city, !city.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(accent.opacity(0.6))
                                Text(city)
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if let street = destinationAcademy?.street, !street.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "road.lanes")
                                    .font(.system(size: 10))
                                    .foregroundColor(accent.opacity(0.4))
                                Text(street)
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundColor(.secondary.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(accent.opacity(0.4))
                }
            }
            .buttonStyle(.plain)

            if isCurrentUser {
                HStack(spacing: 10) {
                    Button { showChangeAcademySheet = true } label: {
                        Text("Change Academy")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button { showLeaveConfirm = true } label: {
                        Text("Leave Academy")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)
                }
            }
        }
        .fullScreenCover(isPresented: $showAcademySetup) {
            AcademySetupFlow(academyName: coachProfile.currentAcademy, coachUID: Auth.auth().currentUser?.uid ?? "") { academy in
                showAcademySetup = false
                if let academy = academy {
                    destinationAcademy = academy
                    navigateToCreated = true
                }
            }
        }
    }

    // MARK: - Actions

    private func submitAcademyChangeRequest(newAcademy: String, fileURL: URL) async {
        guard let uid = Auth.auth().currentUser?.uid,
              let email = Auth.auth().currentUser?.email else { return }
        isProcessing = true
        errorText = nil
        do {
            let db = Firestore.firestore()
            // Upload verification document to Firebase Storage
            let storage = Storage.storage()
            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: fileURL)
            let ref = storage.reference().child("coach_verifications/\(uid)/academy_change_\(UUID().uuidString).\(fileURL.pathExtension)")
            _ = try await ref.putDataAsync(data)
            let downloadURL = try await ref.downloadURL()

            let requestType = coachProfile.currentAcademy.isEmpty ? "join_academy" : "change_academy"
            let requestData: [String: Any] = [
                "uid": uid,
                "email": email,
                "status": "pending",
                "requestType": requestType,
                "requestedAcademy": newAcademy,
                "previousAcademy": coachProfile.currentAcademy,
                "isInAcademy": true,
                "submittedAt": FieldValue.serverTimestamp(),
                "verificationFile": downloadURL.absoluteString,
                "timeline": [[
                    "id": UUID().uuidString,
                    "timestamp": Timestamp(date: Date()),
                    "type": "Submitted",
                    "documentURL": downloadURL.absoluteString,
                    "status": "pending"
                ]]
            ]

            // Store as a new document so admin sees it as a separate request
            let reqRef = db.collection("coachRequests").document()
            try await reqRef.setData(requestData)

            // Remove coach from current academy immediately
            let userDoc = try? await db.collection("users").document(uid).getDocument()
            let currentAcademyId = userDoc?.data()?["academyId"] as? String ?? ""
            if !currentAcademyId.isEmpty {
                let catsSnap = try? await db.collection("academies").document(currentAcademyId)
                    .collection("categories").getDocuments()
                for catDoc in catsSnap?.documents ?? [] {
                    try? await db.collection("academies").document(currentAcademyId)
                        .collection("categories").document(catDoc.documentID)
                        .updateData(["coaches": FieldValue.arrayRemove([uid])])
                }
            }

            // Clear current academy + mark pending on user doc
            try await db.collection("users").document(uid).updateData([
                "currentAcademy": FieldValue.delete(),
                "academyId": FieldValue.delete(),
                "isInAcademy": false,
                "pendingAcademy": newAcademy
            ])

            await MainActor.run {
                coachProfile.currentAcademy = ""
                coachProfile.pendingAcademy = newAcademy
                destinationAcademy = nil
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                errorText = "Failed to submit request: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }
}

// MARK: - Change Academy Sheet
struct ChangeAcademySheet: View {
    let currentAcademy: String
    let onSubmit: (String, URL) -> Void

    @Environment(\.dismiss) private var dismiss
    private let accent = BrandColors.darkTeal

    @State private var selectedAcademy = ""
    @State private var academySearch = ""
    @State private var showAcademyPicker = false
    @State private var verificationFile: URL? = nil
    @State private var verificationFileName = ""
    @State private var showFileImporter = false
    @State private var fileSizeError: String? = nil
    @State private var showVerificationInfo = false
    private let maxFileSizeBytes: Int64 = 10 * 1024 * 1024

    private var isFormValid: Bool {
        !selectedAcademy.isEmpty && verificationFile != nil && fileSizeError == nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !currentAcademy.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Current Academy")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.secondary)
                            Text(currentAcademy)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(UIColor.systemGray6)))
                    }

                    // Academy Picker
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("New Academy")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(accent.opacity(0.75))
                            Text("*").font(.system(size: 12, weight: .bold)).foregroundColor(.red).padding(.top, -2)
                        }
                        Button { academySearch = ""; showAcademyPicker = true } label: {
                            HStack {
                                Text(selectedAcademy.isEmpty ? "Select academy" : selectedAcademy)
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundColor(selectedAcademy.isEmpty ? .gray : accent)
                                    .lineLimit(1).truncationMode(.tail)
                                Spacer()
                                Image(systemName: "chevron.down").foregroundColor(accent.opacity(0.85))
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(BrandColors.background)
                                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showAcademyPicker) {
                            AcademyPickerSheet(
                                selection: $selectedAcademy,
                                searchText: $academySearch,
                                showSheet: $showAcademyPicker,
                                accent: accent
                            )
                        }
                    }

                    // Verification Document Upload
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Verification Document")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(accent.opacity(0.75))
                            Text("*").font(.system(size: 12, weight: .bold)).foregroundColor(.red).padding(.top, -2)
                            Button { showVerificationInfo = true } label: {
                                Image(systemName: "info.circle").font(.system(size: 15)).foregroundColor(accent)
                            }
                        }
                        .alert("Verification Help", isPresented: $showVerificationInfo) {
                            Button("OK", role: .cancel) {}
                        } message: {
                            Text("Upload a document proving your affiliation with the selected academy.")
                            + Text("\n\nAccepted: PDF or image. Max 10 MB.")
                        }

                        Button { showFileImporter = true } label: {
                            HStack {
                                Image(systemName: verificationFile == nil ? "doc.badge.plus" : "doc.fill")
                                    .foregroundColor(accent)
                                Text(verificationFileName.isEmpty ? "Upload Document (Max 10 MB)" : verificationFileName)
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundColor(verificationFile == nil ? .gray : accent)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                if verificationFile != nil {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(BrandColors.actionGreen)
                                } else {
                                    Image(systemName: "arrow.up.doc").foregroundColor(.gray)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(BrandColors.background)
                                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: false) { result in
                            switch result {
                            case .success(let urls):
                                guard let url = urls.first else { return }
                                do {
                                    let accessing = url.startAccessingSecurityScopedResource()
                                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                                    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                                    let size = attrs[.size] as? Int64 ?? 0
                                    if size > maxFileSizeBytes {
                                        fileSizeError = "File exceeds 10 MB limit."
                                        verificationFile = nil; verificationFileName = ""
                                    } else {
                                        verificationFile = url
                                        verificationFileName = url.lastPathComponent
                                        fileSizeError = nil
                                    }
                                } catch {
                                    fileSizeError = "Unable to read file."
                                }
                            case .failure:
                                fileSizeError = "Failed to import file."
                            }
                        }

                        if let err = fileSizeError {
                            Text(err).font(.system(size: 13, design: .rounded)).foregroundColor(.red)
                        }
                    }

                    // Submit Button
                    Button {
                        if isFormValid, let file = verificationFile {
                            onSubmit(selectedAcademy, file)
                            dismiss()
                        }
                    } label: {
                        Text(currentAcademy.isEmpty ? "Request to Join Academy" : "Request Academy Change")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isFormValid ? accent : accent.opacity(0.4))
                            .clipShape(Capsule())
                    }
                    .disabled(!isFormValid)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle(currentAcademy.isEmpty ? "Join Academy" : "Change Academy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .background(BrandColors.backgroundGradientEnd.ignoresSafeArea())
        }
    }
}

// MARK: - CurrentAcademyView helper extension
extension CurrentAcademyView {
    /// Fetches the full HaddafAcademy object for the coach's current academy
    /// and stores it in the parent-owned `destinationAcademy` binding.
    func loadCurrentAcademy() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()

        let academyName = coachProfile.currentAcademy.trimmingCharacters(in: .whitespacesAndNewlines)

        // Load ALL academy docs and find the best one by name match + most categories.
        // This handles ghost docs (created with coach UID, no name/categories) vs real docs.
        let allSnap = try? await db.collection("academies").getDocuments()
        let allDocs = allSnap?.documents ?? []

        // Collect all candidates: docs where name matches OR coach is in categories
        var candidateDocs: [(doc: DocumentSnapshot, catCount: Int, coachIsHere: Bool)] = []
        for doc in allDocs {
            let docName = (doc.data()["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let nameMatch = !academyName.isEmpty && docName.lowercased() == academyName.lowercased()
            let catsSnap = try? await db.collection("academies").document(doc.documentID)
                .collection("categories").getDocuments()
            let catDocs = catsSnap?.documents ?? []
            let catCount = catDocs.count
            let isCoachHere = catDocs.contains { catDoc in
                let coaches = catDoc.data()["coaches"] as? [String] ?? []
                return coaches.contains(uid)
            }
            if nameMatch || isCoachHere {
                candidateDocs.append((doc: doc, catCount: catCount, coachIsHere: isCoachHere))
            }
        }

        // Pick the best doc: prefer one where coach is in categories AND has most cats
        let best = candidateDocs
            .sorted { a, b in
                if a.coachIsHere != b.coachIsHere { return a.coachIsHere }
                return a.catCount > b.catCount
            }
            .first

        var foundDoc: DocumentSnapshot? = best?.doc

        // Fallback: check stored academyId if nothing found yet
        if foundDoc == nil {
            let userDoc = try? await db.collection("users").document(uid).getDocument()
            let storedId = userDoc?.data()?["academyId"] as? String ?? ""
            if !storedId.isEmpty,
               let candidate = try? await db.collection("academies").document(storedId).getDocument(),
               candidate.exists {
                foundDoc = candidate
            }
        }

        // Step 4 (FALLBACK): No academy doc found anywhere.
        // Try to get the real academyId from users doc to build a correct HaddafAcademy.
        if foundDoc == nil {
            let academyName = coachProfile.currentAcademy.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !academyName.isEmpty else { return }

            // Use the academyId from users doc if available — gives us correct doc ID
            let userDoc = try? await db.collection("users").document(uid).getDocument()
            let storedAcademyId = userDoc?.data()?["academyId"] as? String ?? ""
            let fallbackId = storedAcademyId.isEmpty ? uid : storedAcademyId

            // Try to load categories from this ID
            var fallbackCats: [String] = []
            let fbCatsSnap = try? await db.collection("academies").document(fallbackId)
                .collection("categories").getDocuments()
            fallbackCats = (fbCatsSnap?.documents ?? []).map { $0.documentID }.sorted()

            let fallback = HaddafAcademy(
                id: fallbackId,
                name: academyName,
                logoURL: nil,
                city: "",
                street: "",
                categories: fallbackCats,
                coachUIDs: [uid]
            )
            await MainActor.run { self.destinationAcademy = fallback }
            return
        }

        guard let doc = foundDoc else { return }
        var d = doc.data() ?? [:]

        // If academy doc has no "name", write coach's currentAcademy into it
        // This fixes old accounts where the doc was created without a name field.
        let docName = d["name"] as? String ?? ""
        let resolvedName = docName.isEmpty ? coachProfile.currentAcademy : docName
        if docName.isEmpty && !coachProfile.currentAcademy.isEmpty {
            try? await db.collection("academies").document(doc.documentID)
                .setData(["name": coachProfile.currentAcademy], merge: true)
        }

        let catsSnap = try? await db.collection("academies").document(doc.documentID)
            .collection("categories").getDocuments()
        var cats: [String] = []
        var coachSet = Set<String>()
        for catDoc in catsSnap?.documents ?? [] {
            cats.append(catDoc.documentID)
            let coaches = catDoc.data()["coaches"] as? [String] ?? []
            coaches.forEach { coachSet.insert($0) }
        }
        let firestoreCity   = d["city"]   as? String ?? ""
        let firestoreStreet = d["street"] as? String ?? ""
        let localMatch = SAUDI_ACADEMIES.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == resolvedName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let resolvedCity   = firestoreCity.isEmpty   ? (localMatch?.city   ?? "") : firestoreCity
        let resolvedStreet = firestoreStreet.isEmpty ? (localMatch?.street ?? "") : firestoreStreet

        var academy = HaddafAcademy(
            id: doc.documentID,
            name: resolvedName,
            logoURL: d["logoURL"] as? String,
            city: resolvedCity,
            street: resolvedStreet
        )
        academy.categories = cats.sorted()
        academy.coachUIDs = Array(coachSet)
        await MainActor.run { self.destinationAcademy = academy }
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
