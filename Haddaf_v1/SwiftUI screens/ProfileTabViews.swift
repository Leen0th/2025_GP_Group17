import SwiftUI
import FirebaseFirestore

struct PlayerProfileContentView: View {
    @StateObject private var viewModel = PlayerProfileViewModel()
    @State private var selectedContent: ContentType = .posts

    private let postColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Color.white.ignoresSafeArea()
                .overlay(
                    ScrollView {
                        if viewModel.isLoading {
                            ProgressView().padding(.top, 50)
                        } else {
                            VStack(spacing: 24) {
                                TopNavigationBar(userProfile: viewModel.userProfile)
                                ProfileHeaderView(userProfile: viewModel.userProfile)
                                StatsGridView(userProfile: viewModel.userProfile)
                                ContentTabView(selectedContent: $selectedContent)

                                switch selectedContent {
                                case .posts: postsGrid
                                case .progress: progressView
                                case .endorsements:
                                    EndorsementsListView(endorsements: viewModel.userProfile.endorsements)
                                }
                            }
                            .padding()
                            .padding(.bottom, 100)
                        }
                    }
                )
                .task { await viewModel.fetchAllData() }
                .onReceive(NotificationCenter.default.publisher(for: .postCreated)) { note in
                    if let post = note.userInfo?["post"] as? Post {
                        viewModel.posts.insert(post, at: 0) // newest first
                    }
                }
        }
    }

    private var postsGrid: some View {
        LazyVGrid(columns: postColumns, spacing: 12) {
            ForEach(viewModel.posts) { post in
                NavigationLink(destination: PostDetailView(post: post)) {
                    AsyncImage(url: URL(string: post.imageName)) { image in
                        image.resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.05))
                            .frame(height: 110)
                    }
                }
            }
        }
        .refreshable { await viewModel.fetchAllData() }
    }

    private var progressView: some View {
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

// ===== Helper Views that were missing =====

struct TopNavigationBar: View {
    @ObservedObject var userProfile: UserProfile
    var body: some View {
        HStack {
            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape")
            }
            Spacer()
            NavigationLink(destination: EditProfileView(userProfile: userProfile)) {
                Image(systemName: "square.and.pencil")
            }
        }
        .font(.title2)
        .foregroundColor(.primary)
        .padding(.top, -15)
    }
}

struct ProfileHeaderView: View {
    @ObservedObject var userProfile: UserProfile
    var body: some View {
        VStack(spacing: 12) {
            Image(uiImage: userProfile.profileImage ?? UIImage(systemName: "person.circle.fill")!)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 4))
                .shadow(radius: 5)
                .foregroundColor(.gray.opacity(0.5))
            Text(userProfile.name)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(Color(hex: "#36796C"))
        }
    }
}

struct StatsGridView: View {
    @ObservedObject var userProfile: UserProfile
    @State private var showContactInfo = false

    private var mainStats: [PlayerStat] {
        [
            .init(title: "Position", value: userProfile.position),
            .init(title: "Age", value: userProfile.age),
            .init(title: "Weight", value: userProfile.weight),
            .init(title: "Height", value: userProfile.height),
            .init(title: "Team", value: userProfile.team),
            .init(title: "Rank", value: userProfile.rank),
            .init(title: "Score", value: userProfile.score),
            .init(title: "Location", value: userProfile.location)
        ]
    }

    private var contactStats: [PlayerStat] {
        var s: [PlayerStat] = []
        if userProfile.isEmailVisible {
            s.append(.init(title: "Email", value: userProfile.email))
        }
        if userProfile.isPhoneVisible {
            s.append(.init(title: "Phone", value: userProfile.phoneNumber))
        }
        return s
    }

    private let mainGridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible())
    ]
    private let contactGridColumns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible())
    ]
    let accentColor = Color(hex: "#36796C")

    var body: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: mainGridColumns, spacing: 20) {
                ForEach(mainStats) { stat in
                    statItemView(for: stat, alignment: .center)
                }
            }
            Button(action: { withAnimation(.spring()) { showContactInfo.toggle() } }) {
                HStack(spacing: 4) {
                    Text(showContactInfo ? "Show less" : "Show contact info")
                    Image(systemName: showContactInfo ? "chevron.up" : "chevron.down")
                }
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(accentColor)
                .padding(.top, 8)
            }
            if showContactInfo && !contactStats.isEmpty {
                LazyVGrid(columns: contactGridColumns, spacing: 20) {
                    ForEach(contactStats) { stat in
                        statItemView(for: stat, alignment: .leading)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func statItemView(for stat: PlayerStat, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(stat.title).font(.caption).foregroundColor(accentColor)
            Text(stat.value)
                .font(.headline)
                .fontWeight(.semibold)
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct ContentTabView: View {
    @Binding var selectedContent: ContentType
    @Namespace private var animation
    let accentColor = Color(hex: "#36796C")

    var body: some View {
        HStack(spacing: 12) {
            ContentTabButton(title: "My posts", type: .posts, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
            ContentTabButton(title: "My progress", type: .progress, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
            ContentTabButton(title: "Endorsements", type: .endorsements, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
        }
        .font(.headline)
        .fontWeight(.medium)
    }
}

fileprivate struct ContentTabButton: View {
    let title: String
    let type: ContentType
    @Binding var selectedContent: ContentType
    let accentColor: Color
    let animation: Namespace.ID

    var body: some View {
        Button {
            withAnimation(.easeInOut) { selectedContent = type }
        } label: {
            VStack(spacing: 8) {
                Text(title).foregroundColor(selectedContent == type ? accentColor : .secondary)
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

struct EndorsementsListView: View {
    let endorsements: [CoachEndorsement]
    var body: some View {
        VStack(spacing: 16) {
            if endorsements.isEmpty {
                Text("No endorsements yet.")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.top, 40)
            } else {
                ForEach(endorsements) { endorsement in
                    EndorsementCardView(endorsement: endorsement)
                }
            }
        }
    }
}

struct EndorsementCardView: View {
    let endorsement: CoachEndorsement
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(endorsement.coachImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                VStack(alignment: .leading) {
                    Text(endorsement.coachName)
                        .font(.headline)
                        .fontWeight(.bold)
                    HStack(spacing: 2) {
                        ForEach(0..<5) { i in
                            Image(systemName: i < endorsement.rating ? "star.fill" : "star")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }
            Text(endorsement.endorsementText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// TEMP STUB - remove this if you already have a real EditProfileView in another file
struct EditProfileView: View {
    @ObservedObject var userProfile: UserProfile
    var body: some View {
        Text("Edit Profile")
            .font(.title2)
            .padding()
    }
}
