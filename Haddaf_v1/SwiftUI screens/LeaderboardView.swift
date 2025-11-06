//
//  LeaderboardView.swift
//  Haddaf_v1
//
//  ترتيب بالـ cumulativeScore نزولاً، وكسر التعادل بأقدم uploadDateTime.
//  Podium 1..3 (٢–١–٣) بقواعد خضراء فقط، بدون خلفية عامة.
//  فلتر بالأيقونة جهة اليمين يفتح قائمة: All / Attacker / Midfielder / Defender
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

private let MedalGold = Color(red: 0.98, green: 0.80, blue: 0.20) // للتاج فقط
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

enum PositionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case attacker = "Attacker"
    case midfielder = "Midfielder"
    case defender = "Defender"
    var id: String { rawValue }

    func matches(_ pos: String) -> Bool {
        let p = pos.lowercased()
        switch self {
        case .all: return true
        case .attacker:   return p.contains("attack") || p.contains("forward") || p.contains("striker")
        case .midfielder: return p.contains("mid")
        case .defender:   return p.contains("defen")
        }
    }
}

@MainActor
final class LeaderboardViewModel: ObservableObject {
    @Published private(set) var topTen: [LBPlayer] = []
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
        func better(
            _ a: (id: String, name: String, photo: String?, position: String, score: Double, firstPostAt: Date?),
            _ b: (id: String, name: String, photo: String?, position: String, score: Double, firstPostAt: Date?)
        ) -> Bool {
            if abs(a.score - b.score) > 1e-9 { return a.score > b.score }
            switch (a.firstPostAt, b.firstPostAt) {
            case let (la?, lb?): return la < lb
            case (_?, nil):     return true
            case (nil, _?):     return false
            default:            return a.name < b.name
            }
        }

        var filtered = allPlayersRaw.filter { selectedFilter.matches($0.position) }
        filtered.sort(by: better)

        var podium: [LBPlayer] = []
        for (idx, p) in filtered.prefix(3).enumerated() {
            podium.append(LBPlayer(id: p.id, name: p.name, photoURL: p.photo,
                                   position: p.position, score: p.score,
                                   firstPostAt: p.firstPostAt, rank: idx + 1))
        }

        let podiumIDs = Set(podium.map { $0.id })
        var rest = filtered.filter { !podiumIDs.contains($0.id) }
        rest.sort(by: better)

        var restPlayers: [LBPlayer] = []
        for (i, p) in rest.prefix(max(0, 10 - podium.count)).enumerated() {
            restPlayers.append(LBPlayer(id: p.id, name: p.name, photoURL: p.photo,
                                        position: p.position, score: p.score,
                                        firstPostAt: p.firstPostAt, rank: 4 + i))
        }

        self.topTen = podium + restPlayers
    }
}

// MARK: - Avatar (بدون حافة)
struct AvatarAsyncImage: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        if let url = url, let u = URL(string: url) {
            AsyncImage(url: u) { phase in
                switch phase {
                case .empty:
                    placeholder
                case .success(let image):
                    image.resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                case .failure(_):
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(Color.black)
            Image(systemName: "person.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.5, height: size * 0.5)
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// ===== UI =====
struct LeaderboardView: View {
    @ObservedObject var viewModel: LeaderboardViewModel
    @State private var showFilterMenu = false

    var body: some View {
        VStack(spacing: 12) {

            // أيقونة الفلتر يمين (بدون نص)
            HStack {
                Spacer()
                Button {
                    showFilterMenu = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(BrandColors.darkTeal)
                }
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
            .padding(.top, 4)

            if viewModel.isLoading {
                ProgressView().tint(BrandColors.darkTeal).padding(.top, 8)
            } else if viewModel.topTen.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.3")
                        .font(.system(size: 44))
                        .foregroundColor(BrandColors.darkGray.opacity(0.6))
                    Text("No players yet").foregroundColor(.secondary)
                }
                .padding(.top, 16)
            } else {
                ScrollView {
                    VStack(spacing: 20) {

                        // مساحة علوية صغيرة لضمان ظهور التاج فوق الأفاتار
                        TopThreePodium(top: Array(viewModel.topTen.prefix(3)))
                            .padding(.top, 8)

                        VStack(spacing: 12) {
                            ForEach(Array(viewModel.topTen.dropFirst(3))) { p in
                                LeaderboardRow(rank: p.rank,
                                               player: p,
                                               showAsYou: p.id == viewModel.currentUserUid)
                            }
                        }
                        .padding(.horizontal, 16)
                        Spacer(minLength: 8)
                    }
                    .padding(.top, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear { viewModel.loadLeaderboardIfNeeded() }
    }
}

// MARK: - Podium (2–1–3) بقواعد خضراء، وتاج ثابت فوق المركز الأول
struct TopThreePodium: View {
    let top: [LBPlayer]

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            PodiumColumn(player: top.count > 1 ? top[1] : nil,
                         showCrown: false,
                         rankNumberOnBlock: 2,
                         blockHeight: 84,
                         avatarSize: 86)

            PodiumColumn(player: top.first,
                         showCrown: true,
                         rankNumberOnBlock: 1,
                         blockHeight: 120,
                         avatarSize: 104)

            PodiumColumn(player: top.count > 2 ? top[2] : nil,
                         showCrown: false,
                         rankNumberOnBlock: 3,
                         blockHeight: 72,
                         avatarSize: 86)
        }
        .padding(.horizontal, 16)
        // مساحة إضافية للأعلى لضمان عدم قصّ التاج
        .padding(.top, 6)
    }
}

struct PodiumColumn: View {
    let player: LBPlayer?
    let showCrown: Bool
    let rankNumberOnBlock: Int
    let blockHeight: CGFloat
    let avatarSize: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            // صورة اللاعب + تاج مثبت بأوفـرلاي أعلى الصورة
            AvatarAsyncImage(url: player?.photoURL, size: avatarSize)
                .overlay(alignment: .top) {
                    if showCrown {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(MedalGold)
                            .offset(y: -10) // يظهر دائماً فوق الأفاتار
                            .allowsHitTesting(false)
                    }
                }
                .padding(.top, showCrown ? 16 : 0) // مجال علوي للتاج

            // النصوص
            VStack(spacing: 2) {
                Text(player?.name ?? "—")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .frame(width: 110)

                Text((player?.position ?? "—"))
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: 110)

                if let score = player?.score {
                    Text("\(formattedInt(score)) points")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                } else {
                    Text("0 points")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            // القاعدة الخضراء
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(PodiumGreen)
                    .frame(width: 110, height: blockHeight)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 3)

                Text("\(rankNumberOnBlock)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(BrandColors.darkTeal.opacity(0.9))
            }
        }
        .frame(width: 110)
    }
}

struct LeaderboardRow: View {
    let rank: Int
    let player: LBPlayer
    var showAsYou: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(BrandColors.darkTeal)
                .frame(width: 28, alignment: .center)

            NavigationLink(destination: PlayerProfileContentView(userID: player.id)) {
                AvatarAsyncImage(url: player.photoURL, size: 42)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(showAsYou ? "You" : player.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                Text(player.position.isEmpty ? "—" : player.position)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer()

            Text("\(formattedInt(player.score)) points")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(showAsYou ? BrandColors.background.opacity(0.9) : BrandColors.background)
        .overlay(
            showAsYou ? RoundedRectangle(cornerRadius: 16).stroke(BrandColors.darkTeal.opacity(0.3), lineWidth: 1) : nil
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

// MARK: - Helpers
private func formattedInt(_ score: Double) -> String {
    String(format: "%.0f", score)
}
