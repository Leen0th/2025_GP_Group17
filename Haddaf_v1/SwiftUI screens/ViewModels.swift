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
        postCreatedObs = NotificationCenter.default.addObserver(
            forName: .postCreated, object: nil, queue: .main
        ) { [weak self] note in
            guard
                let self,
                let newPost = note.userInfo?["post"] as? Post
            else { return }
            
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

    // MODIFIED: Made sequential to prevent race condition
    func fetchAllData() async {
        isLoading = true
        // Set default image immediately
        userProfile.profileImage = UIImage(systemName: "person.circle.fill")
        
        // 1. Await the profile data (and its image) to be fully fetched.
        await fetchProfile()
        
        // 2. ONLY after the profile is loaded, attach the listener for posts.
        listenToMyPosts()
        
        // 3. Now that all data is fetched and listeners are attached, stop loading.
        isLoading = false
    }

    // MODIFIED: Corrected field names to match SignUpView/PlayerSetupView
    func fetchProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            // 'data' is from the main '/users/{uid}' document
            let userDoc = try await db.collection("users").document(uid).getDocument()
            let data = userDoc.data() ?? [:]

            let first = (data["firstName"] as? String) ?? ""
            let last  = (data["lastName"]  as? String) ?? ""
            let full  = [first, last].joined(separator: " ").trimmingCharacters(in: .whitespaces)

            // 'p' is from the '/users/{uid}/player/profile' sub-document
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
            
            // --- MODIFIED (1) ---
            // 'phone' is in the main 'data' object
            userProfile.phoneNumber = (data["phone"] as? String) ?? ""
            
            userProfile.isEmailVisible = (p["isEmailVisible"] as? Bool) ?? false
            
            // --- MODIFIED (2) ---
            // The key is 'contactVisibility' in 'p'
            userProfile.isPhoneNumberVisible = (p["contactVisibility"] as? Bool) ?? false

            // --- MODIFIED (3) ---
            // 'dob' is in the main 'data' object
            if let dobTimestamp = data["dob"] as? Timestamp { // <-- Read "dob", not "dateOfBirth"
                let dobDate = dobTimestamp.dateValue()
                
                // 1. Set the actual Date object for EditProfileView
                userProfile.dob = dobDate
                
                // 2. Calculate and set the age string for StatsGridView
                let calendar = Calendar.current
                let ageComponents = calendar.dateComponents([.year], from: dobDate, to: Date())
                userProfile.age = "\(ageComponents.year ?? 0)"
            } else {
                // Ensure they are nil/empty if not found
                userProfile.dob = nil
                userProfile.age = ""
            }

            // Asynchronous image fetching
            if let urlStr = data["profilePic"] as? String, !urlStr.isEmpty {
                self.userProfile.profileImage = await fetchImage(from: urlStr)
            } else {
                self.userProfile.profileImage = UIImage(systemName: "person.circle.fill")
            }

            userProfile.team  = "Unassigned"
            userProfile.rank  = "0"
            userProfile.score = "0"
        } catch {
            print("fetchProfile error: \(error)")
        }
    }
    
    private func fetchImage(from urlString: String) async -> UIImage? {
        print("---------------------------------")
        print("ProfileVM: Attempting to fetch image from URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("ProfileVM Error: Invalid URL string. Cannot create URL object.")
            print("---------------------------------")
            return UIImage(systemName: "person.circle.fill")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("ProfileVM: Received response. Status code: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    print("ProfileVM Error: Download failed with status code \(httpResponse.statusCode). Check Firebase Storage Rules.")
                }
            }

            if let image = UIImage(data: data) {
                print("ProfileVM: Successfully downloaded and created image.")
                print("---------------------------------")
                return image
            } else {
                print("ProfileVM Error: Downloaded data (\(data.count) bytes) could not be converted to UIImage.")
                print("---------------------------------")
                return UIImage(systemName: "person.circle.fill")
            }
        } catch {
            // This will catch the "cancelled" error if it still happens
            print("ProfileVM Error: Network request failed. \(error.localizedDescription)")
            print("---------------------------------")
            return UIImage(systemName: "person.circle.fill")
        }
    }

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
                        let postStats: [PostStat] = self.placeholderStats // Using placeholder

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
                        self.posts = mappedPosts
                    }
                }
            }
    }

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
