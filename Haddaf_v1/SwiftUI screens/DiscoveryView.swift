import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AVKit

// MARK: - Discovery View
// The main view for the "Discovery" tab, which also hosts the "Leaderboard" tab
struct DiscoveryView: View {
    // An enum to define the two top level tabs in this view
    enum TopTab: String, CaseIterable { case discovery = "Discovery", leaderboard = "Leaderboard" }
    // The currently selected top tab
    @State private var selectedTab: TopTab = .discovery
    // The view model that fetches and manages all public posts
    @StateObject private var viewModel = DiscoveryViewModel()
    // The view model that fetches and manages the leaderboard data
    @StateObject private var lbViewModel = LeaderboardViewModel()
    // A shared service that tracks reported/hidden content across the app
    @StateObject private var reportService = ReportStateService.shared
    // The text entered into the search bar
    @State private var searchText = ""
    
    // to check for guest
    @EnvironmentObject var session: AppSession

    // --- for auth prompt ---
    @State private var showAuthSheet = false

    // MARK: - Filters
    @State private var filterPosition: String? = nil
    @State private var filterAgeMin: Int? = nil
    @State private var filterAgeMax: Int? = nil
    @State private var filterScoreMin: Int? = nil
    @State private var filterScoreMax: Int? = nil
    @State private var filterTeam: String? = nil
    @State private var filterLocation: String? = nil

    // Controls the presentation of the `FiltersSheetView`
    @State private var showFiltersSheet = false
    
    // Holds the `Post` object when the comment button is tapped, triggering the `CommentsView` sheet
    @State private var postForComments: Post? = nil
    
    // The user ID to navigate to
    @State private var navigateToProfileID: String?
    // The `isActive` binding for the `NavigationLink`.
    @State private var navigationTrigger = false
    
    // Holds the `ReportableItem` when a report button is tapped, triggering the `ReportView` sheet
    @State private var itemToReport: ReportableItem?

    // A computed property that filters the main `viewModel.posts` list
    private var filteredPosts: [Post] {
        viewModel.posts.filter { post in
            // 1. Filter by search text (author name)
            let nameMatch = searchText.isEmpty || post.authorName.localizedCaseInsensitiveContains(searchText)
            // 2. Get the cached author profile for this post
            guard let authorUid = post.authorUid,
                  let profile = viewModel.authorProfiles[authorUid] else {
                // If profile isn't loaded yet, just return the name match
                return nameMatch
            }
            // 3. Apply all filters from the filter sheet
            let positionMatch = filterPosition == nil || profile.position == filterPosition
            let age = Int(profile.age) ?? 0
            let ageMatch = (filterAgeMin == nil || age >= filterAgeMin!) &&
                           (filterAgeMax == nil || age <= filterAgeMax!)
            let score = Int(profile.score) ?? 0
            let scoreMatch = (filterScoreMin == nil || score >= filterScoreMin!) &&
                             (filterScoreMax == nil || score <= filterScoreMax!)
            let teamMatch = filterTeam == nil || profile.team == filterTeam
            let locationMatch = filterLocation == nil || profile.location == filterLocation
            
            // Return true only if all conditions are met
            return nameMatch && positionMatch && ageMatch && scoreMatch && teamMatch && locationMatch
        }
    }

    // returns `true` if any filter (including search) is active
    private var isFiltering: Bool {
        !searchText.isEmpty || filterPosition != nil || filterAgeMin != nil || filterAgeMax != nil ||
        filterScoreMin != nil || filterScoreMax != nil || filterTeam != nil || filterLocation != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.gradientBackground.ignoresSafeArea()
                
                // navigation link to push to a user's profile
                NavigationLink(
                    destination: PlayerProfileContentView(userID: navigateToProfileID ?? ""),
                    isActive: $navigationTrigger
                ) { EmptyView() }

                if viewModel.isLoadingPosts {
                    ProgressView().tint(BrandColors.darkTeal)
                } else {
                    VStack(spacing: 0) {
                        // ===== Top Tabs ("Discovery" / "Leaderboard") =====
                        HStack(spacing: 0) {
                            topTabButton(.discovery)
                            Divider().frame(height: 24).padding(.horizontal, 12)
                            topTabButton(.leaderboard)
                        }
                        .padding(.vertical, 8)

                        // ===== Body content switches based on selected tab =====
                        Group {
                            switch selectedTab {
                            case .discovery:
                                discoveryContent
                            case .leaderboard:
                                LeaderboardView(viewModel: lbViewModel)
                                    .padding(.top, 0)
                            }
                        }
                    }
                }
                
                // --- Show auth prompt as a popup overlay ---
                if showAuthSheet {
                    AuthPromptSheet(isPresented: $showAuthSheet)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .animation(.easeInOut, value: showAuthSheet)
            // Load the leaderboard data when the view appears, if it hasn't been loaded
            .onAppear { lbViewModel.loadLeaderboardIfNeeded() }
            // MARK: - Sheets
            .sheet(isPresented: Binding(get: {
                // Only show the filter sheet if the Discovery tab is active
                selectedTab == .discovery && showFiltersSheet
            }, set: { showFiltersSheet = $0 })) {
                // Filter Sheet
                FiltersSheetView(
                    position: $filterPosition,
                    ageMin: $filterAgeMin,
                    ageMax: $filterAgeMax,
                    scoreMin: $filterScoreMin,
                    scoreMax: $filterScoreMax,
                    team: $filterTeam,
                    location: $filterLocation
                )
            }
            .sheet(item: $postForComments) { post in
                // Comments Sheet
                if let postId = post.id {
                    CommentsView(
                        postId: postId,
                        onProfileTapped: { userID in
                            // This closure handles navigation from a comment to a profile
                            navigateToProfileID = userID
                            postForComments = nil // Dismiss the comment sheet
                            // Use a slight delay to allow the sheet to dismiss before navigating
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                navigationTrigger = true
                            }
                        },
                        showAuthSheet: $showAuthSheet
                    )
                    .environmentObject(session)
                    .presentationBackground(BrandColors.background)
                }
            }
            // --- Sheet for reporting ---
            .sheet(item: $itemToReport) { item in
                ReportView(item: item) { reportedID in
                    // On complete, tell the shared service to hide the post
                    reportService.reportPost(id: reportedID)
                }
            }
            
            // MARK: - Notification Listener
            .onReceive(NotificationCenter.default.publisher(for: .postDataUpdated)) { notification in
                // Listens for updates (likes/comments) from other views and updates the local view model to keep data in sync.
                viewModel.handlePostDataUpdate(notification: notification)
            }
        }
    }
    
    // MARK: - ViewBuilders

    // A view builder for the top tab buttons ("Discovery", "Leaderboard")
    @ViewBuilder
    private func topTabButton(_ tab: TopTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        } label: {
            VStack(spacing: 6) {
                Text(tab.rawValue)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(selectedTab == tab ? BrandColors.darkTeal : BrandColors.darkTeal.opacity(0.45))
                // Underline for the selected tab
                RoundedRectangle(cornerRadius: 1)
                    .frame(height: 2)
                    .foregroundColor(selectedTab == tab ? BrandColors.darkTeal : .clear)
                    .frame(width: 120)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    /// The main content body for the "Discovery" tab
    @ViewBuilder
    private var discoveryContent: some View {
        VStack(spacing: 0) {
            // Search & Filters
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(BrandColors.darkTeal)
                    TextField("Search players by name...", text: $searchText)
                        .font(.system(size: 16, design: .rounded))
                        .tint(BrandColors.darkTeal)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(BrandColors.background)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.08), radius: 5, y: 2)

                // Filter Button
                Button { showFiltersSheet = true } label: {
                    // Icon changes based on isFiltering if active
                    Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(BrandColors.darkTeal)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            // MARK: - Post List
            if filteredPosts.isEmpty && isFiltering {
                // Empty state for when filters return no results
                EmptyStateView(
                    image: "doc.text.magnifyingglass",
                    title: "No Matching Results",
                    message: "Try adjusting your search or filter settings."
                )
            } else {
                // The main list of posts
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredPosts, id: \.id) { post in
                            // Check if this post has been hidden by the report service
                            if let postId = post.id, reportService.hiddenPostIDs.contains(postId) {
                                // If hidden, show the "ReportedContentView" placeholder
                                ReportedContentView(type: .post) {
                                    reportService.unhidePost(id: postId)
                                }
                            } else {
                                // If not hidden, show the post card
                                NavigationLink(destination: PostDetailView(post: post, showAuthSheet: $showAuthSheet)) {
                                    // get the author's profile from the cache
                                    let authorProfile = post.authorUid.flatMap { viewModel.authorProfiles[$0] } ?? UserProfile()
                                    DiscoveryPostCardView(
                                        viewModel: viewModel,
                                        post: post,
                                        authorProfile: authorProfile,
                                        onCommentTapped: {
                                            // Set the post to trigger the comment sheet
                                            self.postForComments = post
                                        },
                                        onReport: {
                                            // Set the item to trigger the report sheet
                                            itemToReport = ReportableItem(
                                                id: post.id ?? "",
                                                type: .post,
                                                contentPreview: post.caption
                                            )
                                        },
                                        reportService: reportService,
                                        showAuthSheet: $showAuthSheet
                                    )
                                    .environmentObject(session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 80)
                }
                .opacity(1)
            }
        }
    }

    // An empty state view for when no posts are found
    @ViewBuilder
    private func EmptyStateView(image: String, title: String, message: String) -> some View {
        VStack {
            Spacer()
            Image(systemName: image)
                .font(.system(size: 50))
                .foregroundColor(BrandColors.darkGray.opacity(0.6))
            Text(title)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
            Text(message)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.secondary)
            Spacer(); Spacer()
        }
        .padding()
    }
}

// MARK: - Post Card
// A view for a single post card shown in the `DiscoveryView` feed
struct DiscoveryPostCardView: View {
    @ObservedObject var viewModel: DiscoveryViewModel
    let post: Post
    let authorProfile: UserProfile
    let onCommentTapped: () -> Void
    let onReport: () -> Void
    
    @ObservedObject var reportService: ReportStateService
    // to check for guest
    @EnvironmentObject var session: AppSession
    // --- for auth prompt ---
    @Binding var showAuthSheet: Bool
    
    // Check if the current user is the owner of the post
    private var currentUserID: String? { Auth.auth().currentUser?.uid }
    private var isOwner: Bool { post.authorUid == currentUserID }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Header (Profile Image, Name, Report)
            HStack(spacing: 12) {
                // Navigate to profile if UID exists
                if let uid = post.authorUid, !uid.isEmpty {
                    NavigationLink(destination: PlayerProfileContentView(userID: uid)) {
                        profileImage
                    }
                    .buttonStyle(.plain)
                } else {
                    profileImage
                }
                VStack(alignment: .leading) {
                    Text(authorProfile.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(post.timestamp)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Only show the report button if the user is NOT the owner
                if !isOwner {
                    let isReported = (post.id != nil && reportService.reportedPostIDs.contains(post.id!))
                    
                    // --- Report Button Action ---
                    Button {
                        if session.isGuest {
                            showAuthSheet = true
                        } else {
                            onReport()
                        }
                    } label: {
                        Image(systemName: isReported ? "flag.fill" : "flag")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // --- Disable only if already reported ---
                    .disabled(isReported)
                }
            }
            
            // MARK: - Video post
            if let videoStr = post.videoURL, let url = URL(string: videoStr) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                // Fallback to thumbnail image
                AsyncImage(url: URL(string: post.imageName)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { BrandColors.lightGray }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            // MARK: - Caption
            Text(post.caption)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(BrandColors.darkGray)
                .lineLimit(2)

            // MARK: - Action Buttons (Like, Comment)
            HStack(spacing: 16) {
                // --- LIKE BUTTON Action ---
                Button {
                    if session.isGuest {
                        showAuthSheet = true
                    } else {
                        Task { await viewModel.toggleLike(post: post) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: post.isLikedByUser ? "heart.fill" : "heart")
                        Text("\(post.likeCount)")
                    }
                    .foregroundColor(post.isLikedByUser ? .red : BrandColors.darkGray)
                }
                .buttonStyle(.plain)

                // --- COMMENT BUTTON Action ---
                Button {
                    if session.isGuest {
                        showAuthSheet = true
                    } else {
                        onCommentTapped()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "message")
                        Text("\(post.commentCount)")
                    }
                    .foregroundColor(BrandColors.darkGray)
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 14, design: .rounded))
        }
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        .opacity(1)
    }

    // A reusable view builder for the author's profile image
    @ViewBuilder
    private var profileImage: some View {
        if let image = authorProfile.profileImage {
            Image(uiImage: image)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
        } else {
            // Placeholder
            Image(systemName: "person.circle.fill")
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .foregroundColor(BrandColors.lightGray)
        }
    }
}

// MARK: - Filters Sheet
struct FiltersSheetView: View {
    // Bindings (Filter State)
    @Binding var position: String?
    @Binding var ageMin: Int?
    @Binding var ageMax: Int?
    @Binding var scoreMin: Int?
    @Binding var scoreMax: Int?
    @Binding var team: String?
    @Binding var location: String?

    // Local Data
    let positions = ["Attacker", "Midfielder", "Defender"]
    let teams = ["Unassigned"]
    let locations = SAUDI_CITIES

    // The environment object for dismissing the sheet
    @Environment(\.dismiss) private var dismiss
    
    // Info Details
    @State private var showScoreInfo = false
    @State private var showLocationInfo = false
    
    // Validation States
    @State private var ageMinString: String = ""
    @State private var ageMaxString: String = ""
    @State private var scoreMinString: String = ""
    @State private var scoreMaxString: String = ""
    @State private var ageMinNotNumber: Bool = false
    @State private var ageMaxNotNumber: Bool = false
    @State private var scoreMinNotNumber: Bool = false
    @State private var scoreMaxNotNumber: Bool = false

    // `true` if age values are outside the logical range (0-100)
    private var ageValuesInvalid: Bool {
        if let min = ageMin, (min < 4 || min > 100) {
            return true
        }
        if let max = ageMax, (max < 0 || max > 100) {
            return true
        }
        return false
    }

    // `true` if the minimum age is greater than the maximum age
    private var ageRangeInvalid: Bool {
        if let min = ageMin, let max = ageMax {
            return min > max
        }
        return false
    }
    
    // `true` if the age section is valid (no numeric errors, value errors, or range errors)
    private var isAgeSectionValid: Bool {
        !ageValuesInvalid && !ageRangeInvalid && !ageMinNotNumber && !ageMaxNotNumber
    }
    
    // `true` if score values are outside the logical range (e.g., < 0)
    private var scoreValuesInvalid: Bool {
        if let min = scoreMin, min < 0 {
            return true
        }
        return false
    }
    
    // `true` if the minimum score is greater than the maximum score
    private var scoreRangeInvalid: Bool {
        if let min = scoreMin, let max = scoreMax {
            return min > max
        }
        return false
    }

    // `true` if the score section is valid (no numeric errors, value errors, or range errors)
    private var isScoreSectionValid: Bool {
        !scoreValuesInvalid && !scoreRangeInvalid && !scoreMinNotNumber && !scoreMaxNotNumber
    }
    
    // `true` if all form sections are valid, enabling the "Apply" button
    private var isFormValid: Bool {
        isAgeSectionValid && isScoreSectionValid
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Position Filter
                Section("Position") {
                    Picker("Position", selection: $position) {
                        Text("Any").tag(String?.none) // Tag for nil (no filter)
                        ForEach(positions, id: \.self) { pos in
                            Text(pos).tag(String?.some(pos)) // Tag for a specific string
                        }
                    }
                }
                // MARK: - Age Filter
                Section("Age Range") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Min", text: $ageMinString)
                                .keyboardType(.numberPad)
                                .tint(BrandColors.darkTeal)
                                .onChange(of: ageMinString) { newValue in
                                    // Live validation as the user types
                                    if newValue.isEmpty {
                                        ageMinNotNumber = false
                                        ageMin = nil
                                    } else if let number = Int(newValue) {
                                        ageMinNotNumber = false
                                        ageMin = number
                                    } else {
                                        ageMinNotNumber = true // Contains non-numbers
                                        ageMin = nil
                                    }
                                }
                            Text("-")
                            TextField("Max", text: $ageMaxString)
                                .keyboardType(.numberPad)
                                .tint(BrandColors.darkTeal)
                                .onChange(of: ageMaxString) { newValue in
                                    if newValue.isEmpty {
                                        ageMaxNotNumber = false
                                        ageMax = nil
                                    } else if let number = Int(newValue) {
                                        ageMaxNotNumber = false
                                        ageMax = number
                                    } else {
                                        ageMaxNotNumber = true
                                        ageMax = nil
                                    }
                                }
                        }
                        
                        // --- Age Error Messages ---
                        if ageMinNotNumber {
                            Text("Min age must be numbers only.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        if ageMaxNotNumber {
                            Text("Max age must be numbers only.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        // Show range/value errors only if there are no text input errors
                        if !ageMinNotNumber && !ageMaxNotNumber && !isAgeSectionValid {
                            if ageValuesInvalid {
                                Text("Age values must be between 4 and 100.")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            if ageRangeInvalid {
                                Text("Min age must be less than or equal to Max age.")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // MARK: - Score Filter
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Min", text: $scoreMinString)
                                .keyboardType(.numberPad)
                                .tint(BrandColors.darkTeal)
                                .onChange(of: scoreMinString) { newValue in
                                    if newValue.isEmpty {
                                        scoreMinNotNumber = false
                                        scoreMin = nil
                                    } else if let number = Int(newValue) {
                                        scoreMinNotNumber = false
                                        scoreMin = number
                                    } else {
                                        scoreMinNotNumber = true
                                        scoreMin = nil
                                    }
                                }
                            Text("-")
                            TextField("Max", text: $scoreMaxString)
                                .keyboardType(.numberPad)
                                .tint(BrandColors.darkTeal)
                                .onChange(of: scoreMaxString) { newValue in
                                    if newValue.isEmpty {
                                        scoreMaxNotNumber = false
                                        scoreMax = nil
                                    } else if let number = Int(newValue) {
                                        scoreMaxNotNumber = false
                                        scoreMax = number
                                    } else {
                                        scoreMaxNotNumber = true
                                        scoreMax = nil
                                    }
                                }
                        }
                        // --- Score Error Messages ---
                        if scoreMinNotNumber {
                            Text("Min score must be numbers only.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        if scoreMaxNotNumber {
                            Text("Max score must be numbers only.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        if !scoreMinNotNumber && !scoreMaxNotNumber && !isScoreSectionValid {
                            if scoreValuesInvalid {
                                Text("Min score must be 0 or greater.")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            if scoreRangeInvalid {
                                Text("Min score must be less than or equal to Max score.")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    // Header with info button
                    HStack {
                        Text("Score Range")
                        Button {
                            showScoreInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(BrandColors.darkTeal)
                        }
                    }
                }
                // MARK: - Team Filter
                Section("Current Team") {
                    Picker("Team", selection: $team) {
                        Text("Any").tag(String?.none)
                        ForEach(teams, id: \.self) { t in Text(t).tag(String?.some(t)) }
                    }
                }
                // MARK: - Location Filter
                Section {
                    Picker("Residence", selection: $location) {
                        Text("Any").tag(String?.none)
                        ForEach(locations, id: \.self) { loc in Text(loc).tag(String?.some(loc)) }
                    }
                } header: {
                    HStack {
                        Text("Residence")
                        Button {
                            showLocationInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(BrandColors.darkTeal)
                        }
                    }
                }
                
                // MARK: - Action Buttons
                Section {
                    Button("Apply Filters") { dismiss() }
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(BrandColors.darkTeal)
                        .frame(maxWidth: .infinity)
                        .disabled(!isFormValid) // Enabled only if form is valid
                        .opacity(isFormValid ? 1.0 : 0.5)
                    
                    Button("Reset All", role: .destructive) {
                        // Clear all bindings and local string state
                        position = nil; ageMin = nil; ageMax = nil
                        scoreMin = nil; scoreMax = nil
                        team = nil; location = nil
                        ageMinString = ""; ageMaxString = ""
                        scoreMinString = ""; scoreMaxString = ""
                        dismiss()
                    }
                    .font(.system(size: 17, design: .rounded))
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            // MARK: - Score Info Alerts
            .alert("How is this calculated?", isPresented: $showScoreInfo) {
                Button("Got it!") { }
            } message: {
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
            }
            .alert("Location", isPresented: $showLocationInfo) {
                Button("Got it!") { }
            } message: {
                Text("The player's place of residence.")
            }
            .onAppear {
                // When the sheet appears, populate the string text fields from the main view's filter bindings
                ageMinString = ageMin.map { String($0) } ?? ""
                ageMaxString = ageMax.map { String($0) } ?? ""
                scoreMinString = scoreMin.map { String($0) } ?? ""
                scoreMaxString = scoreMax.map { String($0) } ?? ""
            }
        }
    }
}

// MARK: - Auth Prompt Popup
// A simple popup to prompt guest users to sign up or log in.
struct AuthPromptSheet: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            // Dimming background
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { withAnimation { isPresented = false } }
                .transition(.opacity)

            // Popup content card
            VStack(spacing: 20) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(BrandColors.darkTeal)
                    .padding(.top, 10)
                
                Text("Join Haddaf!")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                
                Text("To do this action you need to be part of Haddaf. Please sign up or sign in to get started.")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button { withAnimation { isPresented = false } } label: {
                    Text("Got It")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(BrandColors.darkTeal)
                        .clipShape(Capsule())
                }
            }
            .padding(EdgeInsets(top: 20, leading: 30, bottom: 20, trailing: 30))
            .background(BrandColors.background)
            .cornerRadius(20)
            .shadow(radius: 12)
            .padding(.horizontal, 40)
            .transition(.scale.combined(with: .opacity))
        }
        .zIndex(2)
    }
}
