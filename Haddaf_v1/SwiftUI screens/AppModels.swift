//
//  AppModels.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 09/10/2025.
//

import SwiftUI
import Combine
import PhotosUI

// MARK: - View Model (Observable Object)
class UserProfile: ObservableObject {
    @Published var name = "SALEM AL-DAWSARI"
    @Published var position = "Forwards"
    @Published var age = "34"
    @Published var weight = "71kg"
    @Published var height = "172cm"
    @Published var team = "AlHilal"
    @Published var rank = "1"
    @Published var score = "100"
    @Published var location = "Riyadh"
    @Published var email = "salem@email.com"
    @Published var phoneNumber = "+966 55 123 4567"
    @Published var endorsements: [CoachEndorsement] = [
            .init(coachName: "Simone Inzaghi", coachImage: "p1", endorsementText: "Salem is a phenomenal forward with a great work ethic and a powerful shot. A true asset to any team.", rating: 5),
            .init(coachName: "Jorge Jesus", coachImage: "p2", endorsementText: "A true leader on and off the pitch. His tactical awareness is second to none. Highly recommended.", rating: 5),
        ]
    
    @Published var isEmailVisible = true
    @Published var isPhoneVisible = false
    
    @Published var profileImage: UIImage? = UIImage(named: "salem_al-dawsari")
}

// MARK: - Data Models
struct PlayerStat: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

struct CoachEndorsement: Identifiable {
    let id = UUID()
    let coachName: String
    let coachImage: String
    let endorsementText: String
    let rating: Int // e.g., 4 out of 5 stars
}

struct PostStat: Identifiable {
    let id = UUID()
    let label: String
    let value: Int
    let maxValue: Int
}

struct Comment: Identifiable {
    let id = UUID()
    let username: String
    let userImage: String
    let text: String
    let timestamp: String
}

struct Post: Identifiable {
    var id = UUID()
    var imageName: String
    var caption: String = "Default"
    var timestamp: String = "Just now"
    var isPrivate: Bool
    var authorName: String = "Default"
    var authorImageName: String = "Default"
    var likeCount: Int = 0
    var isLikedByUser: Bool = false
    var comments: [Comment] = []
    var stats: [PostStat] = []
}

// MARK: - Enums
enum ContentType {
    case posts, progress, endorsements
}

enum Tab {
    case discovery, teams, action, challenge, profile
    
    var imageName: String {
        switch self {
        case .discovery: return "house"
        case .teams: return "person.3"
        case .action: return ""
        case .challenge: return "chart.bar"
        case .profile: return "person"
        }
    }
    
    var title: String {
        switch self {
        case .discovery: return "Discovery"
        case .teams: return "Teams"
        case .action: return ""
        case .challenge: return "Challenge"
        case .profile: return "Profile"
        }
    }
}

// MARK: - Extensions
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
