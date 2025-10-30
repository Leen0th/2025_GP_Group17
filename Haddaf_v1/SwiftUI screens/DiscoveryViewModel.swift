//
//  DiscoveryViewModel.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 30/10/2025.
//
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AVKit

// MARK: - Discovery View Model
@MainActor
final class DiscoveryViewModel: ObservableObject {
    // @Published var isLoading = false // Replaced with isLoadingPosts
    @Published var isLoadingPosts = true // <-- FIX: Use this for initial load
    @Published var posts: [Post] = []
    @Published var authorProfiles: [String: UserProfile] = [:] // Cache author profiles by UID

    private let db = Firestore.firestore()
    private var postsListener: ListenerRegistration?
    private let df = DateFormatter()

    init() {
        df.dateFormat = "dd/MM/yyyy HH:mm"
        listenToPublicPosts()
    }

    deinit {
        postsListener?.remove()
    }

    // Fetch all public posts (visibility == true)
    func listenToPublicPosts() {
        postsListener?.remove()
        
        self.isLoadingPosts = true

        postsListener = db.collection("videoPosts")
            .whereField("visibility", isEqualTo: true)
            .order(by: "uploadDateTime", descending: true)
            .addSnapshotListener { [weak self] snap, err in
                
                // --- FIX for Error 1 & 2 ---
                // We handle the error case first.
                // We use Task { } to move the UI update off the listener's synchronous closure.
                // We use `self?` because self is weak.
                guard let docs = snap?.documents else {
                    if let err = err { print("listenToPublicPosts error: \(err)") }
                    Task { @MainActor in
                        self?.isLoadingPosts = false
                    }
                    return
                }
                
                // Now we unwrap self for the main logic
                guard let self = self else { return }

                Task {
                    let mappedPosts: [Post] = await docs.asyncMap { doc in
                        let d = doc.data()
                        
                        // ... (rest of your mapping logic) ...
                        var postStats: [PostStat] = []
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
                        let authorIdRef = d["authorId"] as? DocumentReference
                        let authorUid = authorIdRef?.documentID ?? ""

                        if self.authorProfiles[authorUid] == nil && !authorUid.isEmpty {
                            await self.fetchAuthorProfile(uid: authorUid)
                        }

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
                            isLikedByUser: likedBy.contains(uid),
                            stats: postStats,
                            matchDate: matchDate
                        )
                    }
                    
                    await MainActor.run {
                        self.posts = mappedPosts
                        self.isLoadingPosts = false
                    }
                }
            }
        }

    // Fetch author profile (similar to fetchProfile in PlayerProfileViewModel)
    private func fetchAuthorProfile(uid: String) async {
        guard !uid.isEmpty else { return } // Don't fetch for empty UID
        // Avoid re-fetching if already in cache
        if self.authorProfiles[uid] != nil { return }
        
        do {
            let userDoc = try await db.collection("users").document(uid).getDocument()
            let data = userDoc.data() ?? [:]

            let first = (data["firstName"] as? String) ?? ""
            let last = (data["lastName"] as? String) ?? ""
            let full = [first, last].joined(separator: " ").trimmingCharacters(in: .whitespaces)

            let pDoc = try await db.collection("users").document(uid)
                .collection("player").document("profile")
                .getDocument()
            let p = pDoc.data() ?? [:]

            let profile = UserProfile()
            profile.name = full.isEmpty ? "Player" : full
            profile.position = (p["position"] as? String) ?? ""
            if let h = p["height"] as? Int { profile.height = "\(h)cm" } else { profile.height = "" }
            if let w = p["weight"] as? Int { profile.weight = "\(w)kg" } else { profile.weight = "" }
            profile.location = (p["location"] as? String) ?? ""
            profile.email = (data["email"] as? String) ?? ""
            profile.phoneNumber = (data["phone"] as? String) ?? ""
            profile.isEmailVisible = (p["isEmailVisible"] as? Bool) ?? false
            profile.isPhoneNumberVisible = (p["contactVisibility"] as? Bool) ?? false

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

            if let urlStr = data["profilePic"] as? String, !urlStr.isEmpty {
                profile.profileImage = await fetchImage(from: urlStr)
            } else {
                profile.profileImage = UIImage(systemName: "person.circle.fill")
            }

            profile.team = "Unassigned" // As per existing code
            profile.rank = "0"
            profile.score = (p["score"] as? String) ?? "0"

            await MainActor.run {
                self.authorProfiles[uid] = profile
            }
        } catch {
            print("fetchAuthorProfile error for UID \(uid): \(error)")
        }
    }

    private func fetchImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return UIImage(systemName: "person.circle.fill") }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data) ?? UIImage(systemName: "person.circle.fill")
        } catch {
            return UIImage(systemName: "person.circle.fill")
        }
    }
}
