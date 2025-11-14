import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Constants
// Custom color for the first-place crown.
private let MedalGold   = Color(red: 0.98, green: 0.80, blue: 0.20)
// Custom color for the podium blocks.
private let PodiumGreen = Color(red: 0.87, green: 0.96, blue: 0.90)

// Represents a single player's data as displayed on the leaderboard.
struct LBPlayer: Identifiable, Hashable {
    let id: String
    let name: String
    let photoURL: String?
    let position: String
    let score: Double
    let firstPostAt: Date?
    let rank: Int
}

// An enum representing the available filter options for the leaderboard.
enum PositionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case attacker = "Attacker"
    case midfielder = "Midfielder"
    case defender = "Defender"
    var id: String { rawValue }

    // Checks if a given player position string matches the filter case.
    // `true` if the position matches the filter, `false` otherwise.
    func matches(_ pos: String) -> Bool {
        let p = pos.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch self {
        case .all:        return true
        case .attacker:   return p == "attacker"
        case .midfielder: return p == "midfielder"
        case .defender:   return p == "defender"
        }
    }
}

// Manages the state and logic for the leaderboard.
@MainActor
final class LeaderboardViewModel: ObservableObject {
    // The final list of top players (at most 10) to be displayed by the view.
    @Published private(set) var topTen: [LBPlayer] = []
    // True if data is currently being fetched from Firestore.
    @Published var isLoading = false
    // The UID of the currently authenticated user, used to highlight them in the list.
    @Published private(set) var currentUserUid: String? = Auth.auth().currentUser?.uid
    // The currently selected position filter. Setting this automatically triggers `applyFilter()`.
    @Published var selectedFilter: PositionFilter = .all { didSet { applyFilter() } }

    private let db = Firestore.firestore()
    // A flag to ensure the database is only loaded once per session.
    private var loadedOnce = false
    // The complete, unsorted, and unfiltered list of all players fetched from the database.
    // This serves as the "source of truth" cache.
    private var allPlayersRaw: [(id: String, name: String, photo: String?, position: String, score: Double, firstPostAt: Date?)] = []

    // A wrapper function to ensure `loadLeaderboard` is only called once.
    func loadLeaderboardIfNeeded() {
        guard !loadedOnce else { return }
        loadedOnce = true
        Task { await loadLeaderboard() }
    }

    // Fetches all player data from Firestore.
    func loadLeaderboard() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let userSnap = try await db.collection("users")
                .whereField("role", isEqualTo: "player")
                .getDocuments()

            var basic: [(id: String, name: String, photo: String?, position: String, score: Double, firstPostAt: Date?)] = []

            try await withThrowingTaskGroup(of: (String, String, String?, String, Double, Date?)?.self) { group in
                for doc in userSnap.documents {
                    group.addTask { [db] in
                        do {
                            let uid = doc.documentID
                            let data = doc.data()
                            let first = (data["firstName"] as? String) ?? ""
                            let last  = (data["lastName"] as? String) ?? ""
                            let full  = [first, last].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                            let photo = data["profilePic"] as? String

                            // 1. Fetch player-specific profile data (score, position)
                            let pDoc = try await db.collection("users").document(uid)
                                .collection("player").document("profile").getDocument()
                            let p = pDoc.data() ?? [:]

                            // Handle score potentially being Double, Int, or String
                            let score: Double = {
                                if let d = p["cumulativeScore"] as? Double { return d }
                                if let i = p["cumulativeScore"] as? Int { return Double(i) }
                                if let s = p["cumulativeScore"] as? String, let d = Double(s) { return d }
                                return 0.0
                            }()
                            let position = (p["position"] as? String) ?? ""

                            // 2. Fetch earliest post for tie-breaking
                            var earliest: Date? = nil
                            // First, try querying by authorRef (newer data structure)
                            do {
                                let authorRef = db.collection("users").document(uid)
                                let firstPostSnap = try await db.collection("videoPosts")
                                    .whereField("authorId", isEqualTo: authorRef)
                                    .order(by: "uploadDateTime", descending: false)
                                    .limit(to: 1)
                                    .getDocuments()
                                earliest = firstPostSnap.documents.first.flatMap {
                                    ($0.data()["uploadDateTime"] as? Timestamp)?.dateValue()
                                }
                            } catch { }
                            // If not found, try querying by authorUid (older data structure)
                            if earliest == nil {
                                do {
                                    let uidSnap = try await db.collection("videoPosts")
                                        .whereField("authorUid", isEqualTo: uid)
                                        .order(by: "uploadDateTime", descending: false)
                                        .limit(to: 1)
                                        .getDocuments()
                                    earliest = uidSnap.documents.first.flatMap {
                                        ($0.data()["uploadDateTime"] as? Timestamp)?.dateValue()
                                    }
                                } catch { }
                            }

                            return (uid, full.isEmpty ? "Player" : full, photo, position, score, earliest)
                        } catch {
                            return nil // Fail gracefully for a single user
                        }
                    }
                }
                for try await item in group { if let item { basic.append(item) } }
            }

            self.allPlayersRaw = basic
            applyFilter()
        } catch {
            print("Leaderboard load error: \(error)")
            self.topTen = []
        }
    }

    // Applies the current `selectedFilter` and sorting rules to the `allPlayersRaw` data.
    private func applyFilter() {
        var filtered = allPlayersRaw
            .filter { $0.score > 0 } // Only show players who have a score
            .filter { selectedFilter.matches($0.position) } // Apply position filter

        // Sort the filtered list
        filtered.sort { a, b in
            // Primary sort: Score (descending)
            if abs(a.score - b.score) > 1e-9 { return a.score > b.score }
            
            // Secondary sort (tie-breaker): Earliest post date (ascending)
            switch (a.firstPostAt, b.firstPostAt) {
            case let (la?, lb?): return la < lb        // Both have dates, earlier wins
            case (_?, nil):     return true            // Date beats no date
            case (nil, _?):     return false           // No date loses to date
            default:            return a.name < b.name // Tertiary: Alphabetical
            }
        }

        // Map the sorted data to the LBPlayer model, assigning ranks
        var ranked: [LBPlayer] = []
        for (idx, p) in filtered.enumerated() {
            ranked.append(LBPlayer(
                id: p.id,
                name: p.name,
                photoURL: p.photo,
                position: p.position,
                score: p.score,
                firstPostAt: p.firstPostAt,
                rank: idx + 1 // Rank starts at 1
            ))
        }

        // Separate podium (top 3) from the rest of the list (max 7)
        let podium = Array(ranked.prefix(3))
        let rest   = Array(ranked.dropFirst(3).prefix(max(0, 10 - podium.count)))
        // Publish the final top 10 list
        self.topTen = podium + rest
    }
}

// MARK: - Helper Views

// A reusable view for displaying a user's avatar from a URL.
struct AvatarAsyncImage: View {
    // The URL string of the image to load.
    let url: String?
    // The width and height of the circular avatar.
    let size: CGFloat

    var body: some View {
        if let url = url, let u = URL(string: url) {
            AsyncImage(url: u) { phase in
                switch phase {
                case .empty: placeholder
                case .success(let image):
                    image.resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
                case .failure(_): placeholder
                @unknown default: placeholder
                }
            }
        } else {
            placeholder
        }
    }

    // The placeholder view to show when the URL is nil, loading, or fails.
    private var placeholder: some View {
        ZStack {
            Circle().fill(BrandColors.background)
                .overlay(
                    Image(systemName: "person.fill")
                        .resizable().scaledToFit()
                        .frame(width: size * 0.5)
                        .foregroundColor(.black.opacity(0.15))
                )
        }
        .frame(width: size, height: size)
    }
}

// A custom icon view for the filter button.
struct FilterIcon: View {
    // The width and height of the icon.
    var size: CGFloat = 30
    // If `true`, displays the filled "active" state.
    var active: Bool = false

    var body: some View {
        let lineH: CGFloat = max(2.0, size * 0.085)
        ZStack {
            if active {
                Circle().fill(BrandColors.darkTeal).frame(width: size, height: size)
                VStack(spacing: size * 0.10) {
                    RoundedRectangle(cornerRadius: lineH/2)
                        .frame(width: size * 0.62, height: lineH)
                    RoundedRectangle(cornerRadius: lineH/2)
                        .frame(width: size * 0.50, height: lineH)
                    RoundedRectangle(cornerRadius: lineH/2)
                        .frame(width: size * 0.36, height: lineH)
                }
                .foregroundColor(.white)
            } else {
                Circle().stroke(BrandColors.darkTeal, lineWidth: max(2.0, size * 0.085))
                    .frame(width: size, height: size)
                VStack(spacing: size * 0.10) {
                    RoundedRectangle(cornerRadius: lineH/2)
                        .frame(width: size * 0.62, height: lineH)
                    RoundedRectangle(cornerRadius: lineH/2)
                        .frame(width: size * 0.50, height: lineH)
                    RoundedRectangle(cornerRadius: lineH/2)
                        .frame(width: size * 0.36, height: lineH)
                }
                .foregroundColor(BrandColors.darkTeal)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .accessibilityLabel("Filter")
    }
}

// MARK: - Main View

struct LeaderboardView: View {
    // The view model that provides the data for the leaderboard.
    @ObservedObject var viewModel: LeaderboardViewModel
    // State variable to control the presentation of the filter menu.
    @State private var showFilterMenu = false

    var body: some View {
        Group {
            if viewModel.isLoading {
                VStack { Spacer(minLength: 12); ProgressView().tint(BrandColors.darkTeal) }
            } else if viewModel.topTen.isEmpty {
                VStack(spacing: 6) {
                    Spacer(minLength: 12)
                    Image(systemName: "person.3")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No players yet").foregroundColor(.secondary)
                    Spacer(minLength: 6)
                }
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        // Filter Button
                        HStack {
                            Spacer()
                            Button {
                                showFilterMenu = true
                            } label: {
                                FilterIcon(size: 26, active: viewModel.selectedFilter != .all)
                                    .padding(.trailing, 14)
                                    .padding(.top, 6)
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog("Filter by position",
                                                isPresented: $showFilterMenu,
                                                titleVisibility: .visible) {
                                ForEach(PositionFilter.allCases) { f in
                                    Button(f.rawValue) { viewModel.selectedFilter = f }
                                }
                                Button("Cancel", role: .cancel) {}
                            }
                        }
                        .padding(.horizontal, 16)

                        // Top 3 Podium
                        TopThreePodium(top: Array(viewModel.topTen.prefix(3)))
                            .padding(.top, -2)

                        // Ranks 4-10 List
                        VStack(spacing: 8) {
                            ForEach(Array(viewModel.topTen.dropFirst(3))) { p in
                                LeaderboardRow(rank: p.rank,
                                               player: p,
                                               showAsYou: p.id == viewModel.currentUserUid)
                            }
                        }
                        .padding(.horizontal, 16)

                        Spacer(minLength: 2)
                    }
                    .padding(.top, 0)
                    .onAppear { viewModel.loadLeaderboardIfNeeded() }
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 110) }
            }
        }
        .onAppear { viewModel.loadLeaderboardIfNeeded() }
    }
}

// MARK: - Podium

// A view that arranges the top 3 players into a podium.
struct TopThreePodium: View {
    // An array containing the top 3 (or fewer) players.
    let top: [LBPlayer]

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            // 2nd Place
            PodiumColumn(player: top.count > 1 ? top[1] : nil,
                         rankNumberOnBlock: top.count > 1 ? top[1].rank : 2,
                         showCrown: false,
                         blockHeight: 84,
                         avatarSize: 86)

            // 1st Place
            PodiumColumn(player: top.first,
                         rankNumberOnBlock: top.first?.rank ?? 1,
                         showCrown: true,
                         blockHeight: 118,
                         avatarSize: 104)

            // 3rd Place
            PodiumColumn(player: top.count > 2 ? top[2] : nil,
                         rankNumberOnBlock: top.count > 2 ? top[2].rank : 3,
                         showCrown: false,
                         blockHeight: 72,
                         avatarSize: 86)
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
    }
}

// A placeholder view for a podium slot when no player exists for that rank.
struct EmptyPodiumSlot: View {
    let avatarSize: CGFloat
    let columnWidth: CGFloat
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(BrandColors.background)
                    .frame(width: avatarSize, height: avatarSize)
                Image(systemName: "person.fill")
                    .resizable().scaledToFit()
                    .frame(width: avatarSize * 0.5)
                    .foregroundColor(.black.opacity(0.15))
            }
            Text("No player")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: columnWidth)
            Text(" ")
                .font(.system(size: 14))
                .frame(height: 0)
        }
    }
}

// A view representing a single column on the podium (e.g., 1st place).
struct PodiumColumn: View {
    let player: LBPlayer?
    let rankNumberOnBlock: Int
    let showCrown: Bool
    let blockHeight: CGFloat
    let avatarSize: CGFloat
    private let columnWidth: CGFloat = 120

    var body: some View {
        VStack(spacing: 6) {
            if let pl = player {
                // Player Avatar
                NavigationLink(destination: PlayerProfileContentView(userID: pl.id)) {
                    AvatarAsyncImage(url: pl.photoURL, size: avatarSize)
                        .overlay(alignment: .top) {
                            if showCrown {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(MedalGold)
                                    .offset(y: -10)
                                    .allowsHitTesting(false)
                            }
                        }
                        .padding(.top, showCrown ? 10 : 0)
                }
                .buttonStyle(.plain)

                // Player Info
                VStack(spacing: 2) {
                    Text(pl.name)
                        .font(.system(size: 16, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: columnWidth)

                    Text(pl.position.isEmpty ? "—" : pl.position)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    Text("\(formattedInt(pl.score)) score")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            } else {
                // Placeholder for empty slot
                EmptyPodiumSlot(avatarSize: avatarSize, columnWidth: columnWidth)
            }

            // Podium Block
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(PodiumGreen)
                    .frame(width: columnWidth, height: blockHeight)
                Text("\(rankNumberOnBlock)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(BrandColors.darkTeal)
            }
        }
        .frame(width: columnWidth)
    }
}

// MARK: - Row Component

// A view for a single player row in the list (ranks 4-10).
struct LeaderboardRow: View {
    let rank: Int
    let player: LBPlayer
    var showAsYou: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Rank
            Text("\(rank)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(BrandColors.darkTeal)
                .frame(width: 28)

            // Avatar
            NavigationLink(destination: PlayerProfileContentView(userID: player.id)) {
                AvatarAsyncImage(url: player.photoURL, size: 42)
            }
            .buttonStyle(.plain)

            // Name & Position
            VStack(alignment: .leading, spacing: 2) {
                Text(showAsYou ? "You" : player.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(player.position.isEmpty ? "—" : player.position)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()

            // Score
            Text("\(formattedInt(player.score)) score")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(BrandColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 2)
    }
}

// MARK: - Helpers

// Formats a score `Double` into a string with no decimal places.
private func formattedInt(_ score: Double) -> String {
    String(format: "%.0f", score)
}
