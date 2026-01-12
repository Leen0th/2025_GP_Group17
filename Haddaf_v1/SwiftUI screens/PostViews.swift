import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import AVKit

// MARK: - Post Detail View (MODIFIED)
// Define a SwiftUI view that shows the full details of a single post.
struct PostDetailView: View {
    @Environment(\.dismiss) private var dismiss
    // to check for guest
    @EnvironmentObject var session: AppSession
    
    // Hold a mutable copy of the post so the UI can react to changes.
    @State var post: Post
    // --- for auth prompt ---
    @Binding var showAuthSheet: Bool
    
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    @State private var showPrivacyAlert = false
    @State private var showCommentsSheet = false
    private let accentColor = BrandColors.darkTeal
    
    @State private var isEditingCaption = false
    @State private var editedCaption = ""
    @State private var isSavingCaption = false
    
    @State private var navigateToProfileID: String?
    @State private var navigationTrigger = false
    
    private let captionLimit = 15
    
    // Use the shared reporting service and observe its changes
    @StateObject private var reportService = ReportStateService.shared
    
    // --- ADDED: State for reporting ---
    @State private var itemToReport: ReportableItem?
    
    // Hold a lightweight profile object for the post's author.
    @State private var authorProfile = UserProfile()
    
    private var currentUserID: String? {
        Auth.auth().currentUser?.uid
    }
    // Check whether the current user is the owner of this post.
    private var isOwner: Bool {
        post.authorUid == currentUserID
    }

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            
            NavigationLink(
                destination: PlayerProfileContentView(userID: navigateToProfileID ?? ""),
                isActive: $navigationTrigger
            ) { EmptyView() }
            
            if let postId = post.id, reportService.hiddenPostIDs.contains(postId) {
                VStack {
                    header
                    Spacer()
                    ReportedContentView(type: .post) {
                        reportService.unhidePost(id: postId)
                    }
                    .padding()
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        // Try to build a valid URL from the post's videoURL string.
                        if let videoStr = post.videoURL, let url = URL(string: videoStr) {
                            VideoPlayer(player: AVPlayer(url: url))
                                .frame(height: 250)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
                        } else {
                            VideoPlayerPlaceholderView(post: post)
                        }
                        
                        captionAndMetadata
                        
                        authorInfoAndInteractions
                        
                        Divider()
                        statsSection
                    }
                    .padding(.horizontal)
                }
                .disabled(isDeleting || isSavingCaption)
            }
            
            if showPrivacyAlert {
                PrivacyWarningPopupView(
                    isPresented: $showPrivacyAlert,
                    isPrivate: post.isPrivate,
                    onConfirm: {
                        toggleVisibility()
                    }
                )
            }
            
            if showDeleteConfirmation {
                StyledConfirmationOverlay(
                    isPresented: $showDeleteConfirmation,
                    title: "Delete Post",
                    message: "Deleting this post will remove it and reduce your performance score accordingly. Are you sure you want to proceed?",
                    confirmButtonTitle: "Delete",
                    onConfirm: { Task { await deletePost() } }
                )
            }
            
            if isDeleting {
                Color.black.opacity(0.4).ignoresSafeArea()
                ProgressView("Deleting...")
                    .tint(.white)
                    .foregroundColor(.white)
                    .padding()
                    .background(BrandColors.background.opacity(0.6))
                    .cornerRadius(12)
            }
            
            if showAuthSheet {
                AuthPromptSheet(isPresented: $showAuthSheet)
            }
        }
        .navigationBarBackButtonHidden(true)
        // --- Sheet for reporting ---
        .sheet(item: $itemToReport) { item in
            ReportView(item: item) { reportedID in
                // On complete, tell the shared service to report the post
                reportService.reportPost(id: reportedID)
            }
        }
        // Present the comments sheet when showCommentsSheet is true.
        .sheet(isPresented: $showCommentsSheet) {
            if let postId = post.id {
                CommentsView(
                    postId: postId,
                    onProfileTapped: { userID in
                        navigateToProfileID = userID
                        showCommentsSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            navigationTrigger = true
                        }
                    },
                    showAuthSheet: $showAuthSheet
                )
                .environmentObject(session)
                .presentationBackground(BrandColors.background)
            }
        }
        // Listen for .postDataUpdated notifications to keep this view in sync.
        .onReceive(NotificationCenter.default.publisher(for: .postDataUpdated)) { notification in
            guard let userInfo = notification.userInfo,
                  let updatedPostId = userInfo["postId"] as? String,
                  updatedPostId == post.id else {
                return
            }
            if userInfo["commentAdded"] as? Bool == true {
                post.commentCount += 1
            }
            if userInfo["commentDeleted"] as? Bool == true {
                post.commentCount = max(0, post.commentCount - 1)
            }
            if let (isLiked, likeCount) = userInfo["likeUpdate"] as? (Bool, Int) {
                post.isLikedByUser = isLiked
                post.likeCount = likeCount
            }
        }
        .animation(.easeInOut, value: showPrivacyAlert)
        .animation(.easeInOut, value: showDeleteConfirmation)
        .animation(.easeInOut, value: isEditingCaption)
        .animation(.easeInOut, value: showAuthSheet)
        
        // --- Task to fetch the fresh profile on appear ---
        .task {
            // Load the author's profile from Firestore and update the header.
            await fetchAuthorProfile()
        }
    }

    private var header: some View {
            ZStack {
                Text("Post")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundColor(accentColor)

                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(accentColor)
                            .padding(10)
                            .background(Circle().fill(BrandColors.lightGray.opacity(0.7)))
                    }
                    Spacer()
                    
                    if isOwner {
                        Button { showDeleteConfirmation = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.red)
                                .padding(10)
                                .background(Circle().fill(Color.red.opacity(0.1)))
                        }
                    } else {
                        // It checks the *permanent* reported list.
                        let isReported = (post.id != nil && reportService.reportedPostIDs.contains(post.id!))
                        
                        // --- Report Button Action ---
                        Button {
                            if session.isGuest {
                                showAuthSheet = true
                            } else {
                                itemToReport = ReportableItem(
                                    id: post.id ?? "",
                                    parentId: nil,
                                    type: .post,
                                    contentPreview: post.caption
                                )
                            }
                        } label: {
                            Image(systemName: isReported ? "flag.fill" : "flag") // Dynamic icon
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.red) // Always red
                                .padding(10)
                                .background(Circle().fill(BrandColors.lightGray.opacity(0.7)))
                        }
                        .disabled(isReported)
                }
            }
        }
        .padding(.bottom, 8)
    }
    
    private func deletePost() async {
        isDeleting = true
        // Ensure the post has an ID and there is a logged-in user.
        guard let postId = post.id, let uid = Auth.auth().currentUser?.uid else {
            print("Missing post ID or user ID for deletion.")
            isDeleting = false
            return
        }

        do {
            // --- Get the root reference ---
            let storageRef = Storage.storage().reference()
            
            // Build a reference to the video file path for this post.
            let videoRef = storageRef.child("posts/\(uid)/\(postId).mov")
            let thumbRef = storageRef.child("posts/\(uid)/\(postId)_thumb.jpg")
            
            // Attempt to delete the video file; ignore error if it doesn't exist.
            try? await videoRef.delete()
            try? await thumbRef.delete()
            
            // Delete the post document from the `videoPosts` collection.
            let db = Firestore.firestore()
            try await db.collection("videoPosts").document(postId).delete()
            // Notify the app that this post has been deleted.
            NotificationCenter.default.post(name: .postDeleted, object: nil, userInfo: ["postId": postId])
            dismiss()

        } catch {
            print("Error deleting post: \(error.localizedDescription)")
        }
        isDeleting = false
    }

    private var captionAndMetadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            if isEditingCaption {
                VStack(alignment: .leading, spacing: 8) {
                    
                    HStack(spacing: 6) {
                        Text("Edit Caption")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(editedCaption.count)/\(captionLimit)")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(editedCaption.count > captionLimit ? .red : .secondary)
                    }
                    
                    TextField("Edit Caption", text: $editedCaption)
                        .font(.system(size: 16, design: .rounded))
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(BrandColors.lightGray.opacity(0.7))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                        )
                        .tint(accentColor)
                    
                    HStack(spacing: 12) {
                        Spacer()
                        Button("Cancel") {
                            withAnimation {
                                isEditingCaption = false
                                editedCaption = ""
                            }
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(BrandColors.darkGray)
                        
                        Button {
                            Task { await commitCaptionEdit() }
                        } label: {
                            if isSavingCaption {
                                ProgressView()
                                    .tint(.white)
                                    .frame(height: 19)
                            } else {
                                Text("Save")
                            }
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(accentColor)
                        .cornerRadius(20)
                        .disabled(isSavingCaption || editedCaption.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(isSavingCaption || editedCaption.trimmingCharacters(in: .whitespaces).isEmpty ? 0.7 : 1.0)
                    }
                }
            } else {
                HStack(alignment: .top) {
                    Text(post.caption)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(BrandColors.darkGray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if isOwner {
                        Button {
                            editedCaption = post.caption
                            withAnimation { isEditingCaption = true }
                        } label: {
                            Image(systemName: "pencil.line")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(BrandColors.lightGray)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            if let matchDate = post.matchDate {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text("Match Date: \(formatMatchDate(matchDate))")
                }
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.top, 4)
            }
            
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.and.outline")
                    Text("Post Date: \(formatTimestampString(post.timestamp))")
                }
                
                Spacer()
                
                if isOwner {
                    Button(action: { showPrivacyAlert = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: post.isPrivate ? "lock.fill" : "lock.open.fill")
                            Text(post.isPrivate ? "Private" : "Public")
                        }
                        .foregroundColor(post.isPrivate ? .red : accentColor)
                    }
                }
            }
            .font(.system(size: 12, design: .rounded))
            .foregroundColor(.secondary)
            .padding(.top, 4)
        }
        .padding()
        .background(BrandColors.background)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        .onChange(of: editedCaption) { _, newVal in
            if newVal.count > captionLimit {
                editedCaption = String(newVal.prefix(captionLimit))
            }
        }
    }

    private var authorInfoAndInteractions: some View {
        HStack {
            if let uid = post.authorUid, !uid.isEmpty {
                NavigationLink(destination: PlayerProfileContentView(userID: uid)) {
                    authorHeaderContent
                }
                .buttonStyle(.plain)
            } else {
                authorHeaderContent
            }
            
            Spacer()
            
            // --- Like Button Action ---
            Button {
                if session.isGuest {
                    showAuthSheet = true
                } else {
                    Task { await toggleLike() }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: post.isLikedByUser ? "heart.fill" : "heart")
                    Text(formatNumber(post.likeCount))
                }
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(post.isLikedByUser ? .red : BrandColors.darkGray)
            }
            
            // --- Comment Button Action ---
            Button {
                if session.isGuest {
                    showAuthSheet = true
                } else {
                    showCommentsSheet = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "message")
                    Text("\(post.commentCount)")
                }
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(BrandColors.darkGray)
            }
        }
        .foregroundColor(.primary)
    }
    
    // --- Helper view to display the fresh profile info ---
    @ViewBuilder
    private var authorHeaderContent: some View {
        HStack(spacing: 8) {
            if let image = authorProfile.profileImage {
                Image(uiImage: image)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40).clipShape(Circle())
            } else {
                // Placeholder
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .foregroundColor(BrandColors.lightGray)
            }
            // This will show "Loading..." then update to the fresh name
            Text(authorProfile.name)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(BrandColors.darkGray)
        }
    }
    
    // --- Function to fetch the author's profile ---
    private func fetchAuthorProfile() async {
        guard let uid = post.authorUid else { return }
        
        // We only fetch the parts we need for the header (name, image)
        do {
            let db = Firestore.firestore()
            // Read the document for this user from the `users` collection.
            let userDoc = try await db.collection("users").document(uid).getDocument()
            let data = userDoc.data() ?? [:]

            let first = (data["firstName"] as? String) ?? ""
            let last  = (data["lastName"]  as? String) ?? ""
            let full  = [first, last].joined(separator: " ").trimmingCharacters(in: .whitespaces)

            let loadedProfile = UserProfile()
            loadedProfile.name = full.isEmpty ? "Player" : full

            // Asynchronous image fetching
            if let urlStr = data["profilePic"] as? String, !urlStr.isEmpty {
                loadedProfile.profileImage = await fetchImage(from: urlStr)
            } else {
                loadedProfile.profileImage = UIImage(systemName: "person.circle.fill")
            }
            
            // Update the state on the main thread
            await MainActor.run {
                self.authorProfile = loadedProfile
            }

        } catch {
            print("PostDetailView: fetchAuthorProfile error: \(error)")
        }
    }
    
    // --- Image fetching helper ---
    private func fetchImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return UIImage(systemName: "person.circle.fill") }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data) ?? UIImage(systemName: "person.circle.fill")
        } catch {
            print("PostDetailView: fetchImage error: \(error)")
            return UIImage(systemName: "person.circle.fill")
        }
    }

    private func commitCaptionEdit() async {
        guard let postId = post.id else { return }
        let newCaption = editedCaption.trimmingCharacters(in: .whitespaces)
        if newCaption.isEmpty {
            withAnimation { isEditingCaption = false; editedCaption = "" }
            return
        }
        isSavingCaption = true
        do {
            let db = Firestore.firestore()
            try await db.collection("videoPosts").document(postId).updateData(["caption": newCaption])
            post.caption = newCaption
            withAnimation { isEditingCaption = false }
        } catch {
            print("Error updating caption: \(error.localizedDescription)")
        }
        isSavingCaption = false
    }

    private func toggleLike() async {
        // --- Guard for guest users ---
        guard let postId = post.id, let uid = Auth.auth().currentUser?.uid, !session.isGuest else { return }
        
        let isLiking = !post.isLikedByUser
        let delta: Int64 = isLiking ? 1 : -1
        let firestoreAction = isLiking ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid])
        post.isLikedByUser = isLiking
        post.likeCount += Int(delta)
        if isLiking { post.likedBy.append(uid) }
        else { post.likedBy.removeAll { $0 == uid } }
        do {
            // Send the like update to Firestore: increment count and modify likedBy array.
            try await Firestore.firestore().collection("videoPosts").document(postId).updateData([
                "likeCount": FieldValue.increment(delta), "likedBy": firestoreAction
            ])
            // Build a userInfo dictionary to broadcast the new like state.
            var userInfo: [String: Any] = ["postId": postId]
            userInfo["likeUpdate"] = (isLiking, post.likeCount)
            // Post a notification so other views can update their UI.
            NotificationCenter.default.post(name: .postDataUpdated, object: nil, userInfo: userInfo)
        } catch {
            print("Error updating like count: \(error.localizedDescription)")
            post.isLikedByUser = !isLiking
            post.likeCount -= Int(delta)
            if isLiking { post.likedBy.removeAll { $0 == uid } }
            else { post.likedBy.append(uid) }
        }
    }
    
    private func toggleVisibility() {
        post.isPrivate.toggle()
        Task {
            guard let postId = post.id else { return }
            do {
                // Update the `visibility` field to the inverse of isPrivate.
                try await Firestore.firestore().collection("videoPosts").document(postId)
                    .updateData(["visibility": !post.isPrivate])
            } catch {
                print("Error updating post visibility: \(error.localizedDescription)")
                post.isPrivate.toggle()
            }
        }
    }
    
    private func formatTimestampString(_ timestampString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "dd/MM/yyyy HH:mm"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        if let date = inputFormatter.date(from: timestampString) {
            return formatMatchDate(date)
        } else {
            return timestampString
        }
    }
    
    private func formatMatchDate(_ date: Date) -> String {
        let df_dateOnly = DateFormatter()
        df_dateOnly.dateFormat = "MMM d, yyyy"
        return df_dateOnly.string(from: date)
    }

    @ViewBuilder
    private var statsSection: some View {
        if let stats = post.stats, !stats.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("AI Performance Analysis")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)
                    .padding(.bottom, 4)
                
                ForEach(stats) { stat in
                    PostStatBarView(stat: stat, accentColor: accentColor)
                }
            }
            .padding(20)
            .background(BrandColors.background)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        } else {
            EmptyView()
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1000 {
            return String(format: "%.1fK", Double(number) / 1000.0)
        } else {
            return "\(number)"
        }
    }
}

// MARK: - Comments Sheet View (Lifecycle Fix)

struct CommentsView: View {
    let postId: String
    var onProfileTapped: (String) -> Void
    
    @StateObject private var viewModel = CommentsViewModel()
    @Environment(\.dismiss) private var dismiss
    // To check for guests
    @EnvironmentObject var session: AppSession
    
    // --- for auth prompt ---
    @Binding var showAuthSheet: Bool
    
    @State private var newCommentText = ""
    private let accentColor = BrandColors.darkTeal
    
    // Use the shared reporting service and observe its changes
    @StateObject private var reportService = ReportStateService.shared
    
    // --- In-Place Editing State ---
    @State private var editingCommentID: String? = nil
    @State private var editingCommentText: String = ""
    private let commentLimit = 100 // Set a reasonable limit
    
    @State private var showDeleteAlert = false
    @State private var commentToDelete: Comment?
    
    // --- State for reporting ---
    @State private var itemToReport: ReportableItem?

    var body: some View {
        VStack(spacing: 0) {
            // --- Header ---
            HStack {
                Spacer()
                Text("Comments")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.subheadline.bold()) }
            }
            .padding()
            .background(BrandColors.background)
            .overlay(Divider(), alignment: .bottom)

            // --- Scrollable Comments List ---
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(accentColor)
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    } else if viewModel.comments.isEmpty {
                         Text("No comments yet. Be the first!")
                            .font(.system(size: 16, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(viewModel.comments) { comment in
                            // Check if this comment is hidden in the report service.
                            if let commentId = comment.id, reportService.hiddenCommentIDs.contains(commentId) {
                                // If hidden, show the placeholder for reported content.
                                ReportedContentView(type: .comment) {
                                    reportService.unhideComment(id: commentId)
                                }
                                .padding(.horizontal)
                            } else {
                                let authorProfile = viewModel.authorProfiles[comment.userId] ?? UserProfile()
                                
                                CommentRowView(
                                    comment: comment,
                                    authorProfile: authorProfile,
                                    isEditing: editingCommentID == comment.id,
                                    editingText: $editingCommentText,
                                    commentLimit: commentLimit,
                                    onProfileTapped: onProfileTapped,
                                    onEdit: {
                                        viewModel.stopListening()
                                        editingCommentID = comment.id
                                        editingCommentText = comment.text
                                    },
                                    // Callback when the user requests to delete this comment.
                                    onDelete: {
                                        // Store the comment we want to delete.
                                        commentToDelete = comment
                                        // Show the system alert to confirm deletion.
                                        showDeleteAlert = true
                                    },
                                    onSave: {
                                        Task {
                                            await viewModel.editComment(comment, newText: editingCommentText, from: postId)
                                        }
                                        editingCommentID = nil
                                        viewModel.fetchComments(for: postId) // Restart listener
                                    },
                                    onCancel: {
                                        editingCommentID = nil
                                        viewModel.fetchComments(for: postId) // Restart listener
                                    },
                                    onReport: {
                                        // Create a report item so we can open the report sheet.
                                        itemToReport = ReportableItem(
                                            id: comment.id ?? "",
                                            parentId: postId,
                                            type: .comment,
                                            contentPreview: comment.text
                                        )
                                    },
                                    // Pass the shared report service so the row can read report state.
                                    reportService: reportService,
                                    showAuthSheet: $showAuthSheet
                                )
                                .environmentObject(session)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(BrandColors.backgroundGradientEnd)
            .onAppear {
                viewModel.fetchComments(for: postId)
            }
            .onDisappear {
                viewModel.stopListening()
            }
            // --- Sheet for reporting ---
            .sheet(item: $itemToReport) { item in
                ReportView(item: item) { reportedID in
                    // On complete, tell the shared service to report the comment
                    reportService.reportComment(id: reportedID)
                }
            }
            
            // --- Comment Input Area ---
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 12) {
                    ZStack {
                        TextField(session.isGuest ? "Sign in to comment" : "Write Comment...", text: $newCommentText)
                            .font(.system(size: 15, design: .rounded))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(BrandColors.lightGray).clipShape(Capsule())
                            .tint(accentColor)
                            .disabled(session.isGuest)
                        
                        if session.isGuest {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { showAuthSheet = true }
                        }
                    }

                    Button(action: addComment) {
                        Image(systemName: "paperplane.fill")
                            .font(.title2).foregroundColor(accentColor)
                    }
                    // MODIFIED: Disable if empty OR exceeds limit
                    .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty || newCommentText.count > commentLimit || session.isGuest)
                    .opacity((newCommentText.count > commentLimit || session.isGuest) ? 0.5 : 1.0)
                }
                
                // Character Counter for New Comment
                if !newCommentText.isEmpty {
                    Text("\(newCommentText.count)/\(commentLimit)")
                        .font(.caption)
                        .foregroundColor(newCommentText.count > commentLimit ? .red : .secondary)
                        .padding(.trailing, 50) // Align roughly with text field
                }
            }
            .opacity(session.isGuest ? 0.7 : 1.0)
            .padding()
            .background(BrandColors.background)
        }
        // --- Custom overlay for delete confirmation ---
        .overlay(
            ZStack {
                if showDeleteAlert {
                    StyledConfirmationOverlay(
                        isPresented: $showDeleteAlert,
                        title: "Delete Comment?",
                        message: "Are you sure you want to delete this comment?",
                        confirmButtonTitle: "Delete",
                        onConfirm: {
                            if let comment = commentToDelete {
                                Task {
                                    await viewModel.deleteComment(comment, from: postId)
                                }
                            }
                        }
                    )
                }
            }
            .animation(.easeInOut, value: showDeleteAlert)
        )
        // Add listener for character limit on in-place editor
        .onChange(of: editingCommentText) { _, newVal in
            if newVal.count > commentLimit {
                editingCommentText = String(newVal.prefix(commentLimit))
            }
        }
    }

    private func addComment() {
        // --- Guard for guest users ---
        guard !session.isGuest else { return }
        
        let trimmed = newCommentText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task {
            await viewModel.addComment(text: trimmed, for: postId)
            newCommentText = ""
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}


// MARK: - Comments View Model

final class CommentsViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    @Published var isLoading = true
    
    @Published var authorProfiles: [String: UserProfile] = [:]
    
    // Firestore database reference used for all comment operations.
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private let lock = NSLock()

    deinit {
        stopListening()
    }

    func fetchComments(for postId: String) {
        stopListening()
        isLoading = true
        // Build a Firestore query to fetch comments ordered by creation time.
        let ref = db.collection("videoPosts").document(postId).collection("comments").order(by: "createdAt", descending: false)
        
        let newListener = ref.addSnapshotListener { [weak self] snap, error in
            guard let self, let snap = snap else {
                print("Error fetching comments: \(error?.localizedDescription ?? "Unknown error")")
                self?.isLoading = false
                return
            }
            
            self.comments = snap.documents.compactMap { doc in
                try? doc.data(as: Comment.self)
            }
            
            let allUIDs = Set(self.comments.compactMap { $0.userId })
            self.fetchAuthorProfiles(for: Array(allUIDs))
            
            self.isLoading = false
        }
        
        lock.lock()
        self.listener = newListener
        lock.unlock()
    }
    
    func stopListening() {
        lock.lock()
        listener?.remove()
        listener = nil
        lock.unlock()
        print("Comments listener stopped.")
    }
    // Add a new comment document under the specified post in Firestore.
    func addComment(text: String, for postId: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // --- This guard protects against guests (uid will be nil) ---
        guard !trimmed.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
        do {

            let commentData: [String: Any] = [
                "text": trimmed,
                "userId": uid,
                "createdAt": FieldValue.serverTimestamp()
            ]

            let postRef = db.collection("videoPosts").document(postId)
            let commentRef = postRef.collection("comments").document()
            
            let batch = db.batch()
            batch.setData(commentData, forDocument: commentRef)
            batch.updateData(["commentCount": FieldValue.increment(Int64(1))], forDocument: postRef)
            try await batch.commit()
            
            // Post a notification so other views know a comment was added.
            NotificationCenter.default.post(name: .postDataUpdated, object: nil, userInfo: [
                "postId": postId,
                "commentAdded": true
            ])
            
        } catch {
            print("Failed to add comment: \(error)")
        }
    }
    
    @MainActor
    func editComment(_ comment: Comment, newText: String, from postId: String) async {
        let trimmedText = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let commentId = comment.id, !trimmedText.isEmpty else {
            print("Error: Comment ID is missing or text is empty.")
            return
        }
        
        if let index = self.comments.firstIndex(where: { $0.id == commentId }) {
            self.comments[index].text = trimmedText
        }
        
        do {
            let commentRef = db.collection("videoPosts").document(postId).collection("comments").document(commentId)
            // Update only the text field of this comment.
            try await commentRef.updateData(["text": trimmedText])
        } catch {
            print("Error editing comment: \(error.localizedDescription)")
        }
    }
    // Delete a comment document and decrement the parent post's commentCount.
    @MainActor
    func deleteComment(_ comment: Comment, from postId: String) async {
        guard let commentId = comment.id else {
            print("Error: Comment ID is missing.")
            return
        }
        
        self.comments.removeAll(where: { $0.id == commentId })
        
        do {
            let postRef = db.collection("videoPosts").document(postId)
            let commentRef = postRef.collection("comments").document(commentId)
            
            let batch = db.batch()
            batch.deleteDocument(commentRef)
            batch.updateData(["commentCount": FieldValue.increment(Int64(-1))], forDocument: postRef)
            
            try await batch.commit()
            
            NotificationCenter.default.post(name: .postDataUpdated, object: nil, userInfo: [
                "postId": postId,
                "commentDeleted": true
            ])
            
        } catch {
            print("Error deleting comment: \(error.localizedDescription)")
            fetchComments(for: postId) // Re-fetch to correct UI
        }
    }
    
    // --- profile fetching logic ---
    private func fetchAuthorProfiles(for uids: [String]) {
        let uidsToFetch = uids.filter { !$0.isEmpty && self.authorProfiles[$0] == nil }
        guard !uidsToFetch.isEmpty else { return }
        
        for uid in uidsToFetch {
            Task {
                await self.fetchAuthorProfile(uid: uid)
            }
        }
    }

    private func fetchAuthorProfile(uid: String) async {
        guard !uid.isEmpty, self.authorProfiles[uid] == nil else { return }
        
        do {
            let userDoc = try await db.collection("users").document(uid).getDocument()
            let data = userDoc.data() ?? [:]
            let first = (data["firstName"] as? String) ?? ""
            let last = (data["lastName"] as? String) ?? ""
            let full = [first, last].joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let profilePicUrl = (data["profilePic"] as? String) ?? ""

            let profile = UserProfile()
            profile.name = full.isEmpty ? "Player" : full

            if !profilePicUrl.isEmpty {
                profile.profileImage = await fetchImage(from: profilePicUrl)
            } else {
                profile.profileImage = UIImage(systemName: "person.circle.fill")
            }

            await MainActor.run {
                self.authorProfiles[uid] = profile
            }
        } catch {
            print("fetchAuthorProfile error for UID \(uid): \(error)")
        }
    }

    private func fetchImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return UIImage(systemName: "person.circle.fill") }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data) ?? UIImage(systemName: "person.circle.fill")
        } catch {
            return UIImage(systemName: "person.circle.fill")
        }
    }
}


// MARK: - Helper Views (Styling Update)
// View representing a single comment row, including avatar, text, and actions.
fileprivate struct CommentRowView: View {
    let comment: Comment
    let authorProfile: UserProfile
    let isEditing: Bool
    @Binding var editingText: String
    let commentLimit: Int
    
    var onProfileTapped: (String) -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onSave: () -> Void
    var onCancel: () -> Void
    var onReport: () -> Void
    
    @ObservedObject var reportService: ReportStateService
    // To check for guests
    @EnvironmentObject var session: AppSession
    // --- for auth prompt ---
    @Binding var showAuthSheet: Bool
    
    private var currentUserID: String? { Auth.auth().currentUser?.uid }
    private var isOwner: Bool { comment.userId == currentUserID }
    private let accentColor = BrandColors.darkTeal
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            
            Button(action: {
                onProfileTapped(comment.userId)
            }) {
                if let image = authorProfile.profileImage {
                    Image(uiImage: image)
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40).clipShape(Circle())
                } else {
                    Circle().fill(BrandColors.lightGray).frame(width: 40, height: 40)
                }
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                // --- 1. USERNAME/TIMESTAMP (always visible) ---
                HStack(spacing: 8) {
                    Button(action: {
                        onProfileTapped(comment.userId)
                    }) {
                        Text(authorProfile.name)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(BrandColors.darkGray)
                    }
                    .buttonStyle(.plain)
                    
                    Text(comment.timestamp)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                // --- 2. IN-PLACE EDITOR ---
                if isEditing {
                    VStack(alignment: .leading, spacing: 8) {
                        // --- TextEditor ---
                        TextEditor(text: $editingText)
                            .font(.system(size: 15, design: .rounded))
                            .textInputAutocapitalization(.sentences)
                            .disableAutocorrection(true)
                            .padding(8)
                            .frame(minHeight: 80)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(BrandColors.lightGray.opacity(0.7))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                            )
                            .tint(accentColor)
                        
                        // --- Controls ---
                        HStack(spacing: 12) {
                            Spacer()
                            Text("\(editingText.count)/\(commentLimit)")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(editingText.count > commentLimit ? .red : .secondary)
                            
                            Button("Cancel") {
                                withAnimation { onCancel() }
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(BrandColors.darkGray)
                            
                            Button("Save") {
                                withAnimation { onSave() }
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(accentColor)
                            .cornerRadius(20)
                            .disabled(editingText.trimmingCharacters(in: .whitespaces).isEmpty || editingText.count > commentLimit)
                            .opacity((editingText.trimmingCharacters(in: .whitespaces).isEmpty || editingText.count > commentLimit) ? 0.7 : 1.0)
                        }
                    }
                } else {
                    Text(comment.text)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(BrandColors.darkGray)
                }
            }
            
            Spacer()
            
        
            if isOwner && !isEditing {
                Menu {
                    Button(action: {
                        withAnimation { onEdit() }
                    }) {
                        Label("Edit Comment", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Comment", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .tint(.secondary)
            }
            else if !isOwner {
                // It checks the *permanent* reported list.
                let isReported = (comment.id != nil && reportService.reportedCommentIDs.contains(comment.id!))
                
                // --- Report Button Action ---
                Button {
                    if session.isGuest {
                        showAuthSheet = true
                    } else {
                        onReport()
                    }
                } label: {
                    Image(systemName: isReported ? "flag.fill" : "flag")
                        .font(.caption)
                        .foregroundColor(.red) // Always red
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // --- Disable only if already reported ---
                .disabled(isReported)
            }
        }
        .animation(.easeInOut, value: isEditing)
    }
}

struct VideoPlayerPlaceholderView: View {
    let post: Post
    var body: some View {
        ZStack {
            AsyncImage(url: URL(string: post.imageName)) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: { Color.black }
            .frame(height: 250).background(Color.black).clipped()
            Color.black.opacity(0.3)
            Image(systemName: "play.fill").font(.system(size: 40)).foregroundColor(.white)
        }
        .frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }
}

struct PostStatBarView: View {
    let stat: PostStat
    let accentColor: Color
    
    let gradient: LinearGradient
    
    init(stat: PostStat, accentColor: Color) {
        self.stat = stat
        self.accentColor = accentColor
        
        switch stat.label.lowercased() {
        case "dribble":
            self.gradient = LinearGradient(colors: [BrandColors.turquoise.opacity(0.7), BrandColors.turquoise], startPoint: .leading, endPoint: .trailing)
        case "pass":
            self.gradient = LinearGradient(colors: [BrandColors.teal.opacity(0.7), BrandColors.teal], startPoint: .leading, endPoint: .trailing)
        case "shoot":
            self.gradient = LinearGradient(colors: [BrandColors.actionGreen.opacity(0.7), BrandColors.actionGreen], startPoint: .leading, endPoint: .trailing)
        default:
            self.gradient = LinearGradient(colors: [accentColor.opacity(0.7), accentColor], startPoint: .leading, endPoint: .trailing)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stat.label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(stat.value))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BrandColors.lightGray)
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(gradient)
                        .frame(width: (geometry.size.width * CGFloat(stat.value) / CGFloat(stat.maxValue)), height: 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: stat.value)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Popup Views (Styling Update)
struct PrivacyWarningPopupView: View {
    @Binding var isPresented: Bool
    let isPrivate: Bool
    let onConfirm: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { withAnimation { isPresented = false } }.transition(.opacity)
            VStack(spacing: 20) {
                Text("Change Visibility?")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(isPrivate ? "Making this post public will allow everyone to see it and increase your score." : "Making this post private will hide it from other users and reduce your score.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                
                HStack(spacing: 16) {
                    Button("Cancel") { withAnimation { isPresented = false } }
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(BrandColors.darkGray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BrandColors.lightGray)
                        .cornerRadius(12)
                    
                    Button("Confirm") { withAnimation { onConfirm(); isPresented = false } }
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                }.padding(.top, 4)
            }
            .padding(EdgeInsets(top: 24, leading: 24, bottom: 20, trailing: 24))
            .frame(width: 320)
            .background(BrandColors.background)
            .cornerRadius(20)
            .shadow(radius: 12)
            .transition(.scale)
        }
    }
}

struct StyledConfirmationOverlay: View {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let confirmButtonTitle: String
    let onConfirm: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { isPresented = false }
            
            VStack(spacing: 20) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                
                Text(message)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                
                HStack(spacing: 16) {
                    Button("Cancel") { isPresented = false }
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(BrandColors.darkGray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BrandColors.lightGray)
                        .cornerRadius(12)
                    
                    Button(confirmButtonTitle) { onConfirm(); isPresented = false }
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .cornerRadius(12)
                }.padding(.top, 4)
            }
            .padding(EdgeInsets(top: 24, leading: 24, bottom: 20, trailing: 24))
            .frame(width: 320)
            .background(BrandColors.background)
            .cornerRadius(20).shadow(radius: 12)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
