import SwiftUI
import PhotosUI

// MARK: - Main Profile Content View
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
                            ProgressView()
                                .padding(.top, 50)
                        } else {
                            VStack(spacing: 24) {
                                TopNavigationBar(userProfile: viewModel.userProfile)
                                ProfileHeaderView(userProfile: viewModel.userProfile)
                                StatsGridView(userProfile: viewModel.userProfile)
                                ContentTabView(selectedContent: $selectedContent)

                                switch selectedContent {
                                case .posts:
                                    postsGrid
                                case .progress:
                                    progressView
                                case .endorsements:
                                    EndorsementsListView(endorsements: viewModel.userProfile.endorsements)
                                }
                            }
                            .padding()
                            .padding(.bottom, 100)
                        }
                    }
                )
                .task {
                    await viewModel.fetchAllData()
                }
        }
    }

    private var postsGrid: some View {
        LazyVGrid(columns: postColumns, spacing: 12) {
            ForEach(viewModel.posts) { post in
                NavigationLink(destination: PostDetailView(post: post)) {
                    AsyncImage(url: URL(string: post.imageName)) { image in
                        image
                            .resizable().aspectRatio(1, contentMode: .fill)
                            .frame(minWidth: 0, maxWidth: .infinity).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.05))
                    }
                }
            }
        }
    }

    private var progressView: some View {
        VStack {
            Text("Progress Content Here")
                .font(.title2).foregroundColor(.secondary).padding(.top, 40)
            Spacer()
        }.frame(minHeight: 300)
    }
}

// MARK: - Endorsements Views
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
                Image(endorsement.coachImage) // Assuming local asset for now
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())

                VStack(alignment: .leading) {
                    Text(endorsement.coachName)
                        .font(.headline)
                        .fontWeight(.bold)
                    HStack(spacing: 2) {
                        ForEach(0..<5) { index in
                            Image(systemName: index < endorsement.rating ? "star.fill" : "star")
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

// MARK: - Edit Profile View (REBUILT FOR STABILITY)
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var userProfile: UserProfile
    
    // Local state to avoid binding issues with @ObservedObject
    @State private var name: String
    @State private var position: String
    @State private var weight: String
    @State private var height: String
    @State private var location: String
    @State private var email: String
    @State private var phoneNumber: String
    @State private var isEmailVisible: Bool
    @State private var isPhoneVisible: Bool
    @State private var profileImage: UIImage?

    @State private var selectedPhotoItem: PhotosPickerItem?
    private let primary = Color(hex: "#36796C")

    // Custom initializer to populate @State variables from the UserProfile object
    init(userProfile: UserProfile) {
        self.userProfile = userProfile
        _name = State(initialValue: userProfile.name)
        _position = State(initialValue: userProfile.position)
        _weight = State(initialValue: userProfile.weight)
        _height = State(initialValue: userProfile.height)
        _location = State(initialValue: userProfile.location)
        _email = State(initialValue: userProfile.email)
        _phoneNumber = State(initialValue: userProfile.phoneNumber)
        _isEmailVisible = State(initialValue: userProfile.isEmailVisible)
        _isPhoneVisible = State(initialValue: userProfile.isPhoneVisible)
        _profileImage = State(initialValue: userProfile.profileImage)
    }

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
                        .padding(.bottom, 75)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self), let newImage = UIImage(data: data) {
                    await MainActor.run {
                        self.profileImage = newImage
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
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundColor(primary).padding(10).background(Circle().fill(Color.black.opacity(0.05)))
                }
                Spacer()
            }
        }.padding([.horizontal, .top])
    }

    private var profilePictureSection: some View {
        VStack {
            Image(uiImage: profileImage ?? UIImage(systemName: "person.circle.fill")!)
                .resizable().aspectRatio(contentMode: .fill).frame(width: 100, height: 100).clipShape(Circle()).foregroundColor(.gray.opacity(0.5))
            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                Text("Change Picture").font(.custom("Poppins", size: 16)).fontWeight(.semibold).foregroundColor(primary)
            }.padding(.top, 4)
        }.frame(maxWidth: .infinity)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            field(label: "Name", text: $name)
            field(label: "Position", text: $position)
            field(label: "Weight", text: $weight)
            field(label: "Height", text: $height)
            field(label: "Location", text: $location)
            field(label: "Email", text: $email, keyboardType: .emailAddress)
            field(label: "Phone number", text: $phoneNumber, keyboardType: .phonePad)
        }.padding(.horizontal)
    }

    private var togglesSection: some View {
        VStack(spacing: 16) {
            toggleRow(title: "Make my email visible", isOn: $isEmailVisible)
            toggleRow(title: "Make my phone number visible", isOn: $isPhoneVisible)
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }

    private var updateButton: some View {
        Button {
            // Save local state back to the original UserProfile object
            userProfile.name = name
            userProfile.position = position
            userProfile.weight = weight
            userProfile.height = height
            userProfile.location = location
            userProfile.email = email
            userProfile.phoneNumber = phoneNumber
            userProfile.isEmailVisible = isEmailVisible
            userProfile.isPhoneVisible = isPhoneVisible
            userProfile.profileImage = profileImage
            
            // TODO: Add save logic to write changes back to Firestore
            
            dismiss()
        } label: {
            Text("Update").font(.custom("Poppins", size: 18)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 16).background(primary).clipShape(Capsule())
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

    private func roundedField<Content: View>(@ViewBuilder c: () -> Content) -> some View {
        c().padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 14).fill(.white).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.2), lineWidth: 1)))
    }
}


// MARK: - Profile Helper Views
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
        }.font(.title2).foregroundColor(.primary).padding(.top, -15)
    }
}

struct ProfileHeaderView: View {
    @ObservedObject var userProfile: UserProfile
    var body: some View {
        VStack(spacing: 12) {
            Image(uiImage: userProfile.profileImage ?? UIImage(systemName: "person.circle.fill")!)
                .resizable().aspectRatio(contentMode: .fill).frame(width: 100, height: 100).clipShape(Circle()).overlay(Circle().stroke(Color.white, lineWidth: 4)).shadow(radius: 5).foregroundColor(.gray.opacity(0.5))
            Text(userProfile.name).font(.title2).fontWeight(.bold).foregroundColor(Color(hex: "#36796C"))
        }
    }
}

struct StatsGridView: View {
    @ObservedObject var userProfile: UserProfile
    @State private var showContactInfo = false
    private var mainStats: [PlayerStat] { [.init(title: "Position", value: userProfile.position), .init(title: "Age", value: userProfile.age), .init(title: "Weight", value: userProfile.weight), .init(title: "Height", value: userProfile.height), .init(title: "Team", value: userProfile.team), .init(title: "Rank", value: userProfile.rank), .init(title: "Score", value: userProfile.score), .init(title: "Location", value: userProfile.location)] }
    private var contactStats: [PlayerStat] { [.init(title: "Email", value: userProfile.email), .init(title: "Phone", value: userProfile.phoneNumber)] }
    private let mainGridColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())]
    private let contactGridColumns = [GridItem(.flexible(), spacing: 20), GridItem(.flexible())]
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
                }.font(.caption).fontWeight(.bold).foregroundColor(accentColor).padding(.top, 8)
            }
            if showContactInfo {
                LazyVGrid(columns: contactGridColumns, spacing: 20) {
                    ForEach(contactStats) { stat in
                        statItemView(for: stat, alignment: .leading)
                    }
                }.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func statItemView(for stat: PlayerStat, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(stat.title).font(.caption).foregroundColor(accentColor)
            Text(stat.value).font(.headline).fontWeight(.semibold).multilineTextAlignment(alignment == .leading ? .leading : .center)
        }.frame(maxWidth: .infinity, alignment: .center)
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
        Button(action: {
            withAnimation(.easeInOut) { selectedContent = type }
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
