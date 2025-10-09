//
//  PostViews.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 09/10/2025.
//

import SwiftUI

// MARK: - Post Detail View
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

// MARK: - Comments Sheet View
struct CommentsView: View {
    @Binding var post: Post
    @Environment(\.dismiss) var dismiss
    @State private var newCommentText = ""
    private let accentColor = Color(hex: "#36796C")

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Spacer()
                Text("Comment").font(.headline).padding()
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.subheadline.bold()) }
            }.padding().overlay(Divider(), alignment: .bottom)

            // Comments List
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(post.comments) { comment in CommentRowView(comment: comment) }
                }.padding()
            }
            
            // Input Field
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

// MARK: - Post Helper Views
fileprivate struct CommentRowView: View {
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
