import SwiftUI
import Combine
import PhotosUI
import Foundation

// MARK: - NEW: Brand Color Palette
struct BrandColors {
    // Primary
    static let darkGray = Color(hex: "#262626")
    static let lightGray = Color(hex: "#F2F2F2")
    static let background = Color(hex: "#FFFFFC")
    static let actionGreen = Color(hex: "#1EA061")
    static let darkTeal = Color(hex: "#175151")
    
    // Secondary
    static let almostBlack = Color(hex: "#0D0D0D")
    static let gold = Color(hex: "#F8D361")
    static let turquoise = Color(hex: "#33C9B8")
    static let teal = Color(hex: "#26998C")
    
    // Gradients
    static let backgroundGradientEnd = Color(hex: "#F7F9F7") // Subtle green-tinted white
    static let gradientBackground = LinearGradient(
        gradient: Gradient(colors: [background, backgroundGradientEnd]),
        startPoint: .top,
        endPoint: .bottom
    )
}

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
    @Published var dob: Date? = nil
    @Published var weight = ""
    @Published var height = ""
    @Published var team = ""
    @Published var rank = ""
    @Published var score = ""
    @Published var location = ""
    @Published var email = ""
    @Published var phoneNumber: String = ""
    
    // ✅ FIXED: Added properties back to match EditProfileView
    @Published var isEmailVisible = false
    @Published var isPhoneNumberVisible: Bool = false

    @Published var profileImage: UIImage? = UIImage(systemName: "person.circle.fill")
    
    // Endorsements would need their own fetching logic if moved to Firebase
    @Published var endorsements: [CoachEndorsement] = [
        //.init(coachName: "Simone Inzaghi", coachImage: "p1", endorsementText: "Salem is a phenomenal forward with a great work ethic and a powerful shot. A true asset to any team.", rating: 5),
        //.init(coachName: "Jorge Jesus", coachImage: "p2", endorsementText: "A true leader on and off the pitch. His tactical awareness is second to none. Highly recommended.", rating: 5),
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
    var likedBy: [String]
    var isLikedByUser: Bool
    var stats: [PostStat]? // Performance feedback stats
    var matchDate: Date? // --- MODIFIED: Changed from String? to Date? ---
}

// MARK: - Enums (Unchanged)
enum ContentType {
    case posts, progress, endorsements
}

enum Tab {
    case discovery, teams, action, challenge, profile
    
    var imageName: String {
        switch self {
        case .discovery: return "magnifyingglass"
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


// MARK: - - - - - - - - - - - - - - - - - - - -
// MARK: - SHARED MODELS & HELPERS (MOVED HERE)
// MARK: - - - - - - - - - - - - - - - - - - - -

// MARK: - Country Code Model
struct CountryDialCode: Identifiable {
    let id = UUID()
    let name: String
    let code: String
}

let countryCodes: [CountryDialCode] = [
    .init(name: "Saudi Arabia", code: "+966"),
    .init(name: "Qatar", code: "+974"),
    .init(name: "United Arab Emirates", code: "+971"),
    .init(name: "Kuwait", code: "+965"),
    .init(name: "Bahrain", code: "+973"),
    .init(name: "Oman", code: "+968"),
    .init(name: "Jordan", code: "+962"),
    .init(name: "Egypt", code: "+20"),
    .init(name: "United States", code: "+1"),
    .init(name: "United Kingdom", code: "+44"),
    .init(name: "Germany", code: "+49"),
    .init(name: "France", code: "+33"),
    .init(name: "Spain", code: "+34"),
    .init(name: "Italy", code: "+39"),
    .init(name: "India", code: "+91"),
    .init(name: "Pakistan", code: "+92"),
    .init(name: "Philippines", code: "+63"),
    .init(name: "Indonesia", code: "+62"),
    .init(name: "Malaysia", code: "+60"),
    .init(name: "South Africa", code: "+27"),
    .init(name: "Canada", code: "+1"),
    .init(name: "Mexico", code: "+52"),
    .init(name: "Brazil", code: "+55"),
    .init(name: "Argentina", code: "+54"),
    .init(name: "Nigeria", code: "+234"),
    .init(name: "Russia", code: "+7"),
    .init(name: "China", code: "+86"),
    .init(name: "Japan", code: "+81"),
    .init(name: "South Korea", code: "+82")
].sorted { $0.name < $1.name }

// MARK: - Phone Number Parser
/// Splits a full phone number (e.g., "+966501234567" or "0501234567")
/// into its constituent country code and local part.
func parsePhoneNumber(_ phone: String) -> (CountryDialCode, String) {
    let ksa = countryCodes.first { $0.code == "+966" } ?? countryCodes[0]
    
    // Sort codes by length, longest first, to match "+971" before "+97"
    let sortedCodes = countryCodes.sorted { $0.code.count > $1.code.count }

    for country in sortedCodes {
        if phone.hasPrefix(country.code) {
            let localPart = String(phone.dropFirst(country.code.count))
            return (country, localPart)
        }
    }

    // Fallback: Check for local KSA number "05..."
    if phone.starts(with: "05") && phone.count == 10 {
        let localPart = String(phone.dropFirst(1)) // "5..."
        return (ksa, localPart)
    }
    
    // Fallback: Check for local KSA number "5..."
    if phone.starts(with: "5") && phone.count == 9 {
        return (ksa, phone)
    }

    // Default fallback: return KSA and the original string as local
    return (ksa, phone.filter(\.isNumber))
}

// MARK: - Validation Helpers
func isValidEmail(_ raw: String) -> Bool {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return false }
    if value.contains("..") { return false }
    let pattern = #"^(?![.])([A-Za-z0-9._%+-]{1,64})(?<![.])@([A-Za-z0-9-]{1,63}\.)+[A-Za-z]{2,63}$"#
    return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: value)
}

func isValidPhone(code: String, local: String) -> Bool {
    guard !local.isEmpty else { return false }
    let len = local.count
    var ok = (6...15).contains(len) // General rule
    
    // KSA-specific rule
    if code == "+966" {
        ok = (len == 9) && local.first == "5"
    }
    return ok
}

// MARK: - Shared Picker Sheets
struct PositionWheelPickerSheet: View {
    let positions: [String]
    @Binding var selection: String
    @Binding var showSheet: Bool
    @State private var tempSelection: String = ""
    private let primary = Color(hex: "#36796C")

    var body: some View {
        VStack(spacing: 16) {
            Text("Select your position")
                .font(.custom("Poppins", size: 18))
                .foregroundColor(primary)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            
            Picker("", selection: $tempSelection) {
                ForEach(positions, id: \.self) { pos in Text(pos).tag(pos) }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 180)
            
            Button("Done") {
                selection = tempSelection
                showSheet = false
            }
            .font(.custom("Poppins", size: 18))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(primary)
            .clipShape(Capsule())
            .padding(.bottom, 16)
        }
        .onAppear { tempSelection = selection.isEmpty ? (positions.first ?? "") : selection }
        .padding(.horizontal, 20)
    }
}

struct LocationPickerSheet: View {
    let title: String
    let allCities: [String]
    @Binding var selection: String
    @Binding var searchText: String
    @Binding var showSheet: Bool
    let accent: Color
    
    var filtered: [String] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return allCities }
        return allCities.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered, id: \.self) { city in
                    Button {
                        selection = city
                        showSheet = false
                    } label: {
                        HStack {
                            Text(city).foregroundColor(.black)
                            Spacer()
                            if city == selection {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search city")
            .navigationTitle(Text(title))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSheet = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct DateWheelPickerSheet: View {
    @Binding var selection: Date?
    @Binding var tempSelection: Date
    @Binding var showSheet: Bool
    private let primary = Color(hex: "#36796C")

    var body: some View {
        VStack(spacing: 16) {
            Text("Select your birth date")
                .font(.custom("Poppins", size: 18))
                .foregroundColor(primary)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            
            DatePicker("", selection: $tempSelection, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .tint(primary)
                .frame(height: 180)
            
            Button("Done") {
                selection = tempSelection
                showSheet = false
            }
            .font(.custom("Poppins", size: 18))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(primary)
            .clipShape(Capsule())
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
    }
}

struct CountryCodePickerSheet: View {
    @Binding var selected: CountryDialCode
    let primary: Color
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    
    // Filtered list based on search query
    var filteredCodes: [CountryDialCode] {
        if query.isEmpty {
            return countryCodes
        }
        return countryCodes.filter {
            $0.name.lowercased().contains(query.lowercased()) ||
            $0.code.contains(query)
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                // Search bar
                TextField("Search Country or Code", text: $query)
                    .autocorrectionDisabled(true)
                    .tint(primary)

                ForEach(filteredCodes, id: \.id) { country in
                    Button {
                        selected = country
                        dismiss()
                    } label: {
                        HStack {
                            Text(country.name)
                            Spacer()
                            Text(country.code)
                                .foregroundColor(.secondary)
                            if country.code == selected.code {
                                Image(systemName: "checkmark")
                                    .foregroundColor(primary)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Select Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }.tint(primary)
                }
            }
        }
    }
}


// MARK: - Saudi cities
let SAUDI_CITIES: [String] = [
    "Riyadh", "Jeddah", "Mecca", "Medina", "Dammam", "Khobar", "Dhahran", "Taif", "Tabuk",
    "Abha", "Khamis Mushait", "Jizan", "Najran", "Hail", "Buraydah", "Unaizah", "Al Hofuf",
    "Al Mubarraz", "Jubail", "Yanbu", "Rabigh", "Al Baha", "Bisha", "Al Majmaah", "Al Zulfi",
    "Sakaka", "Arar", "Qurayyat", "Rafha", "Turaif", "Tarut", "Qatif", "Safwa", "Saihat",
    "Al Khafji", "Al Ahsa", "Al Qassim", "Al Qaisumah", "Sharurah", "Tendaha", "Wadi ad-Dawasir",
    "Al Qurayyat", "Tayma", "Umluj", "Haql", "Al Wajh", "Al Lith", "Al Qunfudhah", "Sabya",
    "Abu Arish", "Samtah", "Baljurashi", "Al Mandaq", "Qilwah", "Al Namas", "Tanomah",
    "Mahd adh Dhahab", "Badr", "Al Ula", "Khaybar", "Al Bukayriyah", "Riyadh Al Khabra",
    "Al Rass", "Diriyah", "Al Kharj", "Hotat Bani Tamim", "Al Hariq", "Wadi Al Dawasir",
    "Afif", "Dawadmi", "Shaqra", "Thadig", "Muzahmiyah", "Rumah", "Ad Dilam", "Al Quwayiyah",
    "Duba", "Turaif", "Ar Ruwais", "Farasan", "Al Dayer", "Fifa", "Al Aridhah", "Al Bahah City",
    "King Abdullah Economic City", "Al Uyaynah", "Al Badayea", "Al Uwayqilah", "Bathaa",
    "Al Jafr", "Thuqbah", "Buqayq (Abqaiq)", "Ain Dar", "Nairyah", "Al Hassa", "Salwa",
    "Ras Tanura", "Khafji", "Manfouha", "Al Muzahmiyah"
].sorted()

// MARK: - NOTIFICATION MODELS (NEW)

// This enum matches the categories in NotificationsView
enum AppNotificationType: String, CaseIterable, Identifiable {
    case all = "All"
    case newChallenge = "New Challenge"
    case upcomingMatch = "Upcoming Match"
    case personalMilestones = "Personal Milestones"
    case endorsements = "Endorsements"
    case likes = "Likes"
    case comments = "Comments"
    
    var id: String { self.rawValue }
    
    var iconName: String {
        switch self {
        case .all: return "bell"
        case .newChallenge: return "trophy"
        case .upcomingMatch: return "calendar"
        case .personalMilestones: return "star"
        case .endorsements: return "person.badge.shield.checkmark"
        case .likes: return "heart"
        case .comments: return "text.bubble"
        }
    }
}

// A model for a single notification item
struct AppNotification: Identifiable {
    let id = UUID()
    let type: AppNotificationType
    let title: String
    let message: String
    let date: Date
    let isRead: Bool = false
    
    // Helper for displaying time ago
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
