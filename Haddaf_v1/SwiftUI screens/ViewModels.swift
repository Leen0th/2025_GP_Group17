import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

extension Sequence {
    func asyncMap<T>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T] {
        var values = [T]()
        for element in self {
            try await values.append(transform(element))
        }
        return values
    }
}

@MainActor
final class PlayerProfileViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var userProfile = UserProfile()
    @Published var posts: [Post] = []

    private let db = Firestore.firestore()
    private var postsListener: ListenerRegistration?
    private let df = DateFormatter()

    // Observers for post create/delete events
    private var postCreatedObs: NSObjectProtocol?
    private var postDeletedObs: NSObjectProtocol?

    init() {
        df.dateFormat = "dd/MM/yyyy HH:mm"

        // Insert new post immediately into My posts (optimistic UI)
        // ✅ THIS IS CORRECT. KEEP IT.
        postCreatedObs = NotificationCenter.default.addObserver(
            forName: .postCreated, object: nil, queue: .main
        ) { [weak self] note in
            guard
                let self,
                let newPost = note.userInfo?["post"] as? Post
            else { return }
            
            // Prevent duplicate if listener already added it
            if !self.posts.contains(where: { $0.id == newPost.id }) {
                 self.posts.insert(newPost, at: 0)
            }
        }

        // Remove post from UI when it gets deleted
        postDeletedObs = NotificationCenter.default.addObserver(
            forName: .postDeleted, object: nil, queue: .main
        ) { [weak self] note in
            guard
                let self,
                let postId = note.userInfo?["postId"] as? String
            else { return }
            self.posts.removeAll { $0.id == postId }
        }
    }
    
    deinit {
        postsListener?.remove()
        if let t = postCreatedObs { NotificationCenter.default.removeObserver(t) }
        if let t = postDeletedObs { NotificationCenter.default.removeObserver(t) }
    }

    func fetchAllData() async {
        isLoading = true
        // Set default image immediately
        userProfile.profileImage = UIImage(systemName: "person.circle.fill")
        
        // Fetch profile data and posts
        async let _ = fetchProfile()
        listenToMyPosts()
        
        _ = await (()) // Wait for profile fetch to complete
        isLoading = false
    }

    func fetchProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let userDoc = try await db.collection("users").document(uid).getDocument()
            let data = userDoc.data() ?? [:]

            let first = (data["firstName"] as? String) ?? ""
            let last  = (data["lastName"]  as? String) ?? ""
            let full  = [first, last].joined(separator: " ").trimmingCharacters(in: .whitespaces)

            let pDoc = try await db.collection("users").document(uid)
                .collection("player").document("profile")
                .getDocument()
            let p = pDoc.data() ?? [:]

            userProfile.name = full.isEmpty ? "Player" : full
            userProfile.position = (p["position"] as? String) ?? ""
            if let h = p["height"] as? Int { userProfile.height = "\(h)cm" } else { userProfile.height = "" }
            if let w = p["weight"] as? Int { userProfile.weight = "\(w)kg" } else { userProfile.weight = "" }
            userProfile.location = (p["location"] as? String) ?? ""
            userProfile.email = (data["email"] as? String) ?? ""
            userProfile.phoneNumber = (p["phone"] as? String) ?? ""
            userProfile.isEmailVisible = (p["isEmailVisible"] as? Bool) ?? false
            userProfile.isPhoneVisible = (p["contactVisibility"] as? Bool) ?? false

            if let ts = p["dateOfBirth"] as? Timestamp {
                let age = Calendar.current.dateComponents([.year], from: ts.dateValue(), to: Date()).year ?? 0
                userProfile.age = "\(age)"
            } else {
                userProfile.age = ""
            }

            // --- 🛑 OLD SYNCHRONOUS CODE (REMOVED) ---
            // if let urlStr = data["profilePic"] as? String,
            //    let url = URL(string: urlStr),
            //    let bytes = try? Data(contentsOf: url),
            //    let img = UIImage(data: bytes) {
            //     userProfile.profileImage = img
            // } else {
            //     userProfile.profileImage = UIImage(systemName: "person.circle.fill")
            // }
            
            // --- ✅ NEW ASYNCHRONOUS CODE ---
            if let urlStr = data["profilePic"] as? String, !urlStr.isEmpty {
                // Asynchronously fetch image and update the profile
                // This no longer blocks the main thread
                self.userProfile.profileImage = await fetchImage(from: urlStr)
            } else {
                self.userProfile.profileImage = UIImage(systemName: "person.circle.fill")
            }
            // --- END OF FIX ---

            userProfile.team  = "Unassigned"
            userProfile.rank  = "0"
            userProfile.score = "0"
        } catch {
            print("fetchProfile error: \(error)")
        }
    }
    
    // --- ✅ NEW ASYNC HELPER FUNCTION ---
    private func fetchImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else {
            return UIImage(systemName: "person.circle.fill")
        }
        
        do {
            // This runs in the background, not blocking the UI
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data) ?? UIImage(systemName: "person.circle.fill")
        } catch {
            print("Failed to download image: \(error)")
            return UIImage(systemName: "person.circle.fill")
        }
    }
    // --- END OF NEW FUNCTION ---

    // MARK: - Posts (with static placeholder stats)
    func listenToMyPosts() {
        postsListener?.remove()

        guard let uid = Auth.auth().currentUser?.uid else { return }
        let userRef = db.collection("users").document(uid)

        postsListener = db.collection("videoPosts")
            .whereField("authorId", isEqualTo: userRef)
            .order(by: "uploadDateTime", descending: true)
            .addSnapshotListener { [weak self] snap, err in
                guard let self, let docs = snap?.documents else {
                    if let err = err { print("listenToMyPosts error: \(err)") }
                    return
                }

                Task {
                    let mappedPosts: [Post] = await docs.asyncMap { doc in
                        let d = doc.data()

                        // Always show the fixed placeholder stats in UI
                        let postStats: [PostStat] = self.placeholderStats

                        return Post(
                            id: doc.documentID,
                            imageName: (d["thumbnailURL"] as? String) ?? "",
                            videoURL: (d["url"] as? String) ?? "",
                            caption: (d["caption"] as? String) ?? "",
                            timestamp: self.df.string(
                                from: (d["uploadDateTime"] as? Timestamp)?.dateValue() ?? Date()
                            ),
                            isPrivate: !((d["visibility"] as? Bool) ?? true),
                            authorName: (d["authorUsername"] as? String) ?? "",
                            authorImageName: (d["profilePic"] as? String) ?? "",
                            likeCount: (d["likeCount"] as? Int) ?? 0,
                            commentCount: (d["commentCount"] as? Int) ?? 0,
                            isLikedByUser: false,
                            stats: postStats
                        )
                    }
                    
                    await MainActor.run {
                        // ✅ This is correct. It replaces the whole array.
                        self.posts = mappedPosts
                    }
                }
            }
    }

    // Fixed placeholder stats used for every post
    private var placeholderStats: [PostStat] {
        [
            PostStat(label: "GOALS",           value: 4),
            PostStat(label: "TOTAL ATTEMPTS",  value: 5),
            PostStat(label: "BLOCKED",         value: 3),
            PostStat(label: "SHOTS ON TARGET", value: 13),
            PostStat(label: "CORNERS",         value: 13),
            PostStat(label: "OFFSIDES",        value: 3)
        ]
    }
}
