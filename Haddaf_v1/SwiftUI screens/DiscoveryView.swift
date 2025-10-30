//
//  DiscoveryView.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 30/10/2025.
//
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AVKit

// MARK: - Discovery View
struct DiscoveryView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    
    @State private var searchText = "" // Search by player name
    
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
            // Search by author name
            let nameMatch = searchText.isEmpty || post.authorName.localizedCaseInsensitiveContains(searchText)
            
            guard let authorUid = post.authorUid,
                  let profile = viewModel.authorProfiles[authorUid] else {
                return nameMatch
            }
            
            // Position filter
            let positionMatch = filterPosition == nil || profile.position == filterPosition
            
            // Age filter (age is string, convert to Int)
            let age = Int(profile.age) ?? 0
            let ageMatch = (filterAgeMin == nil || age >= filterAgeMin!) &&
                           (filterAgeMax == nil || age <= filterAgeMax!)
            
            // Score filter
            let score = Int(profile.score) ?? 0
            let scoreMatch = (filterScoreMin == nil || score >= filterScoreMin!) &&
                             (filterScoreMax == nil || score <= filterScoreMax!)
            
            // Team filter (assuming profile.team)
            let teamMatch = filterTeam == nil || profile.team == filterTeam
            
            // Location filter
            let locationMatch = filterLocation == nil || profile.location == filterLocation
            
            return nameMatch && positionMatch && ageMatch && scoreMatch && teamMatch && locationMatch
        }
    }
    
    private var isFiltering: Bool {
        !searchText.isEmpty ||
        filterPosition != nil ||
        filterAgeMin != nil ||
        filterAgeMax != nil ||
        filterScoreMin != nil ||
        filterScoreMax != nil ||
        filterTeam != nil ||
        filterLocation != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.gradientBackground.ignoresSafeArea()
                
                // --- 1. LOADING CHECK ---
                // This is the ONLY thing that shows during the initial load
                if viewModel.isLoadingPosts {
                    ProgressView().tint(BrandColors.darkTeal)
                } else {
                    // --- 2. CONTENT VIEW ---
                    VStack(spacing: 0) {
                        Text("Discovery")
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .foregroundColor(BrandColors.darkTeal)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 8)
                        
                        // Search and Filters
                        HStack(spacing: 12) {
                            // Search Bar
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
                            
                            // Filters Button
                            Button {
                                showFiltersSheet = true
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(BrandColors.darkTeal)
                            }
                        }
                        .padding()
                        
                        // --- 3. ⭐️ FIXED EMPTY/RESULTS LOGIC ⭐️ ---
                        if filteredPosts.isEmpty && isFiltering {
                            // CASE A: We are filtering, but have no results
                            EmptyStateView(
                                image: "doc.text.magnifyingglass",
                                title: "No Matching Results",
                                message: "Try adjusting your search or filter settings."
                            )
                        } else {
                            // CASE B: We are NOT filtering (show all posts)
                            // OR we ARE filtering and HAVE results.
                            // If viewModel.posts is empty, this just shows an empty list,
                            // which is the correct behavior (no "No Posts Yet" message).
                            ScrollView {
                                LazyVStack(spacing: 16) {
                                    ForEach(filteredPosts) { post in
                                        NavigationLink(destination: PostDetailView(post: post)) {
                                            let authorProfile = post.authorUid.flatMap { viewModel.authorProfiles[$0] } ?? UserProfile()
                                            DiscoveryPostCardView(post: post, authorProfile: authorProfile)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding()
                                .padding(.bottom, 80) // Padding for tab bar
                            }
                        }
                        // --- END FIX ---
                    }
                }
            }
            .sheet(isPresented: $showFiltersSheet) {
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
    
    // --- Helper View for Empty States ---
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
            Spacer()
            Spacer()
        }
        .padding()
    }
}

// MARK: - Discovery Post Card View
struct DiscoveryPostCardView: View {
    let post: Post
    let authorProfile: UserProfile
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author Info
            HStack(spacing: 12) {
                if let image = authorProfile.profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .foregroundColor(BrandColors.lightGray)
                }
                
                VStack(alignment: .leading) {
                    Text(post.authorName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(post.timestamp)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            
            // Video Placeholder
            if let videoStr = post.videoURL, let url = URL(string: videoStr) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                AsyncImage(url: URL(string: post.imageName)) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    BrandColors.lightGray
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            
            // Caption
            Text(post.caption)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(BrandColors.darkGray)
                .lineLimit(2) // Keep card compact
            
            // Stats
            if let stats = post.stats, !stats.isEmpty {
                VStack(spacing: 8) {
                    ForEach(stats) { stat in
                        PostStatBarView(stat: stat, accentColor: BrandColors.darkTeal)
                    }
                }
            }
            
            // Interactions
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "heart")
                    Text("\(post.likeCount)")
                }
                .foregroundColor(BrandColors.darkGray)
                
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                    Text("\(post.commentCount)")
                }
                .foregroundColor(BrandColors.darkGray)
            }
            .font(.system(size: 14, design: .rounded))
        }
        .padding()
        .background(BrandColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }
}

// MARK: - Filters Sheet View
struct FiltersSheetView: View {
    @Binding var position: String?
    @Binding var ageMin: Int?
    @Binding var ageMax: Int?
    @Binding var scoreMin: Int?
    @Binding var scoreMax: Int?
    @Binding var team: String?
    @Binding var location: String?
    
    let positions = ["Attacker", "Midfielder", "Defender"]
    let teams = ["Unassigned", "Team A", "Team B"] // Placeholder
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
                        TextField("Min", value: $ageMin, format: .number)
                            .keyboardType(.numberPad)
                            .tint(BrandColors.darkTeal)
                        Text("-")
                        TextField("Max", value: $ageMax, format: .number)
                            .keyboardType(.numberPad)
                            .tint(BrandColors.darkTeal)
                    }
                }
                
                Section("Score Range") {
                    HStack {
                        TextField("Min", value: $scoreMin, format: .number)
                            .keyboardType(.numberPad)
                            .tint(BrandColors.darkTeal)
                        Text("-")
                        TextField("Max", value: $scoreMax, format: .number)
                            .keyboardType(.numberPad)
                            .tint(BrandColors.darkTeal)
                    }
                }
                
                Section("Current Team") {
                    Picker("Team", selection: $team) {
                        Text("Any").tag(String?.none)
                        ForEach(teams, id: \.self) { t in
                            Text(t).tag(String?.some(t))
                        }
                    }
                }
                
                Section("Location") {
                    Picker("Location", selection: $location) {
                        Text("Any").tag(String?.none)
                        ForEach(locations, id: \.self) { loc in
                            Text(loc).tag(String?.some(loc))
                        }
                    }
                }
                
                Section {
                    Button("Apply Filters") {
                        dismiss()
                    }
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(BrandColors.darkTeal)
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    Button("Reset All", role: .destructive) {
                        position = nil
                        ageMin = nil
                        ageMax = nil
                        scoreMin = nil
                        scoreMax = nil
                        team = nil
                        location = nil
                    }
                    .font(.system(size: 17, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
