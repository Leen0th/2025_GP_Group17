import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import AVKit

// MARK: - Post Detail View (MODIFIED)
struct PostDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State var post: Post
    
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    @State private var showPrivacyAlert = false
    @State private var showCommentsSheet = false
    private let accentColor = Color(hex: "#36796C")
    
    @State private var isEditingCaption = false
    @State private var editedCaption = ""
    @State private var isSavingCaption = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    
                    if let videoStr = post.videoURL, let url = URL(string: videoStr) {
                        VideoPlayer(player: AVPlayer(url: url))
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
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
            .navigationBarBackButtonHidden(true)
            .disabled(isDeleting || isSavingCaption)

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
                DeleteConfirmationOverlay(
                    isPresented: $showDeleteConfirmation,
                    onConfirm: { Task { await deletePost() } }
                )
            }
            
            if isDeleting {
                Color.black.opacity(0.4).ignoresSafeArea()
                ProgressView("Deleting...")
                    .tint(.white)
                    .foregroundColor(.white)
                    .padding()
                    .background(.black.opacity(0.6))
                    .cornerRadius(12)
            }
        }
        .sheet(isPresented: $showCommentsSheet) {
            if let postId = post.id {
                CommentsView(postId: postId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .postDataUpdated)) { notification in
            guard let userInfo = notification.userInfo,
                  let updatedPostId = userInfo["postId"] as? String,
                  updatedPostId == post.id else {
                return
            }
            
            if userInfo["commentAdded"] as? Bool == true {
                post.commentCount += 1
            }
            
            if let (isLiked, likeCount) = userInfo["likeUpdate"] as? (Bool, Int) {
                post.isLikedByUser = isLiked
                post.likeCount = likeCount
            }
        }
        .animation(.easeInOut, value: showPrivacyAlert)
        .animation(.easeInOut, value: showDeleteConfirmation)
        .animation(.easeInOut, value: isEditingCaption)
    }

    private var header: some View {
        ZStack {
            Text("Post")
                .font(.custom("Poppins", size: 28))
                .fontWeight(.medium)
                .foregroundColor(accentColor)

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(accentColor)
                        .padding(10)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                }
                Spacer()
                Button { showDeleteConfirmation = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.red)
                        .padding(10)
                        .background(Circle().fill(Color.red.opacity(0.1)))
                }
            }
        }
        .padding(.bottom, 8)
    }
    
    private func deletePost() async {
        isDeleting = true
        guard let postId = post.id, let uid = Auth.auth().currentUser?.uid else {
            print("Missing post ID or user ID for deletion.")
            isDeleting = false
            return
        }

        do {
            let storageRef = Storage.storage().reference()
            let videoRef = storageRef.child("posts/\(uid)/\(postId).mov")
            let thumbRef = storageRef.child("posts/\(uid)/\(postId)_thumb.jpg")

            try? await videoRef.delete()
            try? await thumbRef.delete()

            let db = Firestore.firestore()
            try await db.collection("videoPosts").document(postId).delete()

            NotificationCenter.default.post(name: .postDeleted, object: nil, userInfo: ["postId": postId])
            dismiss()

        } catch {
            print("Error deleting post: \(error.localizedDescription)")
        }
        isDeleting = false
    }

    // --- MODIFIED: captionAndMetadata ---
    private var captionAndMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            // --- CAPTION SECTION ---
            if isEditingCaption {
                // --- EDITING VIEW ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("Edit Caption")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $editedCaption)
                        .font(.headline)
                        .frame(minHeight: 80, maxHeight: 200)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .tint(accentColor)
                    
                    HStack(spacing: 12) {
                        Spacer()
                        Button("Cancel") {
                            withAnimation {
                                isEditingCaption = false
                                editedCaption = "" // Clear temp state
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        
                        Button {
                            Task { await commitCaptionEdit() }
                        } label: {
                            if isSavingCaption {
                                ProgressView()
                                    .tint(.white)
                                    .frame(height: 19) // Match text height
                            } else {
                                Text("Save")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
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
                // --- DISPLAY VIEW ---
                HStack(alignment: .top) {
                    Text(post.caption)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Button {
                        editedCaption = post.caption
                        withAnimation {
                            isEditingCaption = true
                        }
                    } label: {
                        Image(systemName: "pencil.line")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // --- METADATA SECTION ---
            
            // --- MODIFIED: Match Date ---
            if let matchDate = post.matchDate, !isEditingCaption {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    // --- Call our new helper function ---
                    Text("Match Date: \(formatMatchDate(matchDate))")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            }
            
            // --- Original Timestamp & Privacy ---
            HStack(spacing: 8) {
                Text("Created at: \(post.timestamp)")
                Spacer()
                Button(action: { showPrivacyAlert = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: post.isPrivate ? "lock.fill" : "lock.open.fill")
                        Text(post.isPrivate ? "Private" : "Public")
                    }
                    .foregroundColor(post.isPrivate ? .red : accentColor)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 4)
        }
    }

    private var authorInfoAndInteractions: some View {
        HStack {
            AsyncImage(url: URL(string: post.authorImageName)) { image in
                image.resizable().aspectRatio(contentMode: .fill).frame(width: 40, height: 40).clipShape(Circle())
            } placeholder: {
                Circle().fill(.gray.opacity(0.1)).frame(width: 40, height: 40)
            }
            Text(post.authorName).font(.headline).fontWeight(.bold)
            Spacer()
            Button(action: { Task { await toggleLike() } }) {
                HStack(spacing: 4) {
                    Image(systemName: post.isLikedByUser ? "heart.fill" : "heart")
                    Text(formatNumber(post.likeCount))
                }
                .foregroundColor(post.isLikedByUser ? .red : .primary)
            }
            Button(action: { showCommentsSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "message")
                    Text("\(post.commentCount)")
                }
            }
        }
        .font(.subheadline)
        .foregroundColor(.primary)
    }

    private func commitCaptionEdit() async {
        guard let postId = post.id else {
            print("Missing post ID for saving caption.")
            return
        }
        
        let newCaption = editedCaption.trimmingCharacters(in: .whitespaces)
        if newCaption.isEmpty {
            withAnimation {
                isEditingCaption = false
                editedCaption = ""
            }
            return
        }
        
        isSavingCaption = true
        
        do {
            let db = Firestore.firestore()
            try await db.collection("videoPosts").document(postId).updateData([
                "caption": newCaption
            ])
            
            post.caption = newCaption
            withAnimation {
                isEditingCaption = false
            }
            
        } catch {
            print("Error updating caption: \(error.localizedDescription)")
        }
        
        isSavingCaption = false
    }

    private func toggleLike() async {
        guard let postId = post.id, let uid = Auth.auth().currentUser?.uid else { return }
        
        let isLiking = !post.isLikedByUser
        let delta: Int64 = isLiking ? 1 : -1
        let firestoreAction = isLiking ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid])

        post.isLikedByUser = isLiking
        post.likeCount += Int(delta)
        
        // --- Update local likedBy array for consistency ---
        if isLiking {
            post.likedBy.append(uid)
        } else {
            post.likedBy.removeAll { $0 == uid }
        }

        do {
            try await Firestore.firestore().collection("videoPosts").document(postId).updateData([
                "likeCount": FieldValue.increment(delta),
                "likedBy": firestoreAction
            ])
            
            var userInfo: [String: Any] = ["postId": postId]
            userInfo["likeUpdate"] = (isLiking, post.likeCount)
            NotificationCenter.default.post(name: .postDataUpdated, object: nil, userInfo: userInfo)
            
        } catch {
            print("Error updating like count: \(error.localizedDescription)")
            post.isLikedByUser = !isLiking
            post.likeCount -= Int(delta)
            // --- Revert local likedBy array ---
            if isLiking {
                post.likedBy.removeAll { $0 == uid }
            } else {
                post.likedBy.append(uid)
            }
        }
    }
    
    private func toggleVisibility() {
        post.isPrivate.toggle()

        Task {
            guard let postId = post.id else { return }
            do {
                try await Firestore.firestore()
                    .collection("videoPosts")
                    .document(postId)
                    .updateData(["visibility": !post.isPrivate])
            } catch {
                print("Error updating post visibility: \(error.localizedDescription)")
                post.isPrivate.toggle()
            }
        }
    }
    
    // --- ADDED: Helper function to fix the error ---
    private func formatMatchDate(_ date: Date) -> String {
        let df_dateOnly = DateFormatter()
        df_dateOnly.dateFormat = "MMM d, yyyY" // e.g. "Oct 23, 2025"
        return df_dateOnly.string(from: date)
    }

    // MARK: - Static Placeholder Stats Section
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(placeholderStats) { stat in
                PostStatBarView(stat: stat, accentColor: accentColor)
            }
        }
    }

    // MARK: - Placeholder Stats (Fixed Values)
    private var placeholderStats: [PostStat] {
        [
            PostStat(label: "DRIBBLE",           value: 4),
            PostStat(label: "PASS",  value: 5),
            PostStat(label: "SHOOT",         value: 3)
        ]
    }


    private func formatNumber(_ number: Int) -> String {
        if number >= 1000 {
            return String(format: "%.1fK", Double(number) / 1000.0)
        } else {
            return "\(number)"
        }
    }
}

// MARK: - Comments Sheet View (Unchanged)
struct CommentsView: View {
    let postId: String
    @StateObject private var viewModel = CommentsViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var newCommentText = ""
    private let accentColor = Color(hex: "#36796C")

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Comments").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.subheadline.bold()) }
            }
            .padding().overlay(Divider(), alignment: .bottom)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(viewModel.comments) { comment in CommentRowView(comment: comment) }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack(spacing: 12) {
                TextField("Write Comment...", text: $newCommentText)
                    .padding(.horizontal).padding(.vertical, 10)
                    .background(Color(.systemGray6)).clipShape(Capsule())
                Button(action: addComment) { Image(systemName: "paperplane.fill").font(.title2).foregroundColor(accentColor) }
                    .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding().background(.white)
        }
        .onAppear { viewModel.fetchComments(for: postId) }
        .onDisappear { viewModel.stopListening() }
    }

    private func addComment() {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task {
            await viewModel.addComment(text: trimmed, for: postId)
            newCommentText = ""
        }
    }
}

// MARK: - Comments ViewModel (Unchanged)
@MainActor
final class CommentsViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    
    func fetchComments(for postId: String) {
        stopListening()
        let ref = db.collection("videoPosts").document(postId).collection("comments").order(by: "createdAt", descending: false)
        listener = ref.addSnapshotListener { [weak self] snap, error in
            guard let self, let docs = snap?.documents else { return }
            let df = DateFormatter(); df.dateFormat = "dd/MM/yyyy HH:mm"
            self.comments = docs.compactMap { doc in
                let d = doc.data()
                return Comment(username: (d["username"] as? String) ?? "Unknown", userImage: (d["userImage"] as? String) ?? "", text: (d["text"] as? String) ?? "", timestamp: df.string(from: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date()))
            }
        }
    }
    func stopListening() { listener?.remove(); listener = nil }
    
    func addComment(text: String, for postId: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let userDoc = try await db.collection("users").document(uid).getDocument()
            let u = userDoc.data() ?? [:]
            let first = (u["firstName"] as? String) ?? ""; let last  = (u["lastName"]  as? String) ?? ""
            let username = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
            
            try await db.collection("videoPosts").document(postId).collection("comments").document().setData([
                "text": trimmed,
                "username": username.isEmpty ? "Unknown" : username,
                "userImage": (u["profilePic"] as? String) ?? "",
                "userId": uid,
                "createdAt": FieldValue.serverTimestamp()
            ])
            
            try await db.collection("videoPosts").document(postId).updateData(["commentCount": FieldValue.increment(Int64(1))])
            
            NotificationCenter.default.post(name: .postDataUpdated, object: nil, userInfo: [
                "postId": postId,
                "commentAdded": true
            ])
            
        } catch {
            print("Failed to add comment: \(error)")
        }
    }
}

// MARK: - Helper Views
fileprivate struct CommentRowView: View {
    let comment: Comment
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: URL(string: comment.userImage)) { image in
                image.resizable().aspectRatio(contentMode: .fill).frame(width: 40, height: 40).clipShape(Circle())
            } placeholder: {
                Circle().fill(.gray.opacity(0.1)).frame(width: 40, height: 40)
            }
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
    }
}

struct PostStatBarView: View {
    let stat: PostStat
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stat.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(stat.value))")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            ProgressView(value: stat.value)
                .tint(accentColor)
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
            VStack(spacing: 20) {
                Text("Change Visibility?").font(.title3).fontWeight(.semibold)
                Text(isPrivate ? "Making this post public will allow everyone to see it." : "Making this post private will hide it from other users.").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                HStack(spacing: 24) {
                    Button("Cancel") { withAnimation { isPresented = false } }.font(.system(size: 18, weight: .semibold)).foregroundColor(.black).frame(width: 120, height: 44).background(Color.gray.opacity(0.15)).cornerRadius(10)
                    Button("Confirm") { withAnimation { onConfirm(); isPresented = false } }.font(.system(size: 18, weight: .semibold)).foregroundColor(.red).frame(width: 120, height: 44).background(Color.gray.opacity(0.15)).cornerRadius(10)
                }.padding(.top, 4)
            }
            .padding().frame(width: 320).background(Color.white).cornerRadius(20).shadow(radius: 12).transition(.scale)
        }
    }
}

struct DeleteConfirmationOverlay: View {
    @Binding var isPresented: Bool
    let onConfirm: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { isPresented = false }
            VStack(spacing: 20) {
                Text("Delete Post?").font(.title3).fontWeight(.semibold)
                Text("Are you sure you want to permanently delete this post?").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                HStack(spacing: 24) {
                    Button("Cancel") { isPresented = false }.font(.system(size: 18, weight: .semibold)).foregroundColor(.black).frame(width: 120, height: 44).background(Color.gray.opacity(0.15)).cornerRadius(10)
                    Button("Delete") { onConfirm(); isPresented = false }.font(.system(size: 18, weight: .semibold)).foregroundColor(.white).frame(width: 120, height: 44).background(Color.red).cornerRadius(10)
                }.padding(.top, 4)
            }
            .padding().frame(width: 320).background(Color.white).cornerRadius(20).shadow(radius: 12)
        }
    }
}
