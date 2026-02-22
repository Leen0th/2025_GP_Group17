import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Player in Team Model
struct TeamPlayer: Identifiable {
    let id: String
    let name: String
    let profilePicURL: String?
    let position: String?
    let jerseyNumber: Int?
}

// MARK: - TeamDetailViewModel
class TeamDetailViewModel: ObservableObject {
    @Published var players: [TeamPlayer] = []
    @Published var pendingInvitedUIDs: Set<String> = []
    @Published var coachName: String = ""
    @Published var coachProfilePicURL: String? = nil
    @Published var isLoading = true

    private let db = Firestore.firestore()
    private var playersListener: ListenerRegistration?
    private var invitationsListener: ListenerRegistration?

    func load(team: SaudiTeam) {
        isLoading = true
        Task {
            if let doc = try? await db.collection("users").document(team.coachUID).getDocument(),
               let data = doc.data() {
                let fn = data["firstName"] as? String ?? ""
                let ln = data["lastName"] as? String ?? ""
                await MainActor.run {
                    self.coachName = "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)
                    self.coachProfilePicURL = data["profilePic"] as? String
                }
            }
        }

        playersListener?.remove()
        playersListener = db.collection("teams").document(team.id)
            .collection("players")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self = self else { return }
                Task {
                    var fetched: [TeamPlayer] = []
                    for doc in snap?.documents ?? [] {
                        let uid = doc.documentID
                        if let userDoc = try? await self.db.collection("users").document(uid).getDocument(),
                           let data = userDoc.data() {
                            let fn = data["firstName"] as? String ?? ""
                            let ln = data["lastName"] as? String ?? ""
                            fetched.append(TeamPlayer(
                                id: uid,
                                name: "\(fn) \(ln)".trimmingCharacters(in: .whitespaces),
                                profilePicURL: data["profilePic"] as? String,
                                position: data["position"] as? String,
                                jerseyNumber: nil
                            ))
                        }
                    }
                    await MainActor.run { self.players = fetched; self.isLoading = false }
                }
            }

        invitationsListener?.remove()
        invitationsListener = db.collection("invitations")
            .whereField("teamID", isEqualTo: team.id)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snap, _ in
                var uids = Set<String>()
                for doc in snap?.documents ?? [] {
                    if let pid = doc.data()["playerID"] as? String { uids.insert(pid) }
                }
                DispatchQueue.main.async { self?.pendingInvitedUIDs = uids }
            }
    }

    func removePlayer(teamId: String, playerUID: String, teamName: String) async throws {
        let batch = db.batch()
        batch.deleteDocument(db.collection("teams").document(teamId).collection("players").document(playerUID))
        batch.updateData(["teamId": FieldValue.delete(), "teamName": FieldValue.delete()],
                         forDocument: db.collection("users").document(playerUID))
        try await batch.commit()
        await NotificationService.sendRemovedFromTeamNotification(playerUID: playerUID, teamName: teamName)
    }

    func sendInvitation(teamId: String, teamName: String, coachUID: String, playerUID: String) async throws {
        let existing = try await db.collection("invitations")
            .whereField("teamID", isEqualTo: teamId)
            .whereField("playerID", isEqualTo: playerUID)
            .whereField("status", isEqualTo: "pending")
            .getDocuments()
        guard existing.documents.isEmpty else { return }

        let invitationId = UUID().uuidString
        let data: [String: Any] = [
            "coachID": coachUID,
            "playerID": playerUID,
            "teamID": teamId,
            "teamName": teamName,
            "status": "pending",
            "createdAt": FieldValue.serverTimestamp()
        ]
        try await db.collection("invitations").document(invitationId).setData(data)
        await NotificationService.sendInvitationNotification(
            playerUID: playerUID, coachUID: coachUID, teamName: teamName, invitationId: invitationId
        )
    }

    deinit { playersListener?.remove(); invitationsListener?.remove() }
}

// MARK: - Team Detail View
struct TeamDetailView: View {
    let team: SaudiTeam
    @EnvironmentObject var session: AppSession
    @StateObject private var viewModel = TeamDetailViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var showInviteSearch = false
    @State private var showRemoveConfirm = false
    @State private var playerToRemove: TeamPlayer? = nil
    @State private var pendingUIDToRemove: String? = nil
    @State private var pendingNameToRemove: String = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var navigateToPlayerUID: String? = nil

    private let accentColor = BrandColors.darkTeal
    private var isCoachOfThisTeam: Bool {
        session.role == "coach" && team.coachUID == session.user?.uid
    }

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    teamHeaderSection
                    coachCard
                    playersSection
                }
                .padding(.bottom, 100)
            }

            // ✅ Remove Player custom popup
            if showRemoveConfirm, let player = playerToRemove {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { withAnimation { showRemoveConfirm = false } }
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Text("Remove Player?")
                            .font(.system(size: 18, weight: .bold))
                        Text("Are you sure you want to remove \(player.name) from the team?")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24).padding(.horizontal, 20).padding(.bottom, 20)

                    Divider()

                    HStack(spacing: 12) {
                        Button {
                            withAnimation { showRemoveConfirm = false }
                        } label: {
                            Text("No")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Button {
                            withAnimation { showRemoveConfirm = false }
                            Task {
                                do {
                                    try await viewModel.removePlayer(teamId: team.id, playerUID: player.id, teamName: team.teamName)
                                } catch {
                                    alertMessage = error.localizedDescription
                                    showAlert = true
                                }
                            }
                        } label: {
                            Text("Yes")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 16)
                }
                .background(RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)))
                .padding(.horizontal, 30)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                .transition(.scale.combined(with: .opacity))
            }

            // ✅ Remove Pending Invitation popup
            if let pendingUID = pendingUIDToRemove {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { withAnimation { pendingUIDToRemove = nil } }
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Text("Cancel Invitation?")
                            .font(.system(size: 18, weight: .bold))
                        Text("Are you sure you want to cancel the invitation for \(pendingNameToRemove)?")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24).padding(.horizontal, 20).padding(.bottom, 20)

                    Divider()

                    HStack(spacing: 12) {
                        Button {
                            withAnimation { pendingUIDToRemove = nil }
                        } label: {
                            Text("No")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Button {
                            let uid = pendingUID
                            withAnimation { pendingUIDToRemove = nil }
                            Task {
                                let db = Firestore.firestore()
                                let snap = try? await db.collection("invitations")
                                    .whereField("playerID", isEqualTo: uid)
                                    .whereField("teamID", isEqualTo: team.id)
                                    .whereField("status", isEqualTo: "pending")
                                    .getDocuments()
                                for doc in snap?.documents ?? [] {
                                    try? await doc.reference.delete()
                                }
                            }
                        } label: {
                            Text("Yes")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 16)
                }
                .background(RoundedRectangle(cornerRadius: 20).fill(Color(.systemBackground)))
                .padding(.horizontal, 30)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: showRemoveConfirm)
        .animation(.spring(response: 0.3), value: pendingUIDToRemove)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                backButton
            }
        }
        .navigationDestination(isPresented: $showInviteSearch) {
            InvitePlayerPage(
                team: team,
                existingPlayerIDs: viewModel.players.map(\.id),
                pendingInvitedUIDs: viewModel.pendingInvitedUIDs
            ) { playerUID in
                Task {
                    guard let coachUID = session.user?.uid else { return }
                    try? await viewModel.sendInvitation(
                        teamId: team.id, teamName: team.teamName, coachUID: coachUID, playerUID: playerUID
                    )
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { navigateToPlayerUID != nil },
            set: { if !$0 { navigateToPlayerUID = nil } }
        )) {
            if let uid = navigateToPlayerUID {
                PlayerProfileContentView(userID: uid)
                    .environmentObject(session)
            }
        }
        .alert("Error", isPresented: $showAlert) { Button("OK", role: .cancel) {} } message: { Text(alertMessage) }
        .onAppear { viewModel.load(team: team) }
    }

    // ✅ Back button موحد زي الصورة
    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(accentColor)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(.systemGray6)))
        }
    }

    private var teamHeaderSection: some View {
        VStack(spacing: 12) {
            TeamLogoCircle(logoURL: team.logoURL, size: 110)
            Text(team.teamName)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(accentColor)
            Label("\(viewModel.players.count) Players", systemImage: "person.3.fill")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coach")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(accentColor)
                .padding(.horizontal, 20)
            HStack(spacing: 14) {
                ProfileAvatar(urlStr: viewModel.coachProfilePicURL, size: 50)
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.coachName.isEmpty ? "Coach" : viewModel.coachName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(accentColor)
                    Label("Head Coach", systemImage: "person.badge.shield.checkmark")
                        .font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(BrandColors.background).shadow(color: .black.opacity(0.07), radius: 8, y: 4)
            )
            .padding(.horizontal, 20)
        }
    }

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ✅ Header: Players title
            Text("Players (\(viewModel.players.count))")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(accentColor)
                .padding(.horizontal, 20)

            if viewModel.isLoading {
                ProgressView().tint(accentColor).frame(maxWidth: .infinity).padding()
            } else {
                // Players list (only show card when there are players)
                let visibleRows = buildPlayerRows()
                if !visibleRows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(visibleRows.enumerated()), id: \.offset) { index, row in
                            PlayerRowItem(
                                row: row,
                                showDivider: index < visibleRows.count - 1,
                                showRemove: isCoachOfThisTeam,
                                index: index + 1,
                                onRemove: {
                                    if case .accepted(let p) = row {
                                        playerToRemove = p
                                        withAnimation { showRemoveConfirm = true }
                                    } else if case .pending(let uid) = row {
                                        pendingUIDToRemove = uid
                                        pendingNameToRemove = "" // will show uid temporarily
                                        withAnimation { }
                                        // fetch name for display
                                        Task {
                                            if let doc = try? await Firestore.firestore().collection("users").document(uid).getDocument(),
                                               let data = doc.data() {
                                                let fn = data["firstName"] as? String ?? ""
                                                let ln = data["lastName"] as? String ?? ""
                                                await MainActor.run {
                                                    pendingNameToRemove = "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)
                                                    withAnimation { pendingUIDToRemove = uid }
                                                }
                                            }
                                        }
                                    }
                                },
                                onNavigate: { uid in navigateToPlayerUID = uid }
                            )
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(BrandColors.background).shadow(color: .black.opacity(0.07), radius: 8, y: 4)
                    )
                    .padding(.horizontal, 20)
                } else {
                    // ✅ No card - just simple text
                    VStack(spacing: 8) {
                        Image(systemName: "person.3")
                            .font(.system(size: 32)).foregroundColor(.secondary.opacity(0.35))
                        Text("No players yet")
                            .font(.system(size: 14, design: .rounded)).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
                }

                // ✅ ADD PLAYER button تحت مباشرة
                if isCoachOfThisTeam {
                    Button { showInviteSearch = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                            Text("ADD PLAYER")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .kerning(1)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                }
            }
        }
    }

    enum PlayerRowData {
        case accepted(TeamPlayer)
        case pending(String)
    }

    private func buildPlayerRows() -> [PlayerRowData] {
        var rows: [PlayerRowData] = viewModel.players.map { .accepted($0) }
        // ✅ Pending players يظهرون للكوتش فقط
        if isCoachOfThisTeam {
            for uid in viewModel.pendingInvitedUIDs {
                if !viewModel.players.contains(where: { $0.id == uid }) {
                    rows.append(.pending(uid))
                }
            }
        }
        return rows
    }
}

// MARK: - Player Row Item
struct PlayerRowItem: View {
    let row: TeamDetailView.PlayerRowData
    let showDivider: Bool
    let showRemove: Bool
    let index: Int
    let onRemove: () -> Void
    let onNavigate: (String) -> Void

    @State private var pendingPlayerName: String = "Player"
    @State private var pendingPlayerPic: String? = nil
    @State private var pendingPlayerPos: String? = nil
    private let accentColor = BrandColors.darkTeal

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("\(index)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                switch row {
                case .accepted(let player):
                    ProfileAvatar(urlStr: player.profilePicURL, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.name.isEmpty ? "Player" : player.name)
                            .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(accentColor)
                        if let pos = player.position, !pos.isEmpty {
                            Text(pos).font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if showRemove {
                        Button { onRemove() } label: {
                            Image(systemName: "trash").font(.system(size: 18)).foregroundColor(.red.opacity(0.8))
                        }.buttonStyle(.plain)
                    }

                case .pending(let uid):
                    ProfileAvatar(urlStr: pendingPlayerPic, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pendingPlayerName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(accentColor)
                        if let pos = pendingPlayerPos, !pos.isEmpty {
                            Text(pos).font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text("Pending")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.orange).clipShape(Capsule())
                    if showRemove {
                        Button {
                            onRemove()
                        } label: {
                            Image(systemName: "trash").font(.system(size: 18)).foregroundColor(.red.opacity(0.8))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                if case .accepted(let player) = row { onNavigate(player.id) }
            }
            .onAppear { if case .pending(let uid) = row { fetchPendingPlayerInfo(uid: uid) } }

            if showDivider {
                Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1).padding(.leading, 74)
            }
        }
    }

    private func fetchPendingPlayerInfo(uid: String) {
        Task {
            guard let doc = try? await Firestore.firestore().collection("users").document(uid).getDocument(),
                  let data = doc.data() else { return }
            await MainActor.run {
                pendingPlayerName = "\(data["firstName"] as? String ?? "") \(data["lastName"] as? String ?? "")".trimmingCharacters(in: .whitespaces)
                pendingPlayerPic = data["profilePic"] as? String
                pendingPlayerPos = data["position"] as? String
            }
        }
    }
}

// MARK: - Team Logo Circle
struct TeamLogoCircle: View {
    let logoURL: String?
    let size: CGFloat
    @State private var image: UIImage? = nil
    private let accentColor = BrandColors.darkTeal

    var body: some View {
        ZStack {
            Circle().fill(accentColor.opacity(0.1)).frame(width: size, height: size)
            if let img = image {
                Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: size * 0.35)).foregroundColor(accentColor.opacity(0.6))
            }
        }
        .onAppear {
            guard let u = logoURL, !u.isEmpty, let url = URL(string: u) else { return }
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url), let img = UIImage(data: data) {
                    await MainActor.run { image = img }
                }
            }
        }
    }
}

// MARK: - Profile Avatar
struct ProfileAvatar: View {
    let urlStr: String?
    let size: CGFloat
    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            Circle().fill(Color.gray.opacity(0.15)).frame(width: size, height: size)
            if let img = image {
                Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.45)).foregroundColor(.gray.opacity(0.5))
            }
        }
        .onAppear {
            guard let s = urlStr, !s.isEmpty, let url = URL(string: s) else { return }
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url), let img = UIImage(data: data) {
                    await MainActor.run { image = img }
                }
            }
        }
    }
}

// MARK: - Invite Player Full Page
struct InvitePlayerPage: View {
    let team: SaudiTeam
    let existingPlayerIDs: [String]
    let pendingInvitedUIDs: Set<String>
    let onInvite: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [SearchedPlayer] = []
    @State private var isSearching = false
    @State private var localInvitedIDs: Set<String> = []

    private let db = Firestore.firestore()
    private let accentColor = BrandColors.darkTeal

    struct SearchedPlayer: Identifiable {
        let id: String; let name: String; let profilePicURL: String?; let position: String?
    }

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
                    TextField("Search players by name...", text: $searchText)
                        .font(.system(size: 15, design: .rounded))
                        .onChange(of: searchText) { _, val in searchPlayers(query: val) }
                    if isSearching { ProgressView().scaleEffect(0.8) }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background).shadow(color: .black.opacity(0.06), radius: 6, y: 2))
                .padding()

                if searchText.count < 2 {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 36)).foregroundColor(.secondary.opacity(0.3))
                        Text("Type at least 2 characters").font(.system(size: 14, design: .rounded)).foregroundColor(.secondary)
                    }
                    Spacer()
                } else if searchResults.isEmpty && !isSearching {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "person.slash").font(.system(size: 36)).foregroundColor(.secondary.opacity(0.4))
                        Text("No players found").font(.system(size: 15, design: .rounded)).foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List(searchResults) { player in
                        HStack(spacing: 14) {
                            ProfileAvatar(urlStr: player.profilePicURL, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(player.name).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundColor(accentColor)
                                if let pos = player.position, !pos.isEmpty {
                                    Text(pos).font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            let inTeam = existingPlayerIDs.contains(player.id)
                            let isPending = pendingInvitedUIDs.contains(player.id) || localInvitedIDs.contains(player.id)

                            if inTeam {
                                Text("In Team")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.secondary)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.gray.opacity(0.15)).clipShape(Capsule())
                            } else if isPending {
                                Text("Invited")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(accentColor)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(accentColor.opacity(0.12)).clipShape(Capsule())
                            } else {
                                Button {
                                    localInvitedIDs.insert(player.id)
                                    onInvite(player.id)
                                } label: {
                                    Text("Invite")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.white)
                                        .padding(.horizontal, 14).padding(.vertical, 6)
                                        .background(accentColor).clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listRowBackground(BrandColors.background)
                    }
                    .listStyle(.plain).background(BrandColors.backgroundGradientEnd)
                }
            }
        }
        .navigationTitle("Add Player")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(accentColor)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(.systemGray6)))
                }
            }
        }
    }

    private func searchPlayers(query: String) {
        guard query.count >= 2 else { searchResults = []; return }
        isSearching = true
        let lower = query.lowercased()
        Task {
            let snap = try? await db.collection("users").whereField("role", isEqualTo: "player").getDocuments()
            var results: [SearchedPlayer] = []
            for doc in snap?.documents ?? [] {
                let data = doc.data()
                let fn = data["firstName"] as? String ?? ""
                let ln = data["lastName"] as? String ?? ""
                if "\(fn) \(ln)".lowercased().contains(lower) {
                    results.append(SearchedPlayer(
                        id: doc.documentID,
                        name: "\(fn) \(ln)".trimmingCharacters(in: .whitespaces),
                        profilePicURL: data["profilePic"] as? String,
                        position: data["position"] as? String
                    ))
                }
            }
            await MainActor.run { searchResults = results; isSearching = false }
        }
    }
}
