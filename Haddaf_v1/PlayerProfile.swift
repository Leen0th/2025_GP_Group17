//
//  MainView.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 06/10/2025.
//

import SwiftUI

// MARK: - Main Container View
struct PlayerProfile: View {
    // This state controls which page is visible.
    @State private var selectedTab: Tab = .profile
    // This state controls the presentation of the video upload sheet.
    @State private var showVideoUpload = false

    var body: some View {
        ZStack(alignment: .bottom) {
            
            // The main content area switches between different views based on the selected tab
            VStack {
                switch selectedTab {
                case .discovery:
                    DiscoveryView()
                case .teams:
                    TeamsView()
                case .challenge:
                    ChallengeView()
                case .profile:
                    PlayerProfileContentView()
                default:
                    DiscoveryView()
                }
            }
            
            // footer sits on top of the content
            CustomTabBar(selectedTab: $selectedTab, showVideoUpload: $showVideoUpload)
        }
        .ignoresSafeArea(.all, edges: .bottom)
        // The sheet for uploading a video is presented here
        .sheet(isPresented: $showVideoUpload) {
            VideoUploadView()
        }
    }
}

// MARK: - Profile Page Views

// This view contains all the original content for the profile page.
struct PlayerProfileContentView: View {
    @State private var selectedContent: ContentType = .posts

    // Mock data
    private let stats: [PlayerStat] = [
        .init(title: "Position", value: "Forwards"),
        .init(title: "Age", value: "34"),
        .init(title: "Weight", value: "71kg"),
        .init(title: "Hight", value: "172m"),
        .init(title: "Team", value: "AlHilal"),
        .init(title: "Rank", value: "1"),
        .init(title: "Score", value: "100"),
        .init(title: "Location", value: "Riyadh")
    ]
    
    private let postColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    // Mock data
    private let posts: [Post] = (0..<9).map { _ in Post(imageName: "post_image_placeholder") }


    var body: some View {
        // navigation to other pages
        NavigationStack {
            Color.white
                .ignoresSafeArea()
                .overlay(
                    ScrollView {
                        VStack(spacing: 24) {
                            TopNavigationBar()
                            ProfileHeader()
                            StatsGridView(stats: stats)
                            ContentTabView(selectedContent: $selectedContent)
                            
                            if selectedContent == .posts {
                                LazyVGrid(columns: postColumns, spacing: 12) {
                                    ForEach(posts) { post in
                                        // Each post is a navigation link to the detail view
                                        NavigationLink(destination: PostDetailView(post: post)) {
                                            Image(post.imageName)
                                                .resizable()
                                                .aspectRatio(1, contentMode: .fill)
                                                .frame(minWidth: 0, maxWidth: .infinity)
                                                .clipped()
                                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                                .background(
                                                    RoundedRectangle(cornerRadius: 16)
                                                        .fill(Color.black.opacity(0.05))
                                                )
                                        }
                                    }
                                }
                            } else {
                                VStack {
                                    Text("Progress Content Here")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 40)
                                    Spacer()
                                }
                                .frame(minHeight: 300)
                            }
                        }
                        .padding()
                        .padding(.bottom, 100)
                    }
                )
        }
    }
}

// Placeholder view for Discovery Tab
struct DiscoveryView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Discovery Page")
                .font(.largeTitle)
                .foregroundColor(.secondary)
        }
    }
}

// Placeholder view for Teams Tab
struct TeamsView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Teams Page")
                .font(.largeTitle)
                .foregroundColor(.secondary)
        }
    }
}

// Placeholder view for Challenge Tab
struct ChallengeView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Challenge Page")
                .font(.largeTitle)
                .foregroundColor(.secondary)
        }
    }
}

// Placeholder pages for Settings
struct SettingsView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Settings Page")
                .navigationTitle("Settings")
        }
    }
}

// Placeholder pages for Edit Profile
struct EditProfileView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Edit Profile Page")
                .navigationTitle("Edit Profile")
        }
    }
}

// Placeholder pages for Video Upload
struct VideoUploadView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("Video Upload Page")
                .font(.largeTitle)
        }
    }
}

// Placeholder pages for Post Details
struct PostDetailView: View {
    let post: Post
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack {
                Image(post.imageName)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding()
                
                Text("This is the detail view for a post.")
                    .font(.headline)
                
                Spacer()
            }
            .navigationTitle("Post")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


// MARK: - Header (settings + edit profile)

struct TopNavigationBar: View {
    var body: some View {
        HStack {
            // navigates to the SettingsView
            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape")
            }
            
            Spacer()
            
            // navigates to the EditProfileView
            NavigationLink(destination: EditProfileView()) {
                Image(systemName: "square.and.pencil")
            }
        }
        .font(.title2)
        .foregroundColor(.primary)
        .padding(.top, -15)
    }
}

// profile pic and name
struct ProfileHeader: View {
    var body: some View {
        VStack(spacing: 12) {
            Image("salem_al-dawsari")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 4))
                .shadow(radius: 5)
            
            Text("SALEM AL-DAWSARI")
                .font(.title2)
                .fontWeight(.bold)
        }
    }
}

struct StatsGridView: View {
    let stats: [PlayerStat]
    private let columns = [
        GridItem(.flexible()), GridItem(.flexible()),
        GridItem(.flexible()), GridItem(.flexible())
    ]
    let accentColor = Color(hex: "#36796C")
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(stats) { stat in
                VStack(spacing: 4) {
                    Text(stat.title).font(.caption).foregroundColor(accentColor)
                    Text(stat.value).font(.headline).fontWeight(.semibold)
                }
            }
        }
    }
}

struct ContentTabView: View {
    @Binding var selectedContent: ContentType
    @Namespace private var animation
    let accentColor = Color(hex: "#36796C")
    
    var body: some View {
        HStack(spacing: 40) {
            ContentTabButton(title: "My posts", type: .posts, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
            ContentTabButton(title: "My progress", type: .progress, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
        }
        .font(.headline)
        .fontWeight(.medium)
    }
}

struct ContentTabButton: View {
    let title: String
    let type: ContentType
    @Binding var selectedContent: ContentType
    let accentColor: Color
    let animation: Namespace.ID

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) { selectedContent = type }
        }) {
            VStack(spacing: 8) {
                Text(title)
                    .foregroundColor(selectedContent == type ? accentColor : .secondary)
                
                if selectedContent == type {
                    Rectangle()
                        .frame(height: 2)
                        .foregroundColor(accentColor)
                        .matchedGeometryEffect(id: "underline", in: animation)
                } else {
                    Color.clear.frame(height: 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Bottom Tab Bar
struct CustomTabBar: View {
    @Binding var selectedTab: Tab
    @Binding var showVideoUpload: Bool
    let accentColor = Color(hex: "#36796C")
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Divider()
                Color.white
                    .frame(height: 85)
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: -5)
            }

            HStack {
                TabButton(tab: .discovery, selectedTab: $selectedTab, accentColor: accentColor)
                TabButton(tab: .teams, selectedTab: $selectedTab, accentColor: accentColor)
                Spacer().frame(width: 80)
                TabButton(tab: .challenge, selectedTab: $selectedTab, accentColor: accentColor)
                TabButton(tab: .profile, selectedTab: $selectedTab, accentColor: accentColor)
            }
            .padding(.horizontal, 30)
            .frame(height: 80)
            .padding(.top, 5)
            
            // button that shows the sheet
            Button(action: { showVideoUpload = true }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 68, height: 68)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 5)

                    Image("Haddaf_logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 70)
                }
            }
            .offset(y: -30)
        }
    }
}


struct TabButton: View {
    let tab: Tab
    @Binding var selectedTab: Tab
    let accentColor: Color
    
    var body: some View {
        Button(action: { selectedTab = tab }) {
            VStack(spacing: 4) {
                Image(systemName: tab.imageName)
                    .font(.title2)
                Text(tab.title)
                    .font(.caption)
            }
            .foregroundColor(selectedTab == tab ? accentColor : .black.opacity(0.7))
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Models, Enums, and Helpers
struct PlayerStat: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

// Data model for a post in the grid
struct Post: Identifiable {
    let id = UUID()
    let imageName: String
}


enum ContentType { case posts, progress }

enum Tab {
    case discovery, teams, action, challenge, profile
    
    var imageName: String {
        switch self {
        case .discovery: return "house"
        case .teams: return "person.3"
        case .action: return ""
        case .challenge: return "chart.bar"
        case .profile: return "person"
        }
    }
    
    var title: String {
        switch self {
        case .discovery: return "Discovery"
        case .teams: return "Teams"
        case .action: return ""
        case .challenge: return "Challenge"
        case .profile: return "Profile"
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Preview
struct PlayerProfile_Previews: PreviewProvider {
    static var previews: some View {
        PlayerProfile()
    }
}

