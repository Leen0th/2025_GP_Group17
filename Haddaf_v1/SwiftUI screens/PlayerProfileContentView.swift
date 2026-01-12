import SwiftUI
import PhotosUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

// Notification posted when the user's profile data has been successfully saved
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
    
    // A boolean to track if this is the root profile (from the tab bar)
    private var isRootProfileView: Bool
    
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
        self.isRootProfileView = true
    }
    
    // Initializes the view for a specific user
    // - Parameter userID: The UID of the user to display
    init(userID: String) {
        _viewModel = StateObject(wrappedValue: PlayerProfileViewModel(userID: userID))
        self.isCurrentUser = (userID == Auth.auth().currentUser?.uid)
        self.isRootProfileView = false
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
                            isRootProfileView: isRootProfileView,
                            onReport: {
                                // --- Check for guest ---
                                if session.isGuest {
                                    showAuthSheet = true
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
                
            } else {
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
