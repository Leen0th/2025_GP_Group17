//
//  LeaderboardView.swift
//  Haddaf_v1
//
//  ترتيب بالـ score نزولاً، وكسر التعادل بأقدم uploadDateTime.
//  Podium 1..3، وتحت يبدأ من 4، Top 10.
//
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

private let MedalGold = Color(red: 0.98, green: 0.80, blue: 0.20)

struct LBPlayer: Identifiable, Hashable {
    let id: String
    let name: String
    let photoURL: String?
    let position: String
    let score: Double
    let firstPostAt: Date?
    let rank: Int
}

@MainActor
final class LeaderboardViewModel: ObservableObject {
    @Published private(set) var topTen: [LBPlayer] = []
    @Published var isLoading = false

    @Published private(set) var currentUserUid: String? = Auth.auth().currentUser?.uid

    private let db = Firestore.firestore()
    private var loadedOnce = false

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

                            // score أساسي ثم fallback على cumulativeScore
                            let score: Double = {
                                if let d = p["score"] as? Double { return d }
                                if let i = p["score"] as? Int { return Double(i) }
                                if let s = p["score"] as? String, let d = Double(s) { return d }
                                if let d = p["cumulativeScore"] as? Double { return d }
                                if let i = p["cumulativeScore"] as? Int { return Double(i) }
                                if let s = p["cumulativeScore"] as? String, let d = Double(s) { return d }
                                return 0.0
                            }()

                            let position = (p["position"] as? String) ?? ""

                            // أقدم uploadDateTime
                            var earliest: Date? = nil
                            do {
                                let authorRef = db.collection("users").document(uid)
                                let refSnap = try await db.collection("videoPosts")
                                    .whereField("authorId", isEqualTo: authorRef)
                                    .order(by: "uploadDateTime", descending: false)
                                    .limit(to: 1)
                                    .getDocuments()
                                earliest = refSnap.documents.first.flatMap { ($0.data()["uploadDateTime"] as? Timestamp)?.dateValue() }
                            } catch { }

                            if earliest == nil {
                                do {
                                    let uidSnap = try await db.collection("videoPosts")
                                        .whereField("authorUid", isEqualTo: uid)
                                        .order(by: "uploadDateTime", descending: false)
                                        .limit(to: 1)
                                        .getDocuments()
                                    earliest = uidSnap.documents.first.flatMap { ($0.data()["uploadDateTime"] as? Timestamp)?.dateValue() }
                                } catch { }
                            }

                            return (uid,
                                    full.isEmpty ? "Player" : full,
                                    photo, position, score, earliest)
                        } catch {
                            return nil
                        }
                    }
                }
                for try await item in group { if let item { basic.append(item) } }
            }

            // المقارنة: score desc ثم earliest asc ثم الاسم
            func better(_ a: (id: String, name: String, photo: String?, position: String, score: Double, firstPostAt: Date?),
                        _ b: (id: String, name: String, photo: String?, position: String, score: Double, firstPostAt: Date?)) -> Bool {
                if abs(a.score - b.score) > 1e-9 { return a.score > b.score }
                switch (a.firstPostAt, b.firstPostAt) {
                case let (la?, lb?): return la < lb
                case (_?, nil):     return true
                case (nil, _?):     return false
                default:            return a.name < b.name
                }
            }
            basic.sort(by: better)

            // Podium
            var podium: [LBPlayer] = []
            for (idx, p) in basic.prefix(3).enumerated() {
                podium.append(LBPlayer(id: p.id, name: p.name, photoURL: p.photo,
                                       position: p.position, score: p.score,
                                       firstPostAt: p.firstPostAt, rank: idx + 1))
            }

            let podiumIDs = Set(podium.map { $0.id })
            var rest = basic.filter { !podiumIDs.contains($0.id) }
            rest.sort(by: better)

            var restPlayers: [LBPlayer] = []
            for (i, p) in rest.prefix(max(0, 10 - podium.count)).enumerated() {
                restPlayers.append(LBPlayer(id: p.id, name: p.name, photoURL: p.photo,
                                            position: p.position, score: p.score,
                                            firstPostAt: p.firstPostAt, rank: 4 + i))
            }

            self.topTen = podium + restPlayers
        } catch {
            print("Leaderboard load error: \(error)")
            self.topTen = []
        }
    }
}

// MARK: - Avatar (with fallback)
struct AvatarAsyncImage: View {
    let url: String?
    let size: CGFloat
    var ringColor: Color? = nil   // مرر MedalGold للبوديوم

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
                        .overlay(ring)
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
        .overlay(ring)
    }

    private var ring: some View {
        Group {
            if let ringColor {
                Circle().stroke(ringColor, lineWidth: 4)
            } else {
                Circle().stroke(Color.clear, lineWidth: 0)
            }
        }
    }
}

// ===== UI =====
struct LeaderboardView: View {
    @ObservedObject var viewModel: LeaderboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                ProgressView().tint(BrandColors.darkTeal).padding(.top, 0)
            } else if viewModel.topTen.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.3")
                        .font(.system(size: 44))
                        .foregroundColor(BrandColors.darkGray.opacity(0.6))
                    Text("No players yet").foregroundColor(.secondary)
                }
                .padding(.top, 0)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        TopThreePodium(top: Array(viewModel.topTen.prefix(3)))

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
                    .padding(.top, 0)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct TopThreePodium: View {
    let top: [LBPlayer]

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            if top.count > 1 { TopCircle(player: top[1]) }
            if top.count > 0 { TopCircle(player: top[0], bigger: true) }
            if top.count > 2 { TopCircle(player: top[2]) }
        }
        .padding(.horizontal, 16)
    }
}

struct TopCircle: View {
    let player: LBPlayer
    var bigger: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                // ✅ صورة قابلة للضغط → بروفايل (مع أفاتار افتراضي)
                NavigationLink(destination: PlayerProfileContentView(userID: player.id)) {
                    AvatarAsyncImage(url: player.photoURL,
                                     size: bigger ? 120 : 96,
                                     ringColor: MedalGold)
                }
                .buttonStyle(.plain)

                Text("\(player.rank)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .padding(8)
                    .background(MedalGold)
                    .clipShape(Circle())
                    .offset(y: 12)
            }
            Text(player.name)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)

            Text("\(formattedInt(player.score))[\(player.position)]")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.secondary)
        }
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

            // ✅ صورة/أفاتار قابلة للضغط
            NavigationLink(destination: PlayerProfileContentView(userID: player.id)) {
                AvatarAsyncImage(url: player.photoURL, size: 42)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(showAsYou ? "You" : player.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            Spacer()

            Text("\(formattedInt(player.score))[\(player.position)]")
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
    String(format: "%.0f", score) // بدون فاصلة عشرية
}
