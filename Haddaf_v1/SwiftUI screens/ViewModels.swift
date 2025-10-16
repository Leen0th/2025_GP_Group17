import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class PlayerProfileViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var userProfile = UserProfile()
    @Published var posts: [Post] = []

    private let db = Firestore.firestore()
    private var postsListener: ListenerRegistration?

    deinit {
        postsListener?.remove()
    }

    // Public
    func fetchAllData() async {
        isLoading = true
        async let _ = fetchProfile()
        listenToMyPosts() // realtime
        _ = await (())
        isLoading = false
    }

    func fetchProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            // users doc
            let userDoc = try await db.collection("users").document(uid).getDocument()
            let data = userDoc.data() ?? [:]

            let first = (data["firstName"] as? String) ?? ""
            let last  = (data["lastName"]  as? String) ?? ""
            let full  = [first, last].joined(separator: " ").trimmingCharacters(in: .whitespaces)

            // player/profile
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

            // profile picture
            if let urlStr = data["profilePic"] as? String,
               let url = URL(string: urlStr),
               let bytes = try? Data(contentsOf: url),
               let img = UIImage(data: bytes) {
                userProfile.profileImage = img
            } else {
                userProfile.profileImage = UIImage(systemName: "person.circle.fill")
            }

            // optional placeholders
            userProfile.team  = "Unassigned"
            userProfile.rank  = "0"
            userProfile.score = "0"
        } catch {
            print("fetchProfile error: \(error)")
        }
    }

    // Realtime newest-first
    func listenToMyPosts() {
        postsListener?.remove()
        posts.removeAll()

        guard let uid = Auth.auth().currentUser?.uid else { return }
        let userRef = db.collection("users").document(uid)
        let df = DateFormatter(); df.dateFormat = "dd/MM/yyyy HH:mm"

        postsListener = db.collection("videoPosts")
            .whereField("authorId", isEqualTo: userRef)
            .order(by: "uploadDateTime", descending: true)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                if let err = err {
                    print("listenToMyPosts error: \(err)")
                    return
                }
                guard let docs = snap?.documents else { return }

                let mapped: [Post] = docs.compactMap { doc in
                    let d = doc.data()
                    return Post(
                        id: doc.documentID,
                        imageName: (d["thumbnailURL"] as? String) ?? "",
                        videoURL: (d["url"] as? String) ?? "",
                        caption: (d["caption"] as? String) ?? "",
                        timestamp: df.string(from: (d["uploadDateTime"] as? Timestamp)?.dateValue() ?? Date()),
                        isPrivate: !((d["visibility"] as? Bool) ?? true),
                        authorName: (d["authorUsername"] as? String) ?? "",
                        authorImageName: (d["profilePic"] as? String) ?? "",
                        likeCount: (d["likeCount"] as? Int) ?? 0,
                        commentCount: (d["commentCount"] as? Int) ?? 0,
                        isLikedByUser: false,
                        stats: nil
                    )
                }

                Task { @MainActor in
                    self.posts = mapped // already newest-first
                }
            }
    }
}
