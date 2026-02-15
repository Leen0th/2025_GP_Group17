import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AVKit
import FirebaseStorage
import UniformTypeIdentifiers

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
    @State private var showDeactivationDetails = false
    // --- for re-application ---
    @State private var showReapplySheet = false
    
    @State private var showRejectionDetails = false

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
            // --- Sheet for Re-applying ---
            .sheet(isPresented: $showReapplySheet) {
                ReapplyCoachSheet()
                    .presentationDetents([.medium, .large])
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
            // Deactivation Banner - Show for all deactivated accounts
            if !session.isActive {
                VStack(spacing: 0) {
                    // Collapsed Banner - Always visible
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showDeactivationDetails.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                            
                            Text(showDeactivationDetails ? "Account Deactivated - Tap to minimize" : "Account Deactivated - Tap to view details")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Spacer()
                            
                            Image(systemName: showDeactivationDetails ? "chevron.up" : "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(Color.red.opacity(0.9))
                    
                    // Expanded Details
                    if showDeactivationDetails, let reason = session.deactivationReason {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.red)
                                Text("Reason:")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(reason)
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Text("If you think this is a mistake, contact support@haddaf.com")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                        .padding(16)
                        .background(Color.white)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            
            // Coach banners - only show if account is active
            if session.role == "coach" && session.isActive {
                if session.coachStatus == "rejected" {
                    // Navigate to request status to see rejection in timeline
                    NavigationLink {
                        CoachRequestStatusView()
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                            
                            Text("Application Rejected - Tap to view")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                } else if !session.isVerifiedCoach {
                    // MARK: - Under Review / Pending Banner
                    if session.coachStatus == "under_review" {
                        // Under Review - Action might be required
                        NavigationLink {
                            CoachRequestStatusView()
                        } label: {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Action Required")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    
                                    Text("Admin has requested additional information")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.9))
                        }
                    } else {
                        // Pending - Normal review
                        Text("Your coaching profile is under review (It usually takes 1–2 business days to verify). Social features will be unlocked once approved!")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.9))
                    }
                }
            }
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
                                NavigationLink(destination: PostDetailView(post: post, showAuthSheet: $showAuthSheet, isAdminViewing: session.isAdmin)) {
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
                                                parentId: nil,
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
                        guard session.isActive else {
                            // Show alert that account is deactivated
                            return
                        }
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
                    .disabled(isReported || (session.role == "coach" && !session.isVerifiedCoach))
                    .opacity((session.role == "coach" && !session.isVerifiedCoach) ? 0.5 : 1.0)
                    // --- Disable only if already reported ---
                    .disabled(isReported)
                }
            }
            
            // MARK: - Video post
            if let videoStr = post.videoURL, let url = URL(string: videoStr) {
                FeedVideoPlayer(url: url)
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
                    guard session.isActive else {
                        // Show alert that account is deactivated
                        return
                    }
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
                .disabled(session.role == "coach" && !session.isVerifiedCoach)
                .opacity((session.role == "coach" && !session.isVerifiedCoach) ? 0.5 : 1.0)

                // --- COMMENT BUTTON Action ---
                Button {
                    guard session.isActive else {
                        // Show alert that account is deactivated
                        return
                    }
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
                .disabled(session.role == "coach" && !session.isVerifiedCoach)
                .opacity((session.role == "coach" && !session.isVerifiedCoach) ? 0.5 : 1.0)
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
        if let min = ageMin, (min < 7 || min > 100) {
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
                                    // 1. Enforce max 3 digits
                                    if newValue.count > 3 {
                                        ageMinString = String(newValue.prefix(3))
                                    }
                                    
                                    // 2. Use the truncated value for validation
                                    let actualValue = newValue.count > 3 ? String(newValue.prefix(3)) : newValue
                                    
                                    if actualValue.isEmpty {
                                        ageMinNotNumber = false
                                        ageMin = nil
                                    } else if let number = Int(actualValue) {
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
                                    // 1. Enforce max 3 digits
                                    if newValue.count > 3 {
                                        ageMaxString = String(newValue.prefix(3))
                                    }
                                    
                                    // 2. Use the truncated value for validation
                                    let actualValue = newValue.count > 3 ? String(newValue.prefix(3)) : newValue
                                    
                                    if actualValue.isEmpty {
                                        ageMaxNotNumber = false
                                        ageMax = nil
                                    } else if let number = Int(actualValue) {
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
                                Text("Age values must be between 7 and 100.")
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
                                    // 1. Enforce max 4 digits
                                    if newValue.count > 4 {
                                        scoreMinString = String(newValue.prefix(4))
                                    }
                                    
                                    // 2. Use the truncated value for validation
                                    let actualValue = newValue.count > 4 ? String(newValue.prefix(4)) : newValue
                                    
                                    if actualValue.isEmpty {
                                        scoreMinNotNumber = false
                                        scoreMin = nil
                                    } else if let number = Int(actualValue) {
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
                                    // 1. Enforce max 4 digits
                                    if newValue.count > 4 {
                                        scoreMaxString = String(newValue.prefix(4))
                                    }
                                    
                                    // 2. Use the truncated value for validation
                                    let actualValue = newValue.count > 4 ? String(newValue.prefix(4)) : newValue
                                    
                                    if actualValue.isEmpty {
                                        scoreMaxNotNumber = false
                                        scoreMax = nil
                                    } else if let number = Int(actualValue) {
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
                   ATK     1      5      10
                   MID     10     5       1
                   DEF     5     10       1
                
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
                
                Text("To perform this action, you need to be part of Haddaf. Please go to the Profile tab and sign up or sign in to get started.")
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
struct FeedVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                if player == nil {
                    player = AVPlayer(url: url)
                }
            }
            .onDisappear {
                // Pause when scrolling away to save resources
                player?.pause()
            }
    }
}

struct ReapplyCoachSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let primary = BrandColors.darkTeal
    
    @State private var showFileImporter = false
    @State private var selectedFileURL: URL?
    @State private var selectedFileName: String = ""
    @State private var isUploading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.background.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    
                    // Icon
                    Image(systemName: "doc.text.arrow.up")
                        .font(.system(size: 50))
                        .foregroundColor(primary)
                        .padding(.top, 40)
                    
                    VStack(spacing: 12) {
                        Text("Resubmit Verification Document")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(BrandColors.darkGray)
                        
                        Text("Please upload a valid coaching certificate or ID")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    
                    // File Selection Area
                    Button {
                        showFileImporter = true
                    } label: {
                        VStack(spacing: 12) {
                            if let _ = selectedFileURL {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.green)
                                Text(selectedFileName)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .padding(.horizontal)
                                Text("Tap to change file")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 30))
                                    .foregroundColor(primary.opacity(0.8))
                                Text("Select PDF or Image")
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundColor(primary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                                .foregroundColor(primary.opacity(0.3))
                                .background(primary.opacity(0.03))
                        )
                        .padding(.horizontal, 20)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    // Submit Button
                    Button {
                        Task { await submitReapplication() }
                    } label: {
                        HStack {
                            Text(isUploading ? "Uploading..." : "Submit Application")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                            if isUploading {
                                ProgressView().tint(.white).padding(.leading, 8)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(selectedFileURL == nil ? Color.gray : primary)
                        .clipShape(Capsule())
                    }
                    .disabled(selectedFileURL == nil || isUploading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType.pdf, UTType.image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    // Security scope access is required for file importer URLs
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        // Create a temporary copy to ensure we can read it later during upload
                        do {
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                            try? FileManager.default.removeItem(at: tempURL) // clear previous
                            try FileManager.default.copyItem(at: url, to: tempURL)
                            
                            self.selectedFileURL = tempURL
                            self.selectedFileName = url.lastPathComponent
                            self.errorMessage = nil
                        } catch {
                            self.errorMessage = "Failed to select file: \(error.localizedDescription)"
                        }
                    } else {
                        self.errorMessage = "Permission denied to access the file."
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func submitReapplication() async {
        guard let fileURL = selectedFileURL,
              let user = Auth.auth().currentUser else { return }
        
        isUploading = true
        errorMessage = nil
        
        do {
            let uid = user.uid
            let fileName = UUID().uuidString + "_" + fileURL.lastPathComponent
            let storageRef = Storage.storage().reference().child("coach_verifications/\(uid)/\(fileName)")
            
            // 1. Upload File
            // Note: putFileAsync is safer for local files than putDataAsync
            _ = try await storageRef.putFileAsync(from: fileURL, metadata: nil)
            let downloadURL = try await storageRef.downloadURL()
            
            let db = Firestore.firestore()
            let batch = db.batch()
            
            // 2. Add new request to 'coachRequests' collection
            // We use .document() without ID to auto-generate a new request ID
            // This ensures admins see it as a fresh request in their list
            let newRequestRef = db.collection("coachRequests").document()
            
            // Fetch user name/email first to populate the request
            let userDoc = try await db.collection("users").document(uid).getDocument()
            let userData = userDoc.data() ?? [:]
            let firstName = userData["firstName"] as? String ?? ""
            let lastName = userData["lastName"] as? String ?? ""
            let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            let email = user.email ?? ""
            
            let requestData: [String: Any] = [
                "uid": uid,
                "email": email,
                "fullName": fullName.isEmpty ? "Coach" : fullName,
                "verificationFile": downloadURL.absoluteString,
                "status": "pending",
                "submittedAt": FieldValue.serverTimestamp()
            ]
            batch.setData(requestData, forDocument: newRequestRef)
            
            // 3. Update User Document
            // Reset status to pending and remove the old rejection reason
            let userRef = db.collection("users").document(uid)
            batch.updateData([
                "coachStatus": "pending",
                "rejectionReason": FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: userRef)
            
            try await batch.commit()
            
            await MainActor.run {
                isUploading = false
                dismiss()
            }
            
        } catch {
            await MainActor.run {
                isUploading = false
                errorMessage = "Upload failed: \(error.localizedDescription)"
            }
        }
    }
}
