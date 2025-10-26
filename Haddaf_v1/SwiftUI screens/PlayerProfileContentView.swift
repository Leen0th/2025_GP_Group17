import SwiftUI
import PhotosUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

extension Notification.Name {
    static let profileUpdated = Notification.Name("profileUpdated")
}

// MARK: - Main Profile Content View
struct PlayerProfileContentView: View {
    @StateObject private var viewModel = PlayerProfileViewModel()
    @State private var selectedContent: ContentType = .posts

    // MODIFIED: New 3-column grid for posts
    private let postColumns = [
        GridItem(.flexible(), spacing: 2), // Reduced spacing
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    @State private var showDeleteAlert = false
    @State private var postToDelete: Post? = nil
    @State private var selectedPost: Post? = nil
    @State private var goToSettings = false
    
    @State private var showNotificationsList = false
    
    enum PostFilter: String, CaseIterable {
        case all = "All"
        case `public` = "Public"
        case `private` = "Private"
    }
    
    enum PostSort: String, CaseIterable {
        case newestFirst = "Newest Post First"
        case oldestFirst = "Oldest Post First"
        case matchDateNewest = "Newest Match Date"
        case matchDateOldest = "Oldest Match Date"
    }

    @State private var postFilter: PostFilter = .all
    @State private var postSort: PostSort = .newestFirst
    
    @State private var searchText = ""

    private var filteredAndSortedPosts: [Post] {
        let searched: [Post]
        if searchText.isEmpty {
            searched = viewModel.posts
        } else {
            searched = viewModel.posts.filter { $0.caption.localizedCaseInsensitiveContains(searchText) }
        }

        let filtered: [Post]
        switch postFilter {
        case .all: filtered = searched
        case .public: filtered = searched.filter { !$0.isPrivate }
        case .private: filtered = searched.filter { $0.isPrivate }
        }

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
            // MODIFIED: Use new gradient background
            BrandColors.backgroundGradientEnd.ignoresSafeArea()

            ScrollView {
                if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 50)
                        .tint(BrandColors.darkTeal) // MODIFIED: Tint
                } else {
                    VStack(spacing: 24) {
                        TopNavigationBar(
                            userProfile: viewModel.userProfile,
                            goToSettings: $goToSettings,
                            showNotifications: $showNotificationsList
                        )
                        
                        // MODIFIED: Header now "hugs" the content below
                        // We use a negative spacing to pull the StatsGridView "under" the header
                        ProfileHeaderView(userProfile: viewModel.userProfile)
                            .padding(.bottom, 0) // <-- This pulls the next view up
                            .zIndex(1) // <-- Ensures header stays on top

                        // MODIFIED: StatsGridView is now the new "Chip" design
                        StatsGridView(userProfile: viewModel.userProfile)
                            .zIndex(0) // <-- Stays below the header
                        
                        ContentTabView(selectedContent: $selectedContent)

                        switch selectedContent {
                        case .posts:
                            // MODIFIED: New search bar style
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(BrandColors.darkTeal) // MODIFIED
                                    .padding(.leading, 12)
                                
                                TextField("Search by title...", text: $searchText)
                                    .font(.system(size: 16, design: .rounded)) // MODIFIED
                                    .tint(BrandColors.darkTeal) // MODIFIED
                                    .submitLabel(.search)
                                
                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.trailing, 8)
                                }
                            }
                            .padding(.vertical, 12)
                            .background(BrandColors.lightGray.opacity(0.7)) // MODIFIED
                            .clipShape(Capsule())
                            .padding(.horizontal) // Add padding to the search bar
                            // --- END: Search Bar ---

                            postControls
                                .padding(.horizontal) // Add padding to controls

                            postsGrid
                                .padding(.horizontal) // Add padding to grid
                            
                        case .progress:
                        // --- MODIFIED: Commented out ProgressTabView ---
                        // ProgressTabView() // <-- Placeholder commented out
                        EmptyStateView(
                            imageName: "chart.bar.xaxis",
                            message: "Your progress analytics will appear here once you start uploading videos."
                        )
                        .padding(.top, 40)
                        // --- END MODIFICATION ---

                    case .endorsements:
                        EndorsementsListView(endorsements: viewModel.userProfile.endorsements)
                            .padding(.horizontal)
                    }
                    }
                    // MODIFIED: Removed top-level padding, applied to children
                    .padding(.bottom, 100)
                }
            }
            .task { await viewModel.fetchAllData() }
            // This watches the userProfile.position. If it changes
            // (like after EditProfileView saves), it will re-run the calculation.
            .onChange(of: viewModel.userProfile.position) { _, _ in
                Task {
                    await viewModel.calculateAndUpdateScore()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .postDeleted)) { note in
                if let postId = note.userInfo?["postId"] as? String {
                    withAnimation { viewModel.posts.removeAll { $0.id == postId } }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .postDataUpdated)) { note in
                guard let userInfo = note.userInfo,
                      let postId = userInfo["postId"] as? String else { return }

                if let index = viewModel.posts.firstIndex(where: { $0.id == postId }) {
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
                    
                    if userInfo["commentAdded"] as? Bool == true {
                        withAnimation {
                            viewModel.posts[index].commentCount += 1
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $goToSettings) {
                NavigationStack { SettingsView(userProfile: viewModel.userProfile) }
            }
            .fullScreenCover(isPresented: $showNotificationsList) {
                ProfileNotificationsListView()
            }
            .fullScreenCover(item: $selectedPost) { post in
                NavigationStack { PostDetailView(post: post) }
            }
        }
    }
    
    private var postControls: some View {
        HStack {
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
                // MODIFIED: New style
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(BrandColors.darkTeal)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(BrandColors.lightGray)
                .clipShape(Capsule())
            }
            
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
                .background(BrandColors.lightGray)
                .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var postsGrid: some View {
        // MODIFIED: Reduced spacing to 2
        LazyVGrid(columns: postColumns, spacing: 2) {
            ForEach(filteredAndSortedPosts) { post in
                Button { selectedPost = post } label: {
                    ZStack(alignment: .bottomLeading) {
                        AsyncImage(url: URL(string: post.imageName)) { $0.resizable().aspectRatio(1, contentMode: .fill) }
                        placeholder: {
                            RoundedRectangle(cornerRadius: 0) // MODIFIED: No corner radius
                                .fill(BrandColors.lightGray) // MODIFIED
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
                        
                        Text(post.caption)
                            // MODIFIED: New font
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
                    // MODIFIED: No corner radius or shadow on individual posts
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.default, value: filteredAndSortedPosts)
        .refreshable { await viewModel.fetchAllData() }
    }
}

// MARK: - Edit Profile View
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var userProfile: UserProfile
    
    // Fields
    @State private var name: String
    @State private var position: String
    @State private var weight: String
    @State private var height: String
    @State private var location: String
    @State private var email: String
    @State private var isEmailVisible: Bool
    @State private var profileImage: UIImage?
    @State private var dob: Date?
    
    @State private var selectedDialCode: CountryDialCode
    @State private var phoneLocal: String
    @State private var phoneNonDigitError = false
    @State private var showDialPicker = false
    
    @State private var isPhoneNumberVisible: Bool
    
    // UI States
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
    
    private let primary = BrandColors.darkTeal
    private let db = Firestore.firestore()
    private let positions = ["Attacker", "Midfielder", "Defender"]
    
    
    // MARK: - Validation Properties
    private var isEmailFieldValid: Bool { isValidEmail(email) }
    
    private var isPhoneNumberValid: Bool {
        isValidPhone(code: selectedDialCode.code, local: phoneLocal)
    }
    
    private var isNameValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = #"^[\p{L}][\p{L}\s.'-]*$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
    private var isWeightValid: Bool {
        guard let w = Int(weight) else { return false }
        return (15...200).contains(w)
    }
    private var isHeightValid: Bool {
        guard let h = Int(height) else { return false }
        return (100...230).contains(h)
    }
    private var isFormValid: Bool {
        isNameValid && isEmailFieldValid && isPhoneNumberValid &&
        isWeightValid && isHeightValid && !position.isEmpty
    }
    
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
        _dob = State(initialValue: userProfile.dob)
        
        // Parse the full phone number from the profile
        let (parsedCode, parsedLocal) = parsePhoneNumber(userProfile.phoneNumber)
        _selectedDialCode = State(initialValue: parsedCode)
        _phoneLocal = State(initialValue: parsedLocal)
        
        _isPhoneNumberVisible = State(initialValue: userProfile.isPhoneNumberVisible)
    }

    var body: some View {
        ZStack {
            // MODIFIED: Use new gradient background
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            
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
                // MODIFIED: Pass new primary color
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
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let newImage = UIImage(data: data) {
                    await MainActor.run { self.profileImage = newImage }
                }
            }
        }
        .sheet(isPresented: $showDialPicker) {
            CountryCodePickerSheet(selected: $selectedDialCode, primary: primary)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showInfoOverlay)
    }

    private var header: some View {
        ZStack {
            // MODIFIED: Use new font
            Text("Edit Profile")
                .font(.system(size: 28, weight: .medium, design: .rounded)) // MODIFIED
                .foregroundColor(primary)
            
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                        .foregroundColor(primary).padding(10).background(Circle().fill(BrandColors.lightGray.opacity(0.7))) // MODIFIED
                }
                Spacer()
            }
        }
        .padding(.top)
    }

    private var profilePictureSection: some View {
        VStack {
            Image(uiImage: profileImage ?? UIImage(systemName: "person.circle.fill")!)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100).clipShape(Circle())
                .foregroundColor(.gray.opacity(0.5))
            
            HStack(spacing: 20) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    // MODIFIED: Use new font
                    Text("Change Picture")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(primary)
                }
                
                if profileImage != nil {
                    Button(role: .destructive) {
                        withAnimation { self.profileImage = nil; self.selectedPhotoItem = nil }
                    } label: {
                        // MODIFIED: Use new font
                        Text("Remove")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Name
            field(label: "Name", text: $name, isValid: isNameValid)
            if !name.isEmpty && !isNameValid {
                // MODIFIED: Use new font
                Text("Please enter a valid name (letters and spaces only).")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.red)
            }
            
            // Position
            fieldLabel("Position")
            buttonLikeField {
                HStack {
                    // MODIFIED: Use new font
                    Text(position.isEmpty ? "Select position" : position)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(position.isEmpty ? .gray : primary)
                    Spacer()
                    Image(systemName: "chevron.down").foregroundColor(primary.opacity(0.85))
                }
            } onTap: { showPositionPicker = true }
            .sheet(isPresented: $showPositionPicker) {
                PositionWheelPickerSheet(positions: positions, selection: $position, showSheet: $showPositionPicker)
                    .presentationDetents([.height(300)])
                    .presentationBackground(BrandColors.background) // MODIFIED
                    .presentationCornerRadius(28)
            }
            
            // Height
            field(label: "Height (cm)", text: $height, keyboardType: .numberPad, isValid: isHeightValid)
            if !height.isEmpty && !isHeightValid {
                // MODIFIED: Use new font
                Text("Enter a realistic height between 100–230 cm.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.red)
            }
            
            // Weight
            field(label: "Weight (kg)", text: $weight, keyboardType: .numberPad, isValid: isWeightValid)
            if !weight.isEmpty && !isWeightValid {
                // MODIFIED: Use new font
                Text("Enter a realistic weight between 15–200 kg.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.red)
            }
            
            // DOB
            fieldLabel("Date of birth")
            buttonLikeField {
                HStack {
                    // MODIFIED: Use new font
                    Text(dob.map { formatDate($0) } ?? "Select date")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(dob == nil ? .gray : primary)
                    Spacer()
                    Image(systemName: "calendar").foregroundColor(primary.opacity(0.85))
                }
            } onTap: { tempDOB = dob ?? Date(); showDOBPicker = true }
            .sheet(isPresented: $showDOBPicker) {
                DateWheelPickerSheet(selection: $dob, tempSelection: $tempDOB, showSheet: $showDOBPicker)
                    .presentationDetents([.height(300)])
                    .presentationBackground(BrandColors.background) // MODIFIED
                    .presentationCornerRadius(28)
            }
            
            // Location
            fieldLabel("Location")
            buttonLikeField {
                HStack {
                    // MODIFIED: Use new font
                    Text(location.isEmpty ? "Select city" : location)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(location.isEmpty ? .gray : primary)
                    Spacer()
                    Image(systemName: "chevron.down").foregroundColor(primary.opacity(0.85))
                }
            } onTap: { locationSearch = ""; showLocationPicker = true }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerSheet(title: "Select your city", allCities: SAUDI_CITIES, selection: $location, searchText: $locationSearch, showSheet: $showLocationPicker, accent: primary)
                    .presentationDetents([.large])
                    .presentationBackground(BrandColors.background) // MODIFIED
                    .presentationCornerRadius(28)
            }
            
            // Email
            field(label: "Email", text: $email, keyboardType: .emailAddress, isValid: isEmailFieldValid)
            if !email.isEmpty && !isEmailFieldValid {
                // MODIFIED: Use new font
                Text("Please enter a valid email address.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.red)
            }
            
            // Phone Field
            fieldLabel("Phone number")
            roundedField {
                HStack(spacing: 10) {
                    Button { showDialPicker = true } label: {
                        HStack(spacing: 6) {
                            // MODIFIED: Use new font
                            Text(selectedDialCode.code)
                                .font(.system(size: 16, design: .rounded))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(primary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(primary.opacity(0.08))
                        )
                    }

                    TextField("", text: Binding(
                        get: { phoneLocal },
                        set: { val in
                            phoneNonDigitError = val.contains { !$0.isNumber }
                            phoneLocal = val.filter { $0.isNumber }
                        }
                    ))
                    .keyboardType(.numberPad)
                    // MODIFIED: Use new font
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(primary)
                    .tint(primary)
                }
            }
            // Error messages for phone
            if phoneNonDigitError {
                // MODIFIED: Use new font
                Text("Numbers only (0–9).")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.red)
            } else if !phoneLocal.isEmpty && !isPhoneNumberValid {
                if selectedDialCode.code == "+966" {
                    // MODIFIED: Use new font
                    Text("Must be 9 digits and start with 5.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.red)
                } else {
                    // MODIFIED: Use new font
                    Text("Enter a valid phone number.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var togglesSection: some View {
        VStack(spacing: 16) {
            toggleRow(title: "Make my email visible", isOn: $isEmailVisible)
            toggleRow(title: "Make my phone visible", isOn: $isPhoneNumberVisible)
        }
        .padding(.top, 10)
    }

    private var updateButton: some View {
        Button { Task { await saveChanges() } } label: {
            HStack {
                // MODIFIED: Use new font
                Text("Update")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                if isSaving { ProgressView().colorInvert().scaleEffect(0.9) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16).background(primary).clipShape(Capsule())
        }
        .disabled(!isFormValid || isSaving)
        .opacity((!isFormValid || isSaving) ? 0.6 : 1.0)
    }

    private func saveChanges() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            overlayMessage = "User not authenticated"; overlayIsError = true; showInfoOverlay = true
            return
        }
        
        isSaving = true
        do {
            // Re-join phone number
            let fullPhone = selectedDialCode.code + phoneLocal
            
            // MARK: --- Main /users/{uid} Doc Updates ---
            var userUpdates: [String: Any] = [
                "firstName": name.split(separator: " ").first.map(String.init) ?? name,
                "lastName": name.split(separator: " ").dropFirst().joined(separator: " "),
                "email": email,
                "phone": fullPhone,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            if let dob = dob {
                userUpdates["dob"] = Timestamp(date: dob)
            } else {
                userUpdates["dob"] = NSNull()
            }
            
            let oldImage = userProfile.profileImage
            if let newImage = profileImage, newImage != oldImage {
                if let imageData = newImage.jpegData(compressionQuality: 0.8) {
                    let fileName = "\(UUID().uuidString).jpg"
                    let ref = Storage.storage().reference().child("profile/\(uid)/\(fileName)")
                    _ = try await ref.putDataAsync(imageData)
                    let url = try await ref.downloadURL()
                    userUpdates["profilePic"] = url.absoluteString
                }
            } else if profileImage == nil, oldImage != nil {
                userUpdates["profilePic"] = ""
            }
            
            try await db.collection("users").document(uid).setData(userUpdates, merge: true)
            
            // MARK: --- Sub-doc /users/{uid}/player/profile Updates ---
            let profileUpdates: [String: Any] = [
                "position": position,
                "weight": Int(weight) ?? 0,
                "height": Int(height) ?? 0,
                "Residence": location,
                "isEmailVisible": isEmailVisible,
                "contactVisibility": isPhoneNumberVisible,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            try await db.collection("users").document(uid)
                .collection("player").document("profile")
                .setData(profileUpdates, merge: true)
            
            // MARK: --- Update Local @ObservedObject ---
            await MainActor.run {
                userProfile.name = name
                userProfile.position = position
                userProfile.weight = "\(weight)kg"
                userProfile.height = "\(height)cm"
                userProfile.location = location
                userProfile.email = email
                userProfile.isEmailVisible = isEmailVisible
                userProfile.phoneNumber = fullPhone
                userProfile.isPhoneNumberVisible = isPhoneNumberVisible
                userProfile.dob = dob
                
                if let dob = dob {
                    let comps = Calendar.current.dateComponents([.year], from: dob, to: Date())
                    userProfile.age = "\(comps.year ?? 0)"
                } else {
                    userProfile.age = ""
                }
                
                if profileImage == nil {
                    userProfile.profileImage = nil
                } else if let newImage = profileImage, newImage != oldImage {
                    userProfile.profileImage = newImage
                }
                
                overlayMessage = "Profile updated successfully"
                overlayIsError = false
                showInfoOverlay = true
                
                // This tells the app the profile has changed
                NotificationCenter.default.post(name: .profileUpdated, object: nil)
            }
        } catch {
            overlayMessage = "Failed to update profile: \(error.localizedDescription)"
            overlayIsError = true
            showInfoOverlay = true
        }
        isSaving = false
    }
    
    // MARK: - View Helpers
    
    private func field(label: String, text: Binding<String>, keyboardType: UIKeyboardType = .default, isValid: Bool) -> some View {
        VStack(alignment: .leading) {
            fieldLabel(label)
            roundedField {
                TextField("", text: text)
                    // MODIFIED: Use new font
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(primary)
                    .tint(primary).keyboardType(keyboardType)
                    .onChange(of: text.wrappedValue) { oldValue, newValue in
                        if keyboardType == .numberPad {
                            text.wrappedValue = newValue.filter(\.isNumber)
                        }
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isValid || text.wrappedValue.isEmpty ? Color.clear : Color.red, lineWidth: 1)
            )
        }
    }
    
    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            // MODIFIED: Use new font
            Text(title)
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(BrandColors.darkGray) // MODIFIED
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(primary)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        // MODIFIED: Use new font
        Text(title)
            .font(.system(size: 14, design: .rounded))
            .foregroundColor(.gray)
    }

    private func roundedField<Content: View>(@ViewBuilder c: () -> Content) -> some View {
        c()
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                // MODIFIED: Use new shadow spec
                RoundedRectangle(cornerRadius: 14).fill(BrandColors.background)
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
            )
    }
    
    private func buttonLikeField<Content: View>(@ViewBuilder content: () -> Content, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            content()
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                // MODIFIED: Use new shadow spec and background
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(BrandColors.background)
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                )
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"; return f.string(from: date)
    }
}

// MARK: - Profile Helper Views (Styling Update)
struct TopNavigationBar: View {
    @ObservedObject var userProfile: UserProfile
    @Binding var goToSettings: Bool
    @Binding var showNotifications: Bool

    var body: some View {
        HStack(spacing: 16) {
            Spacer()
            
            Button { showNotifications = true } label: {
                Image(systemName: "bell")
                    .font(.title2)
                    // MODIFIED: Use new color
                    .foregroundColor(BrandColors.darkTeal)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            Button { goToSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
                    // MODIFIED: Use new color
                    .foregroundColor(BrandColors.darkTeal)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}

struct ProfileHeaderView: View {
    @ObservedObject var userProfile: UserProfile
    var body: some View {
        VStack(spacing: 12) {
            Image(uiImage: userProfile.profileImage ?? UIImage(systemName: "person.circle.fill")!)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100).clipShape(Circle())
                .overlay(Circle().stroke(BrandColors.background, lineWidth: 4)) // MODIFIED
                .shadow(color: .black.opacity(0.08), radius: 12, y: 5) // MODIFIED
                .foregroundColor(.gray.opacity(0.5))
            
            // MODIFIED: Use new font and color
            Text(userProfile.name)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(BrandColors.darkTeal)
        }
    }
}

// MARK: - Stats Grid (COMPLETE REDESIGN - Refined)
struct StatsGridView: View {
    @ObservedObject var userProfile: UserProfile
    @State private var showContactInfo = false

    let accentColor = BrandColors.darkTeal
    let goldColor = BrandColors.gold

    // --- REFINED: Helper for User-Provided Stats (Centered) ---
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
            // --- MODIFIED: Allow vertical expansion ---
                .fixedSize(horizontal: false, vertical: true)
        }
        // --- MODIFIED: Remove explicit width constraints, allow natural sizing ---
        // .frame(minWidth: 60) // Removed
        // .frame(maxWidth: .infinity) // Removed - let HStack distribute/
    }
    // Helper for System Stats (Centered)
    @ViewBuilder
    private func SystemStatItem(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(accentColor)
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(BrandColors.darkGray)
                .multilineTextAlignment(.center) // Ensure value is centered
        }
         .frame(maxWidth: .infinity) // Allow expansion
    }

    // MARK: - Body (Redesigned & Rearranged)
    var body: some View {
        VStack(spacing: 18) { // Slightly reduced main spacing

            // --- 1. Hero Stat (Score) ---
            VStack(spacing: 8) {
                Text("Performance Score")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(accentColor)

                Text(userProfile.score.isEmpty ? "0" : userProfile.score)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(goldColor)
            }
            .padding(.top, 10)

            // --- 2. User-Provided Stats (Centered HStack) ---
            HStack(alignment: .top) { // Removed explicit spacing
                Spacer(minLength: 3) // Add minLength to ensure some space
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
            .padding(.horizontal, 5) // Minimal padding around the HStack itself

            Divider().padding(.horizontal)

            // --- 3. System Stats (Centered HStack) ---
            HStack(alignment: .top) {
                Spacer()
                SystemStatItem(title: "Team", value: userProfile.team)
                Spacer()
                SystemStatItem(title: "Challenge Rank", value: userProfile.rank)
                Spacer()
                // Removed Residence from here
            }
             .padding(.horizontal, 20) // Add padding to space out Team/Rank

            // --- 4. Contact Info ---
            // (Keep this section as it was)
            if userProfile.isEmailVisible || userProfile.isPhoneNumberVisible {
                Button(action: { withAnimation(.spring()) { showContactInfo.toggle() } }) {
                    HStack(spacing: 4) {
                        Text(showContactInfo ? "Show less" : "Show contact info")
                        Image(systemName: showContactInfo ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
                    .padding(.top, 8) // Keep padding above button
                }

                if showContactInfo {
                    VStack(alignment: .center, spacing: 12) { // Centered alignment
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
        .padding(.vertical, 25) // Adjusted vertical padding slightly
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(BrandColors.background)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        )
        .padding(.horizontal)
    }

    // Contact Item Helper (Unchanged)
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

// MARK: - Content Tab (Styling Update)
struct ContentTabView: View {
    @Binding var selectedContent: ContentType
    @Namespace private var animation
    
    // MODIFIED: Use new color
    let accentColor = BrandColors.darkTeal

    var body: some View {
        HStack(spacing: 12) {
            ContentTabButton(title: "My posts", type: .posts, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
            ContentTabButton(title: "My progress", type: .progress, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
            ContentTabButton(title: "Endorsements", type: .endorsements, selectedContent: $selectedContent, accentColor: accentColor, animation: animation)
        }
        // MODIFIED: Use new font
        .font(.system(size: 16, weight: .medium, design: .rounded))
    }
}

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

// MARK: - Endorsements (Styling Update)
struct EndorsementsListView: View {
    let endorsements: [CoachEndorsement]
    var body: some View {
        VStack(spacing: 16) {
            if endorsements.isEmpty {
                // MODIFIED: Use new font in EmptyStateView
                EmptyStateView(
                    imageName: "person.badge.shield.checkmark",
                    message: "Endorsements from coaches will appear here once you receive them."
                )
                .padding(.top, 40)
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
                Image(endorsement.coachImage).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44).clipShape(Circle())
                VStack(alignment: .leading) {
                    // MODIFIED: Use new font
                    Text(endorsement.coachName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    HStack(spacing: 2) {
                        ForEach(0..<5) { i in
                            Image(systemName: i < endorsement.rating ? "star.fill" : "star")
                                .font(.caption).foregroundColor(.yellow)
                        }
                    }
                }
            }
            // MODIFIED: Use new font
            Text(endorsement.endorsementText)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        // MODIFIED: Use new shadow spec
        .background(BrandColors.background)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(BrandColors.darkTeal.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Info Overlay (Styling Update)
struct InfoOverlay: View {
    let primary: Color, title: String, isError: Bool
    var onOk: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 50)).foregroundColor(isError ? .red : primary)
                
                // MODIFIED: Use new font
                Text(title)
                    .font(.system(size: 16, design: .rounded))
                    .multilineTextAlignment(.center).padding(.horizontal)
                
                Button("OK") { onOk() }
                    // MODIFIED: Use new font
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12).background(primary).clipShape(Capsule())
            }
            .padding(EdgeInsets(top: 30, leading: 20, bottom: 20, trailing: 20))
            .background(BrandColors.background) // MODIFIED
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 10).padding(.horizontal, 40)
        }
    }
}
