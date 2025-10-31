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
                    Image(systemName: "line.3.horizontal.decrease.circle")
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
                        ForEach(filteredPosts) { post in
                            NavigationLink(destination: PostDetailView(post: post)) {
                                let authorProfile = post.authorUid.flatMap { viewModel.authorProfiles[$0] } ?? UserProfile()
                                DiscoveryPostCardView(post: post, authorProfile: authorProfile)
                            }
                            .buttonStyle(.plain)
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
    let post: Post
    let authorProfile: UserProfile

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
                    Text(post.authorName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(post.timestamp)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
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

            // Interactions
            HStack(spacing: 16) {
                HStack(spacing: 4) { Image(systemName: "heart"); Text("\(post.likeCount)") }
                HStack(spacing: 4) { Image(systemName: "text.bubble"); Text("\(post.commentCount)") }
            }
            .foregroundColor(BrandColors.darkGray)
            .font(.system(size: 14, design: .rounded))
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
                    HStack {
                        TextField("Min", value: $ageMin, format: .number).keyboardType(.numberPad).tint(BrandColors.darkTeal)
                        Text("-")
                        TextField("Max", value: $ageMax, format: .number).keyboardType(.numberPad).tint(BrandColors.darkTeal)
                    }
                }
                Section("Score Range") {
                    HStack {
                        TextField("Min", value: $scoreMin, format: .number).keyboardType(.numberPad).tint(BrandColors.darkTeal)
                        Text("-")
                        TextField("Max", value: $scoreMax, format: .number).keyboardType(.numberPad).tint(BrandColors.darkTeal)
                    }
                }
                Section("Current Team") {
                    Picker("Team", selection: $team) {
                        Text("Any").tag(String?.none)
                        ForEach(teams, id: \.self) { t in Text(t).tag(String?.some(t)) }
                    }
                }
                Section("Location") {
                    Picker("Location", selection: $location) {
                        Text("Any").tag(String?.none)
                        ForEach(locations, id: \.self) { loc in Text(loc).tag(String?.some(loc)) }
                    }
                }
                Section {
                    Button("Apply Filters") { dismiss() }
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(BrandColors.darkTeal)
                        .frame(maxWidth: .infinity)
                    Button("Reset All", role: .destructive) {
                        position = nil; ageMin = nil; ageMax = nil
                        scoreMin = nil; scoreMax = nil
                        team = nil; location = nil
                        dismiss()
                    }
                    .font(.system(size: 17, design: .rounded))
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
