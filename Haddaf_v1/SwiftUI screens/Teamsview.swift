import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Team Model
struct SaudiTeam: Identifiable, Hashable {
    let id: String
    let teamName: String
    let logoURL: String?
    let coachUID: String
    let coachName: String?
    var playerCount: Int
}

// MARK: - Teams ViewModel
class TeamsViewModel: ObservableObject {
    @Published var allTeams: [SaudiTeam] = []
    @Published var myTeam: SaudiTeam? = nil
    @Published var isLoading = true
    @Published var searchText = ""

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    var filteredTeams: [SaudiTeam] {
        if searchText.isEmpty { return allTeams }
        return allTeams.filter { $0.teamName.localizedCaseInsensitiveContains(searchText) }
    }

    func startListening(currentUID: String?, currentRole: String?, currentTeamId: String?) {
        listener?.remove()
        isLoading = true

        listener = db.collection("teams").addSnapshotListener { [weak self] snap, _ in
            guard let self = self, let docs = snap?.documents else {
                self?.isLoading = false
                return
            }
            Task {
                var teams: [SaudiTeam] = []
                for doc in docs {
                    let data = doc.data()
                    let teamName = data["teamName"] as? String ?? ""
                    let logoURL = data["logoURL"] as? String
                    let coachUID = data["coachUid"] as? String ?? doc.documentID

                    var coachName: String? = nil
                    if let coachDoc = try? await self.db.collection("users").document(coachUID).getDocument(),
                       let cData = coachDoc.data() {
                        let fn = cData["firstName"] as? String ?? ""
                        let ln = cData["lastName"] as? String ?? ""
                        coachName = "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)
                    }

                    let playersSnap = try? await self.db.collection("teams").document(doc.documentID)
                        .collection("players").getDocuments()
                    let playerCount = playersSnap?.documents.count ?? 0

                    teams.append(SaudiTeam(
                        id: doc.documentID,
                        teamName: teamName,
                        logoURL: logoURL,
                        coachUID: coachUID,
                        coachName: coachName,
                        playerCount: playerCount
                    ))
                }

                await MainActor.run {
                    self.allTeams = teams
                    if let uid = currentUID {
                        if currentRole == "coach" {
                            self.myTeam = teams.first { $0.coachUID == uid }
                        } else if let teamId = currentTeamId {
                            self.myTeam = teams.first { $0.id == teamId }
                        }
                    }
                    self.isLoading = false
                }
            }
        }
    }

    func stopListening() { listener?.remove(); listener = nil }
}

// MARK: - Teams View
struct TeamsView: View {
    @EnvironmentObject var session: AppSession
    @StateObject private var viewModel = TeamsViewModel()
    @State private var selectedTeam: SaudiTeam? = nil
    @State private var showCreateTeam = false
    @State private var userTeamId: String? = nil
    @State private var coachStatusApproved = false

    private let accentColor = BrandColors.darkTeal

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ✅ Header - كلمة Teams في النص
                    VStack(spacing: 16) {
                        Text("Teams")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(accentColor)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 16)

                        // Search Bar
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").foregroundColor(.gray)
                            TextField("Search teams...", text: $viewModel.searchText)
                                .font(.system(size: 15, design: .rounded))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(BrandColors.background)
                                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                        )
                        .padding(.horizontal, 20)
                    }

                    if viewModel.isLoading {
                        Spacer()
                        ProgressView().tint(accentColor)
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 20) {

                                // ✅ My Team section
                                if let myTeam = viewModel.myTeam {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("My Team")
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundColor(accentColor.opacity(0.8))
                                            .padding(.horizontal, 20)
                                        TeamCard(team: myTeam, isHighlighted: true)
                                            .padding(.horizontal, 20)
                                            .onTapGesture { selectedTeam = myTeam }
                                    }
                                } else if session.role == "coach" && coachStatusApproved {
                                    // ✅ كوتش بدون فريق - زر Create Team في وسط الصفحة فقط
                                    VStack(spacing: 16) {
                                        Image(systemName: "shield.slash")
                                            .font(.system(size: 50))
                                            .foregroundColor(.secondary.opacity(0.4))
                                        Text("No Team Yet")
                                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                                            .foregroundColor(.secondary)
                                        Text("Create your team to start inviting players.")
                                            .font(.system(size: 14, design: .rounded))
                                            .foregroundColor(.secondary.opacity(0.7))
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 40)
                                        Button { showCreateTeam = true } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: "plus.circle.fill")
                                                Text("Create Team")
                                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 30).padding(.vertical, 14)
                                            .background(accentColor)
                                            .clipShape(Capsule())
                                            .shadow(color: accentColor.opacity(0.3), radius: 10, y: 4)
                                        }
                                    }
                                    .padding(.top, 60)
                                }

                                // All Teams Grid
                                if !viewModel.filteredTeams.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("All Teams")
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundColor(accentColor.opacity(0.8))
                                            .padding(.horizontal, 20)
                                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                            ForEach(viewModel.filteredTeams) { team in
                                                TeamCard(team: team, isHighlighted: false)
                                                    .onTapGesture { selectedTeam = team }
                                            }
                                        }
                                        .padding(.horizontal, 20)
                                    }
                                } else if !viewModel.isLoading && viewModel.myTeam == nil && !(session.role == "coach" && coachStatusApproved) {
                                    emptyTeamsView
                                }
                            }
                            .padding(.top, 16).padding(.bottom, 100)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedTeam) { team in
                TeamDetailView(team: team)
            }
            .sheet(isPresented: $showCreateTeam) {
                CreateTeamSheet(onCreated: { showCreateTeam = false; loadUserData() })
            }
            .onAppear { loadUserData() }
        }
    }

    private var emptyTeamsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.slash").font(.system(size: 50)).foregroundColor(.secondary.opacity(0.4))
            Text("No teams yet").font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundColor(.secondary)
            Text("Teams will appear here once coaches create them.")
                .font(.system(size: 14, design: .rounded)).foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .padding(.top, 60)
    }

    private func loadUserData() {
        guard let uid = session.user?.uid else {
            viewModel.startListening(currentUID: nil, currentRole: nil, currentTeamId: nil); return
        }
        Task {
            let doc = try? await Firestore.firestore().collection("users").document(uid).getDocument()
            let teamId = doc?.data()?["teamId"] as? String
            let coachStatus = doc?.data()?["coachStatus"] as? String
            await MainActor.run {
                self.userTeamId = teamId
                self.coachStatusApproved = (coachStatus == "approved")
            }
            viewModel.startListening(currentUID: uid, currentRole: session.role, currentTeamId: teamId)
        }
    }
}

struct TeamCard: View {
    let team: SaudiTeam
    let isHighlighted: Bool
    @State private var logoImage: UIImage? = nil
    private let accentColor = BrandColors.darkTeal

    var body: some View {
        if isHighlighted {
            HStack(spacing: 16) {
                teamLogoView(size: 70)
                VStack(alignment: .leading, spacing: 6) {
                    Text(team.teamName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor).lineLimit(1)
                    if let cn = team.coachName, !cn.isEmpty {
                        Label(cn, systemImage: "person.fill")
                            .font(.system(size: 13, design: .rounded)).foregroundColor(.secondary)
                    }
                    Label("\(team.playerCount) players", systemImage: "person.3.fill")
                        .font(.system(size: 13, design: .rounded)).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(accentColor.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(BrandColors.background)
                    .shadow(color: accentColor.opacity(0.15), radius: 12, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(accentColor.opacity(0.3), lineWidth: 1.5))
            )
        } else {
            VStack(spacing: 12) {
                teamLogoView(size: 80)
                Text(team.teamName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(accentColor).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            .padding(16).frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(BrandColors.background).shadow(color: .black.opacity(0.07), radius: 8, y: 4)
            )
        }
    }

    @ViewBuilder
    private func teamLogoView(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(accentColor.opacity(0.1)).frame(width: size, height: size)
            if let img = logoImage {
                Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
            } else {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: size * 0.4)).foregroundColor(accentColor.opacity(0.6))
            }
        }
        .onAppear { loadLogo() }
    }

    private func loadLogo() {
        guard let u = team.logoURL, !u.isEmpty, let url = URL(string: u) else { return }
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url), let img = UIImage(data: data) {
                await MainActor.run { logoImage = img }
            }
        }
    }
}
