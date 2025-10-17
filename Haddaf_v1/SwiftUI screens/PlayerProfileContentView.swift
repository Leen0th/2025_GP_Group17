import SwiftUI
import PhotosUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

// MARK: - Validation Helper
private func isValidEmail(_ value: String) -> Bool {
    let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
    return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
}

// MARK: - Main Profile Content View
struct PlayerProfileContentView: View {
    @StateObject private var viewModel = PlayerProfileViewModel()
    @State private var selectedContent: ContentType = .posts

    private let postColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    @State private var showDeleteAlert = false
    @State private var postToDelete: Post? = nil
    @State private var showEditProfile = false

    var body: some View {
        NavigationStack {
            Color.white.ignoresSafeArea()
                .overlay(
                    ScrollView {
                        if viewModel.isLoading {
                            ProgressView().padding(.top, 50)
                        } else {
                            VStack(spacing: 24) {
                                TopNavigationBar(userProfile: viewModel.userProfile, showEditProfile: $showEditProfile)
                                ProfileHeaderView(userProfile: viewModel.userProfile)
                                StatsGridView(userProfile: viewModel.userProfile)
                                ContentTabView(selectedContent: $selectedContent)

                                switch selectedContent {
                                case .posts:
                                    postsGrid
                                case .progress:
                                    ProgressTabView()
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
                .onReceive(NotificationCenter.default.publisher(for: .postCreated)) { note in
                    if let post = note.userInfo?["post"] as? Post {
                        viewModel.posts.insert(post, at: 0)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .postDeleted)) { note in
                    if let postId = note.userInfo?["postId"] as? String {
                        viewModel.posts.removeAll { $0.id == postId }
                    }
                }
                .fullScreenCover(isPresented: $showEditProfile) {
                    EditProfileView(userProfile: viewModel.userProfile)
                }
        }
    }

    private var postsGrid: some View {
        LazyVGrid(columns: postColumns, spacing: 12) {
            ForEach(viewModel.posts) { post in
                NavigationLink(destination: PostDetailView(post: post)) {
                    ZStack(alignment: .topTrailing) {
                        AsyncImage(url: URL(string: post.imageName)) { image in
                            image.resizable().aspectRatio(1, contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.05)).frame(height: 110)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity).clipped()
                        
                        if post.isPrivate {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.red.opacity(0.8))
                                .clipShape(Circle())
                                .padding(8)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .refreshable { await viewModel.fetchAllData() }
    }
}

// MARK: - Edit Profile View
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var userProfile: UserProfile
    
    @State private var name: String
    @State private var position: String
    @State private var weight: String
    @State private var height: String
    @State private var location: String
    @State private var email: String
    @State private var isEmailVisible: Bool
    @State private var profileImage: UIImage?
    @State private var dob: Date?
    
    @State private var showDOBPicker = false
    @State private var tempDOB = Date()
    @State private var showPositionPicker = false
    @State private var showLocationPicker = false
    @State private var locationSearch = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    @State private var isSaving = false
    @State private var showInfoOverlay = false
    @State private var overlayMessage = ""
    @State private var overlayIsError = false
    
    private let primary = Color(hex: "#36796C")
    private let db = Firestore.firestore()
    private let positions = ["Attacker", "Midfielder", "Defender"]
    
    private var isEmailFieldValid: Bool { isValidEmail(email) }
    private var isFormValid: Bool { isEmailFieldValid && !name.isEmpty && !position.isEmpty }
    
    init(userProfile: UserProfile) {
        self.userProfile = userProfile
        _name = State(initialValue: userProfile.name)
        _position = State(initialValue: userProfile.position)
        _weight = State(initialValue: userProfile.weight.replacingOccurrences(of: "kg", with: ""))
        _height = State(initialValue: userProfile.height.replacingOccurrences(of: "cm", with: ""))
        _location = State(initialValue: userProfile.location)
        _email = State(initialValue: userProfile.email)
        _isEmailVisible = State(initialValue: userProfile.isEmailVisible)
        _profileImage = State(initialValue: userProfile.profileImage)
        
        if let ageInt = Int(userProfile.age) {
            _dob = State(initialValue: Calendar.current.date(byAdding: .year, value: -ageInt, to: Date()))
        } else {
            _dob = State(initialValue: nil)
        }
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    profilePictureSection
                    Divider()
                    formFields
                    togglesSection
                    updateButton
                        .padding(.top, 20)
                        .padding(.bottom)
                }
                .padding(.horizontal)
            }
            
            if showInfoOverlay {
                InfoOverlay(primary: primary, title: overlayMessage, isError: overlayIsError, onOk: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showInfoOverlay = false }
                    if !overlayIsError { dismiss() }
                })
                .transition(.scale.combined(with: .opacity)).zIndex(1)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self), let newImage = UIImage(data: data) {
                    await MainActor.run { self.profileImage = newImage }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showInfoOverlay)
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
        }.padding(.top)
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
            
            fieldLabel("Position")
            buttonLikeField {
                HStack {
                    Text(position.isEmpty ? "Select position" : position).font(.custom("Poppins", size: 16)).foregroundColor(position.isEmpty ? .gray : primary)
                    Spacer()
                    Image(systemName: "chevron.down").foregroundColor(primary.opacity(0.85))
                }
            } onTap: { showPositionPicker = true }
            .sheet(isPresented: $showPositionPicker) {
                PositionWheelPickerSheet(positions: positions, selection: $position, showSheet: $showPositionPicker)
                    .presentationDetents([.height(300)]).presentationBackground(.white).presentationCornerRadius(28)
            }
            
            field(label: "Height (cm)", text: $height, keyboardType: .numberPad)
            field(label: "Weight (kg)", text: $weight, keyboardType: .numberPad)
            
            fieldLabel("Date of birth")
            buttonLikeField {
                HStack {
                    Text(dob.map { formatDate($0) } ?? "Select date").font(.custom("Poppins", size: 16)).foregroundColor(dob == nil ? .gray : primary)
                    Spacer()
                    Image(systemName: "calendar").foregroundColor(primary.opacity(0.85))
                }
            } onTap: {
                tempDOB = dob ?? Date(); showDOBPicker = true
            }
            .sheet(isPresented: $showDOBPicker) {
                DateWheelPickerSheet(selection: $dob, tempSelection: $tempDOB, showSheet: $showDOBPicker)
                    .presentationDetents([.height(300)]).presentationBackground(.white).presentationCornerRadius(28)
            }
            
            fieldLabel("Location")
            buttonLikeField {
                HStack {
                    Text(location.isEmpty ? "Select city" : location).font(.custom("Poppins", size: 16)).foregroundColor(location.isEmpty ? .gray : primary)
                    Spacer()
                    Image(systemName: "chevron.down").foregroundColor(primary.opacity(0.85))
                }
            } onTap: {
                locationSearch = ""; showLocationPicker = true
            }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerSheet(title: "Select your city", allCities: SAUDI_CITIES, selection: $location, searchText: $locationSearch, showSheet: $showLocationPicker, accent: primary)
                    .presentationDetents([.large]).presentationBackground(.white).presentationCornerRadius(28)
            }
            
            field(label: "Email", text: $email, keyboardType: .emailAddress)
            if !email.isEmpty && !isEmailFieldValid {
                Text("Please enter a valid email address.").font(.system(size: 13)).foregroundColor(.red)
            }
        }
    }

    private var togglesSection: some View {
        VStack(spacing: 16) {
            toggleRow(title: "Make my email visible", isOn: $isEmailVisible)
        }
        .padding(.top, 10)
    }

    private var updateButton: some View {
        Button { Task { await saveChanges() } } label: {
            HStack {
                Text("Update").font(.custom("Poppins", size: 18)).foregroundColor(.white)
                if isSaving { ProgressView().colorInvert().scaleEffect(0.9) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16).background(primary).clipShape(Capsule())
        }
        .disabled(!isFormValid || isSaving)
        .opacity((!isFormValid || isSaving) ? 0.6 : 1.0)
    }

    private func saveChanges() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            overlayMessage = "User not authenticated"; overlayIsError = true; showInfoOverlay = true; return
        }
        
        isSaving = true
        
        do {
            var userUpdates: [String: Any] = [
                "firstName": name.split(separator: " ").first.map(String.init) ?? name,
                "lastName": name.split(separator: " ").dropFirst().joined(separator: " "),
                "email": email,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            if let newImage = profileImage, let oldImage = userProfile.profileImage, newImage != oldImage, let imageData = newImage.jpegData(compressionQuality: 0.8) {
                let fileName = "\(UUID().uuidString).jpg"
                let ref = Storage.storage().reference().child("profile/\(uid)/\(fileName)")
                _ = try await ref.putDataAsync(imageData)
                let url = try await ref.downloadURL()
                userUpdates["profilePic"] = url.absoluteString
            }
            
            try await db.collection("users").document(uid).setData(userUpdates, merge: true)
            
            var profileUpdates: [String: Any] = [
                "position": position, "weight": Int(weight) ?? 0, "height": Int(height) ?? 0,
                "location": location, "isEmailVisible": isEmailVisible,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            if let dob = dob { profileUpdates["dateOfBirth"] = Timestamp(date: dob) }
            
            try await db.collection("users").document(uid).collection("player").document("profile").setData(profileUpdates, merge: true)
            
            await MainActor.run {
                userProfile.name = name; userProfile.position = position; userProfile.weight = "\(weight)kg"
                userProfile.height = "\(height)cm"; userProfile.location = location; userProfile.email = email
                userProfile.isEmailVisible = isEmailVisible
                if let dob = dob {
                    let ageComponents = Calendar.current.dateComponents([.year], from: dob, to: Date())
                    userProfile.age = "\(ageComponents.year ?? 0)"
                }
                if let img = profileImage { userProfile.profileImage = img }
                
                overlayMessage = "Profile updated successfully"; overlayIsError = false; showInfoOverlay = true
            }
        } catch {
            overlayMessage = "Failed to update profile: \(error.localizedDescription)"; overlayIsError = true; showInfoOverlay = true
        }
        isSaving = false
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
    
    private func buttonLikeField<Content: View>(@ViewBuilder content: () -> Content, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            content().padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 14).fill(.white).shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2))
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; return f.string(from: date)
    }
}


// MARK: - Profile Helper Views
struct TopNavigationBar: View {
    @ObservedObject var userProfile: UserProfile
    @Binding var showEditProfile: Bool
    
    var body: some View {
        HStack {
            NavigationLink(destination: SettingsView()) { Image(systemName: "gearshape") }
            Spacer()
            Button(action: { showEditProfile = true }) {
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
    private var contactStats: [PlayerStat] {
        var stats: [PlayerStat] = []
        if userProfile.isEmailVisible {
            stats.append(.init(title: "Email", value: userProfile.email))
        }
        return stats
    }
    private let mainGridColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())]
    let accentColor = Color(hex: "#36796C")

    var body: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: mainGridColumns, spacing: 20) {
                ForEach(mainStats) { stat in
                    statItemView(for: stat, alignment: .center)
                }
            }
            if !contactStats.isEmpty {
                Button(action: { withAnimation(.spring()) { showContactInfo.toggle() } }) {
                    HStack(spacing: 4) {
                        Text(showContactInfo ? "Show less" : "Show contact info")
                        Image(systemName: showContactInfo ? "chevron.up" : "chevron.down")
                    }.font(.caption).fontWeight(.bold).foregroundColor(accentColor).padding(.top, 8)
                }
                if showContactInfo {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(contactStats) { stat in
                            statItemView(for: stat, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func statItemView(for stat: PlayerStat, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(stat.title).font(.caption).foregroundColor(accentColor)
            Text(stat.value).font(.headline).fontWeight(.semibold).multilineTextAlignment(alignment == .leading ? .leading : .center)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
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
        .font(.headline).fontWeight(.medium)
    }
}

fileprivate struct ContentTabButton: View {
    let title: String
    let type: ContentType
    @Binding var selectedContent: ContentType
    let accentColor: Color
    let animation: Namespace.ID

    var body: some View {
        Button(action: { withAnimation(.easeInOut) { selectedContent = type } }) {
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

struct EndorsementsListView: View {
    let endorsements: [CoachEndorsement]
    var body: some View {
        VStack(spacing: 16) {
            if endorsements.isEmpty {
                Text("No endorsements yet.").font(.headline).foregroundColor(.secondary).padding(.top, 40)
            } else {
                ForEach(endorsements) { endorsement in EndorsementCardView(endorsement: endorsement) }
            }
        }
    }
}

struct EndorsementCardView: View {
    let endorsement: CoachEndorsement
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(endorsement.coachImage).resizable().aspectRatio(contentMode: .fill).frame(width: 44, height: 44).clipShape(Circle())
                VStack(alignment: .leading) {
                    Text(endorsement.coachName).font(.headline).fontWeight(.bold)
                    HStack(spacing: 2) {
                        ForEach(0..<5) { index in Image(systemName: index < endorsement.rating ? "star.fill" : "star").font(.caption).foregroundColor(.yellow) }
                    }
                }
            }
            Text(endorsement.endorsementText).font(.subheadline).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.white).cornerRadius(12).shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Custom Overlay for Notices
struct InfoOverlay: View {
    let primary: Color
    let title: String
    let isError: Bool
    var onOk: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill").font(.system(size: 50)).foregroundColor(isError ? .red : primary)
                Text(title).font(.custom("Poppins", size: 16)).multilineTextAlignment(.center).padding(.horizontal)
                Button("OK") { onOk() }.font(.custom("Poppins", size: 18)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(primary).clipShape(Capsule())
            }
            .padding(EdgeInsets(top: 30, leading: 20, bottom: 20, trailing: 20)).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 10).padding(.horizontal, 40)
        }
    }
}

// MARK: - Picker Sheets
private struct PositionWheelPickerSheet: View {
    let positions: [String]
    @Binding var selection: String
    @Binding var showSheet: Bool
    @State private var tempSelection: String = ""
    private let primary = Color(hex: "#36796C")

    var body: some View {
        VStack(spacing: 16) {
            Text("Select your position").font(.custom("Poppins", size: 18)).foregroundColor(primary).frame(maxWidth: .infinity).padding(.top, 16)
            Picker("", selection: $tempSelection) {
                ForEach(positions, id: \.self) { pos in Text(pos).tag(pos) }
            }.pickerStyle(.wheel).labelsHidden().frame(height: 180)
            Button("Done") { selection = tempSelection; showSheet = false }.font(.custom("Poppins", size: 18)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(primary).clipShape(Capsule()).padding(.bottom, 16)
        }
        .onAppear { tempSelection = selection.isEmpty ? (positions.first ?? "") : selection }.padding(.horizontal, 20)
    }
}

private struct LocationPickerSheet: View {
    let title: String
    let allCities: [String]
    @Binding var selection: String
    @Binding var searchText: String
    @Binding var showSheet: Bool
    let accent: Color

    var filtered: [String] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return allCities }
        return allCities.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered, id: \.self) { city in
                    Button { selection = city; showSheet = false } label: {
                        HStack {
                            Text(city).foregroundColor(.black)
                            Spacer()
                            if city == selection { Image(systemName: "checkmark.circle.fill").foregroundColor(accent) }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .listStyle(.plain).searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search city").navigationTitle(Text(title))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSheet = false } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 20, weight: .semibold)).foregroundColor(.secondary) }
                }
            }
        }
    }
}

private struct DateWheelPickerSheet: View {
    @Binding var selection: Date?
    @Binding var tempSelection: Date
    @Binding var showSheet: Bool
    private let primary = Color(hex: "#36796C")

    var body: some View {
        VStack(spacing: 16) {
            Text("Select your birth date").font(.custom("Poppins", size: 18)).foregroundColor(primary).frame(maxWidth: .infinity).padding(.top, 16)
            DatePicker("", selection: $tempSelection, in: ...Date(), displayedComponents: .date).datePickerStyle(.wheel).labelsHidden().tint(primary).frame(height: 180)
            Button("Done") { selection = tempSelection; showSheet = false }.font(.custom("Poppins", size: 18)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(primary).clipShape(Capsule()).padding(.bottom, 16)
        }.padding(.horizontal, 20)
    }
}

// MARK: - Saudi cities (English)
private let SAUDI_CITIES: [String] = [
    "Riyadh", "Jeddah", "Mecca", "Medina", "Dammam", "Khobar", "Dhahran", "Taif", "Tabuk", "Abha", "Khamis Mushait", "Jizan", "Najran", "Hail", "Buraydah", "Unaizah", "Al Hofuf", "Al Mubarraz", "Jubail", "Yanbu", "Rabigh", "Al Baha", "Bisha", "Al Majmaah", "Al Zulfi", "Sakaka", "Arar", "Qurayyat", "Rafha", "Turaif", "Tarut", "Qatif", "Safwa", "Saihat", "Al Khafji", "Al Ahsa", "Al Qassim", "Al Qaisumah", "Sharurah", "Tendaha", "Wadi ad-Dawasir", "Al Qurayyat", "Tayma", "Umluj", "Haql", "Al Wajh", "Al Lith", "Al Qunfudhah", "Sabya", "Abu Arish", "Samtah", "Baljurashi", "Al Mandaq", "Qilwah", "Al Namas", "Tanomah", "Mahd adh Dhahab", "Badr", "Al Ula", "Khaybar", "Al Bukayriyah", "Riyadh Al Khabra", "Al Rass", "Diriyah", "Al Kharj", "Hotat Bani Tamim", "Al Hariq", "Wadi Al Dawasir", "Afif", "Dawadmi", "Shaqra", "Thadig", "Muzahmiyah", "Rumah", "Ad Dilam", "Al Quwayiyah", "Duba", "Turaif", "Ar Ruwais", "Farasan", "Al Dayer", "Fifa", "Al Aridhah", "Al Bahah City", "King Abdullah Economic City", "Al Uyaynah", "Al Badayea", "Al Uwayqilah", "Bathaa", "Al Jafr", "Thuqbah", "Buqayq (Abqaiq)", "Ain Dar", "Nairyah", "Al Hassa", "Salwa", "Ras Tanura", "Khafji", "Manfouha", "Al Muzahmiyah"
].sorted()

