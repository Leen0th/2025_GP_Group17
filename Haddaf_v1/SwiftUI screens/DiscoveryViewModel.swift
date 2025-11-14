import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AVKit

// MARK: - Discovery View Model

// Manages the state for the Discovery feed
@MainActor
final class DiscoveryViewModel: ObservableObject {
    // `true` while the initial batch of posts is being loaded
    @Published var isLoadingPosts = true
    // The array of public posts to be displayed in the feed
    @Published var posts: [Post] = []
    // A dictionary caching `UserProfile` objects, keyed by author UID, to avoid redundant fetches
    @Published var authorProfiles: [String: UserProfile] = [:]
    
    // A reference to the Firestore database
    private let db = Firestore.firestore()
    // The registration for the real-time Firestore listener
    private var postsListener: ListenerRegistration?
    // A shared `DateFormatter` for converting timestamps to strings
    private let df = DateFormatter()

    // Initializes the view model
    init() {
        df.dateFormat = "dd/MM/yyyy HH:mm"
        listenToPublicPosts()
    }

    // Cleans up the Firestore listener when the view model is deallocated to prevent memory leaks
    deinit {
        postsListener?.remove()
    }

    // A real-time listener for all public video posts in Firestore
    /// This function queries the `videoPosts` collection where `visibility` is `true`
    /// orders them by date, and maps the documents to `Post` objects
    /// It also triggers the concurrent fetching of author profiles for any new posts
    func listenToPublicPosts() {
        postsListener?.remove()
        
        self.isLoadingPosts = true

        postsListener = db.collection("videoPosts")
            .whereField("visibility", isEqualTo: true)
            .order(by: "uploadDateTime", descending: true)
            .addSnapshotListener { [weak self] snap, err in
                
                guard let docs = snap?.documents else {
                    if let err = err { print("listenToPublicPosts error: \(err)") }
                    Task { @MainActor in
                        self?.isLoadingPosts = false
                    }
                    return
                }
                
                guard let self = self else { return }

                Task {
                    // Asynchronously map each Firestore document to a `Post` model
                    let mappedPosts: [Post] = docs.compactMap { doc in
                        let d = doc.data()
                        var postStats: [PostStat] = []
                        // A helper to safely convert Firestore's `Any` (which could be `Int` or `Double`) to `Double`
                        func toDouble(_ val: Any?) -> Double? {
                            return val as? Double ?? (val as? Int).map(Double.init)
                        }
                        
                        if let feedbackMap = d["performanceFeedback"] as? [String: Any] {
                            postStats = feedbackMap.compactMap { (key, anyValue) in
                                guard let value = toDouble(anyValue) else { return nil }
                                return PostStat(
                                    label: key.uppercased(),
                                    value: value,
                                    maxValue: 10.0
                                )
                            }.sorted { $0.label < $1.label }
                        } else if let feedbackArray = d["performanceFeedback"] as? [[String: Any]] {
                            postStats = feedbackArray.compactMap { dict in
                                guard let label = dict["label"] as? String,
                                      let value = toDouble(dict["value"]) else { return nil }
                                let maxValue = toDouble(dict["maxValue"]) ?? 10.0
                                return PostStat(label: label, value: value, maxValue: maxValue)
                            }
                        }

                        let likedBy = (d["likedBy"] as? [String]) ?? []
                        let uid = Auth.auth().currentUser?.uid ?? ""
                        let matchDateTimestamp = d["matchDate"] as? Timestamp
                        let matchDate: Date? = matchDateTimestamp?.dateValue()
                        
                        // Extracts the author's UID from the `DocumentReference`
                        let authorIdRef = d["authorId"] as? DocumentReference
                        let authorUid = authorIdRef?.documentID ?? ""

                        return Post(
                            authorUid: authorUid,
                            id: doc.documentID,
                            imageName: (d["thumbnailURL"] as? String) ?? "",
                            videoURL: (d["url"] as? String) ?? "",
                            caption: (d["caption"] as? String) ?? "",
                            timestamp: self.df.string(from: (d["uploadDateTime"] as? Timestamp)?.dateValue() ?? Date()),
                            isPrivate: !((d["visibility"] as? Bool) ?? true),
                            authorName: (d["authorUsername"] as? String) ?? "",
                            authorImageName: (d["profilePic"] as? String) ?? "",
                            likeCount: (d["likeCount"] as? Int) ?? 0,
                            commentCount: (d["commentCount"] as? Int) ?? 0,
                            likedBy: likedBy,
                            isLikedByUser: likedBy.contains(uid), // Check if current user liked it
                            stats: postStats,
                            matchDate: matchDate
                        )
                    }
                    
                    // Gathers all unique author UIDs from the newly fetched posts
                    let allUIDs = Set(mappedPosts.compactMap { $0.authorUid })
                    
                    // Fetches any author profiles that aren't already in the cache
                    await self.fetchAuthorProfiles(for: Array(allUIDs))
                    
                    // After all data is fetched and mapped, update the UI on the main thread
                    await MainActor.run {
                        self.posts = mappedPosts
                        self.isLoadingPosts = false
                    }
                }
            }
        }
    
    // Concurrently fetches multiple author profiles from Firestore
    private func fetchAuthorProfiles(for uids: [String]) async {
        // Filters out UIDs that are empty or already present in the `authorProfiles` cache
        let uidsToFetch = uids.filter { !$0.isEmpty && self.authorProfiles[$0] == nil }
        
        guard !uidsToFetch.isEmpty else { return }
        
        await withTaskGroup(of: Void.self) { group in
            for uid in uidsToFetch {
                group.addTask {
                    await self.fetchAuthorProfile(uid: uid)
                }
            }
        }
    }

    // Fetches a single user's complete profile data from multiple Firestore documents
    private func fetchAuthorProfile(uid: String) async {
        guard !uid.isEmpty else { return } // Don't fetch for empty UID
        
        // Skips the fetch if the profile is already cached
        if self.authorProfiles[uid] != nil { return }
        
        do {
            // 1. Fetch root user document
            let userDoc = try await db.collection("users").document(uid).getDocument()
            let data = userDoc.data() ?? [:]

            let first = (data["firstName"] as? String) ?? ""
            let last = (data["lastName"] as? String) ?? ""
            let full = [first, last].joined(separator: " ").trimmingCharacters(in: .whitespaces)

            // 2. Fetch nested player profile document
            let pDoc = try await db.collection("users").document(uid)
                .collection("player").document("profile")
                .getDocument()
            let p = pDoc.data() ?? [:]

            // 3. Map data to a UserProfile object
            let profile = UserProfile()
            profile.name = full.isEmpty ? "Player" : full
            profile.position = (p["position"] as? String) ?? ""
            if let h = p["height"] as? Int { profile.height = "\(h)cm" } else { profile.height = "" }
            if let w = p["weight"] as? Int { profile.weight = "\(w)kg" } else { profile.weight = "" }
            
            // Handle keys for location
            profile.location = (p["location"] as? String) ?? (p["Residence"] as? String) ?? ""
            
            profile.email = (data["email"] as? String) ?? ""
            profile.phoneNumber = (data["phone"] as? String) ?? ""
            profile.isEmailVisible = (p["isEmailVisible"] as? Bool) ?? false
            profile.isPhoneNumberVisible = (p["contactVisibility"] as? Bool) ?? false

            // Calculate age from Date of Birth
            if let dobTimestamp = data["dob"] as? Timestamp {
                let dobDate = dobTimestamp.dateValue()
                profile.dob = dobDate
                let calendar = Calendar.current
                let ageComponents = calendar.dateComponents([.year], from: dobDate, to: Date())
                profile.age = "\(ageComponents.year ?? 0)"
            } else {
                profile.dob = nil
                profile.age = ""
            }

            // 4. Asynchronously fetch the profile image from its URL
            if let urlStr = data["profilePic"] as? String, !urlStr.isEmpty {
                profile.profileImage = await fetchImage(from: urlStr)
            } else {
                profile.profileImage = UIImage(systemName: "person.circle.fill")
            }

            profile.team = "Unassigned" // Default value
            profile.rank = "0" // Default value
            profile.score = (p["cumulativeScore"] as? String) ?? "0"

            // Saves the newly fetched profile to the cache on the main thread
            await MainActor.run {
                self.authorProfiles[uid] = profile
            }
        } catch {
            print("fetchAuthorProfile error for UID \(uid): \(error)")
        }
    }

    // Asynchronously downloads an image from a given URL string.
    private func fetchImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return UIImage(systemName: "person.circle.fill") }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data) ?? UIImage(systemName: "person.circle.fill")
        } catch {
            return UIImage(systemName: "person.circle.fill")
        }
    }
    
    // Toggles the "like" state for a post for the current user
    func toggleLike(post: Post) async {
        guard let postId = post.id, let uid = Auth.auth().currentUser?.uid else { return }
        
        // Determine the action to take and the change in like count
        let isLiking = !post.isLikedByUser
        let delta: Int64 = isLiking ? 1 : -1
        let firestoreAction = isLiking ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid])

        // 1. Optimistic UI Update: Change local data first
        if let index = self.posts.firstIndex(where: { $0.id == postId }) {
            self.posts[index].isLikedByUser = isLiking
            self.posts[index].likeCount += Int(delta)
            if isLiking {
                self.posts[index].likedBy.append(uid)
            } else {
                self.posts[index].likedBy.removeAll { $0 == uid }
            }
        }

        do {
            // 2. Remote Update:  Send the change to Firestore
            try await db.collection("videoPosts").document(postId).updateData([
                "likeCount": FieldValue.increment(delta), "likedBy": firestoreAction
            ])
            // 3. Sync State: Notify other parts of the app
            var userInfo: [String: Any] = ["postId": postId]
            let newLikeCount = post.likeCount + Int(delta)
            userInfo["likeUpdate"] = (isLiking, newLikeCount)
            NotificationCenter.default.post(name: .postDataUpdated, object: nil, userInfo: userInfo)

        } catch {
            print("Error updating like count from DiscoveryVM: \(error.localizedDescription)")
            
            // 4. Rollback:  Revert local changes if the remote update fails
            if let index = self.posts.firstIndex(where: { $0.id == postId }) {
                self.posts[index].isLikedByUser = !isLiking
                self.posts[index].likeCount -= Int(delta)
                if isLiking {
                    self.posts[index].likedBy.removeAll { $0 == uid }
                } else {
                    self.posts[index].likedBy.append(uid)
                }
            }
        }
    }
    
    // Handles incoming notifications from `.postDataUpdated`
    /// This keeps the Discovery feed's like/comment counts in sync with changes made elsewhere in the app without requiring a full re-fetch.
    @MainActor
    func handlePostDataUpdate(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let updatedPostId = userInfo["postId"] as? String else {
            return
        }

        // Finds the post in the `posts` array to update
        guard let index = self.posts.firstIndex(where: { $0.id == updatedPostId }) else {
            return // This post isn't in our list
        }

        // Check for comment updates
        if userInfo["commentAdded"] as? Bool == true {
            self.posts[index].commentCount += 1
        }
        
        // Check for like updates
        if let (isLiked, likeCount) = userInfo["likeUpdate"] as? (Bool, Int) {
            self.posts[index].isLikedByUser = isLiked
            self.posts[index].likeCount = likeCount
        }
    }
}
