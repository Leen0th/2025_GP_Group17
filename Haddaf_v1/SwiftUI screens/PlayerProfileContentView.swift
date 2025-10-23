import SwiftUI
import PhotosUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

private let countryCodes: [CountryDialCode] = [
    .init(name: "Saudi Arabia", code: "+966"),
    .init(name: "Qatar", code: "+974"),
    .init(name: "United Arab Emirates", code: "+971"),
    .init(name: "Kuwait", code: "+965"),
    .init(name: "Bahrain", code: "+973"),
    .init(name: "Oman", code: "+968"),
    .init(name: "Jordan", code: "+962"),
    .init(name: "Egypt", code: "+20"),
    .init(name: "United States", code: "+1"),
    .init(name: "United Kingdom", code: "+44"),
    .init(name: "Germany", code: "+49"),
    .init(name: "France", code: "+33"),
    .init(name: "Spain", code: "+34"),
    .init(name: "Italy", code: "+39"),
    .init(name: "India", code: "+91"),
    .init(name: "Pakistan", code: "+92"),
    .init(name: "Philippines", code: "+63"),
    .init(name: "Indonesia", code: "+62"),
    .init(name: "Malaysia", code: "+60"),
    .init(name: "South Africa", code: "+27"),
    .init(name: "Canada", code: "+1"),
    .init(name: "Mexico", code: "+52"),
    .init(name: "Brazil", code: "+55"),
    .init(name: "Argentina", code: "+54"),
    .init(name: "Nigeria", code: "+234"),
    .init(name: "Russia", code: "+7"),
    .init(name: "China", code: "+86"),
    .init(name: "Japan", code: "+81"),
    .init(name: "South Korea", code: "+82")
].sorted { $0.name < $1.name }

// MARK: - Phone Number Parser
/// Splits a full phone number (e.g., "+966501234567" or "0501234567")
/// into its constituent country code and local part.
private func parsePhoneNumber(_ phone: String) -> (CountryDialCode, String) {
    let ksa = countryCodes.first { $0.code == "+966" } ?? countryCodes[0]
    
    // Sort codes by length, longest first, to match "+971" before "+97"
    let sortedCodes = countryCodes.sorted { $0.code.count > $1.code.count }

    for country in sortedCodes {
        if phone.hasPrefix(country.code) {
            let localPart = String(phone.dropFirst(country.code.count))
            return (country, localPart)
        }
    }

    // Fallback: Check for local KSA number "05..."
    if phone.starts(with: "05") && phone.count == 10 {
        let localPart = String(phone.dropFirst(1)) // "5..."
        return (ksa, localPart)
    }
    
    // Fallback: Check for local KSA number "5..."
    if phone.starts(with: "5") && phone.count == 9 {
        return (ksa, phone)
    }

    // Default fallback: return KSA and the original string as local
    return (ksa, phone.filter(\.isNumber))
}


// MARK: - Validation Helpers
private func isValidEmail(_ raw: String) -> Bool {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return false }
    if value.contains("..") { return false }
    let pattern = #"^(?![.])([A-Za-z0-9._%+-]{1,64})(?<![.])@([A-Za-z0-9-]{1,63}\.)+[A-Za-z]{2,63}$"#
    return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: value)
}

// COPIED FROM SIGNUP
private func isValidPhone(code: String, local: String) -> Bool {
    guard !local.isEmpty else { return false }
    let len = local.count
    var ok = (6...15).contains(len) // General rule
    
    // KSA-specific rule
    if code == "+966" {
        ok = (len == 9) && local.first == "5"
    }
    return ok
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
    @State private var selectedPost: Post? = nil
    @State private var goToSettings = false
    
    enum PostFilter: String, CaseIterable {
        case all = "All", `public` = "Public", `private` = "Private"
    }
    
    enum PostSort: String, CaseIterable {
        case newestFirst = "Newest", oldestFirst = "Oldest"
    }

    @State private var postFilter: PostFilter = .all
    @State private var postSort: PostSort = .newestFirst

    private var filteredAndSortedPosts: [Post] {
        let filtered: [Post]
        switch postFilter {
        case .all:      filtered = viewModel.posts
        case .public:   filtered = viewModel.posts.filter { !$0.isPrivate }
        case .private:  filtered = viewModel.posts.filter { $0.isPrivate }
        }
        return postSort == .newestFirst ? filtered : filtered.reversed()
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
                .overlay(
                    ScrollView {
                        if viewModel.isLoading {
                            ProgressView().padding(.top, 50)
                        } else {
                            VStack(spacing: 24) {
                                TopNavigationBar(userProfile: viewModel.userProfile,
                                                 showEditProfile: $showEditProfile,
                                                 goToSettings: $goToSettings)
                                ProfileHeaderView(userProfile: viewModel.userProfile)
                                StatsGridView(userProfile: viewModel.userProfile)
                                ContentTabView(selectedContent: $selectedContent)

                                switch selectedContent {
                                case .posts:
                                    postControls
                                    postsGrid
                                case .progress:
                                    ProgressTabView() // Assumed to exist
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
                .onReceive(NotificationCenter.default.publisher(for: .postDeleted)) { note in
                    if let postId = note.userInfo?["postId"] as? String {
                        withAnimation { viewModel.posts.removeAll { $0.id == postId } }
                    }
                }
            // --- ADDED: This block listens for updates from PostDetailView ---
                .onReceive(NotificationCenter.default.publisher(for: .postDataUpdated)) { note in
                    guard let userInfo = note.userInfo,
                          let postId = userInfo["postId"] as? String else { return }

                    // Find the index of the post to update in our main list
                    if let index = viewModel.posts.firstIndex(where: { $0.id == postId }) {
                        
                        // Check for like updates
                        if let (isLiked, likeCount) = userInfo["likeUpdate"] as? (Bool, Int) {
                            withAnimation {
                                viewModel.posts[index].isLikedByUser = isLiked
                                viewModel.posts[index].likeCount = likeCount
                                // Also update the likedBy array for consistency
                                if isLiked {
                                    if let uid = Auth.auth().currentUser?.uid, !viewModel.posts[index].likedBy.contains(uid) {
                                        viewModel.posts[index].likedBy.append(uid)
                                    }
                                } else {
                                    if let uid = Auth.auth().currentUser?.uid {
                                        viewModel.posts[index].likedBy.removeAll { $0 == uid }
                                    }
                                }
                            }
                        }
                        
                        // Check for comment updates
                        if userInfo["commentAdded"] as? Bool == true {
                            withAnimation {
                                viewModel.posts[index].commentCount += 1
                            }
                        }
                    }
                }
                .fullScreenCover(isPresented: $showEditProfile) {
                    EditProfileView(userProfile: viewModel.userProfile)
                }
                .fullScreenCover(isPresented: $goToSettings) {
                    NavigationStack { SettingsView() } // Assumed to exist
                }
                .fullScreenCover(item: $selectedPost) { post in
                    // This now passes the *updated* post object
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
                .font(.caption).foregroundColor(.primary).padding(.horizontal, 10)
                .padding(.vertical, 6).background(Color.black.opacity(0.05)).clipShape(Capsule())
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
                .font(.caption).foregroundColor(.primary).padding(.horizontal, 10)
                .padding(.vertical, 6).background(Color.black.opacity(0.05)).clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var postsGrid: some View {
        LazyVGrid(columns: postColumns, spacing: 12) {
            ForEach(filteredAndSortedPosts) { post in
                Button { selectedPost = post } label: {
                    ZStack(alignment: .topTrailing) {
                        AsyncImage(url: URL(string: post.imageName)) { $0.resizable().aspectRatio(1, contentMode: .fill) }
                        placeholder: { RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.05)).frame(height: 110) }
                        .frame(minWidth: 0, maxWidth: .infinity).clipped()

                        if post.isPrivate {
                            Image(systemName: "lock.fill").font(.caption).foregroundColor(.white)
                                .padding(6).background(Color.red.opacity(0.8)).clipShape(Circle()).padding(8)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.default, value: postFilter)
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        .id(postSort)
        .refreshable { await viewModel.fetchAllData() }
    }
}

// MARK: - Edit Profile View (MODIFIED)
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
    
    // --- MODIFIED: Phone state replaced ---
    @State private var selectedDialCode: CountryDialCode
    @State private var phoneLocal: String
    @State private var phoneNonDigitError = false
    @State private var showDialPicker = false
    // ---
    
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
    
    private let primary = Color(hex: "#36796C")
    private let db = Firestore.firestore()
    private let positions = ["Attacker", "Midfielder", "Defender"]
    
    
    // MARK: - Validation Properties
    private var isEmailFieldValid: Bool { isValidEmail(email) }
    
    // --- MODIFIED: Use new validator ---
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
    
    // --- MODIFIED: Init parses phone number ---
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
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let newImage = UIImage(data: data) {
                    await MainActor.run { self.profileImage = newImage }
                }
            }
        }
        // --- ADDED: Sheet for country code picker ---
        .sheet(isPresented: $showDialPicker) {
            CountryCodePickerSheet(selected: $selectedDialCode, primary: primary)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showInfoOverlay)
    }

    private var header: some View {
        ZStack {
            Text("Edit Profile").font(.custom("Poppins", size: 28)).fontWeight(.medium).foregroundColor(primary)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                        .foregroundColor(primary).padding(10).background(Circle().fill(Color.black.opacity(0.05)))
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
                    Text("Change Picture").font(.custom("Poppins", size: 16)).fontWeight(.semibold).foregroundColor(primary)
                }
                
                if profileImage != nil {
                    Button(role: .destructive) {
                        withAnimation { self.profileImage = nil; self.selectedPhotoItem = nil }
                    } label: {
                        Text("Remove").font(.custom("Poppins", size: 16)).fontWeight(.semibold).foregroundColor(.red)
                    }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // --- MODIFIED: formFields uses new phone UI ---
    private var formFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Name
            field(label: "Name", text: $name, isValid: isNameValid)
            if !name.isEmpty && !isNameValid {
                Text("Please enter a valid name (letters and spaces only).").font(.caption).foregroundColor(.red)
            }
            // Position
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
            
            // Height
            field(label: "Height (cm)", text: $height, keyboardType: .numberPad, isValid: isHeightValid)
            if !height.isEmpty && !isHeightValid {
                Text("Enter a realistic height between 100–230 cm.").font(.caption).foregroundColor(.red)
            }
            
            // Weight
            field(label: "Weight (kg)", text: $weight, keyboardType: .numberPad, isValid: isWeightValid)
            if !weight.isEmpty && !isWeightValid {
                Text("Enter a realistic weight between 15–200 kg.").font(.caption).foregroundColor(.red)
            }
            
            // DOB
            fieldLabel("Date of birth")
            buttonLikeField {
                HStack {
                    Text(dob.map { formatDate($0) } ?? "Select date").font(.custom("Poppins", size: 16)).foregroundColor(dob == nil ? .gray : primary)
                    Spacer()
                    Image(systemName: "calendar").foregroundColor(primary.opacity(0.85))
                }
            } onTap: { tempDOB = dob ?? Date(); showDOBPicker = true }
            .sheet(isPresented: $showDOBPicker) {
                DateWheelPickerSheet(selection: $dob, tempSelection: $tempDOB, showSheet: $showDOBPicker)
                    .presentationDetents([.height(300)]).presentationBackground(.white).presentationCornerRadius(28)
            }
            
            // Location
            fieldLabel("Location")
            buttonLikeField {
                HStack {
                    Text(location.isEmpty ? "Select city" : location).font(.custom("Poppins", size: 16)).foregroundColor(location.isEmpty ? .gray : primary)
                    Spacer()
                    Image(systemName: "chevron.down").foregroundColor(primary.opacity(0.85))
                }
            } onTap: { locationSearch = ""; showLocationPicker = true }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerSheet(title: "Select your city", allCities: SAUDI_CITIES, selection: $location, searchText: $locationSearch, showSheet: $showLocationPicker, accent: primary)
                    .presentationDetents([.large]).presentationBackground(.white).presentationCornerRadius(28)
            }
            
            // Email
            field(label: "Email", text: $email, keyboardType: .emailAddress, isValid: isEmailFieldValid)
            if !email.isEmpty && !isEmailFieldValid {
                Text("Please enter a valid email address.").font(.system(size: 13)).foregroundColor(.red)
            }
            
            // --- MODIFIED: Phone Field ---
            fieldLabel("Phone number")
            roundedField {
                HStack(spacing: 10) {
                    Button { showDialPicker = true } label: {
                        HStack(spacing: 6) {
                            Text(selectedDialCode.code)
                                .font(.custom("Poppins", size: 16))
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
                    .font(.custom("Poppins", size: 16))
                    .foregroundColor(primary)
                    .tint(primary)
                }
            }
            // Error messages for phone
            if phoneNonDigitError {
                Text("Numbers only (0–9).").font(.system(size: 13)).foregroundColor(.red)
            } else if !phoneLocal.isEmpty && !isPhoneNumberValid {
                // Special message for KSA
                if selectedDialCode.code == "+966" {
                    Text("Must be 9 digits and start with 5.").font(.system(size: 13)).foregroundColor(.red)
                } else {
                    Text("Enter a valid phone number.").font(.system(size: 13)).foregroundColor(.red)
                }
            }
            // --- End of Phone Field ---
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
                Text("Update").font(.custom("Poppins", size: 18)).foregroundColor(.white)
                if isSaving { ProgressView().colorInvert().scaleEffect(0.9) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16).background(primary).clipShape(Capsule())
        }
        .disabled(!isFormValid || isSaving)
        .opacity((!isFormValid || isSaving) ? 0.6 : 1.0)
    }

    // --- MODIFIED: saveChanges re-joins the phone number ---
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
                "phone": fullPhone, // MODIFIED
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
                userProfile.phoneNumber = fullPhone // MODIFIED
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
            }
        } catch {
            overlayMessage = "Failed to update profile: \(error.localizedDescription)"
            overlayIsError = true
            showInfoOverlay = true
        }
        isSaving = false
    }
    
    // MARK: - View Helpers
    
    // This helper is for Name, Height, Weight, Email
    private func field(label: String, text: Binding<String>, keyboardType: UIKeyboardType = .default, isValid: Bool) -> some View {
        VStack(alignment: .leading) {
            fieldLabel(label)
            roundedField {
                TextField("", text: text)
                    .font(.custom("Poppins", size: 16)).foregroundColor(primary)
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
            Text(title).font(.custom("Poppins", size: 16)).foregroundColor(.black)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(primary)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title).font(.custom("Poppins", size: 14)).foregroundColor(.gray)
    }

    private func roundedField<Content: View>(@ViewBuilder c: () -> Content) -> some View {
        c()
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(.white)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            )
    }
    
    private func buttonLikeField<Content: View>(@ViewBuilder content: () -> Content, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            content()
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white).shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2))
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
    @Binding var goToSettings: Bool
    var body: some View {
        HStack {
            Button { goToSettings = true } label: {
                Image(systemName: "gearshape").font(.title2).foregroundColor(.primary).padding(8)
            }.buttonStyle(.plain).contentShape(Rectangle())
            Spacer()
            Button { showEditProfile = true } label: {
                Image(systemName: "square.and.pencil").font(.title2).foregroundColor(.primary).padding(8)
            }.buttonStyle(.plain).contentShape(Rectangle())
        }
        .padding(.horizontal, 12).padding(.top, 6)
    }
}

struct ProfileHeaderView: View {
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
    @State private var showContactInfo = false
    
    // MARK: - Stat Groups
    
    // Group 1: User-input player details (5 items)
    private var userInputStats: [PlayerStat] {
        [
            .init(title: "Position", value: userProfile.position),
            .init(title: "Age", value: userProfile.age),
            .init(title: "Weight", value: userProfile.weight),
            .init(title: "Height", value: userProfile.height),
            .init(title: "Residence", value: userProfile.location)
        ]
    }
    
    // Group 2: System-given performance stats (3 items)
    private var givenStats: [PlayerStat] {
        [
            .init(title: "Team", value: userProfile.team),
            .init(title: "Rank", value: userProfile.rank),
            .init(title: "Score", value: userProfile.score)
        ]
    }
    
    // Group 3: Contact info (unchanged)
    private var contactStats: [PlayerStat] {
        var stats: [PlayerStat] = []
        if userProfile.isEmailVisible {
            stats.append(.init(title: "Email", value: userProfile.email))
        }
        if userProfile.isPhoneNumberVisible {
            stats.append(.init(title: "Phone", value: userProfile.phoneNumber))
        }
        return stats
    }
    
    // MARK: - Grid Columns
    
    // 5 columns for the user input details to keep them on one line
    private let userInputGridColumns = [
        GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10),
        GridItem(.flexible()) // 5th column
    ]
    
    // 3 columns for the performance stats
    private let givenGridColumns = [
        GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    
    let accentColor = Color(hex: "#36796C")

    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 24) { // Increased spacing between sections
            
            // --- Section 1: User Input Stats ---
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: userInputGridColumns, spacing: 20) { // Using 5-column grid
                    ForEach(userInputStats) { stat in statItemView(for: stat, alignment: .center) }
                }
            }
            
            // --- Section 2: Given Stats ---
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: givenGridColumns, spacing: 20) { // Using 3-column grid
                    ForEach(givenStats) { stat in statItemView(for: stat, alignment: .center) }
                }
            }
            
            // --- Section 3: Contact Info (Unchanged) ---
            if !contactStats.isEmpty {
                Button(action: { withAnimation(.spring()) { showContactInfo.toggle() } }) {
                    HStack(spacing: 4) {
                        Text(showContactInfo ? "Show less" : "Show contact info")
                        Image(systemName: showContactInfo ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption).fontWeight(.bold).foregroundColor(accentColor).padding(.top, 8)
                }
                if showContactInfo {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(contactStats) { stat in statItemView(for: stat, alignment: .leading) }
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
            Text(stat.value).font(.headline).fontWeight(.semibold)
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
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
    let title: String, type: ContentType
    @Binding var selectedContent: ContentType
    let accentColor: Color, animation: Namespace.ID

    var body: some View {
        Button(action: { withAnimation(.easeInOut) { selectedContent = type } }) {
            VStack(spacing: 8) {
                Text(title).foregroundColor(selectedContent == type ? accentColor : .secondary)
                if selectedContent == type {
                    Rectangle().frame(height: 2).foregroundColor(accentColor)
                        .matchedGeometryEffect(id: "underline", in: animation)
                } else { Color.clear.frame(height: 2) }
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
                Image(endorsement.coachImage).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44).clipShape(Circle())
                VStack(alignment: .leading) {
                    Text(endorsement.coachName).font(.headline).fontWeight(.bold)
                    HStack(spacing: 2) {
                        ForEach(0..<5) { i in
                            Image(systemName: i < endorsement.rating ? "star.fill" : "star")
                                .font(.caption).foregroundColor(.yellow)
                        }
                    }
                }
            }
            Text(endorsement.endorsementText).font(.subheadline).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white).cornerRadius(12).shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct InfoOverlay: View {
    let primary: Color, title: String, isError: Bool
    var onOk: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 50)).foregroundColor(isError ? .red : primary)
                Text(title).font(.custom("Poppins", size: 16)).multilineTextAlignment(.center).padding(.horizontal)
                Button("OK") { onOk() }
                    .font(.custom("Poppins", size: 18)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12).background(primary).clipShape(Capsule())
            }
            .padding(EdgeInsets(top: 30, leading: 20, bottom: 20, trailing: 20))
            .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 10).padding(.horizontal, 40)
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
            Text("Select your position").font(.custom("Poppins", size: 18)).foregroundColor(primary)
                .frame(maxWidth: .infinity).padding(.top, 16)
            Picker("", selection: $tempSelection) {
                ForEach(positions, id: \.self) { pos in Text(pos).tag(pos) }
            }
            .pickerStyle(.wheel).labelsHidden().frame(height: 180)
            Button("Done") { selection = tempSelection; showSheet = false }
                .font(.custom("Poppins", size: 18)).foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12).background(primary)
                .clipShape(Capsule()).padding(.bottom, 16)
        }
        .onAppear { tempSelection = selection.isEmpty ? (positions.first ?? "") : selection }
        .padding(.horizontal, 20)
    }
}

private struct LocationPickerSheet: View {
    let title: String, allCities: [String]
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
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search city")
            .navigationTitle(Text(title))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSheet = false } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 20, weight: .semibold)).foregroundColor(.secondary)
                    }
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
            Text("Select your birth date").font(.custom("Poppins", size: 18)).foregroundColor(primary)
                .frame(maxWidth: .infinity).padding(.top, 16)
            DatePicker("", selection: $tempSelection, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel).labelsHidden().tint(primary).frame(height: 180)
            Button("Done") { selection = tempSelection; showSheet = false }
                .font(.custom("Poppins", size: 18)).foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12).background(primary)
                .clipShape(Capsule()).padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Country code picker (COPIED FROM SIGNUP)
private struct CountryCodePickerSheet: View {
    @Binding var selected: CountryDialCode
    let primary: Color
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    
    // Filtered list based on search query
    var filteredCodes: [CountryDialCode] {
        if query.isEmpty {
            return countryCodes
        }
        return countryCodes.filter {
            $0.name.lowercased().contains(query.lowercased()) ||
            $0.code.contains(query)
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                // Search bar
                TextField("Search Country or Code", text: $query)
                    .autocorrectionDisabled(true)
                    .tint(primary)

                ForEach(filteredCodes, id: \.id) { country in
                    Button {
                        selected = country
                        dismiss()
                    } label: {
                        HStack {
                            Text(country.name)
                            Spacer()
                            Text(country.code)
                                .foregroundColor(.secondary)
                            if country.code == selected.code {
                                Image(systemName: "checkmark")
                                    .foregroundColor(primary)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Select Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }.tint(primary)
                }
            }
        }
    }
}


// MARK: - Saudi cities (Copied from PlayerSetupView)
private let SAUDI_CITIES: [String] = [
    "Riyadh", "Jeddah", "Mecca", "Medina", "Dammam", "Khobar", "Dhahran", "Taif", "Tabuk",
    "Abha", "Khamis Mushait", "Jizan", "Najran", "Hail", "Buraydah", "Unaizah", "Al Hofuf",
    "Al Mubarraz", "Jubail", "Yanbu", "Rabigh", "Al Baha", "Bisha", "Al Majmaah", "Al Zulfi",
    "Sakaka", "Arar", "Qurayyat", "Rafha", "Turaif", "Tarut", "Qatif", "Safwa", "Saihat",
    "Al Khafji", "Al Ahsa", "Al Qassim", "Al Qaisumah", "Sharurah", "Tendaha", "Wadi ad-Dawasir",
    "Al Qurayyat", "Tayma", "Umluj", "Haql", "Al Wajh", "Al Lith", "Al Qunfudhah", "Sabya",
    "Abu Arish", "Samtah", "Baljurashi", "Al Mandaq", "Qilwah", "Al Namas", "Tanomah",
    "Mahd adh Dhahab", "Badr", "Al Ula", "Khaybar", "Al Bukayriyah", "Riyadh Al Khabra",
    "Al Rass", "Diriyah", "Al Kharj", "Hotat Bani Tamim", "Al Hariq", "Wadi Al Dawasir",
    "Afif", "Dawadmi", "Shaqra", "Thadig", "Muzahmiyah", "Rumah", "Ad Dilam", "Al Quwayiyah",
    "Duba", "Turaif", "Ar Ruwais", "Farasan", "Al Dayer", "Fifa", "Al Aridhah", "Al Bahah City",
    "King Abdullah Economic City", "Al Uyaynah", "Al Badayea", "Al Uwayqilah", "Bathaa",
    "Al Jafr", "Thuqbah", "Buqayq (Abqaiq)", "Ain Dar", "Nairyah", "Al Hassa", "Salwa",
    "Ras Tanura", "Khafji", "Manfouha", "Al Muzahmiyah"
].sorted()
