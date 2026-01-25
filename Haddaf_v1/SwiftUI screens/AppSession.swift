//
//  AppSession.swift
//  Haddaf_v1
//
//  Created by Lujain Alhussan on 21/05/1447 AH.
//

import SwiftUI
import FirebaseAuth

final class AppSession: ObservableObject {
    @Published var user: User?
    @Published var isGuest = false
    @Published var role: String? = nil
    @Published var isVerifiedCoach: Bool = false
    
    func signOut() {
        try? Auth.auth().signOut()
        self.user = nil
        self.role = nil // Reset the role
        self.isVerifiedCoach = false
        self.isGuest = true
    }

}

