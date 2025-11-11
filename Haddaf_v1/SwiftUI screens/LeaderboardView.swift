//
//  LeaderboardView.swift
//  Haddaf_v1
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

private let MedalGold   = Color(red: 0.98, green: 0.80, blue: 0.20)
private let PodiumGreen = Color(red: 0.87, green: 0.96, blue: 0.90)

struct LBPlayer: Identifiable, Hashable {
    let id: String
    let name: String
    let photoURL: String?
    let position: String
    let score: Double
    let firstPostAt: Date?
    let rank: Int
}

// ====== فلتر المراكز ======
enum PositionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case attacker = "Attacker"
    case midfielder = "Midfielder"
    case defender = "Defender"
    var id: String { rawValue }

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

@MainActor
final class LeaderboardViewModel: ObservableObject {
    @Published private(set) var topTen: [LBPlayer] = []   // 1..3 بوديوم + 4..10
    @Published var isLoading = false
    @Published private(set) var currentUserUid: String? = Auth.auth().currentUser?.uid
    @Published var selectedFilter: PositionFilter = .all { didSet { applyFilter() } }

    private let db = Firestore.firestore()
    private var loadedOnce = false
    private var allPlayersRaw: [(id: String, name: String, photo: String?, position: String, score: Double, firstPostAt: Date?)] = []

    func loadLeaderboardIfNeeded() {
        guard !loadedOnce else { return }
        loadedOnce = true
        Task { await loadLeaderboard() }
    }

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

                            let pDoc = try await db.collection("users").document(uid)
                                .collection("player").document("profile").getDocument()
                            let p = pDoc.data() ?? [:]

                            let score: Double = {
                                if let d = p["cumulativeScore"] as? Double { return d }
                                if let i = p["cumulativeScore"] as? Int { return Double(i) }
                                if let s = p["cumulativeScore"] as? String, let d = Double(s) { return d }
                                return 0.0
                            }()
                            let position = (p["position"] as? String) ?? ""

                            var earliest: Date? = nil
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
                            return nil
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

    private func applyFilter() {
        // 1) فلترة حسب المركز + إخفاء score = 0
        var filtered = allPlayersRaw
            .filter { $0.score > 0 }
            .filter { selectedFilter.matches($0.position) }

        // 2) ترتيب نهائي: score ↓ ثم firstPostAt ↑ (يكسر التعادل حتى بالثواني) ثم الاسم
        filtered.sort { a, b in
            if abs(a.score - b.score) > 1e-9 { return a.score > b.score }
            switch (a.firstPostAt, b.firstPostAt) {
            case let (la?, lb?): return la < lb
            case (_?, nil):     return true
            case (nil, _?):     return false
            default:            return a.name < b.name
            }
        }

        // 3) تحويل إلى LBPlayer برتب فريدة (idx + 1)
        var ranked: [LBPlayer] = []
        for (idx, p) in filtered.enumerated() {
            ranked.append(LBPlayer(
                id: p.id,
                name: p.name,
                photoURL: p.photo,
                position: p.position,
                score: p.score,
                firstPostAt: p.firstPostAt,
                rank: idx + 1
            ))
        }

        // 4) بوديوم 1..3 ثم 4..10
        let podium = Array(ranked.prefix(3))
        let rest   = Array(ranked.dropFirst(3).prefix(max(0, 10 - podium.count)))
        self.topTen = podium + rest
    }
}

// MARK: - Avatar
struct AvatarAsyncImage: View {
    let url: String?
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

// MARK: - أيقونة الفلتر (نفس درجة لون التيال عند التفعيل)
struct FilterIcon: View {
    var size: CGFloat = 30
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

// ===== UI =====
struct LeaderboardView: View {
    @ObservedObject var viewModel: LeaderboardViewModel
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

                        // زر الفلتر – أبعدناه عن الحافة ويتلوّن عند التفعيل
                        HStack {
                            Spacer()
                            Button {
                                showFilterMenu = true
                            } label: {
                                FilterIcon(size: 26, active: viewModel.selectedFilter != .all)
                                    .padding(.trailing, 14) // أبعد عن الحافة
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

                        // بوديوم 1–2–3
                        TopThreePodium(top: Array(viewModel.topTen.prefix(3)))
                            .padding(.top, -2)  // قللنا المسافة أكثر

                        // بقية المراكز 4..10
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
                    .padding(.top, 0) // أقل ما يمكن
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
struct TopThreePodium: View {
    let top: [LBPlayer]

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            PodiumColumn(player: top.count > 1 ? top[1] : nil,
                         rankNumberOnBlock: top.count > 1 ? top[1].rank : 2,
                         showCrown: false,
                         blockHeight: 84,
                         avatarSize: 86)

            PodiumColumn(player: top.first,
                         rankNumberOnBlock: top.first?.rank ?? 1,
                         showCrown: true,
                         blockHeight: 118,
                         avatarSize: 104)

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

// خانة فاضية للبوديوم
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
            Text(" ") // يحافظ على الارتفاع بدلاً من سطر البوزشن
                .font(.system(size: 14))
                .frame(height: 0)
        }
    }
}

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
                EmptyPodiumSlot(avatarSize: avatarSize, columnWidth: columnWidth)
            }

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

struct LeaderboardRow: View {
    let rank: Int
    let player: LBPlayer
    var showAsYou: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(BrandColors.darkTeal)
                .frame(width: 28)

            NavigationLink(destination: PlayerProfileContentView(userID: player.id)) {
                AvatarAsyncImage(url: player.photoURL, size: 42)
            }
            .buttonStyle(.plain)

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

private func formattedInt(_ score: Double) -> String {
    String(format: "%.0f", score)
}
