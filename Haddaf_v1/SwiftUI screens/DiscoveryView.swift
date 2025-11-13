//
//  DiscoveryView.swift
//  Haddaf_v1
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AVKit

// MARK: - Discovery View
struct DiscoveryView: View {
    enum TopTab: String, CaseIterable { case discovery = "Discovery", leaderboard = "Leaderboard" }
    @State private var selectedTab: TopTab = .discovery   // يفتح على الديسكفري

    @StateObject private var viewModel = DiscoveryViewModel()
    @StateObject private var lbViewModel = LeaderboardViewModel()
    
    // --- Use the shared reporting service and observe its changes ---
    @StateObject private var reportService = ReportStateService.shared

    @State private var searchText = ""

    // Filters
    @State private var filterPosition: String? = nil
    @State private var filterAgeMin: Int? = nil
    @State private var filterAgeMax: Int? = nil
    @State private var filterScoreMin: Int? = nil
    @State private var filterScoreMax: Int? = nil
    @State private var filterTeam: String? = nil
    @State private var filterLocation: String? = nil

    @State private var showFiltersSheet = false
    
    // State to manage the comments sheet
    @State private var postForComments: Post? = nil
    
    // --- 1. ADDED STATE FOR PROGRAMMATIC NAVIGATION ---
    @State private var navigateToProfileID: String?
    @State private var navigationTrigger = false
    // --- END ADDED ---
    
    // --- ADDED: State for reporting ---
    @State private var itemToReport: ReportableItem?
    // --- END ADDED ---

    private var filteredPosts: [Post] {
        viewModel.posts.filter { post in
            let nameMatch = searchText.isEmpty || post.authorName.localizedCaseInsensitiveContains(searchText)
            guard let authorUid = post.authorUid,
                  let profile = viewModel.authorProfiles[authorUid] else {
                return nameMatch
            }
            let positionMatch = filterPosition == nil || profile.position == filterPosition
            let age = Int(profile.age) ?? 0
            let ageMatch = (filterAgeMin == nil || age >= filterAgeMin!) &&
                           (filterAgeMax == nil || age <= filterAgeMax!)
            let score = Int(profile.score) ?? 0
            let scoreMatch = (filterScoreMin == nil || score >= filterScoreMin!) &&
                             (filterScoreMax == nil || score <= filterScoreMax!)
            let teamMatch = filterTeam == nil || profile.team == filterTeam
            let locationMatch = filterLocation == nil || profile.location == filterLocation
            return nameMatch && positionMatch && ageMatch && scoreMatch && teamMatch && locationMatch
        }
    }

    private var isFiltering: Bool {
        !searchText.isEmpty || filterPosition != nil || filterAgeMin != nil || filterAgeMax != nil ||
        filterScoreMin != nil || filterScoreMax != nil || filterTeam != nil || filterLocation != nil
    }

    var body: some View {
        // ✅ NavigationStack هنا يزيل الضباب ويُفعّل التنقّل للروابط
        NavigationStack {
            ZStack {
                // خلفية ثابتة بدون أي مواد ضبابية
                BrandColors.gradientBackground.ignoresSafeArea()
                
                // --- 2. ADDED HIDDEN NAVIGATIONLINK ---
                NavigationLink(
                    destination: PlayerProfileContentView(userID: navigateToProfileID ?? ""),
                    isActive: $navigationTrigger
                ) { EmptyView() }
                // --- END ADDED ---

                if viewModel.isLoadingPosts {
                    ProgressView().tint(BrandColors.darkTeal)
                } else {
                    VStack(spacing: 0) {
                        // ===== Tabs =====
                        HStack(spacing: 0) {
                            topTabButton(.discovery)
                            Divider().frame(height: 24).padding(.horizontal, 12)
                            topTabButton(.leaderboard)
                        }
                        .padding(.vertical, 8)

                        // ===== Body per tab =====
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
            }
            .toolbar(.hidden, for: .navigationBar) // لا شريط علوي
            .navigationBarBackButtonHidden(true)
            .onAppear { lbViewModel.loadLeaderboardIfNeeded() }
            .sheet(isPresented: Binding(get: {
                selectedTab == .discovery && showFiltersSheet
            }, set: { showFiltersSheet = $0 })) {
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
            // --- ✅ MODIFIED: Sheet for showing comments ---
            .sheet(item: $postForComments) { post in
                if let postId = post.id {
                    CommentsView(
                        postId: postId,
                        // --- 3. THIS IS THE FIX ---
                        onProfileTapped: { userID in
                            // 1. Set the ID for our NavigationLink
                            navigateToProfileID = userID
                            // 2. Dismiss the sheet
                            postForComments = nil // Use this to dismiss an item-based sheet
                            // 3. Trigger the navigation after a short delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                navigationTrigger = true
                            }
                        }
                    )
                    .presentationBackground(BrandColors.background)
                }
            }
            // --- Sheet for reporting ---
            .sheet(item: $itemToReport) { item in
                ReportView(item: item) { reportedID in
                    // On complete, tell the shared service to report the post
                    reportService.reportPost(id: reportedID)
                }
            }
            // --- Listener for sync ---
            .onReceive(NotificationCenter.default.publisher(for: .postDataUpdated)) { notification in
                viewModel.handlePostDataUpdate(notification: notification)
            }
            // --- END ADDED ---
        }
    }

    // MARK: - Tab Button
    @ViewBuilder
    private func topTabButton(_ tab: TopTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        } label: {
            VStack(spacing: 6) {
                Text(tab.rawValue)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(selectedTab == tab ? BrandColors.darkTeal : BrandColors.darkTeal.opacity(0.45))
                RoundedRectangle(cornerRadius: 1)
                    .frame(height: 2)
                    .foregroundColor(selectedTab == tab ? BrandColors.darkTeal : .clear)
                    .frame(width: 120)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Discovery Tab Content
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
                .background(BrandColors.lightGray.opacity(0.7))
                .clipShape(Capsule())

                Button { showFiltersSheet = true } label: {
                    // Icon changes based on isFiltering
                    Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(BrandColors.darkTeal)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if filteredPosts.isEmpty && isFiltering {
                EmptyStateView(
                    image: "doc.text.magnifyingglass",
                    title: "No Matching Results",
                    message: "Try adjusting your search or filter settings."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredPosts, id: \.id) { post in
                        
                            // Check the *hidden* list to show the placeholder
                            if let postId = post.id, reportService.hiddenPostIDs.contains(postId) {
                                ReportedContentView(type: .post) {
                                    // This call is now correct: it only un-hides
                                    reportService.unhidePost(id: postId)
                                }
                            } else {
                                NavigationLink(destination: PostDetailView(post: post)) {
                                    let authorProfile = post.authorUid.flatMap { viewModel.authorProfiles[$0] } ?? UserProfile()
                                    DiscoveryPostCardView(
                                        viewModel: viewModel, // Pass the view model
                                        post: post,
                                        authorProfile: authorProfile,
                                        onCommentTapped: { // Pass the closure
                                            self.postForComments = post
                                        },
                                        onReport: {
                                            // --- ADDED: Trigger report flow ---
                                            itemToReport = ReportableItem(
                                                id: post.id ?? "",
                                                type: .post,
                                                contentPreview: post.caption
                                            )
                                        },
                                        reportService: reportService
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 80)
                }
                .opacity(1) // تأكيد: لا تعتيم
            }
        }
    }

    // --- Empty state
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
struct DiscoveryPostCardView: View {
    @ObservedObject var viewModel: DiscoveryViewModel
    let post: Post
    let authorProfile: UserProfile
    let onCommentTapped: () -> Void
    let onReport: () -> Void
    
    @ObservedObject var reportService: ReportStateService
    
    // Check if the current user is the owner of the post
    private var currentUserID: String? { Auth.auth().currentUser?.uid }
    private var isOwner: Bool { post.authorUid == currentUserID }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
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
                    // It checks the *permanent* reported list.
                    let isReported = (post.id != nil && reportService.reportedPostIDs.contains(post.id!))
                    
                    Button(action: onReport) {
                        Image(systemName: isReported ? "flag.fill" : "flag") // Dynamic icon
                            .font(.caption)
                            .foregroundColor(.red) // Always red
                            .padding(8)
                            .contentShape(Rectangle()) // Make tap area larger
                    }
                    .buttonStyle(.plain) // Prevent NavigationLink trigger
                    .disabled(isReported)
                }
            }
            
            // Media
            if let videoStr = post.videoURL, let url = URL(string: videoStr) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                AsyncImage(url: URL(string: post.imageName)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { BrandColors.lightGray }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            // Caption
            Text(post.caption)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(BrandColors.darkGray)
                .lineLimit(2)

            // --- ✅ MODIFIED: Interactions are now buttons ---
            HStack(spacing: 16) {
                // --- LIKE BUTTON ---
                Button {
                    Task { await viewModel.toggleLike(post: post) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: post.isLikedByUser ? "heart.fill" : "heart")
                        Text("\(post.likeCount)")
                    }
                    .foregroundColor(post.isLikedByUser ? .red : BrandColors.darkGray)
                }
                .buttonStyle(.plain) // IMPORTANT: Prevents triggering the NavigationLink

                // --- COMMENT BUTTON ---
                Button {
                    onCommentTapped()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "message")
                        Text("\(post.commentCount)")
                    }
                    .foregroundColor(BrandColors.darkGray)
                }
                .buttonStyle(.plain) // IMPORTANT
            }
            .font(.system(size: 14, design: .rounded))
            // --- END MODIFICATION ---
        }
        .padding()
        .background(Color.white) // لا مواد ولا تعتيم
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        .opacity(1)
    }

    @ViewBuilder
    private var profileImage: some View {
        if let image = authorProfile.profileImage {
            Image(uiImage: image)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .foregroundColor(BrandColors.lightGray)
        }
    }
}

// MARK: - Filters Sheet
struct FiltersSheetView: View {
    @Binding var position: String?
    @Binding var ageMin: Int?
    @Binding var ageMax: Int?
    @Binding var scoreMin: Int?
    @Binding var scoreMax: Int?
    @Binding var team: String?
    @Binding var location: String?

    let positions = ["Attacker", "Midfielder", "Defender"]
    let teams = ["Unassigned"]
    let locations = SAUDI_CITIES

    @Environment(\.dismiss) private var dismiss
    
    @State private var showScoreInfo = false
    @State private var showLocationInfo = false
    
    // --- NEW: State for string text field values ---
    @State private var ageMinString: String = ""
    @State private var ageMaxString: String = ""
    @State private var scoreMinString: String = ""
    @State private var scoreMaxString: String = ""
    
    // --- NEW: State for number validation ---
    @State private var ageMinNotNumber: Bool = false
    @State private var ageMaxNotNumber: Bool = false
    @State private var scoreMinNotNumber: Bool = false
    @State private var scoreMaxNotNumber: Bool = false

    // Check if Age min/max are within the 0-100 range
    private var ageValuesInvalid: Bool {
        if let min = ageMin, (min < 0 || min > 100) {
            return true // Min age must be 0-100
        }
        if let max = ageMax, (max < 0 || max > 100) {
            return true // Max age must be 0-100
        }
        return false
    }

    // Check if Age min is greater than max
    private var ageRangeInvalid: Bool {
        if let min = ageMin, let max = ageMax {
            return min > max // Min must be <= Max
        }
        return false
    }
    
    // --- MODIFIED: Added NotNumber checks ---
    private var isAgeSectionValid: Bool {
        !ageValuesInvalid && !ageRangeInvalid && !ageMinNotNumber && !ageMaxNotNumber
    }
    
    // Check if Score min/max are within the 0-100 range
    private var scoreValuesInvalid: Bool {
        if let min = scoreMin, (min < 0 || min > 100) {
            return true // Min score must be 0-100
        }
        if let max = scoreMax, (max < 0 || max > 100) {
            return true // Max score must be 0-100
        }
        return false
    }
    
    // Check if Score min is greater than max
    private var scoreRangeInvalid: Bool {
        if let min = scoreMin, let max = scoreMax {
            return min > max // Min must be <= Max
        }
        return false
    }

    // --- MODIFIED: Added NotNumber checks ---
    private var isScoreSectionValid: Bool {
        !scoreValuesInvalid && !scoreRangeInvalid && !scoreMinNotNumber && !scoreMaxNotNumber
    }
    
    private var isFormValid: Bool {
        isAgeSectionValid && isScoreSectionValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Position") {
                    Picker("Position", selection: $position) {
                        Text("Any").tag(String?.none)
                        ForEach(positions, id: \.self) { pos in
                            Text(pos).tag(String?.some(pos))
                        }
                    }
                }
                Section("Age Range") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Min", text: $ageMinString)
                                .keyboardType(.numberPad)
                                .tint(BrandColors.darkTeal)
                                .onChange(of: ageMinString) { newValue in
                                    if newValue.isEmpty {
                                        ageMinNotNumber = false
                                        ageMin = nil
                                    } else if let number = Int(newValue) {
                                        ageMinNotNumber = false
                                        ageMin = number
                                    } else {
                                        ageMinNotNumber = true
                                        ageMin = nil // Set to nil to trigger other validations
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
                        
                        // Show other errors only if number format is valid
                        if !ageMinNotNumber && !ageMaxNotNumber && !isAgeSectionValid {
                            if ageValuesInvalid {
                                Text("Age values must be between 0 and 100.")
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
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            // --- MODIFIED: Use text binding and .onChange ---
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
                            // --- MODIFIED: Use text binding and .onChange ---
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

                        // Show other errors only if number format is valid
                        if !scoreMinNotNumber && !scoreMaxNotNumber && !isScoreSectionValid {
                            if scoreValuesInvalid {
                                Text("Score values must be between 0 and 100.")
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
                Section("Current Team") {
                    Picker("Team", selection: $team) {
                        Text("Any").tag(String?.none)
                        ForEach(teams, id: \.self) { t in Text(t).tag(String?.some(t)) }
                    }
                }
                Section {
                    Picker("Location", selection: $location) {
                        Text("Any").tag(String?.none)
                        ForEach(locations, id: \.self) { loc in Text(loc).tag(String?.some(loc)) }
                    }
                } header: {
                    HStack {
                        Text("Location")
                        Button {
                            showLocationInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(BrandColors.darkTeal)
                        }
                    }
                }
                Section {
                    Button("Apply Filters") { dismiss() }
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(BrandColors.darkTeal)
                        .frame(maxWidth: .infinity)
                        .disabled(!isFormValid)
                        .opacity(isFormValid ? 1.0 : 0.5)
                    
                    Button("Reset All", role: .destructive) {
                        position = nil; ageMin = nil; ageMax = nil
                        scoreMin = nil; scoreMax = nil
                        team = nil; location = nil
                        // --- NEW: Also reset string fields ---
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
                .font(.system(size: 13, design: .monospaced)) // Monospaced for table
                .multilineTextAlignment(.leading)   // Aligned left
                .foregroundColor(.secondary)
                .padding(.horizontal, 12) // Give text a bit more room
            }
            .alert("Location", isPresented: $showLocationInfo) {
                Button("Got it!") { }
            } message: {
                Text("The player's place of residence.")
            }
            .onAppear {
                ageMinString = ageMin.map { String($0) } ?? ""
                ageMaxString = ageMax.map { String($0) } ?? ""
                scoreMinString = scoreMin.map { String($0) } ?? ""
                scoreMaxString = scoreMax.map { String($0) } ?? ""
            }
        }
    }
}
