//
//  PostViews.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 30/10/2025.
//
//

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
    private let accentColor = BrandColors.darkTeal
    
    @State private var isEditingCaption = false
    @State private var editedCaption = ""
    @State private var isSavingCaption = false
    
    @State private var navigateToProfileID: String?
    @State private var navigationTrigger = false
    
    private let captionLimit = 15
    
    private var currentUserID: String? {
        Auth.auth().currentUser?.uid
    }
    
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
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    
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
                    .background(BrandColors.background.opacity(0.6))
                    .cornerRadius(12)
            }
        }
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
                    }
                )
                .presentationBackground(BrandColors.background)
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
                    HStack(spacing: 8) {
                        AsyncImage(url: URL(string: post.authorImageName)) { image in
                            image.resizable().aspectRatio(contentMode: .fill).frame(width: 40, height: 40).clipShape(Circle())
                        } placeholder: {
                            Circle().fill(BrandColors.lightGray).frame(width: 40, height: 40)
                        }
                        Text(post.authorName)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(BrandColors.darkGray)
                    }
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    AsyncImage(url: URL(string: post.authorImageName)) { image in
                        image.resizable().aspectRatio(contentMode: .fill).frame(width: 40, height: 40).clipShape(Circle())
                    } placeholder: {
                        Circle().fill(BrandColors.lightGray).frame(width: 40, height: 40)
                    }
                    Text(post.authorName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(BrandColors.darkGray)
                }
            }
            
            Spacer()
            
            Button(action: { Task { await toggleLike() } }) {
                HStack(spacing: 4) {
                    Image(systemName: post.isLikedByUser ? "heart.fill" : "heart")
                    Text(formatNumber(post.likeCount))
                }
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(post.isLikedByUser ? .red : BrandColors.darkGray)
            }
            
            Button(action: { showCommentsSheet = true }) {
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
        guard let postId = post.id, let uid = Auth.auth().currentUser?.uid else { return }
        let isLiking = !post.isLikedByUser
        let delta: Int64 = isLiking ? 1 : -1
        let firestoreAction = isLiking ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid])
        post.isLikedByUser = isLiking
        post.likeCount += Int(delta)
        if isLiking { post.likedBy.append(uid) }
        else { post.likedBy.removeAll { $0 == uid } }
        do {
            try await Firestore.firestore().collection("videoPosts").document(postId).updateData([
                "likeCount": FieldValue.increment(delta), "likedBy": firestoreAction
            ])
            var userInfo: [String: Any] = ["postId": postId]
            userInfo["likeUpdate"] = (isLiking, post.likeCount)
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

// --- MODIFICATION: In-place editing state ---
struct CommentsView: View {
    let postId: String
    var onProfileTapped: (String) -> Void
    
    @StateObject private var viewModel = CommentsViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var newCommentText = ""
    private let accentColor = BrandColors.darkTeal
    
    // --- 1. REMOVED Sheet state ---
    // @State private var showEditSheet = false
    // @State private var commentToEdit: Comment?
    // @State private var editedCommentText = ""
    
    // --- 2. ADDED In-Place Editing State ---
    @State private var editingCommentID: String? = nil
    @State private var editingCommentText: String = ""
    private let commentLimit = 280 // Set a reasonable limit
    
    @State private var showDeleteAlert = false
    @State private var commentToDelete: Comment?

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
                        // --- 3. MODIFIED ForEach ---
                        ForEach(viewModel.comments) { comment in
                            CommentRowView(
                                comment: comment,
                                isEditing: editingCommentID == comment.id,
                                editingText: $editingCommentText,
                                commentLimit: commentLimit,
                                onProfileTapped: onProfileTapped,
                                onEdit: {
                                    viewModel.stopListening()
                                    editingCommentID = comment.id
                                    editingCommentText = comment.text
                                },
                                onDelete: {
                                    commentToDelete = comment
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
                                }
                            )
                        }
                        // --- END MODIFICATION ---
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
            // --- 4. REMOVED .sheet modifier ---
            .alert("Delete Comment?", isPresented: $showDeleteAlert, presenting: commentToDelete) { comment in
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteComment(comment, from: postId)
                    }
                }
            } message: { _ in
                Text("Are you sure you want to delete this comment? This action cannot be undone.")
            }

            // --- Comment Input Area ---
            HStack(spacing: 12) {
                TextField("Write Comment...", text: $newCommentText)
                    .font(.system(size: 15, design: .rounded))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(BrandColors.lightGray).clipShape(Capsule())
                    .tint(accentColor)

                Button(action: addComment) {
                    Image(systemName: "paperplane.fill")
                        .font(.title2).foregroundColor(accentColor)
                }
                .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            .background(BrandColors.background)
        }
        // Add listener for character limit on in-place editor
        .onChange(of: editingCommentText) { _, newVal in
            if newVal.count > commentLimit {
                editingCommentText = String(newVal.prefix(commentLimit))
            }
        }
    }

    private func addComment() {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task {
            await viewModel.addComment(text: trimmed, for: postId)
            newCommentText = ""
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}
// --- END MODIFICATION ---

// ===================================================================
// MARK: - Comments View Model (NO CHANGE)
// ===================================================================
final class CommentsViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    @Published var isLoading = true
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private let lock = NSLock()

    deinit {
        stopListening()
    }

    func fetchComments(for postId: String) {
        stopListening()
        isLoading = true
        
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

    func addComment(text: String, for postId: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let userDoc = try await db.collection("users").document(uid).getDocument()
            let u = userDoc.data() ?? [:]
            let first = (u["firstName"] as? String) ?? ""; let last  = (u["lastName"]  as? String) ?? ""
            let username = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
            let userImage = (u["profilePic"] as? String) ?? ""

            let commentData: [String: Any] = [
                "text": trimmed,
                "username": username.isEmpty ? "Unknown" : username,
                "userImage": userImage,
                "userId": uid,
                "createdAt": FieldValue.serverTimestamp()
            ]

            let postRef = db.collection("videoPosts").document(postId)
            let commentRef = postRef.collection("comments").document()
            
            let batch = db.batch()
            batch.setData(commentData, forDocument: commentRef)
            batch.updateData(["commentCount": FieldValue.increment(Int64(1))], forDocument: postRef)
            try await batch.commit()

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
            try await commentRef.updateData(["text": trimmedText])
        } catch {
            print("Error editing comment: \(error.localizedDescription)")
        }
    }
    
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
}


// MARK: - Helper Views (Styling Update)

// --- MODIFICATION: Replaced simple text with in-place editor ---
fileprivate struct CommentRowView: View {
    let comment: Comment
    let isEditing: Bool
    @Binding var editingText: String
    let commentLimit: Int
    
    var onProfileTapped: (String) -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onSave: () -> Void
    var onCancel: () -> Void
    
    private var currentUserID: String? { Auth.auth().currentUser?.uid }
    private var isOwner: Bool { comment.userId == currentUserID }
    private let accentColor = BrandColors.darkTeal
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            
            Button(action: {
                onProfileTapped(comment.userId)
            }) {
                AsyncImage(url: URL(string: comment.userImage)) { image in
                    image.resizable().aspectRatio(contentMode: .fill).frame(width: 40, height: 40).clipShape(Circle())
                } placeholder: {
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
                        Text(comment.username)
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
                            .padding(8) // Internal padding
                            .frame(minHeight: 80) // Give it some space
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
                            .disabled(editingText.trimmingCharacters(in: .whitespaces).isEmpty)
                            .opacity(editingText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.7 : 1.0)
                        }
                    }
                } else {
                    // --- 3. STANDARD TEXT (Read-only) ---
                    Text(comment.text)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(BrandColors.darkGray)
                }
            }
            
            Spacer()
            
            // --- 4. "THREE DOTS" MENU ---
            // Hide menu if we are editing this row
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
        }
        .animation(.easeInOut, value: isEditing) // Animate the transition
    }
}
// --- END MODIFICATION ---

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
                Text(isPrivate ? "Making this post public will allow everyone to see it." : "Making this post private will hide it from other users.")
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

struct DeleteConfirmationOverlay: View {
    @Binding var isPresented: Bool
    let onConfirm: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { isPresented = false }
            VStack(spacing: 20) {
                Text("Delete Post")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("Deleting this post will remove it and reduce your performance score accordingly. Are you sure you want to proceed?")
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
                    
                    Button("Delete") { onConfirm(); isPresented = false }
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
    }
}
