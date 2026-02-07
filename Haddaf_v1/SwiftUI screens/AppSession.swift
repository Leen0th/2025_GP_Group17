//
//  AppSession.swift
//  Haddaf_v1
//
//  Created by Lujain Alhussan on 21/05/1447 AH.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

final class AppSession: ObservableObject {
    @Published var user: User?
    @Published var isGuest = false
    @Published var role: String? = nil
    
    @Published var coachStatus: String? = nil
    @Published var isVerifiedCoach: Bool = false
    @Published var rejectionReason: String? = nil
    @Published var rejectionCategory: String? = nil
    
    var userListener: ListenerRegistration?
    
    init() {
        // ⬇️ استمع للتغيرات في Auth
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.user = user
                
                if let user = user {
                    // المستخدم مسجل دخول
                    self.isGuest = user.isAnonymous
                    self.listenToUserDoc(uid: user.uid)
                } else {
                    // المستخدم مسجل خروج
                    self.isGuest = false
                    self.role = nil
                    self.coachStatus = nil
                    self.isVerifiedCoach = false
                    self.userListener?.remove()
                    self.userListener = nil
                }
            }
        }
    }
    
    func listenToUserDoc(uid: String) {
        userListener?.remove()
        userListener = Firestore.firestore().collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, error in
                guard let self = self, let data = snap?.data() else { return }
                
                let r = data["role"] as? String ?? "player"
                let status = data["coachStatus"] as? String ?? "pending"
                let reason = data["rejectionReason"] as? String
                let category = data["rejectionCategory"] as? String
                
                DispatchQueue.main.async {
                    self.role = r
                    self.coachStatus = status
                    self.rejectionReason = reason
                    self.rejectionCategory = category
                    self.isVerifiedCoach = (r == "coach" && status == "approved")
                }
            }
    }
    
    func signOut() {
        // امسح الـ listener أولاً
        userListener?.remove()
        userListener = nil
        
        // امسح الـ session data
        self.user = nil
        self.role = nil
        self.coachStatus = nil
        self.isVerifiedCoach = false
        self.isGuest = false
        
        // سجل خروج من Firebase
        try? Auth.auth().signOut()
    }
}
