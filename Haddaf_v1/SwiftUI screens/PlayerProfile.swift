//
//  PlayerProfile.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 06/10/2025.
//

import SwiftUI
import Combine
import PhotosUI

// MARK: - Shared Data Model
class UserProfile: ObservableObject {
    @Published var name = "SALEM AL-DAWSARI"
    @Published var position = "Forwards"
    @Published var age = "34"
    @Published var weight = "71kg"
    @Published var height = "172cm"
    @Published var team = "AlHilal"
    @Published var rank = "1"
    @Published var score = "100"
    @Published var location = "Riyadh"
    @Published var email = "salem.d@example.com"
    @Published var phoneNumber = "+966 55 123 4567"
    @Published var isEmailVisible = true
    @Published var isPhoneVisible = false
    @Published var profileImage: UIImage? = UIImage(named: "salem_al-dawsari")
}

// MARK: - Main Container View
struct PlayerProfile: View {
    @State private var selectedTab: Tab = .profile
    @State private var showVideoUpload = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack {
                switch selectedTab {
                case .discovery: DiscoveryView()
                case .teams: TeamsView()
                case .challenge: ChallengeView()
                case .profile: PlayerProfileContentView()
                default: DiscoveryView()
                }
            }
            CustomTabBar(selectedTab: $selectedTab, showVideoUpload: $showVideoUpload)
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .sheet(isPresented: $showVideoUpload) {
            VideoUploadView()
        }
    }
}

// MARK: - Profile Page View
struct PlayerProfileContentView: View {
    @StateObject private var userProfile = UserProfile()
    @State private var selectedContent: ContentType = .posts
    
    private let postColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    @State private var posts: [Post] = [
        Post(
            imageName: "post_placeholder1", caption: "Cool dribble right :)", timestamp: "1 hour ago", isPrivate: true,
            authorName: "SALEM AL-DAWSARI", authorImageName: "salem_al-dawsari",
            likeCount: 200, isLikedByUser: true,
            comments: [
                .init(username: "Jakob Septimus", userImage: "p1", text: "This is it! Arsenal must stay focused to claim the Premier League title after so many years", timestamp: "30 min ago"),
                .init(username: "Jaxson Torff", userImage: "p2", text: "Newcastle has been impressive, and I believe they can give Arsenal a tough fight for the title!", timestamp: "30 min ago")
            ],
            stats: [
                .init(label: "GOALS", value: 2, maxValue: 10),
                .init(label: "TOTAL ATTEMPTS", value: 9, maxValue: 15),
                .init(label: "BLOCKED", value: 3, maxValue: 5),
                .init(label: "SHOTS ON TARGET", value: 12, maxValue: 20),
                .init(label: "CORNERS", value: 9, maxValue: 10),
                .init(label: "OFFSIDES", value: 4, maxValue: 5)
            ]
        ),
        Post(
            imageName: "post_placeholder2", caption: "Great team win today!", timestamp: "3 hours ago", isPrivate: false,
            authorName: "SALEM AL-DAWSARI", authorImageName: "salem_al-dawsari",
            likeCount: 300, isLikedByUser: false,
            comments: [
                .init(username: "Kaylynn Dokidis", userImage: "p3", text: "A thrilling end to the season! Both teams will fight hard for glory. May the best win!", timestamp: "30 min ago"),
                .init(username: "Jordyn Torff", userImage: "p4", text: "Arsenal can't afford to underestimate Newcastle. It'll be a tense battle to decide the champion!", timestamp: "30 min ago")
            ],
            stats: [
                .init(label: "GOALS", value: 2, maxValue: 10),
                .init(label: "TOTAL ATTEMPTS", value: 9, maxValue: 15),
                .init(label: "BLOCKED", value: 3, maxValue: 5),
                .init(label: "SHOTS ON TARGET", value: 12, maxValue: 20),
                .init(label: "CORNERS", value: 9, maxValue: 10),
                .init(label: "OFFSIDES", value: 4, maxValue: 5)
            ]
        )
    ]

    var body: some View {
        NavigationStack {
            Color.white.ignoresSafeArea()
                .overlay(
                    ScrollView {
                        VStack(spacing: 24) {
                            TopNavigationBar(userProfile: userProfile)
                            ProfileHeader(userProfile: userProfile)
                            StatsGridView(userProfile: userProfile)
                            ContentTabView(selectedContent: $selectedContent)
                            
                            if selectedContent == .posts {
                                LazyVGrid(columns: postColumns, spacing: 12) {
                                    ForEach($posts) { $post in
                                        NavigationLink(destination: PostDetailView(post: $post)) {
                                            Image(post.imageName)
                                                .resizable().aspectRatio(1, contentMode: .fill)
                                                .frame(minWidth: 0, maxWidth: .infinity).clipped()
                                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                                .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.05)))
                                        }
                                    }
                                }
                            } else {
                                VStack {
                                    Text("Progress Content Here")
                                        .font(.title2).foregroundColor(.secondary).padding(.top, 40)
                                    Spacer()
                                }.frame(minHeight: 300)
                            }
                        }
                        .padding().padding(.bottom, 100)
                    }
                )
        }
    }
}

// MARK: - Edit Profile View
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var userProfile: UserProfile
    @State private var selectedPhotoItem: PhotosPickerItem?
    private let primary = Color(hex: "#36796C")

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    profilePictureSection
                    Divider().padding(.horizontal)
                    formFields
                    togglesSection
                    Spacer(minLength: 20)
                    updateButton
                        .padding(.horizontal)
                        .padding(.bottom, 77)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    DispatchQueue.main.async {
                        userProfile.profileImage = UIImage(data: data)
                    }
                }
            }
        }
    }

    private var header: some View {
        ZStack {
            Text("Edit Profile").font(.custom("Poppins", size: 28)).fontWeight(.medium).foregroundColor(primary)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(primary)
                        .padding(10).background(Circle().fill(Color.black.opacity(0.05)))
                }
                Spacer()
            }
        }.padding([.horizontal, .top])
    }
    
    private var profilePictureSection: some View {
        VStack {
            Image(uiImage: userProfile.profileImage ?? UIImage(systemName: "person.circle.fill")!)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100).clipShape(Circle())
                .foregroundColor(.gray.opacity(0.5))

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Text("Change Picture").font(.custom("Poppins", size: 16)).fontWeight(.semibold).foregroundColor(primary)
            }.padding(.top, 4)
        }.frame(maxWidth: .infinity)
    }
    
    private var formFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            field(label: "Name", text: $userProfile.name)
            field(label: "Position", text: $userProfile.position)
            field(label: "Weight", text: $userProfile.weight)
            field(label: "Height", text: $userProfile.height)
            field(label: "Location", text: $userProfile.location)
            field(label: "Email", text: $userProfile.email, keyboardType: .emailAddress)
            field(label: "Phone number", text: $userProfile.phoneNumber, keyboardType: .phonePad)
        }.padding(.horizontal)
    }
    
    private var togglesSection: some View {
        VStack(spacing: 16) {
            toggleRow(title: "Make my email visible", isOn: $userProfile.isEmailVisible)
            toggleRow(title: "Make my phone number visible", isOn: $userProfile.isPhoneVisible)
        }.padding(.horizontal).padding(.top, 10)
    }
    
    private var updateButton: some View {
        Button { dismiss() } label: {
            Text("Update").font(.custom("Poppins", size: 18)).foregroundColor(.white).frame(maxWidth: .infinity)
                .padding(.vertical, 16).background(primary).clipShape(Capsule())
        }
    }
    
    private func field(label: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading) {
            fieldLabel(label)
            roundedField {
                TextField("", text: text).font(.custom("Poppins", size: 16)).foregroundColor(primary).tint(primary).keyboardType(keyboardType)
            }
        }
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.custom("Poppins", size: 16)).foregroundColor(.black)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(primary)
        }
    }
    
    private func fieldLabel(_ title: String) -> some View {
        Text(title).font(.custom("Poppins", size: 14)).foregroundColor(.gray)
    }

    private func roundedField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.2), lineWidth: 1)))
    }
}

// MARK: - Profile Page Subviews
struct TopNavigationBar: View {
    @ObservedObject var userProfile: UserProfile
    var body: some View {
        HStack {
            NavigationLink(destination: SettingsView()) { Image(systemName: "gearshape") }
            Spacer()
            NavigationLink(destination: EditProfileView(userProfile: userProfile)) { Image(systemName: "square.and.pencil") }
        }.font(.title2).foregroundColor(.primary).padding(.top, -15)
    }
}
struct ProfileHeader: View {
    @ObservedObject var userProfile: UserProfile
    var body: some View {
        VStack(spacing: 12) {
            Image(uiImage: userProfile.profileImage ?? UIImage(systemName: "person.circle.fill")!)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100).clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 4)).shadow(radius: 5)
                .foregroundColor(.gray.opacity(0.5))
            Text(userProfile.name).font(.title2).fontWeight(.bold).foregroundColor(Color(hex: "#36796C"))
        }
    }
}
struct StatsGridView: View {
    @ObservedObject var userProfile: UserProfile
    private var stats: [PlayerStat] {
        [.init(title: "Position", value: userProfile.position), .init(title: "Age", value: userProfile.age), .init(title: "Weight", value: userProfile.weight), .init(title: "Hight", value: userProfile.height), .init(title: "Team", value: userProfile.team), .init(title: "Rank", value: userProfile.rank), .init(title: "Score", value: userProfile.score), .init(title: "Location", value: userProfile.location)]
    }
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
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

// MARK: - Post Detail View & Comment System
struct PostDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var post: Post
    @State private var showPrivacyAlert = false
    @State private var showCommentsSheet = false
    let accentColor = Color(hex: "#36796C")

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    VideoPlayerPlaceholderView(post: post)
                    captionAndMetadata
                    authorInfoAndInteractions
                    Divider()
                    statsSection
                }.padding(.horizontal)
            }.navigationBarBackButtonHidden(true)
            
            if showPrivacyAlert {
                PrivacyWarningPopupView(isPresented: $showPrivacyAlert, isPrivate: post.isPrivate, onConfirm: { post.isPrivate.toggle() })
            }
        }
        .sheet(isPresented: $showCommentsSheet) { CommentsView(post: $post) }
        .onChange(of: showPrivacyAlert) { _,_ in withAnimation(.easeInOut) {} }
    }

    private var header: some View {
        ZStack {
            Text("Post").font(.custom("Poppins", size: 28)).fontWeight(.medium).foregroundColor(accentColor)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(accentColor)
                        .padding(10).background(Circle().fill(Color.black.opacity(0.05)))
                }
                Spacer()
            }
        }.padding(.bottom, 8)
    }
    private var captionAndMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.caption).font(.headline)
            HStack(spacing: 8) {
                Text(post.timestamp)
                Spacer()
                Button(action: { showPrivacyAlert = true }) {
                    Image(systemName: post.isPrivate ? "lock.fill" : "lock.open.fill")
                        .foregroundColor(post.isPrivate ? .red : accentColor)
                }
            }.font(.caption).foregroundColor(.secondary)
        }
    }
    private var authorInfoAndInteractions: some View {
        HStack {
            Image(post.authorImageName).resizable().aspectRatio(contentMode: .fill).frame(width: 40, height: 40).clipShape(Circle())
            Text(post.authorName).font(.headline).fontWeight(.bold)
            Spacer()
            Button(action: {
                post.isLikedByUser.toggle()
                if post.isLikedByUser { post.likeCount += 1 } else { post.likeCount -= 1 }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: post.isLikedByUser ? "heart.fill" : "heart")
                    Text(formatNumber(post.likeCount))
                }.foregroundColor(post.isLikedByUser ? .red : .primary)
            }
            Button(action: { showCommentsSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "message")
                    Text("\(post.comments.count)")
                }
            }
        }.font(.subheadline).foregroundColor(.primary)
    }
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(post.stats) { stat in PostStatBarView(stat: stat, accentColor: accentColor) }
        }
    }
    private func formatNumber(_ number: Int) -> String {
        if number >= 1000 {
            let num = Double(number) / 1000.0
            return String(format: "%.1fK", num)
        } else {
            return "\(number)"
        }
    }
}
struct CommentsView: View {
    @Binding var post: Post
    @Environment(\.dismiss) var dismiss
    @State private var newCommentText = ""
    private let accentColor = Color(hex: "#36796C")

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Comment").font(.headline).padding()
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.subheadline.bold()) }
            }.padding().overlay(Divider(), alignment: .bottom)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(post.comments) { comment in CommentRowView(comment: comment) }
                }.padding()
            }
            HStack(spacing: 12) {
                TextField("Write Comment...", text: $newCommentText)
                    .padding(.horizontal).padding(.vertical, 10)
                    .background(Color(.systemGray6)).clipShape(Capsule())
                Button(action: addComment) {
                    Image(systemName: "paperplane.fill").font(.title2).foregroundColor(accentColor)
                }.disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding().background(.white)
        }
    }
    func addComment() {
        guard !newCommentText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let newComment = Comment(username: "SALEM AL-DAWSARI", userImage: "salem_al-dawsari", text: newCommentText, timestamp: "Just now")
        post.comments.append(newComment)
        newCommentText = ""
    }
}
struct CommentRowView: View {
    let comment: Comment
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(comment.userImage).resizable().aspectRatio(contentMode: .fill).frame(width: 40, height: 40).clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(comment.username).fontWeight(.semibold)
                    Text(comment.timestamp).font(.caption).foregroundColor(.secondary)
                }
                Text(comment.text)
            }
        }
    }
}
struct PrivacyWarningPopupView: View {
    @Binding var isPresented: Bool
    let isPrivate: Bool
    let onConfirm: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { withAnimation { isPresented = false } }.transition(.opacity)
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    VStack(spacing: 20) {
                        Text("Change Visibility?").font(.title3).fontWeight(.semibold)
                        Text(isPrivate ? "Making this post public will allow everyone to see it." : "Making this post private will hide it from other users.").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                        HStack(spacing: 24) {
                            Button("Cancel") { withAnimation { isPresented = false } }.font(.system(size: 18, weight: .semibold)).foregroundColor(.black).frame(width: 120, height: 44).background(Color.gray.opacity(0.15)).cornerRadius(10)
                            Button("Confirm") { withAnimation { onConfirm(); isPresented = false } }.font(.system(size: 18, weight: .semibold)).foregroundColor(.red).frame(width: 120, height: 44).background(Color.gray.opacity(0.15)).cornerRadius(10)
                        }.padding(.top, 4)
                    }.padding().frame(width: 320).background(Color.white).cornerRadius(20).shadow(radius: 12).transition(.scale)
                    Spacer()
                }.frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }
}
struct VideoPlayerPlaceholderView: View {
    let post: Post
    var body: some View {
        ZStack {
            Image(post.imageName).resizable().aspectRatio(contentMode: .fit).frame(height: 250).background(Color.black).clipped()
            Color.black.opacity(0.3)
            VStack {
                Spacer()
                HStack(spacing: 40) {
                    Image(systemName: "backward.fill")
                    Image(systemName: "play.fill").font(.system(size: 40))
                    Image(systemName: "forward.fill")
                }
                Spacer()
                HStack {
                    Text("3:21")
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }.padding(12).background(.black.opacity(0.4))
            }.font(.callout).foregroundColor(.white)
        }.frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
struct PostStatBarView: View {
    let stat: PostStat
    let accentColor: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stat.label).font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("\(stat.value)").font(.caption).fontWeight(.bold)
            }
            ProgressView(value: Double(stat.value), total: Double(stat.maxValue)).tint(accentColor)
        }
    }
}

// MARK: - Reusable Views
struct ContentTabView: View {
    @Binding var selectedContent: ContentType
    @Namespace private var animation
    let accentColor = Color(hex: "#36796C")
    var body: some View {
        HStack(spacing: 40) {
            ContentTabButton(title: "My posts", type: .posts, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
            ContentTabButton(title: "My progress", type: .progress, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
        }.font(.headline).fontWeight(.medium)
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
                Text(title).foregroundColor(selectedContent == type ? accentColor : .secondary)
                if selectedContent == type {
                    Rectangle().frame(height: 2).foregroundColor(accentColor).matchedGeometryEffect(id: "underline", in: animation)
                } else {
                    Color.clear.frame(height: 2)
                }
            }
        }.frame(maxWidth: .infinity)
    }
}
struct DiscoveryView: View {
    var body: some View { ZStack { Color.white.ignoresSafeArea(); Text("Discovery Page").font(.largeTitle).foregroundColor(.secondary) } }
}
struct TeamsView: View {
    var body: some View { ZStack { Color.white.ignoresSafeArea(); Text("Teams Page").font(.largeTitle).foregroundColor(.secondary) } }
}
struct ChallengeView: View {
    var body: some View { ZStack { Color.white.ignoresSafeArea(); Text("Challenge Page").font(.largeTitle).foregroundColor(.secondary) } }
}
struct VideoUploadView: View {
    var body: some View { ZStack { Color.white.ignoresSafeArea(); Text("Video Upload Page").font(.largeTitle) } }
}
struct CustomTabBar: View {
    @Binding var selectedTab: Tab
    @Binding var showVideoUpload: Bool
    let accentColor = Color(hex: "#36796C")
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Divider()
                Color.white.frame(height: 85).shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: -5)
            }
            HStack {
                TabButton(tab: .discovery, selectedTab: $selectedTab, accentColor: accentColor)
                TabButton(tab: .teams, selectedTab: $selectedTab, accentColor: accentColor)
                Spacer().frame(width: 80)
                TabButton(tab: .challenge, selectedTab: $selectedTab, accentColor: accentColor)
                TabButton(tab: .profile, selectedTab: $selectedTab, accentColor: accentColor)
            }.padding(.horizontal, 30).frame(height: 80).padding(.top, 5)
            Button(action: { showVideoUpload = true }) {
                ZStack {
                    Circle().fill(Color.white).frame(width: 68, height: 68).shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 5)
                    Image("Haddaf_logo").resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 70)
                }
            }.offset(y: -30)
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
                Image(systemName: tab.imageName).font(.title2)
                Text(tab.title).font(.caption)
            }.foregroundColor(selectedTab == tab ? accentColor : .black.opacity(0.7)).frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Models, Enums, and Helpers
struct PlayerStat: Identifiable { let id = UUID(); let title: String; let value: String }
struct PostStat: Identifiable { let id = UUID(); let label: String; let value: Int; let maxValue: Int }
struct Comment: Identifiable { let id = UUID(); let username: String; let userImage: String; let text: String; let timestamp: String }
struct Post: Identifiable { var id = UUID(); var imageName: String; var caption: String = "Default"; var timestamp: String = "Just now"; var isPrivate: Bool; var authorName: String = "Default"; var authorImageName: String = "Default"; var likeCount: Int = 0; var isLikedByUser: Bool = false; var comments: [Comment] = []; var stats: [PostStat] = [] }
enum ContentType { case posts, progress }
enum Tab {
    case discovery, teams, action, challenge, profile
    var imageName: String {
        switch self {
        case .discovery: return "house"; case .teams: return "person.3"; case .action: return ""; case .challenge: return "chart.bar"; case .profile: return "person"
        }
    }
    var title: String {
        switch self {
        case .discovery: return "Discovery"; case .teams: return "Teams"; case .action: return ""; case .challenge: return "Challenge"; case .profile: return "Profile"
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

#if DEBUG
struct PlayerProfile_Previews: PreviewProvider {
    static var previews: some View {
        PlayerProfile()
    }
}
#endif
