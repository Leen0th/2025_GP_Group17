import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

extension Sequence {
    /// Async version of map that awaits each transform.
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

    //Insert newly created posts at the top of the list for instant UI feedback.
    private var postCreatedObs: NSObjectProtocol?
    //Remove deleted posts from the local list when a delete event is broadcast.
    private var postDeletedObs: NSObjectProtocol?
    private var profileUpdatedObs: NSObjectProtocol?
    
    // Observer for like/comment sync
    private var postDataUpdatedObs: NSObjectProtocol?
    
    // Tracks which user's profile we are showing
    private var targetUserID: String?
    private var uidToFetch: String? {
        // Prefer target user, otherwise current authenticated user

        return targetUserID ?? Auth.auth().currentUser?.uid
    }

    /// Initialize view model and set up notification observers.
    init(userID: String? = nil) {
        self.targetUserID = userID
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
        
        // Recompute score when profile (non-image fields) changes.
        profileUpdatedObs = NotificationCenter.default.addObserver(
            forName: .profileUpdated, object: nil, queue: .main
        ) { [weak self] note in
            if let fields = note.userInfo?["fields"] as? [String] {
                let imgKeys: Set<String> = ["profilePic", "profileImage", "profilePicURL"]
                if Set(fields).isSubset(of: imgKeys) { return }
            }
            Task { await self?.calculateAndUpdateScore() }
        }
        
        // Keep likes and comments in sync across the app.
        postDataUpdatedObs = NotificationCenter.default.addObserver(
            forName: .postDataUpdated, object: nil, queue: .main
        ) { [weak self] notification in
            // Call the handler function
            self?.handlePostDataUpdate(notification: notification)
        }
            
    }
    
    /// Clean up Firestore listeners and notification observers.
    deinit {
        postsListener?.remove()
        if let t = postCreatedObs { NotificationCenter.default.removeObserver(t) }
        if let t = postDeletedObs { NotificationCenter.default.removeObserver(t) }
        if let t = profileUpdatedObs { NotificationCenter.default.removeObserver(t) }
        
        if let t = postDataUpdatedObs { NotificationCenter.default.removeObserver(t) }
    }

    /// Load profile first, then attach posts listener in sequence.
    func fetchAllData() async {
        isLoading = true
        // Set default image immediately
        userProfile.profileImage = UIImage(systemName: "person.circle.fill")
        
        await fetchProfile()
        
        listenToMyPosts()
        
        isLoading = false
    }

    /// Fetch user profile data and basic player info from Firestore.
    func fetchProfile() async {
        guard let uid = uidToFetch else { return }
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
            
            userProfile.location = (p["location"] as? String) ?? (p["Residence"] as? String) ?? ""
            
            userProfile.email = (data["email"] as? String) ?? ""
            
            
            userProfile.phoneNumber = (data["phone"] as? String) ?? ""
            
            userProfile.isEmailVisible = (p["isEmailVisible"] as? Bool) ?? false
            
           
            userProfile.isPhoneNumberVisible = (p["contactVisibility"] as? Bool) ?? false

           
            if let dobTimestamp = data["dob"] as? Timestamp {
                let dobDate = dobTimestamp.dateValue()
                
                userProfile.dob = dobDate
                
             
                let calendar = Calendar.current
                let ageComponents = calendar.dateComponents([.year], from: dobDate, to: Date())
                userProfile.age = "\(ageComponents.year ?? 0)"
            } else {
                userProfile.dob = nil
                userProfile.age = ""
            }

            if let urlStr = data["profilePic"] as? String, !urlStr.isEmpty {
                self.userProfile.profileImage = await fetchImage(from: urlStr)
            } else {
                self.userProfile.profileImage = UIImage(systemName: "person.circle.fill")
            }

            userProfile.team  = "Unassigned"
            userProfile.rank  = "0"
            
           
            userProfile.score = (p["cumulativeScore"] as? String) ?? "0"
            
        } catch {
            print("fetchProfile error: \(error)")
        }
    }
    /// Download a profile image from a remote URL.
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
            
            print("ProfileVM Error: Network request failed. \(error.localizedDescription)")
            print("---------------------------------")
            return UIImage(systemName: "person.circle.fill")
        }
    }

    // MARK: - Posts (with static placeholder stats)
    /// Attach a Firestore listener for this user's posts.
    func listenToMyPosts() {
        postsListener?.remove()

        guard let uid = uidToFetch else { return }
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
                        
                        // Build stats array from either map or array format.
                        var postStats: [PostStat] = []
                        
                        // Helper function to safely convert Any to Double
                        func toDouble(_ val: Any?) -> Double? {
                            return val as? Double ?? (val as? Int).map(Double.init)
                        }
                        
                        if let feedbackMap = d["performanceFeedback"] as? [String: Any] {
                           
                            postStats = feedbackMap.compactMap { (key, anyValue) in
                                guard let value = toDouble(anyValue) else { return nil }
                                return PostStat(
                                    label: key.uppercased(),
                                    value: value,
                                    maxValue: 10.0 // Default to 10
                                )
                            }
                            .sorted { $0.label < $1.label }
                            
                        } else if let feedbackArray = d["performanceFeedback"] as? [[String: Any]] {
                            
                            postStats = feedbackArray.compactMap { dict in
                                guard let label = dict["label"] as? String,
                                      let value = toDouble(dict["value"])
                                else {
                                    return nil
                                }
                                
                               
                                let maxValue = toDouble(dict["maxValue"]) ?? 10.0
                                
                                return PostStat(label: label, value: value, maxValue: maxValue)
                            }
                        }
                      

                        let likedBy = (d["likedBy"] as? [String]) ?? []
                        
                      
                        let currentUserID = self.uidToFetch ?? ""
                        
                        let matchDateTimestamp = d["matchDate"] as? Timestamp
                        let matchDate: Date? = matchDateTimestamp?.dateValue()

                        return Post(
                            authorUid: uid, // Pass the author's ID
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
                            likedBy: likedBy,
                            isLikedByUser: likedBy.contains(currentUserID), // Use correct ID
                            stats: postStats, // <-- Pass the correctly parsed stats
                            matchDate: matchDate
                        )
                    }
                    
                    await MainActor.run {
                        self.posts = mappedPosts
                        
                        // Recompute cumulative score after posts change.
                        Task {
                            await self.calculateAndUpdateScore()
                        }
                        
                    }
                }
            }
    }
    
    /// Apply local updates to like and comment counts based on notifications.
    @MainActor
    private func handlePostDataUpdate(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let updatedPostId = userInfo["postId"] as? String else {
            return
        }

        guard let index = self.posts.firstIndex(where: { $0.id == updatedPostId }) else {
            return
        }

        // Check for comment updates
        if userInfo["commentAdded"] as? Bool == true {
            self.posts[index].commentCount += 1
        }
        
        // --- ADDED: Handle comment deletion ---
        if userInfo["commentDeleted"] as? Bool == true {
            self.posts[index].commentCount = max(0, self.posts[index].commentCount - 1)
        }
        
        // Check for like updates
        if let (isLiked, likeCount) = userInfo["likeUpdate"] as? (Bool, Int) {
            self.posts[index].isLikedByUser = isLiked
            self.posts[index].likeCount = likeCount
        }
    }
    /// Calculate and persist the player's cumulative score from public AI-scored posts.
    @MainActor
    func calculateAndUpdateScore() async {
        guard let uid = uidToFetch else {
            print("Error: No user ID found.")
            return
        }

        // Weights are now Integers
        let weights: [String: [String: Int]] = [
            "Attacker": ["PASS": 3, "DRIBBLE": 8, "SHOOT": 10],
            "Midfielder": ["PASS": 8, "DRIBBLE": 7, "SHOOT": 6],
            "Defender": ["PASS": 9, "DRIBBLE": 3, "SHOOT": 1],
            "Default": ["PASS": 1, "DRIBBLE": 1, "SHOOT": 1]
        ]
        
        // 1. Get the player's position
        let position = self.userProfile.position
        
        // 2. Select the correct weights
        let positionWeights = weights[position] ?? weights["Default"]!

        // 3. Filter for posts that actually have AI data AND ARE PUBLIC
        let scoredPosts = self.posts.filter { !($0.stats?.isEmpty ?? true) && !$0.isPrivate }

        if scoredPosts.isEmpty {
            // No posts with scores yet, set score to 0
            self.userProfile.score = "0"
            // Also save '0' to Firebase if there are no public posts ---
            Task(priority: .background) {
                do {
                    let profileRef = Firestore.firestore()
                        .collection("users").document(uid)
                        .collection("player").document("profile")
                    
                    try await profileRef.setData([
                        "cumulativeScore": "0"
                    ], merge: true)
                    
                    print("✅ Successfully updated cumulativeScore: 0 (No public posts)")
                    
                } catch {
                    print("❌ Error saving cumulativeScore (0) to Firestore: \(error.localizedDescription)")
                }
            }
            return
        }

        // 4. Loop, calculate score for each post, and get the sum
        let totalScore = scoredPosts.reduce(0.0) { (accumulator, post) in
            
            let passValue = post.stats?.first { $0.label.uppercased() == "PASS" }?.value ?? 0.0
            let dribbleValue = post.stats?.first { $0.label.uppercased() == "DRIBBLE" }?.value ?? 0.0
            let shootValue = post.stats?.first { $0.label.uppercased() == "SHOOT" }?.value ?? 0.0

            // Apply weights (we cast the Int weight to Double for the math)
            let passScore = passValue * Double(positionWeights["PASS"] ?? 1)
            let dribbleScore = dribbleValue * Double(positionWeights["DRIBBLE"] ?? 1)
            let shootScore = shootValue * Double(positionWeights["SHOOT"] ?? 1)
            
            return accumulator + passScore + dribbleScore + shootScore
        }
        
        // 5. Calculate the average
        let averageScore = totalScore / Double(scoredPosts.count)
        
        // --- MODIFIED: Round to nearest whole number and convert to String ---
        let roundedScore = Int(averageScore.rounded())
        let scoreString = String(roundedScore)

        // 6. Update the UI *immediately*
        self.userProfile.score = scoreString

        // 7. Save the new score back to Firestore
        Task(priority: .background) {
            do {
                let profileRef = Firestore.firestore()
                    .collection("users").document(uid)
                    .collection("player").document("profile")
                
                try await profileRef.setData([
                    "cumulativeScore": scoreString
                ], merge: true)
                
                print("✅ Successfully updated cumulativeScore: \(scoreString)")
                
            } catch {
                print("❌ Error saving cumulativeScore to Firestore: \(error.localizedDescription)")
            }
        }

    }
}
