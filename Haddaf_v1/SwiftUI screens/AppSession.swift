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
    
    private var userListener: ListenerRegistration?
    
    init() {
        // Listen to auth changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
            if let user = user {
                self?.isGuest = false
                self?.listenToUserDoc(uid: user.uid)
            } else {
                self?.isGuest = true
                self?.role = nil
                self?.coachStatus = nil
                self?.isVerifiedCoach = false
                self?.userListener?.remove()
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
                
                DispatchQueue.main.async {
                    self.role = r
                    self.coachStatus = status
                    
                    // Logic: You are verified only if role is coach AND status is approved
                    self.isVerifiedCoach = (r == "coach" && status == "approved")
                }
            }
    }
    
    func signOut() {
        try? Auth.auth().signOut()
        self.user = nil
        self.role = nil // Reset the role
        self.isVerifiedCoach = false
        self.isGuest = true
    }

}

