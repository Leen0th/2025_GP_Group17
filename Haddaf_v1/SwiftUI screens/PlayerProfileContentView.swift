import SwiftUI
import PhotosUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

// Notification posted when the user's profile data has been successfully saved in `EditProfileView`
extension Notification.Name {
    static let profileUpdated = Notification.Name("profileUpdated")
}

// MARK: - Main Profile Content View
struct PlayerProfileContentView: View {
    // The view model responsible for fetching and managing all profile data
    @StateObject private var viewModel: PlayerProfileViewModel
    // The currently selected tab in the content section (Posts, Progress, or Endorsements)
    @State private var selectedContent: ContentType = .posts
    // Controls the visibility of the popup explaining the score calculation
    @State private var showScoreInfoAlert = false

    // Defines the 3-column layout for the posts grid
    private let postColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    // Controls the visibility of an alert to confirm post deletion
    @State private var showDeleteAlert = false
    // Stores the post that is pending deletion
    @State private var postToDelete: Post? = nil
    // Stores the post that was tapped, triggering the `PostDetailView` full-screen cover
    @State private var selectedPost: Post? = nil
    // Controls the presentation of the `SettingsView` full-screen cover
    @State private var goToSettings = false
    // Controls the presentation of the `ProfileNotificationsListView` full-screen cover
    @State private var showNotificationsList = false
    
    // --- Session for guest-checking ---
    @EnvironmentObject var session: AppSession
    
    // --- State to manage the auth prompt sheet ---
    @State private var showAuthSheet = false
    
    // A boolean indicating if this profile belongs to the currently logged-in user
    private var isCurrentUser: Bool
    
    // An enum defining the filter options for the post grid (only visible to the current user)
    enum PostFilter: String, CaseIterable {
        case all = "All"
        case `public` = "Public"
        case `private` = "Private"
    }
    
    // An enum defining the sorting options for the post grid
    enum PostSort: String, CaseIterable {
        case newestFirst = "Newest Post First"
        case oldestFirst = "Oldest Post First"
        case matchDateNewest = "Newest Match Date"
        case matchDateOldest = "Oldest Match Date"
    }

    // The currently selected `PostFilter` state.
    @State private var postFilter: PostFilter = .all
    // The currently selected `PostSort` state.
    @State private var postSort: PostSort = .newestFirst
    
    // The text entered into the post search bar
    @State private var searchText = ""

    // Stores the item (profile or post) to be reported, triggering the `ReportView` sheet
    @State private var itemToReport: ReportableItem?
    // Controls the "Report Submitted" confirmation alert
    @State private var showReportAlert = false
    
    // A shared service that tracks reported/hidden content
    @StateObject private var reportService = ReportStateService.shared

    // Initializes the view for the currently logged-in user (UserID is `nil`)
    init() {
        _viewModel = StateObject(wrappedValue: PlayerProfileViewModel(userID: nil))
        self.isCurrentUser = true
    }
    
    // Initializes the view for a specific user
    // - Parameter userID: The UID of the user to display
    init(userID: String) {
        _viewModel = StateObject(wrappedValue: PlayerProfileViewModel(userID: userID))
        self.isCurrentUser = (userID == Auth.auth().currentUser?.uid)
    }

    // Filters the posts by `searchText` and `postFilter` then sorts them based on `postSort` preferences
    private var filteredAndSortedPosts: [Post] {
        // 1. Filter by search text
        let searched: [Post]
        if searchText.isEmpty {
            searched = viewModel.posts
        } else {
            searched = viewModel.posts.filter { $0.caption.localizedCaseInsensitiveContains(searchText) }
        }

        // 2. Filter by privacy (if current user)
        let filtered: [Post]
        if isCurrentUser {
            switch postFilter {
            case .all: filtered = searched
            case .public: filtered = searched.filter { !$0.isPrivate }
            case .private: filtered = searched.filter { $0.isPrivate }
            }
        } else {
            // Other users can only see public posts
            filtered = searched.filter { !$0.isPrivate }
        }

        // 3. Sort the results
        switch postSort {
        case .newestFirst:
            return filtered
        case .oldestFirst:
            return filtered.reversed()
        case .matchDateNewest:
            return filtered.sorted {
                guard let d1 = $0.matchDate else { return false }
                guard let d2 = $1.matchDate else { return true }
                return d1 > d2
            }
        case .matchDateOldest:
            return filtered.sorted {
                guard let d1 = $0.matchDate else { return false }
                guard let d2 = $1.matchDate else { return true }
                return d1 < d2
            }
        }
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
                        // MARK: - Header & Stats
                        TopNavigationBar(
                            userProfile: viewModel.userProfile,
                            goToSettings: $goToSettings,
                            showNotifications: $showNotificationsList,
                            isCurrentUser: isCurrentUser,
                            onReport: {
                                // --- Check for guest ---
                                if session.isGuest {
                                    showAuthSheet = true
                                } else {
                                    // Set the item to report (this profile)
                                    itemToReport = ReportableItem(
                                        id: viewModel.userProfile.email,
                                        type: .profile,
                                        contentPreview: viewModel.userProfile.name
                                    )
                                }
                            },
                            reportService: reportService,
                            reportedID: viewModel.userProfile.email
                        )
                        ProfileHeaderView(userProfile: viewModel.userProfile)
                            .padding(.bottom, 0)
                            .zIndex(1)

                        StatsGridView(userProfile: viewModel.userProfile, showScoreInfoAlert: $showScoreInfoAlert)
                            .zIndex(0)
                       
                        ContentTabView(selectedContent: $selectedContent, isCurrentUser: isCurrentUser)

                        // MARK: - Tab Content
                        switch selectedContent {
                        case .posts:
                            // Search Bar for posts
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(BrandColors.darkTeal)
                                        .padding(.leading, 12)
                               
                                    TextField("Search by title...", text: $searchText)
                                        .font(.system(size: 16, design: .rounded))
                                        .tint(BrandColors.darkTeal)
                                        .submitLabel(.search)
                               
                                    if !searchText.isEmpty {
                                        Button {
                                            searchText = ""
                                            // Dismiss keyboard
                                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.trailing, 8)
                                    }
                                }
                                .padding(.vertical, 12)
                                .background(BrandColors.background)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                                .padding(.horizontal)

                                // Post Controls (Filter & Sort)
                                postControls(isCurrentUser: isCurrentUser)
                                    .padding(.horizontal)
                            
                            postsGrid
                                .padding(.horizontal)
                       
                        case .progress:
                            // ProgressTabView() // <-- Placeholder commented out
                            EmptyStateView(
                                imageName: "chart.bar.xaxis",
                                message: "Your progress analytics will appear here once you start uploading videos."
                            )
                            .padding(.top, 40)

                        case .endorsements:
                            EndorsementsListView(endorsements: viewModel.userProfile.endorsements)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
            .task { await viewModel.fetchAllData() } // Fetch all data on appear
            .onChange(of: viewModel.userProfile.position) { _, _ in
                // If the user's position changes (in EditProfile), recalculate the score
                Task {
                    await viewModel.calculateAndUpdateScore()
                }
            }
            // MARK: - Notification Listeners
            .onReceive(NotificationCenter.default.publisher(for: .postDeleted)) { note in
                // When a post is deleted elsewhere (PostDetailView), remove it here
                if let postId = note.userInfo?["postId"] as? String {
                    withAnimation { viewModel.posts.removeAll { $0.id == postId } }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .postDataUpdated)) { note in
                // When post data is updated (like/comment), sync the local post
                guard let userInfo = note.userInfo,
                      let postId = userInfo["postId"] as? String else { return }

                if let index = viewModel.posts.firstIndex(where: { $0.id == postId }) {
                    // Sync like state
                    if let (isLiked, likeCount) = userInfo["likeUpdate"] as? (Bool, Int) {
                        withAnimation {
                            viewModel.posts[index].isLikedByUser = isLiked
                            viewModel.posts[index].likeCount = likeCount
                            if let uid = Auth.auth().currentUser?.uid {
                                if isLiked {
                                    if !viewModel.posts[index].likedBy.contains(uid) {
                                        viewModel.posts[index].likedBy.append(uid)
                                    }
                                } else {
                                    viewModel.posts[index].likedBy.removeAll { $0 == uid }
                                }
                            }
                        }
                    }
                     
                    // Sync comment count
                    if userInfo["commentAdded"] as? Bool == true {
                        withAnimation {
                            viewModel.posts[index].commentCount += 1
                        }
                    }
                }
            }
            // MARK: - Sheets & Full Screen Covers
            .fullScreenCover(isPresented: $goToSettings) {
                NavigationStack { SettingsView(userProfile: viewModel.userProfile) }
            }
            .fullScreenCover(isPresented: $showNotificationsList) {
                ProfileNotificationsListView()
            }
            // --- Open Post Detail view ---
            .fullScreenCover(item: $selectedPost) { post in
                NavigationStack {
                    PostDetailView(post: post, showAuthSheet: $showAuthSheet)
                        .environmentObject(session)
                }
            }
            // Open Report view
            .sheet(item: $itemToReport) { item in
                ReportView(item: item) { reportedID in
                    if item.type == .profile {
                        reportService.reportProfile(id: reportedID)
                    }
                    showReportAlert = true
                }
            }
            
            
            // MARK: - Popups
            if showScoreInfoAlert {
                ScoreInfoPopupView(isPresented: $showScoreInfoAlert)
            }
            
            // --- Show auth prompt as a popup overlay ---
            if showAuthSheet {
                AuthPromptSheet(isPresented: $showAuthSheet)
            }
            
        }
        .animation(.easeInOut, value: showScoreInfoAlert)
        .animation(.easeInOut, value: showAuthSheet)
        .navigationBarBackButtonHidden(true)
    }
    
    // A view builder for the post filter and sort menus
    @ViewBuilder
    private func postControls(isCurrentUser: Bool) -> some View {
        HStack {
            if isCurrentUser {
                // Filter Menu (Only for current user)
                Menu {
                    Picker("Filter", selection: $postFilter) {
                        ForEach(PostFilter.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("Filter: \(postFilter.rawValue)")
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(BrandColors.darkTeal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(BrandColors.background)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                }
            }
            // Sort Menu
            Menu {
                Picker("Sort", selection: $postSort) {
                    ForEach(PostSort.allCases, id: \.self) { option in
                         Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down.circle")
                    Text("Sort: \(postSort.rawValue)")
                }
                // MODIFIED: New style
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(BrandColors.darkTeal)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(BrandColors.background)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
            }
            Spacer()
        }
        .padding(.top, 8)
    }
    // A view builder for the 3-column grid of post thumbnails
    private var postsGrid: some View {
        LazyVGrid(columns: postColumns, spacing: 2) {
            ForEach(filteredAndSortedPosts) { post in
                Button { selectedPost = post } label: {
                    ZStack(alignment: .bottomLeading) {
                        // Thumbnail image
                        AsyncImage(url: URL(string: post.imageName)) { $0.resizable().aspectRatio(1, contentMode: .fill) }
                        placeholder: {
                            RoundedRectangle(cornerRadius: 0)
                                .fill(BrandColors.lightGray)
                                .aspectRatio(1, contentMode: .fill)
                        }
                        .aspectRatio(1, contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .clipped()

                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        // Caption
                        Text(post.caption)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if post.isPrivate {
                            Image(systemName: "lock.fill").font(.caption).foregroundColor(.white)
                                .padding(6).background(Color.red.opacity(0.8)).clipShape(Circle())
                                .padding(8)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.default, value: filteredAndSortedPosts)
        .refreshable { await viewModel.fetchAllData() } // Pull-to-refresh
    }
}

// MARK: - Score Info Popup
// A popup view that explains how the "Performance Score" is calculated
struct ScoreInfoPopupView: View {
    // To control the visibility of the popup
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { withAnimation { isPresented = false } }
                .transition(.opacity)

            // Popup content card
            VStack(spacing: 20) {
                Text("Score Calculation")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))

                Text("""
                1. Weights assigned by position:
                
                   Pos.   Pass   Drib   Shoot
                   -------------------------
                   ATK     3      8      10
                   MID     8      7       6
                   DEF     9      3       1
                
                2. Score calculated for each post.
                
                3. Scores averaged & rounded.
                """)
                .font(.system(size: 13, design: .monospaced))
                .multilineTextAlignment(.leading)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)

                Button("OK") { withAnimation { isPresented = false } }
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(BrandColors.darkTeal)
                    .cornerRadius(12)
                    .padding(.top, 4)
            }
            .padding(EdgeInsets(top: 24, leading: 24, bottom: 20, trailing: 24))
            .frame(width: 320)
            .background(BrandColors.background)
            .cornerRadius(20)
            .shadow(radius: 12)
            .transition(.scale)
        }
    }
}


// MARK: - Edit Profile View
// A view that allows the current user to edit their profile details
struct EditProfileView: View {
    // The environment object for dismissing the view
    @Environment(\.dismiss) private var dismiss
    // The `UserProfile` object to be observed and updated
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
    
    // The dial code, fixed to Saudi Arabia.
    private let selectedDialCode = CountryDialCode.saudi
    @State private var phoneLocal: String
    @State private var phoneNonDigitError = false
    
    // Local state for the phone number visibility toggle.
    @State private var isPhoneNumberVisible: Bool
    
    // MARK: - Sheet Presentation State
    @State private var showDOBPicker = false
    @State private var tempDOB = Date()
    @State private var showPositionPicker = false
    @State private var showLocationPicker = false
    @State private var locationSearch = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    // MARK: - View Operation State
    @State private var isSaving = false
    @State private var showInfoOverlay = false
    @State private var overlayMessage = ""
    @State private var overlayIsError = false
    
    private let primary = BrandColors.darkTeal
    
    private let db = Firestore.firestore()
    
    private let positions = ["Attacker", "Midfielder", "Defender"]
    
    
    // MARK: - Validation Properties
    // `true` if the email format is valid.
    private var isEmailFieldValid: Bool { isValidEmail(email) }
    
    // `true` if the phone number is valid (based on KSA rules).
    private var isPhoneNumberValid: Bool {
        isValidPhone(code: selectedDialCode.code, local: phoneLocal)
    }
    
    // `true` if the name is not empty and contains valid characters.
    private var isNameValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = #"^[\p{L}][\p{L}\s.'-]*$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
    
    // `true` if the weight is a number within a realistic range.
    private var isWeightValid: Bool {
        guard let w = Int(weight) else { return false }
        return (15...200).contains(w)
    }
    
    // `true` if the height is a number within a realistic range.
    private var isHeightValid: Bool {
        guard let h = Int(height) else { return false }
        return (100...230).contains(h)
    }
    
    // `true` if all form fields are valid, enabling the "Update" button.
    private var isFormValid: Bool {
        isNameValid && isEmailFieldValid && isPhoneNumberValid &&
        isWeightValid && isHeightValid && !position.isEmpty
    }
    
    // Initializes the view with data from the passed `UserProfile` object
    // This initializer populates all `@State` variables with the
    // current data from the `userProfile`, "un-formatting" values
    // like weight and height (e.g., "75kg" -> "75").
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
            
            if showInfoOverlay {
                InfoOverlay(primary: primary, title: overlayMessage, isError: overlayIsError, onOk: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showInfoOverlay = false }
                    if !overlayIsError { dismiss() } // Dismiss view on success
                })
                .transition(.scale.combined(with: .opacity)).zIndex(1)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: selectedPhotoItem) { _, newItem in
            // When a new photo is selected, load it into the `profileImage` state
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let newImage = UIImage(data: data) {
                    await MainActor.run { self.profileImage = newImage }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showInfoOverlay)
    }

    // MARK: - View Builders
    
    // The view's header with the title and back button.
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

    // The section for changing or removing the profile picture
    private var profilePictureSection: some View {
        VStack {
            Image(uiImage: profileImage ?? UIImage(systemName: "person.circle.fill")!)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100).clipShape(Circle())
                .foregroundColor(.gray.opacity(0.5))
            
            HStack(spacing: 20) {
                // PhotosPicker for selecting a new image
                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    Text("Change Picture")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(primary)
                }
                
                // "Remove" button, only shows if an image is set
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

    // The main section containing all text fields and pickers for profile data.
    private var formFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Name
            field(label: "Name", text: $name, isValid: isNameValid)
            if !name.isEmpty && !isNameValid {
                Text("Please enter a valid name (letters and spaces only).")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.red)
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
                    .presentationDetents([.height(300)])
                    .presentationBackground(BrandColors.background) // MODIFIED
                    .presentationCornerRadius(28)
            }
            
            // Height
            field(label: "Height (cm)", text: $height, keyboardType: .numberPad, isValid: isHeightValid)
            if !height.isEmpty && !isHeightValid {
                Text("Enter a realistic height between 100–230 cm.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.red)
            }
            
            // Weight
            field(label: "Weight (kg)", text: $weight, keyboardType: .numberPad, isValid: isWeightValid)
            if !weight.isEmpty && !isWeightValid {
                Text("Enter a realistic weight between 15–200 kg.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.red)
            }
            
            // Date of birth
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
                    .presentationDetents([.height(300)])
                    .presentationBackground(BrandColors.background)
                    .presentationCornerRadius(28)
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
                    .presentationDetents([.large])
                    .presentationBackground(BrandColors.background)
                    .presentationCornerRadius(28)
            }
            
            // Email
            field(label: "Email", text: $email, keyboardType: .emailAddress, isValid: isEmailFieldValid)
            if !email.isEmpty && !isEmailFieldValid {
                Text("Please enter a valid email address.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.red)
            }
            
            // Phone Number
            fieldLabel("Phone number")
            roundedField {
                HStack(spacing: 10) {
                    Text(selectedDialCode.code)
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
                            // Filter out non-numeric characters in real-time
                            phoneNonDigitError = val.contains { !$0.isNumber }
                            phoneLocal = val.filter { $0.isNumber }
                        }
                    ))
                    .keyboardType(.numberPad)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(primary)
                    .tint(primary)
                }
            }
            if phoneNonDigitError {
                Text("Numbers only (0–9).")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.red)
            } else if !phoneLocal.isEmpty && !isPhoneNumberValid {
                if selectedDialCode.code == "+966" {
                    Text("Must be 9 digits and start with 5.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.red)
                } else {
                    Text("Enter a valid phone number.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.red)
                }
            }
        }
    }

    // The section for the email/phone visibility toggles
    private var togglesSection: some View {
        VStack(spacing: 16) {
            toggleRow(title: "Make my email visible", isOn: $isEmailVisible)
            toggleRow(title: "Make my phone visible", isOn: $isPhoneNumberVisible)
        }
        .padding(.top, 10)
    }

    // The "Update" button, which is disabled if the form is invalid or saving
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
        .disabled(!isFormValid || isSaving)
        .opacity((!isFormValid || isSaving) ? 0.6 : 1.0)
    }

    // MARK: - Save Logic
    
    // Asynchronously saves all local state changes to Firestore.
    private func saveChanges() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            overlayMessage = "User not authenticated"; overlayIsError = true; showInfoOverlay = true
            return
        }
        
        isSaving = true
        do {
            let fullPhone = selectedDialCode.code + phoneLocal
            
            // MARK: --- 1. Main /users/{uid} Doc Updates ---
            var userUpdates: [String: Any] = [
                "firstName": name.split(separator: " ").first.map(String.init) ?? name,
                "lastName": name.split(separator: " ").dropFirst().joined(separator: " "),
                "email": email,
                "phone": fullPhone,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            // Handle DOB
            if let dob = dob {
                userUpdates["dob"] = Timestamp(date: dob)
            } else {
                userUpdates["dob"] = NSNull()
            }
            
            // MARK: --- 2. Profile Picture Upload (if changed) ---
            let oldImage = userProfile.profileImage
            if let newImage = profileImage, newImage != oldImage {
                // If a new image is set, upload it
                if let imageData = newImage.jpegData(compressionQuality: 0.8) {
                    let fileName = "\(UUID().uuidString).jpg"
                    let ref = Storage.storage().reference().child("profile/\(uid)/\(fileName)")
                    _ = try await ref.putDataAsync(imageData)
                    let url = try await ref.downloadURL()
                    userUpdates["profilePic"] = url.absoluteString
                }
            } else if profileImage == nil, oldImage != nil {
                // If image was removed (set to nil)
                userUpdates["profilePic"] = ""
            }
            
            // Perform the first Firestore write
            try await db.collection("users").document(uid).setData(userUpdates, merge: true)
            
            // MARK: --- 3. Sub-doc /users/{uid}/player/profile Updates ---
            let profileUpdates: [String: Any] = [
                "position": position,
                "weight": Int(weight) ?? 0,
                "height": Int(height) ?? 0,
                "location": location,
                "isEmailVisible": isEmailVisible,
                "contactVisibility": isPhoneNumberVisible,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            // Perform the second Firestore write
            try await db.collection("users").document(uid)
                .collection("player").document("profile")
                .setData(profileUpdates, merge: true)
            
            // MARK: --- 4. Update Local @ObservedObject ---
            await MainActor.run {
                userProfile.name = name
                userProfile.position = position
                userProfile.weight = "\(weight)kg"
                userProfile.height = "\(height)cm"
                userProfile.location = location
                userProfile.email = email
                userProfile.isEmailVisible = isEmailVisible
                userProfile.phoneNumber = fullPhone
                userProfile.isPhoneNumberVisible = isPhoneNumberVisible
                userProfile.dob = dob
                
                // Recalculate age
                if let dob = dob {
                    let comps = Calendar.current.dateComponents([.year], from: dob, to: Date())
                    userProfile.age = "\(comps.year ?? 0)"
                } else {
                    userProfile.age = ""
                }
                
                // Update local profile image
                if profileImage == nil {
                    userProfile.profileImage = nil
                } else if let newImage = profileImage, newImage != oldImage {
                    userProfile.profileImage = newImage
                }
                
                // MARK: --- 5. Show Success & Notify ---
                overlayMessage = "Profile updated successfully"
                overlayIsError = false
                showInfoOverlay = true
                
                // Post notification to update other views (like ProfileHeader)
                NotificationCenter.default.post(name: .profileUpdated, object: nil)
            }
        } catch {
            // MARK: --- 6. Handle Errors ---
            overlayMessage = "Failed to update profile: \(error.localizedDescription)"
            overlayIsError = true
            showInfoOverlay = true
        }
        isSaving = false
    }
    
    // MARK: - View Helpers
    
    // A reusable, styled `TextField` with a label and validation outline
    private func field(label: String, text: Binding<String>, keyboardType: UIKeyboardType = .default, isValid: Bool) -> some View {
        VStack(alignment: .leading) {
            fieldLabel(label)
            roundedField {
                TextField("", text: text)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(primary)
                    .tint(primary).keyboardType(keyboardType)
                    .onChange(of: text.wrappedValue) { oldValue, newValue in
                        // Enforce number pad filtering
                        if keyboardType == .numberPad {
                            text.wrappedValue = newValue.filter(\.isNumber)
                        }
                    }
            }
            .overlay(
                // Show red border if field is invalid and not empty
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isValid || text.wrappedValue.isEmpty ? Color.clear : Color.red, lineWidth: 1)
            )
        }
    }
    
    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(BrandColors.darkGray)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(primary)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, design: .rounded))
            .foregroundColor(.gray)
    }

    private func roundedField<Content: View>(@ViewBuilder c: () -> Content) -> some View {
        c()
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(BrandColors.background)
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
            )
    }
    
    private func buttonLikeField<Content: View>(@ViewBuilder content: () -> Content, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            content()
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(BrandColors.background)
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                )
        }
    }
    
    // A helper to format a `Date` as "dd/MM/yyyy".
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; return f.string(from: date)
    }
}

// MARK: - Profile Helper Views

// The navigation bar for the profile view
/// It shows "Settings" and "Notifications" buttons for the current user,
/// or a "Back" and "Report" button for other users.
struct TopNavigationBar: View {
    // The environment object for dismissing the view (if not the current user's profile).
    @Environment(\.dismiss) private var dismiss
    // The profile being displayed (used for reporting).
    @ObservedObject var userProfile: UserProfile
    // A binding to trigger the `SettingsView`.
    @Binding var goToSettings: Bool
    // A binding to trigger the `ProfileNotificationsListView`.
    @Binding var showNotifications: Bool
    
    // `true` if this profile is for the current user.
    var isCurrentUser: Bool
    // The unique ID of the profile being viewed (for reporting).
    var onReport: () -> Void

    @ObservedObject var reportService: ReportStateService
    var reportedID: String

    var body: some View {
        HStack(spacing: 16) {
            if !isCurrentUser {
                // "Back" button for other users' profiles
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
                // "Notifications" button for current user
                Button { showNotifications = true } label: {
                    Image(systemName: "bell")
                        .font(.title2)
                        .foregroundColor(BrandColors.darkTeal)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                // "Settings" button for current user
                Button { goToSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .foregroundColor(BrandColors.darkTeal)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            } else {
                // "Report" button for other users' profiles
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

// The view displaying the user's profile picture and name
struct ProfileHeaderView: View {
    // The profile to display.
    @ObservedObject var userProfile: UserProfile
    
    var body: some View {
        VStack(spacing: 12) {
            Image(uiImage: userProfile.profileImage ?? UIImage(systemName: "person.circle.fill")!)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100).clipShape(Circle())
                .overlay(Circle().stroke(BrandColors.background, lineWidth: 4))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
                .foregroundColor(.gray.opacity(0.5))
            
            Text(userProfile.name)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(BrandColors.darkTeal)
        }
    }
}

// MARK: - Stats Grid
// The main grid of stats on the profile, including the hero score and user-provided details
struct StatsGridView: View {
    // The profile data to display.
    @ObservedObject var userProfile: UserProfile
    // `true` to show the contact info (email/phone) dropdown.
    @State private var showContactInfo = false
    // A binding to control the "Score Info" popup.
    @Binding var showScoreInfoAlert: Bool
    
    let accentColor = BrandColors.darkTeal
    let goldColor = BrandColors.gold

    // A small view for a single user-provided stat (e.g., Weight, Height).
    @ViewBuilder
    private func UserStatItem(title: String, value: String) -> some View {
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
    
    // A view for a system-provided stat (e.g., Team, Rank).
    @ViewBuilder
    private func SystemStatItem(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(accentColor)
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(BrandColors.darkGray)
                .multilineTextAlignment(.center)
        }
           .frame(maxWidth: .infinity)
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 18) {

            // --- 1. Hero Stat (Score) ---
            VStack(spacing: 8) {
                
                HStack(spacing: 8) {
                    Text("Performance Score")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(accentColor)
                    
                    // Info button to trigger the popup
                    Button {
                        showScoreInfoAlert = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(accentColor)
                    }
                }

                Text(userProfile.score.isEmpty ? "0" : userProfile.score)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(goldColor)
            }
            .padding(.top, 10)

            // --- 2. User-Provided Stats ---
            HStack(alignment: .top) {
                Spacer(minLength: 3)
                UserStatItem(title: "POSITION", value: userProfile.position)
                Spacer(minLength: 3)
                UserStatItem(title: "AGE", value: userProfile.age)
                Spacer(minLength: 3)
                UserStatItem(title: "WEIGHT", value: userProfile.weight)
                Spacer(minLength: 3)
                UserStatItem(title: "HEIGHT", value: userProfile.height)
                Spacer(minLength: 3)
                UserStatItem(title: "RESIDENCE", value: userProfile.location)
                Spacer(minLength: 3)
            }
            .padding(.horizontal, 5)

            Divider().padding(.horizontal)

            // --- 3. System Stats ---
            HStack(alignment: .top) {
                Spacer()
                SystemStatItem(title: "Team", value: userProfile.team)
                Spacer()
                SystemStatItem(title: "Challenge Rank", value: userProfile.rank)
                Spacer()
            }
               .padding(.horizontal, 20)

            // --- 4. Contact Info ---
            if userProfile.isEmailVisible || userProfile.isPhoneNumberVisible {
                Button(action: { withAnimation(.spring()) { showContactInfo.toggle() } }) {
                    HStack(spacing: 4) {
                        Text(showContactInfo ? "Show less" : "Show contact info")
                        Image(systemName: showContactInfo ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
                    .padding(.top, 8)
                }

                if showContactInfo {
                    VStack(alignment: .center, spacing: 12) {
                        if userProfile.isEmailVisible {
                            contactItem(icon: "envelope.fill", value: userProfile.email)
                        }
                        if userProfile.isPhoneNumberVisible {
                            contactItem(icon: "phone.fill", value: userProfile.phoneNumber)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 25)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(BrandColors.background)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        )
        .padding(.horizontal)
    }

    // A small view for displaying a contact detail (email or phone) with an icon.
    private func contactItem(icon: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(accentColor)
                .frame(width: 20)
            Text(value)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(BrandColors.darkGray)
        }
    }
}

// MARK: - Content Tab
// The tab bar for switching between "Posts", "Progress", and "Endorsements".
struct ContentTabView: View {
    // The binding to the parent view's selected tab.
    @Binding var selectedContent: ContentType
    // A namespace for the sliding underline animation.
    @Namespace private var animation
    
    let accentColor = BrandColors.darkTeal
    
    // `true` if this is the current user's profile, to adjust tab titles.
    var isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 12) {
            ContentTabButton(title: isCurrentUser ? "My posts" : "Posts", type: .posts, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
            ContentTabButton(title: isCurrentUser ? "My progress" : "Progress", type: .progress, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
            ContentTabButton(title: "Endorsements", type: .endorsements, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
        }
        .font(.system(size: 16, weight: .medium, design: .rounded))
    }
}

// A single button for the `ContentTabView`, handling the tap action and animated underline.
fileprivate struct ContentTabButton: View {
    let title: String, type: ContentType
    @Binding var selectedContent: ContentType
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

// MARK: - Endorsements
// A view that displays a list of `EndorsementCardView`s or an empty state.
struct EndorsementsListView: View {
    // The list of endorsements to display.
    let endorsements: [CoachEndorsement]
    var body: some View {
        VStack(spacing: 16) {
            if endorsements.isEmpty {
                EmptyStateView(
                    imageName: "person.badge.shield.checkmark",
                    message: "Endorsements from coaches will appear here once you receive them."
                )
                .padding(.top, 40)
            } else {
                ForEach(endorsements) { endorsement in EndorsementCardView(endorsement: endorsement) }
            }
        }
    }
}

// A card view that displays a single coach endorsement.
struct EndorsementCardView: View {
    // The endorsement data to display.
    let endorsement: CoachEndorsement
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(endorsement.coachImage).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44).clipShape(Circle())
                VStack(alignment: .leading) {
                    Text(endorsement.coachName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    // Star rating
                    HStack(spacing: 2) {
                        ForEach(0..<5) { i in
                            Image(systemName: i < endorsement.rating ? "star.fill" : "star")
                                .font(.caption).foregroundColor(.yellow)
                        }
                    }
                }
            }
            Text(endorsement.endorsementText)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColors.background)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(BrandColors.darkTeal.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Info Overlay
// A reusable modal overlay for showing success or error messages (e.g., "Profile Updated").
struct InfoOverlay: View {
    let primary: Color, title: String, isError: Bool
    var onOk: () -> Void
    var body: some View {
        ZStack {
            // Dimming background
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                // Icon
                Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 50)).foregroundColor(isError ? .red : primary)
                // Message
                Text(title)
                    .font(.system(size: 16, design: .rounded))
                    .multilineTextAlignment(.center).padding(.horizontal)
                // OK Button
                Button("OK") { onOk() }
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12).background(primary).clipShape(Capsule())
            }
            .padding(EdgeInsets(top: 30, leading: 20, bottom: 20, trailing: 20))
            .background(BrandColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 10).padding(.horizontal, 40)
        }
    }
}
