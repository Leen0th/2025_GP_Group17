//
//  PostViews.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 09/10/2025.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Post Detail View
struct PostDetailView: View {
    @Environment(\.dismiss) private var dismiss

    // We keep a local copy of the post for UI updates
    @State var post: Post

    @State private var showPrivacyAlert = false
    @State private var showCommentsSheet = false
    private let accentColor = Color(hex: "#36796C")

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    VideoPlayerPlaceholderView(post: post) // Replace with real AVPlayer later if needed
                    captionAndMetadata
                    authorInfoAndInteractions
                    Divider()
                    statsSection
                }
                .padding(.horizontal)
            }
            .navigationBarBackButtonHidden(true)

            if showPrivacyAlert {
                PrivacyWarningPopupView(
                    isPresented: $showPrivacyAlert,
                    isPrivate: post.isPrivate,
                    onConfirm: {
                        // Toggle locally; you can also persist to Firestore if desired
                        post.isPrivate.toggle()
                        // TODO: Update visibility in Firestore if your data model supports it
                    }
                )
            }
        }
        .sheet(isPresented: $showCommentsSheet) {
            if let postId = post.id {
                CommentsView(postId: postId)
            }
        }
        .onChange(of: showPrivacyAlert) { _, _ in
            withAnimation(.easeInOut) { }
        }
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
            }
        }
        .padding(.bottom, 8)
    }

    private var captionAndMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.caption)
                .font(.headline)

            HStack(spacing: 8) {
                Text(post.timestamp)
                Spacer()
                Button(action: { showPrivacyAlert = true }) {
                    Image(systemName: post.isPrivate ? "lock.fill" : "lock.open.fill")
                        .foregroundColor(post.isPrivate ? .red : accentColor)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private var authorInfoAndInteractions: some View {
        HStack {
            // Author avatar
            AsyncImage(url: URL(string: post.authorImageName)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } placeholder: {
                Circle()
                    .fill(.gray.opacity(0.1))
                    .frame(width: 40, height: 40)
            }

            Text(post.authorName)
                .font(.headline)
                .fontWeight(.bold)

            Spacer()

            // Like button
            Button(action: { Task { await toggleLike() } }) {
                HStack(spacing: 4) {
                    Image(systemName: post.isLikedByUser ? "heart.fill" : "heart")
                    Text(formatNumber(post.likeCount))
                }
                .foregroundColor(post.isLikedByUser ? .red : .primary)
            }

            // Comments button
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

    // Update like count in Firestore with optimistic UI
    private func toggleLike() async {
        guard let postId = post.id else { return }

        // Optimistic UI
        post.isLikedByUser.toggle()
        let delta: Int64 = post.isLikedByUser ? 1 : -1
        post.likeCount += Int(delta)

        do {
            try await Firestore.firestore()
                .collection("videoPosts")
                .document(postId)
                .updateData(["likeCount": FieldValue.increment(delta)])
            // NOTE: For real-world apps, also save a per-user likes subcollection
        } catch {
            print("Error updating like count: \(error.localizedDescription)")
            // Revert on failure
            post.isLikedByUser.toggle()
            post.likeCount -= Int(delta)
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let stats = post.stats, !stats.isEmpty {
                ForEach(stats) { stat in
                    PostStatBarView(stat: stat, accentColor: accentColor)
                }
            } else {
                Text("No performance stats available for this post.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1000 {
            let n = Double(number) / 1000.0
            return String(format: "%.1fK", n)
        } else {
            return "\(number)"
        }
    }
}

// MARK: - Comments Sheet View
struct CommentsView: View {
    let postId: String
    @StateObject private var viewModel = CommentsViewModel()

    @Environment(\.dismiss) private var dismiss
    @State private var newCommentText = ""
    private let accentColor = Color(hex: "#36796C")

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Spacer()
                Text("Comments")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.bold())
                }
            }
            .padding()
            .overlay(Divider(), alignment: .bottom)

            // Comments List
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(viewModel.comments) { comment in
                        CommentRowView(comment: comment)
                    }
                }
                .padding()
            }

            // Input field
            HStack(spacing: 12) {
                TextField("Write Comment...", text: $newCommentText)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())

                Button(action: addComment) {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                        .foregroundColor(accentColor)
                }
                .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            .background(.white)
        }
        .onAppear {
            viewModel.fetchComments(for: postId)
        }
        .onDisappear {
            viewModel.stopListening()
        }
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

// MARK: - Comments ViewModel (Realtime listener)
@MainActor
final class CommentsViewModel: ObservableObject {
    @Published var comments: [Comment] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    /// Start realtime listener for comments on a post
    func fetchComments(for postId: String) {
        stopListening()

        let ref = db.collection("videoPosts")
            .document(postId)
            .collection("comments")
            .order(by: "createdAt", descending: false) // Oldest -> Newest (set true if you want newest first)

        listener = ref.addSnapshotListener { [weak self] snap, error in
            guard let self else { return }
            if let error = error {
                print("Comments listener error: \(error)")
                return
            }
            guard let docs = snap?.documents else { return }

            let df = DateFormatter()
            df.dateFormat = "dd/MM/yyyy HH:mm"

            let items: [Comment] = docs.compactMap { doc in
                let d = doc.data()
                let text  = (d["text"] as? String) ?? ""
                let uname = (d["username"] as? String) ?? "Unknown"
                let uimg  = (d["userImage"] as? String) ?? ""
                let date  = (d["createdAt"] as? Timestamp)?.dateValue() ?? Date()

                return Comment(
                    username: uname,
                    userImage: uimg,
                    text: text,
                    timestamp: df.string(from: date)
                )
            }

            Task { @MainActor in
                self.comments = items
            }
        }
    }

    /// Stop listening (call from onDisappear)
    func stopListening() {
        listener?.remove()
        listener = nil
    }

    /// Add a comment and increment commentCount on the post
    func addComment(text: String, for postId: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            // Current user info
            guard let uid = Auth.auth().currentUser?.uid else { return }
            let userDoc = try await db.collection("users").document(uid).getDocument()
            let u = userDoc.data() ?? [:]
            let first = (u["firstName"] as? String) ?? ""
            let last  = (u["lastName"]  as? String) ?? ""
            let username = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
            let userImage = (u["profilePic"] as? String) ?? ""

            // Write comment document
            let commentRef = db.collection("videoPosts")
                .document(postId)
                .collection("comments")
                .document()

            try await commentRef.setData([
                "text": trimmed,
                "username": username.isEmpty ? "Unknown" : username,
                "userImage": userImage,
                "userId": uid,
                "createdAt": FieldValue.serverTimestamp()
            ])

            // Increment aggregate on the post
            try await db.collection("videoPosts")
                .document(postId)
                .updateData(["commentCount": FieldValue.increment(Int64(1))])
        } catch {
            print("Failed to add comment: \(error)")
        }
    }
}

// MARK: - Row for a single comment
fileprivate struct CommentRowView: View {
    let comment: Comment
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: URL(string: comment.userImage)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } placeholder: {
                Circle()
                    .fill(.gray.opacity(0.1))
                    .frame(width: 40, height: 40)
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

// MARK: - Helper Views (thumbnail/video placeholder + stat bar + privacy popup)
struct VideoPlayerPlaceholderView: View {
    let post: Post
    var body: some View {
        ZStack {
            AsyncImage(url: URL(string: post.imageName)) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Color.black
            }
            .frame(height: 250)
            .background(Color.black)
            .clipped()

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
                }
                .padding(12)
                .background(.black.opacity(0.4))
            }
            .font(.callout)
            .foregroundColor(.white)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                Text(String(format: "%.1f", stat.value))
                    .font(.caption)
                    .fontWeight(.bold)
            }
            // Assuming maxValue is 100 for normalized stats
            ProgressView(value: stat.value, total: 100)
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
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { isPresented = false } }
                .transition(.opacity)

            GeometryReader { geometry in
                VStack {
                    Spacer()
                    VStack(spacing: 20) {
                        Text("Change Visibility?")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(isPrivate
                             ? "Making this post public will allow everyone to see it."
                             : "Making this post private will hide it from other users.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                        HStack(spacing: 24) {
                            Button("Cancel") {
                                withAnimation { isPresented = false }
                            }
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 120, height: 44)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(10)

                            Button("Confirm") {
                                withAnimation {
                                    onConfirm()
                                    isPresented = false
                                }
                            }
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(width: 120, height: 44)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(10)
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .frame(width: 320)
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(radius: 12)
                    .transition(.scale)
                    Spacer()
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }
}
