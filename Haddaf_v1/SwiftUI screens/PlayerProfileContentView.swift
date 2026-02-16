import SwiftUI
import PhotosUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

// Notification posted when the user's profile data has been successfully saved
extension Notification.Name {
    static let profileUpdated = Notification.Name("profileUpdated")
}

// MARK: - Score Filter Enum
enum ScoreFilter: String, CaseIterable, Identifiable {
    case `public` = "Public Score"
    case `private` = "Private Score"
    case both = "Total Score (All)"
    
    var id: String { rawValue }
}

// MARK: - Main Profile Content View
struct PlayerProfileContentView: View {
    // The view model responsible for fetching and managing all profile data
    @StateObject private var viewModel: PlayerProfileViewModel
    // The currently selected tab in the content section (Posts, Progress, or Endorsements)
    @State private var selectedContent: ContentType = .posts
    // Controls the visibility of the popup explaining the score calculation
    @State private var showScoreInfoAlert = false
    // Score Filter State
    @State private var selectedScoreFilter: ScoreFilter = .public

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
    @State private var showDeactivatedSheet = false
    @State private var showUnverifiedCoachSheet = false
    // A boolean indicating if this profile belongs to the currently logged-in user
    private var isCurrentUser: Bool
    
    // A boolean to track if this is the root profile (from the tab bar)
    private var isRootProfileView: Bool
    
    var isAdminViewing: Bool
    
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
    
    // Search Date Filters
    @State private var searchDate: Date? = nil
    @State private var showSearchDatePicker = false

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
        self.isRootProfileView = true
        self.isAdminViewing = false
    }

    // Initializes the view for a specific user
    // - Parameter userID: The UID of the user to display
    init(userID: String, isAdminViewing: Bool = false) {
        _viewModel = StateObject(wrappedValue: PlayerProfileViewModel(userID: userID))
        self.isCurrentUser = (userID == Auth.auth().currentUser?.uid)
        self.isRootProfileView = false
        self.isAdminViewing = isAdminViewing
    }

    // Filters the posts by `searchText` and `postFilter` then sorts them based on `postSort` preferences
    private var filteredAndSortedPosts: [Post] {
        // Start with all posts
        var result = viewModel.posts

        // 1. Filter by Caption (Text)
        if !searchText.isEmpty {
            result = result.filter { $0.caption.localizedCaseInsensitiveContains(searchText) }
        }
        
        // 2. Filter by Match Date (Calendar Picker)
        if let targetDate = searchDate {
            result = result.filter { post in
                guard let pDate = post.matchDate else { return false }
                // Compare Year, Month, Day (ignoring time)
                return Calendar.current.isDate(pDate, inSameDayAs: targetDate)
            }
        }

        // 3. Filter by Privacy (if current user)
        let privacyFiltered: [Post]
        if isCurrentUser {
            switch postFilter {
            case .all: privacyFiltered = result
            case .public: privacyFiltered = result.filter { !$0.isPrivate }
            case .private: privacyFiltered = result.filter { $0.isPrivate }
            }
        } else {
            // Other users can only see public posts
            privacyFiltered = result.filter { !$0.isPrivate }
        }

        // 4. Sort the results
        switch postSort {
        case .newestFirst:
            return privacyFiltered
        case .oldestFirst:
            return privacyFiltered.reversed()
        case .matchDateNewest:
            return privacyFiltered.sorted {
                guard let d1 = $0.matchDate else { return false }
                guard let d2 = $1.matchDate else { return true }
                return d1 > d2
            }
        case .matchDateOldest:
            return privacyFiltered.sorted {
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
                            isRootProfileView: isRootProfileView,
                            onReport: {
                                if session.isGuest {
                                    showAuthSheet = true
                                } else if !session.isActive {
                                    showDeactivatedSheet = true
                                } else if session.role == "coach" && !session.isVerifiedCoach {
                                    showUnverifiedCoachSheet = true
                                } else {
                                    // Set the item to report (this profile)
                                    itemToReport = ReportableItem(
                                        id: viewModel.userProfile.email,
                                        parentId: nil,
                                        type: .profile,
                                        contentPreview: viewModel.userProfile.name
                                    )
                                }
                            },
                            reportService: reportService,
                            reportedID: viewModel.userProfile.email,
                            isAdminViewing: isAdminViewing
                        )
                        ProfileHeaderView(userProfile: viewModel.userProfile)
                            .padding(.bottom, 0)
                            .zIndex(1)

                        StatsGridView(
                            userProfile: viewModel.userProfile,
                            posts: viewModel.posts,
                            isCurrentUser: isCurrentUser,
                            selectedFilter: $selectedScoreFilter,
                            showScoreInfoAlert: $showScoreInfoAlert
                        )
                        .zIndex(0)
                       
                        ContentTabView(selectedContent: $selectedContent, isCurrentUser: isCurrentUser)

                        // MARK: - Tab Content
                        switch selectedContent {
                        case .posts:
                                // Search Bar with Calendar
                                HStack(spacing: 12) {
                                    // Magnifying Glass
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(BrandColors.darkTeal)
                                        .padding(.leading, 12)
                               
                                    // Text Field
                                    TextField("Search by title...", text: $searchText)
                                        .font(.system(size: 16, design: .rounded))
                                        .tint(BrandColors.darkTeal)
                                        .submitLabel(.search)
                                    
                                    // Vertical Divider
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 1, height: 20)
                                    
                                    // Calendar Button
                                    Button {
                                        showSearchDatePicker = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "calendar")
                                            // If date selected, show day/month
                                            if let d = searchDate {
                                                Text(d.formatted(.dateTime.day().month()))
                                                    .font(.caption).bold()
                                            }
                                        }
                                        .foregroundColor(searchDate == nil ? .secondary : BrandColors.darkTeal)
                                        .padding(.vertical, 4)
                                    }
                               
                                    // Clear Button (Clears both Text and Date)
                                    if !searchText.isEmpty || searchDate != nil {
                                        Button {
                                            searchText = ""
                                            searchDate = nil
                                            // Dismiss keyboard
                                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.trailing, 8)
                                    } else {
                                        Spacer().frame(width: 8)
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
                                message: "To be developed in upcoming sprints"
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
            .task {
                await viewModel.fetchAllData()
                
                // Start listening to notifications
                if isCurrentUser, let userId = Auth.auth().currentUser?.uid {
                    NotificationService.shared.startListening(for: userId)
                }
            }
            .onDisappear {
                if isCurrentUser {
                    NotificationService.shared.stopListening()
                }
            }
            .onChange(of: viewModel.userProfile.position) { _, _ in
                // If the user's position changes (in EditProfile), recalculate the score
                Task {
                    await viewModel.fetchProfile()
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
                NotificationsView()
                    .environmentObject(session)
            }
            .fullScreenCover(isPresented: $showNotificationsList) {
                ProfileNotificationsListView()
            }
            // Search Date Picker Sheet
            .sheet(isPresented: $showSearchDatePicker) {
                VStack(spacing: 20) {
                    Capsule()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 10)
                    
                    Text("Search by Match Date")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(BrandColors.darkTeal)
                        .padding(.top, 10)
                    
                    DatePicker("Select Date", selection: Binding(
                        get: { searchDate ?? Date() },
                        set: { searchDate = $0 }
                    ), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(BrandColors.darkTeal)
                    .padding(.horizontal)
                    
                    Button {
                        showSearchDatePicker = false
                    } label: {
                        Text("Apply Filter")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(BrandColors.darkTeal)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .presentationDetents([.medium])
                .presentationCornerRadius(25)
                .presentationBackground(BrandColors.background)
            }
            // --- Open Post Detail view ---
            .fullScreenCover(item: $selectedPost) { post in
                NavigationStack {
                    PostDetailView(post: post, showAuthSheet: $showAuthSheet, isAdminViewing: session.isAdmin)
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
            
            if showAuthSheet {
                AuthPromptSheet(isPresented: $showAuthSheet)
            }

            if showDeactivatedSheet {
                DeactivatedAccountGateView(isPresented: $showDeactivatedSheet)
                    .animation(.easeInOut, value: showDeactivatedSheet)
            }

            if showUnverifiedCoachSheet {
                UnverifiedCoachGateView(isPresented: $showUnverifiedCoachSheet)
                    .animation(.easeInOut, value: showUnverifiedCoachSheet)
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
    // `true` if this is the root profile (from the tab bar).
    var isRootProfileView: Bool
    // The unique ID of the profile being viewed (for reporting).
    var onReport: () -> Void

    @ObservedObject var reportService: ReportStateService
    var reportedID: String
    var isAdminViewing: Bool

    var body: some View {
        HStack(spacing: 16) {
            // --- 1. Left Back Button ---
            // Show the "Back" button if this is NOT the root profile view.
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
            
            // --- 2. Right Buttons ---
            if isCurrentUser {
                // It's the current user. Always show Settings/Notifications on right
                
                // "Notifications" button
                Button { showNotifications = true } label: {
                    Image(systemName: "bell")
                        .font(.title2)
                        .foregroundColor(BrandColors.darkTeal)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                // "Settings" button
                Button { goToSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .foregroundColor(BrandColors.darkTeal)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                
            } else if !isAdminViewing {
                // It's another user. (!isRootProfileView is true)
                // Show the "Report" button insted
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
// MARK: - Stats Grid (UPDATED)
struct StatsGridView: View {
    // The profile data to display.
    @ObservedObject var userProfile: UserProfile
    
    // NEW Params for dynamic calculation
    var posts: [Post]
    var isCurrentUser: Bool
    @Binding var selectedFilter: ScoreFilter
    
    // --- Dropdown States ---
    @State private var showContactInfo = false
    @State private var showOtherPositions = false
    
    // A binding to control the "Score Info" popup.
    @Binding var showScoreInfoAlert: Bool
    
    let accentColor = BrandColors.darkTeal
    let goldColor = BrandColors.gold

    // --- LOGIC: Dynamic Hero Score Calculation ---
    var currentPositionScore: String {
        // If not current user, default to standard public calculation from map
        if !isCurrentUser {
            guard let stat = userProfile.positionStats[userProfile.position], stat.postCount > 0 else {
                return "0"
            }
            let avg = stat.totalScore / Double(stat.postCount)
            return String(format: "%.0f", avg)
        }
        
        // For current user, calculate dynamically from posts array
        let currentPos = userProfile.position
        if currentPos.isEmpty { return "0" }
        
        // 1. Filter posts
        let relevantPosts = posts.filter { post in
            guard post.positionAtUpload == currentPos else { return false }
            switch selectedFilter {
            case .public: return !post.isPrivate
            case .private: return post.isPrivate
            case .both: return true
            }
        }
        
        if relevantPosts.isEmpty { return "0" }
        
        // 2. Average Calculation
        let totalScore = relevantPosts.reduce(0.0) { $0 + $1.postScore }
        let avg = totalScore / Double(relevantPosts.count)
        
        return String(format: "%.0f", avg)
    }
    
    // --- LOGIC: Other Positions Calculation (Public & Private) ---
    var otherPositionStats: [(position: String, publicScore: String, privateScore: String)] {
        let postPositions = Set(posts.map { $0.positionAtUpload }.filter { !$0.isEmpty })
        let mapPositions = Set(userProfile.positionStats.keys)
        let allPositions = postPositions.union(mapPositions).filter { $0 != userProfile.position }
        
        return allPositions.compactMap { pos in
            let posPosts = posts.filter { $0.positionAtUpload == pos }
            
            // Public
            let publicPosts = posPosts.filter { !$0.isPrivate }
            let pubScoreStr: String
            if !publicPosts.isEmpty {
                let total = publicPosts.reduce(0.0) { $0 + $1.postScore }
                pubScoreStr = String(format: "%.0f", total / Double(publicPosts.count))
            } else if let stat = userProfile.positionStats[pos], stat.postCount > 0 {
                let avg = stat.totalScore / Double(stat.postCount)
                pubScoreStr = String(format: "%.0f", avg)
            } else {
                pubScoreStr = "-"
            }
            
            // Private
            let privScoreStr: String
            if isCurrentUser {
                let privatePosts = posPosts.filter { $0.isPrivate }
                if !privatePosts.isEmpty {
                    let total = privatePosts.reduce(0.0) { $0 + $1.postScore }
                    privScoreStr = String(format: "%.0f", total / Double(privatePosts.count))
                } else {
                    privScoreStr = "-"
                }
            } else {
                privScoreStr = "-"
            }
            
            if pubScoreStr == "-" && privScoreStr == "-" { return nil }
            return (pos, pubScoreStr, privScoreStr)
        }
        .sorted { $0.position < $1.position }
    }

    // --- Components ---
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

            // 1. Hero Stat
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    if isCurrentUser {
                        Menu {
                            Picker("Score Filter", selection: $selectedFilter) {
                                ForEach(ScoreFilter.allCases) { filter in
                                    Text(filter.rawValue).tag(filter)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(selectedFilter.rawValue)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .foregroundColor(accentColor)
                        }
                    } else {
                        Text("Performance Score")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(accentColor)
                    }
                    
                    Button { showScoreInfoAlert = true } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(accentColor)
                    }
                }

                Text(currentPositionScore)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(goldColor)
                
                if !userProfile.position.isEmpty {
                    Text(userProfile.position)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(accentColor.opacity(0.6))
                }
            }
            .padding(.top, 10)

            // 2. User-Provided Stats
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

            // 3. System Stats
            HStack(alignment: .top) {
                Spacer()
                SystemStatItem(title: "Team", value: userProfile.team)
                Spacer()
                SystemStatItem(title: "Challenge Rank", value: userProfile.rank)
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // 4. Horizontal Container for Dropdowns
            HStack(alignment: .top, spacing: 0) {
                
                // --- Left Side: Past Positions ---
                // Show ONLY if the user has allowed it to be visible
                if !otherPositionStats.isEmpty && userProfile.isPastPositionsVisible {
                    VStack(alignment: .center, spacing: 10) {
                        Button(action: { withAnimation(.spring()) { showOtherPositions.toggle() } }) {
                            HStack(spacing: 4) {
                                Text(showOtherPositions ? "Hide Past" : "Past Positions")
                                    .font(.system(size: 13, weight: .bold, design: .rounded)) // UNIFIED FONT
                                Image(systemName: showOtherPositions ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                            }
                            .foregroundColor(accentColor)
                        }
                        
                        if showOtherPositions {
                            VStack(spacing: 12) {
                                ForEach(otherPositionStats, id: \.position) { item in
                                    VStack(spacing: 4) {
                                        // Position Name
                                        Text(item.position)
                                            .font(.system(size: 12, weight: .medium, design: .rounded)) // MATCHES CONTACT FONT
                                            .foregroundColor(BrandColors.darkGray)
                                        
                                        // Score Pills
                                        HStack(spacing: 6) {
                                            // Public
                                            if item.publicScore != "-" {
                                                Text("Pub: \(item.publicScore)")
                                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                                    .foregroundColor(BrandColors.darkGray)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(goldColor.opacity(0.3))
                                                    .cornerRadius(6)
                                            }
                                            
                                            // Private
                                            if item.privateScore != "-" {
                                                Text("Pvt: \(item.privateScore)")
                                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(accentColor.opacity(0.8))
                                                    .cornerRadius(6)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top) // TOP ALIGNMENT
                }

                // Vertical Divider
                if !otherPositionStats.isEmpty && (userProfile.isEmailVisible || userProfile.isPhoneNumberVisible) {
                    Divider()
                        .frame(height: 20)
                        .padding(.top, 4)
                }
                
                // --- Right Side: Contact Info ---
                if userProfile.isEmailVisible || userProfile.isPhoneNumberVisible {
                    VStack(alignment: .center, spacing: 10) {
                        Button(action: { withAnimation(.spring()) { showContactInfo.toggle() } }) {
                            HStack(spacing: 4) {
                                Text(showContactInfo ? "Hide Contact" : "Contact Info")
                                    .font(.system(size: 13, weight: .bold, design: .rounded)) // UNIFIED FONT
                                Image(systemName: showContactInfo ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                            }
                            .foregroundColor(accentColor)
                        }
                        
                        if showContactInfo {
                            VStack(spacing: 8) {
                                if userProfile.isEmailVisible {
                                    contactItem(icon: "envelope.fill", value: userProfile.email)
                                }
                                if userProfile.isPhoneNumberVisible {
                                    contactItem(icon: "phone.fill", value: userProfile.phoneNumber)
                                }
                            }
                            .padding(.bottom, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top) // TOP ALIGNMENT
                }
            }
            .padding(.top, 4)
            .padding(.horizontal)
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

    // A small view for displaying a contact detail
    private func contactItem(icon: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(accentColor)
                .frame(width: 16)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded)) // UNIFIED FONT
                .foregroundColor(BrandColors.darkGray)
                .lineLimit(1)
                .truncationMode(.tail)
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
                    message: "To be developed in upcoming sprints"
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
