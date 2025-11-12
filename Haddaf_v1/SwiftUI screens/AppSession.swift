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
}
