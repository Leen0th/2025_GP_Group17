import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

// MARK: - Player Profile ViewModel
@MainActor
class PlayerProfileViewModel: ObservableObject {
    @Published var userProfile = UserProfile()
    @Published var posts: [Post] = []
    @Published var isLoading = false
    
    private var db = Firestore.firestore()

    func fetchAllData() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("Error: User not logged in.")
            return
        }
        
        isLoading = true
        await fetchUserProfile(uid: uid)
        await fetchUserPosts(uid: uid)
        isLoading = false
    }

    private func fetchUserProfile(uid: String) async {
        let userDocRef = db.collection("users").document(uid)
        let playerProfileDocRef = userDocRef.collection("player").document("profile")

        do {
            // Fetch main user document
            let userDocument = try await userDocRef.getDocument()
            if let data = userDocument.data() {
                let firstName = data["firstName"] as? String ?? ""
                let lastName = data["lastName"] as? String ?? ""
                userProfile.name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                userProfile.email = data["email"] as? String ?? ""
                
                if let imageURLString = data["profilePic"] as? String, let url = URL(string: imageURLString) {
                    URLSession.shared.dataTask(with: url) { (data, _, _) in
                        if let data = data, let image = UIImage(data: data) {
                            DispatchQueue.main.async {
                                self.userProfile.profileImage = image
                            }
                        }
                    }.resume()
                }
            }

            // Fetch player sub-collection document
            let playerDocument = try await playerProfileDocRef.getDocument()
            if let data = playerDocument.data() {
                userProfile.position = data["position"] as? String ?? "N/A"
                
                if let dobTimestamp = data["dateOfBirth"] as? Timestamp {
                    let dob = dobTimestamp.dateValue()
                    let calendar = Calendar.current
                    let ageComponents = calendar.dateComponents([.year], from: dob, to: Date())
                    userProfile.age = "\(ageComponents.year ?? 0)"
                }
                
                userProfile.weight = "\(data["weight"] as? Int ?? 0)kg"
                userProfile.height = "\(data["height"] as? Int ?? 0)cm"
                userProfile.team = data["team"] as? String ?? "Unassigned"
                userProfile.rank = "\(data["rank"] as? Int ?? 0)"
                userProfile.score = "\(data["cumulativeScore"] as? Int ?? 0)"
                userProfile.location = data["location"] as? String ?? "N/A"
                
                // Fix #3: Get phone number from player/profile
                userProfile.phoneNumber = data["phone"] as? String ?? ""
                
                // Fix #5: Check visibility flags
                let isPhoneVisible = data["contactVisibility"] as? Bool ?? false
                let isEmailVisible = data["isEmailVisible"] as? Bool ?? false
                
                userProfile.isPhoneVisible = isPhoneVisible
                userProfile.isEmailVisible = isEmailVisible
            }

        } catch {
            print("Error fetching user profile from Firestore: \(error.localizedDescription)")
        }
    }

    private func fetchUserPosts(uid: String) async {
        let userRef = db.collection("users").document(uid)
        
        do {
            let snapshot = try await db.collection("videoPosts")
                                        .whereField("authorId", isEqualTo: userRef)
                                        .order(by: "uploadDateTime", descending: true)
                                        .getDocuments()
            
            self.posts = snapshot.documents.compactMap { document in
                let data = document.data()
                let timestamp = data["uploadDateTime"] as? Timestamp
                
                return Post(
                    id: document.documentID,
                    imageName: data["thumbnailURL"] as? String ?? "",
                    videoURL: data["url"] as? String ?? "",
                    caption: data["caption"] as? String ?? "",
                    timestamp: timestamp?.dateValue().formatted(date: .abbreviated, time: .shortened) ?? "N/A",
                    isPrivate: !(data["visibility"] as? Bool ?? true),
                    authorName: data["authorUsername"] as? String ?? "User",
                    authorImageName: data["profilePic"] as? String ?? "",
                    likeCount: data["likeCount"] as? Int ?? 0,
                    commentCount: data["commentCount"] as? Int ?? 0,
                    isLikedByUser: false
                )
            }
        } catch {
            print("Error fetching user posts: \(error.localizedDescription)")
        }
    }
}

// MARK: - Comments ViewModel
@MainActor
class CommentsViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    private var db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func fetchComments(for postId: String) {
        let commentsRef = db.collection("videoPosts").document(postId).collection("comments").order(by: "comment_date", descending: true)
        
        listener = commentsRef.addSnapshotListener { querySnapshot, error in
            guard let documents = querySnapshot?.documents else {
                print("Error fetching comments: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            self.comments = documents.compactMap { doc -> Comment? in
                let data = doc.data()
                let timestamp = data["comment_date"] as? Timestamp
                
                return Comment(
                    username: data["authorUsername"] as? String ?? "User",
                    userImage: data["authorProfileImageURL"] as? String ?? "",
                    text: data["comment_text"] as? String ?? "",
                    timestamp: timestamp?.dateValue().formatted() ?? "Just now"
                )
            }
        }
    }

    func addComment(text: String, for postId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        let userDoc = try? await db.collection("users").document(uid).getDocument()
        let username = (userDoc?.data()?["firstName"] as? String ?? "User")
        let profilePic = userDoc?.data()?["profilePic"] as? String ?? ""

        let commentData: [String: Any] = [
            "authorId": db.collection("users").document(uid),
            "authorUsername": username,
            "authorProfileImageURL": profilePic,
            "comment_text": text,
            "comment_date": Timestamp(date: Date())
        ]
        
        do {
            try await db.collection("videoPosts").document(postId).collection("comments").addDocument(data: commentData)
            try await db.collection("videoPosts").document(postId).updateData([
                "commentCount": FieldValue.increment(Int64(1))
            ])
        } catch {
            print("Error adding comment: \(error.localizedDescription)")
        }
    }
    
    func stopListening() {
        listener?.remove()
    }
}
