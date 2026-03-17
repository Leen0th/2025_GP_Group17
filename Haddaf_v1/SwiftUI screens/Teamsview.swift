/*import SwiftUI
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
    let city: String
    let street: String
}

// MARK: - Teams ViewModel
class TeamsViewModel: ObservableObject {
    @Published var allTeams: [SaudiTeam] = []
    @Published var myTeam: SaudiTeam? = nil
    @Published var isLoading = true

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func startListening(currentUID: String?, currentRole: String?, currentTeamId: String?) {
        listener?.remove()
        isLoading = true

        listener = db.collection("teams").addSnapshotListener { [weak self] snap, _ in
            guard let self = self, let docs = snap?.documents else {
                self?.isLoading = false; return
            }
            Task {
                var teams: [SaudiTeam] = []
                for doc in docs {
                    let data = doc.data()
                    let teamName = data["teamName"] as? String ?? ""
                    let logoURL  = data["logoURL"]  as? String
                    let coachUID = data["coachUid"] as? String ?? doc.documentID
                    let city     = data["city"]     as? String ?? ""
                    let street   = data["street"]   as? String ?? ""

                    var coachName: String? = nil
                    if let cd = try? await self.db.collection("users").document(coachUID).getDocument(),
                       let cData = cd.data() {
                        let fn = cData["firstName"] as? String ?? ""
                        let ln = cData["lastName"]  as? String ?? ""
                        coachName = "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)
                    }

                    let playersSnap = try? await self.db.collection("teams").document(doc.documentID)
                        .collection("players").getDocuments()
                    let playerCount = playersSnap?.documents.count ?? 0

                    teams.append(SaudiTeam(
                        id: doc.documentID, teamName: teamName, logoURL: logoURL,
                        coachUID: coachUID, coachName: coachName, playerCount: playerCount,
                        city: city, street: street
                    ))
                }

                await MainActor.run {
                    self.allTeams = teams
                    if let uid = currentUID {
                        if currentRole == "coach" {
                            // كوتش يشوف كل التيمز اللي هو كوتشها (ممكن يكون عنده أكثر من تيم)
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

    // Navigation
    @State private var selectedTeam: SaudiTeam? = nil

    // User state
    @State private var userTeamId: String? = nil

    // Tabs
    @State private var selectedTab: TeamsTab = .saudiTeams

    // Filters
    @State private var searchText = ""
    @State private var filterCity: String? = nil
    @State private var filterStreet: String? = nil
    @State private var showFilters = false

    private let accentColor = BrandColors.darkTeal

    enum TeamsTab: String, CaseIterable {
        case saudiTeams    = "Saudi Teams"
        case matchOpps     = "Match Opportunities"
    }

    // ── Filtered teams ──────────────────────────────────────────────────
    private var filteredTeams: [SaudiTeam] {
        viewModel.allTeams.filter { team in
            let nameMatch = searchText.isEmpty
                || team.teamName.localizedCaseInsensitiveContains(searchText)
                || (team.coachName ?? "").localizedCaseInsensitiveContains(searchText)
            let cityMatch   = filterCity   == nil || team.city   == filterCity
            let streetMatch = filterStreet == nil || team.street == filterStreet
            return nameMatch && cityMatch && streetMatch
        }
    }

    // Available cities/streets for filter
    // Cities from SAUDI_ACADEMIES static data
    private var availableCities: [String] { SAUDI_ACADEMY_CITIES }

    // Streets from SAUDI_ACADEMIES, filtered by city if selected
    private var availableStreets: [String] {
        guard let city = filterCity else {
            return Array(Set(SAUDI_ACADEMIES.map { $0.street }.filter { !$0.isEmpty })).sorted()
        }
        return Array(Set(SAUDI_ACADEMIES.filter { $0.city == city }.map { $0.street })).sorted()
    }

    private var activeFiltersCount: Int {
        (filterCity != nil ? 1 : 0) + (filterStreet != nil ? 1 : 0)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Header ──────────────────────────────────────────
                    VStack(spacing: 0) {
                        // Tab Bar — exact Discovery style
                        HStack(spacing: 0) {
                            teamsTabButton(.saudiTeams)
                            Divider().frame(height: 24).padding(.horizontal, 12)
                            teamsTabButton(.matchOpps)
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(.bottom, 4)

                    // ── Tab Content — exact Discovery style (no lag) ─────
                    Group {
                        switch selectedTab {
                        case .saudiTeams:
                            saudiTeamsContent
                        case .matchOpps:
                            matchOppsContent
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedTeam) { team in
                TeamDetailView(team: team)
            }
            .onAppear { loadUserData() }
            .sheet(isPresented: $showFilters) { filtersSheet }
        }
    }

    // ── Saudi Teams Content ──────────────────────────────────────────────
    private var saudiTeamsContent: some View {
        VStack(spacing: 0) {
            // Search + Filter — exact same style as Discovery
            // Search & Filters — exact Discovery style
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(accentColor)
                    TextField("Search teams or coach...", text: $searchText)
                        .font(.system(size: 16, design: .rounded))
                        .tint(accentColor)
                }
                .padding(.vertical, 12)
                .padding(.horizontal)
                .background(BrandColors.background)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.08), radius: 5, y: 2)

                Button { showFilters = true } label: {
                    Image(systemName: activeFiltersCount > 0
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if viewModel.isLoading {
                Spacer()
                ProgressView().tint(accentColor)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {

                        // ── Player only: My Team on top ──────────────
                        if session.role == "player", let myTeam = viewModel.myTeam {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionHeader("My Team")
                                TeamCard(team: myTeam, isHighlighted: true)
                                    .padding(.horizontal, 20)
                                    .onTapGesture { selectedTeam = myTeam }
                            }
                        }

                        // ── All Teams (flat for everyone) ─────────────
                        if !filteredTeams.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionHeader("All Teams")
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                    ForEach(filteredTeams) { team in
                                        TeamCard(team: team, isHighlighted: false)
                                            .onTapGesture { selectedTeam = team }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        } else if !viewModel.isLoading {
                            emptyTeamsView
                        }
                    }
                    .padding(.top, 4).padding(.bottom, 100)
                }
            }
        }
    }

    // ── Match Opportunities ──────────────────────────────────────────────
    private var matchOppsContent: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 52))
                    .foregroundColor(accentColor.opacity(0.35))
                Text("Coming Soon")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
                Text("Match Opportunities will be available\nin the next sprint.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Text("🚧 To be developed next sprint")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.top, 4)
            }
            Spacer()
        }
    }

    // ── Filters Sheet — exact Challenge style ──────────────────────────
    private var filtersSheet: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                VStack(spacing: 14) {
                    Text("Filters")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .padding(.top, 8)

                    // City
                    filterRow(
                        title: "City",
                        rightLabel: filterCity ?? "All",
                        menu: {
                            Button("All") { filterCity = nil; filterStreet = nil }
                            Divider()
                            ForEach(SAUDI_ACADEMY_CITIES, id: \.self) { c in
                                Button(c) { filterCity = c; filterStreet = nil }
                            }
                        }
                    )

                    // Street
                    filterRow(
                        title: "Street",
                        rightLabel: filterStreet ?? "Any",
                        menu: {
                            Button("Any") { filterStreet = nil }
                            Divider()
                            ForEach(availableStreets, id: \.self) { s in
                                Button(s) { filterStreet = s }
                            }
                        }
                    )

                    Button { showFilters = false } label: {
                        Text("Apply Filters")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.95))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)

                    Button {
                        filterCity = nil; filterStreet = nil
                    } label: {
                        Text("Reset All")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showFilters = false }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func filterRow<M: View>(title: String, rightLabel: String, @ViewBuilder menu: @escaping () -> M) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
            Spacer()
            Menu { menu() } label: {
                HStack(spacing: 6) {
                    Text(rightLabel)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 5)
    }

        // ── Tab button — exact clone of Discovery's topTabButton ────────────
    @ViewBuilder
    private func teamsTabButton(_ tab: TeamsTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        } label: {
            VStack(spacing: 6) {
                Text(tab.rawValue)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(selectedTab == tab ? accentColor : accentColor.opacity(0.45))
                RoundedRectangle(cornerRadius: 1)
                    .frame(height: 2)
                    .foregroundColor(selectedTab == tab ? accentColor : .clear)
                    .frame(width: 120)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────
    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(accentColor)
            .padding(.horizontal, 20)
    }

    private var emptyTeamsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.slash").font(.system(size: 50)).foregroundColor(.secondary.opacity(0.4))
            Text("No teams found").font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundColor(.secondary)
            Text("Try adjusting your search or filters.")
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
            await MainActor.run { self.userTeamId = teamId }
            viewModel.startListening(currentUID: uid, currentRole: session.role, currentTeamId: teamId)
        }
    }
}

// MARK: - Team Card
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
                    if !team.city.isEmpty {
                        Label([team.street, team.city].filter { !$0.isEmpty }.joined(separator: "، "),
                              systemImage: "mappin.circle.fill")
                            .font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(accentColor.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(BrandColors.background)
                    .shadow(color: accentColor.opacity(0.15), radius: 12, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(accentColor.opacity(0.3), lineWidth: 1.5))
            )
        } else {
            VStack(spacing: 8) {
                teamLogoView(size: 64)
                Text(team.teamName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(accentColor).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                if !team.city.isEmpty {
                    // Street، City
                    Text([team.street, team.city].filter { !$0.isEmpty }.joined(separator: "، "))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(14).frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
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
}*/
