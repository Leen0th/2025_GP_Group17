import SwiftUI
import Combine
import PhotosUI

// MARK: - Video Transferable
// This struct helps transfer the video from the PhotosPicker to the app.
// It has been moved here from the ViewModel to be more accessible.
struct VideoPickerTransferable: Transferable {
    let videoURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.videoURL)
        } importing: { received in
            let fileName = received.file.lastPathComponent
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: copy.path) {
                try FileManager.default.removeItem(at: copy)
            }
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self.init(videoURL: copy)
        }
    }
}


// MARK: - View Model (Observable Object)
// This class is now primarily a data holder. The fetching logic is in PlayerProfileViewModel.
class UserProfile: ObservableObject {
    @Published var name = "Loading..."
    @Published var position = ""
    @Published var age = ""
    @Published var weight = ""
    @Published var height = ""
    @Published var team = ""
    @Published var rank = ""
    @Published var score = ""
    @Published var location = ""
    @Published var email = ""
    @Published var phoneNumber = ""
    
    // ✅ FIXED: Added properties back to match EditProfileView
    @Published var isEmailVisible = false
    @Published var isPhoneVisible = false
    
    @Published var profileImage: UIImage? = UIImage(systemName: "person.circle.fill")
    
    // Endorsements would need their own fetching logic if moved to Firebase
    @Published var endorsements: [CoachEndorsement] = [
        .init(coachName: "Simone Inzaghi", coachImage: "p1", endorsementText: "Salem is a phenomenal forward with a great work ethic and a powerful shot. A true asset to any team.", rating: 5),
        .init(coachName: "Jorge Jesus", coachImage: "p2", endorsementText: "A true leader on and off the pitch. His tactical awareness is second to none. Highly recommended.", rating: 5),
    ]
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
    let rating: Int
}

// MODIFIED: This now aligns with the 'performanceFeedback' subcollection
struct PostStat: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let value: Double
}

struct Comment: Identifiable {
    let id = UUID()
    let username: String
    let userImage: String
    let text: String
    let timestamp: String
}

// MODIFIED: Post struct updated for Firebase data and made Equatable
struct Post: Identifiable, Equatable {
    var id: String? // Firestore Document ID
    var imageName: String // Thumbnail URL
    var videoURL: String?
    var caption: String
    var timestamp: String
    var isPrivate: Bool
    var authorName: String
    var authorImageName: String // Author Profile Pic URL
    var likeCount: Int
    var commentCount: Int
    var isLikedByUser: Bool
    var stats: [PostStat]? // Performance feedback stats
}

// MARK: - Enums (Unchanged)
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

// MARK: - Extensions (Unchanged)
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
