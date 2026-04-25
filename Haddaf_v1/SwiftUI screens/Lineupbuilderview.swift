import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct LineupPlayer: Identifiable, Equatable {
    let id: String
    let name: String
    let profilePicURL: String?
    let position: String?   // player's natural position from their profile
    let score: Double       // average score across all posts

    static func == (lhs: LineupPlayer, rhs: LineupPlayer) -> Bool { lhs.id == rhs.id }
}

struct FormationPosition: Hashable {
    let label: String
    let relX: Double
    let relY: Double
}

struct Formation: Identifiable, Hashable {
    let id: String          // e.g. "4-4-2"
    let label: String
    // relX: 0=left touchline, 1=right touchline
    // relY: 0=coach's goal, 1=opponent's goal
    let positions: [FormationPosition]
}

struct AssignedSlot: Identifiable {
    let id: String          // "GK", "CB-L", etc.
    let label: String
    let relX: Double
    let relY: Double
    var assignedPlayer: LineupPlayer? = nil
}

// MARK: - Saved Lineup Models

struct SavedSlotEntry: Identifiable {
    let id: String          // slotId
    let label: String       // e.g. "GK", "CB"
    let playerId: String
    let playerName: String
}

struct SavedLineup: Identifiable {
    let id: String
    let categoryId: String      // which category this lineup belongs to
    let title: String
    let formationId: String
    let formationLabel: String
    let note: String
    let date: Date
    let assignedPlayers: [SavedSlotEntry]
}

// MARK: - Formations catalogue

extension Formation {
    static let all: [Formation] = [
        Formation(
            id: "4-4-2", label: "4-4-2",
            positions: [
                FormationPosition(label: "GK",  relX: 0.50, relY: 0.07),
                FormationPosition(label: "RB",  relX: 0.18, relY: 0.22),
                FormationPosition(label: "CB",  relX: 0.37, relY: 0.22),
                FormationPosition(label: "CB",  relX: 0.63, relY: 0.22),
                FormationPosition(label: "LB",  relX: 0.82, relY: 0.22),
                FormationPosition(label: "RM",  relX: 0.10, relY: 0.50),
                FormationPosition(label: "CM",  relX: 0.35, relY: 0.50),
                FormationPosition(label: "CM",  relX: 0.65, relY: 0.50),
                FormationPosition(label: "LM",  relX: 0.90, relY: 0.50),
                FormationPosition(label: "ST",  relX: 0.37, relY: 0.77),
                FormationPosition(label: "ST",  relX: 0.63, relY: 0.77)
            ]
        ),
        Formation(
            id: "4-3-3", label: "4-3-3",
            positions: [
                FormationPosition(label: "GK",  relX: 0.50, relY: 0.07),
                FormationPosition(label: "RB",  relX: 0.18, relY: 0.22),
                FormationPosition(label: "CB",  relX: 0.37, relY: 0.22),
                FormationPosition(label: "CB",  relX: 0.63, relY: 0.22),
                FormationPosition(label: "LB",  relX: 0.82, relY: 0.22),
                FormationPosition(label: "CM",  relX: 0.25, relY: 0.53),
                FormationPosition(label: "CDM", relX: 0.50, relY: 0.48),
                FormationPosition(label: "CM",  relX: 0.75, relY: 0.53),
                FormationPosition(label: "RW",  relX: 0.18, relY: 0.77),
                FormationPosition(label: "ST",  relX: 0.50, relY: 0.82),
                FormationPosition(label: "LW",  relX: 0.82, relY: 0.77)
            ]
        ),
        Formation(
            id: "4-2-3-1", label: "4-2-3-1",
            positions: [
                FormationPosition(label: "GK",  relX: 0.50, relY: 0.07),
                FormationPosition(label: "RB",  relX: 0.18, relY: 0.22),
                FormationPosition(label: "CB",  relX: 0.37, relY: 0.22),
                FormationPosition(label: "CB",  relX: 0.63, relY: 0.22),
                FormationPosition(label: "LB",  relX: 0.82, relY: 0.22),
                FormationPosition(label: "CDM", relX: 0.36, relY: 0.43),
                FormationPosition(label: "CDM", relX: 0.64, relY: 0.43),
                FormationPosition(label: "RW",  relX: 0.18, relY: 0.63),
                FormationPosition(label: "CAM", relX: 0.50, relY: 0.63),
                FormationPosition(label: "LW",  relX: 0.82, relY: 0.63),
                FormationPosition(label: "ST",  relX: 0.50, relY: 0.82)
            ]
        ),
        Formation(
            id: "3-5-2", label: "3-5-2",
            positions: [
                FormationPosition(label: "GK",  relX: 0.50, relY: 0.07),
                FormationPosition(label: "CB",  relX: 0.25, relY: 0.22),
                FormationPosition(label: "CB",  relX: 0.50, relY: 0.22),
                FormationPosition(label: "CB",  relX: 0.75, relY: 0.22),
                FormationPosition(label: "RWB", relX: 0.10, relY: 0.48),
                FormationPosition(label: "CM",  relX: 0.30, relY: 0.50),
                FormationPosition(label: "CDM", relX: 0.50, relY: 0.45),
                FormationPosition(label: "CM",  relX: 0.70, relY: 0.50),
                FormationPosition(label: "LWB", relX: 0.90, relY: 0.48),
                FormationPosition(label: "ST",  relX: 0.37, relY: 0.80),
                FormationPosition(label: "ST",  relX: 0.63, relY: 0.80)
            ]
        ),
        Formation(
            id: "5-3-2", label: "5-3-2",
            positions: [
                FormationPosition(label: "GK",  relX: 0.50, relY: 0.07),
                FormationPosition(label: "RWB", relX: 0.10, relY: 0.25),
                FormationPosition(label: "CB",  relX: 0.30, relY: 0.22),
                FormationPosition(label: "CB",  relX: 0.50, relY: 0.22),
                FormationPosition(label: "CB",  relX: 0.70, relY: 0.22),
                FormationPosition(label: "LWB", relX: 0.90, relY: 0.25),
                FormationPosition(label: "CM",  relX: 0.25, relY: 0.53),
                FormationPosition(label: "CM",  relX: 0.50, relY: 0.50),
                FormationPosition(label: "CM",  relX: 0.75, relY: 0.53),
                FormationPosition(label: "ST",  relX: 0.37, relY: 0.80),
                FormationPosition(label: "ST",  relX: 0.63, relY: 0.80)
            ]
        ),
    ]
}

// MARK: - Position abbreviation → full name helper

func positionFullName(_ abbr: String) -> String {
    // Strip suffix like "-2" from duplicate slot ids (e.g. "CB-2" → "CB")
    let base = abbr.components(separatedBy: "-").first ?? abbr
    let map: [String: String] = [
        "GK":  "Goalkeeper",
        "CB":  "Centre-Back",
        "RB":  "Right-Back",
        "LB":  "Left-Back",
        "RWB": "Right Wing-Back",
        "LWB": "Left Wing-Back",
        "CDM": "Defensive Midfielder",
        "CM":  "Central Midfielder",
        "CAM": "Attacking Midfielder",
        "RM":  "Right Midfielder",
        "LM":  "Left Midfielder",
        "RW":  "Right Winger",
        "LW":  "Left Winger",
        "ST":  "Striker",
        "CF":  "Centre-Forward"
    ]
    return map[base] ?? abbr
}

// MARK: - ViewModel

class LineupBuilderViewModel: ObservableObject {
    @Published var coachCategories: [String] = []
    @Published var selectedCategory: String? = nil
    @Published var players: [LineupPlayer] = []
    @Published var isLoadingCategories = true
    @Published var isLoadingPlayers = false

    // Saved lineups (per-category, used inside builder)
    @Published var savedLineups: [SavedLineup] = []
    @Published var isLoadingSavedLineups = false
    @Published var isSavingLineup = false

    // All lineups across every category (used on the home page)
    @Published var allSavedLineups: [SavedLineup] = []
    @Published var isLoadingAllLineups = false

    private let db = Firestore.firestore()
    private var academyId: String? = nil

    // MARK: Load coach's categories from their academy
    func loadCoachCategories(coachUID: String, sessionAcademyId: String?) async {
        await MainActor.run { isLoadingCategories = true }

        var resolvedAcademyId = sessionAcademyId

        if resolvedAcademyId == nil {
            if let snap = try? await db.collection("academies").getDocuments() {
                for doc in snap.documents {
                    let catsSnap = try? await db.collection("academies").document(doc.documentID)
                        .collection("categories").getDocuments()
                    for cat in catsSnap?.documents ?? [] {
                        let coaches = cat.data()["coaches"] as? [String] ?? []
                        if coaches.contains(coachUID) {
                            resolvedAcademyId = doc.documentID
                            break
                        }
                    }
                    if resolvedAcademyId != nil { break }
                }
            }
        }

        guard let aId = resolvedAcademyId else {
            await MainActor.run {
                self.coachCategories = []
                self.isLoadingCategories = false
            }
            return
        }

        self.academyId = aId

        var cats: [String] = []
        if let catsSnap = try? await db.collection("academies").document(aId)
            .collection("categories").getDocuments() {
            for cat in catsSnap.documents {
                let coaches = cat.data()["coaches"] as? [String] ?? []
                if coaches.contains(coachUID) {
                    cats.append(cat.documentID)
                }
            }
        }

        await MainActor.run {
            self.coachCategories = cats.sorted()
            self.isLoadingCategories = false
        }
    }

    // MARK: Load accepted players in category with their scores
    func loadPlayers(for category: String) async {
        guard let aId = academyId else { return }
        await MainActor.run { isLoadingPlayers = true; players = [] }

        let playersSnap = try? await db.collection("academies").document(aId)
            .collection("categories").document(category)
            .collection("players")
            .whereField("status", isEqualTo: "accepted")
            .getDocuments()

        var list: [LineupPlayer] = []
        for doc in playersSnap?.documents ?? [] {
            let uid = doc.documentID

            if let ud = try? await db.collection("users").document(uid).getDocument(),
               let d = ud.data() {
                let firstName = d["firstName"] as? String ?? ""
                let lastName  = d["lastName"]  as? String ?? ""
                let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
                let pic  = d["profilePic"] as? String

                var pos: String? = nil
                var avgScore = 0.0

                if let profileDoc = try? await db.collection("users").document(uid)
                    .collection("player").document("profile").getDocument(),
                   let p = profileDoc.data() {

                    pos = p["position"] as? String

                    if let statsMap = p["positionStats"] as? [String: [String: Any]] {
                        if let currentPos = pos,
                           let statData = statsMap[currentPos],
                           let ts = statData["totalScore"] as? Double,
                           let pc = statData["postCount"] as? Int,
                           pc > 0 {
                            avgScore = ts / Double(pc)
                        } else {
                            var best = 0.0
                            for (_, statData) in statsMap {
                                let ts = statData["totalScore"] as? Double ?? 0
                                let pc = statData["postCount"] as? Int ?? 0
                                guard pc > 0 else { continue }
                                let avg = ts / Double(pc)
                                if avg > best { best = avg }
                            }
                            avgScore = best
                        }
                    }
                }

                list.append(LineupPlayer(id: uid, name: name, profilePicURL: pic, position: pos, score: avgScore))
            }
        }

        list.sort { $0.score > $1.score }

        await MainActor.run {
            self.players = list
            self.isLoadingPlayers = false
        }
    }

    // MARK: Save a lineup to Firestore
    func saveLineup(title: String, slots: [AssignedSlot], formationId: String, formationLabel: String, note: String) async {
        guard let aId = academyId, let cat = selectedCategory else { return }
        await MainActor.run { isSavingLineup = true }

        let assignedSlots = slots.filter { $0.assignedPlayer != nil }
        let entries: [[String: Any]] = assignedSlots.map { slot in
            [
                "slotId":     slot.id,
                "slotLabel":  slot.label,
                "playerId":   slot.assignedPlayer?.id   ?? "",
                "playerName": slot.assignedPlayer?.name ?? ""
            ]
        }

        let data: [String: Any] = [
            "title":           title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                   ? "Untitled Lineup" : title,
            "formationId":     formationId,
            "formationLabel":  formationLabel,
            "note":            note,
            "date":            Timestamp(date: Date()),
            "assignedPlayers": entries
        ]

        try? await db.collection("academies").document(aId)
            .collection("categories").document(cat)
            .collection("lineups").addDocument(data: data)

        await loadSavedLineups()
        await loadAllSavedLineups()
        await MainActor.run { isSavingLineup = false }
    }

    // MARK: Load saved lineups for current category (most recent first)
    func loadSavedLineups() async {
        guard let aId = academyId, let cat = selectedCategory else { return }
        await MainActor.run { isLoadingSavedLineups = true }

        let snap = try? await db.collection("academies").document(aId)
            .collection("categories").document(cat)
            .collection("lineups")
            .order(by: "date", descending: true)
            .getDocuments()

        var lineups: [SavedLineup] = []
        for doc in snap?.documents ?? [] {
            let d = doc.data()
            let entries = (d["assignedPlayers"] as? [[String: Any]] ?? []).map { e in
                SavedSlotEntry(
                    id:         e["slotId"]     as? String ?? "",
                    label:      e["slotLabel"]  as? String ?? "",
                    playerId:   e["playerId"]   as? String ?? "",
                    playerName: e["playerName"] as? String ?? ""
                )
            }
            lineups.append(SavedLineup(
                id:             doc.documentID,
                categoryId:     cat,
                title:          d["title"]          as? String ?? "Untitled",
                formationId:    d["formationId"]    as? String ?? "",
                formationLabel: d["formationLabel"] as? String ?? "",
                note:           d["note"]           as? String ?? "",
                date:           (d["date"] as? Timestamp)?.dateValue() ?? Date(),
                assignedPlayers: entries
            ))
        }

        await MainActor.run {
            self.savedLineups = lineups
            self.isLoadingSavedLineups = false
        }
    }

    // MARK: Load ALL saved lineups across every category the coach manages
    func loadAllSavedLineups() async {
        guard let aId = academyId else { return }
        await MainActor.run { isLoadingAllLineups = true }

        var all: [SavedLineup] = []
        for cat in coachCategories {
            let snap = try? await db.collection("academies").document(aId)
                .collection("categories").document(cat)
                .collection("lineups")
                .order(by: "date", descending: true)
                .getDocuments()

            for doc in snap?.documents ?? [] {
                let d = doc.data()
                let entries = (d["assignedPlayers"] as? [[String: Any]] ?? []).map { e in
                    SavedSlotEntry(
                        id:         e["slotId"]     as? String ?? "",
                        label:      e["slotLabel"]  as? String ?? "",
                        playerId:   e["playerId"]   as? String ?? "",
                        playerName: e["playerName"] as? String ?? ""
                    )
                }
                all.append(SavedLineup(
                    id:             doc.documentID,
                    categoryId:     cat,
                    title:          d["title"]          as? String ?? "Untitled",
                    formationId:    d["formationId"]    as? String ?? "",
                    formationLabel: d["formationLabel"] as? String ?? "",
                    note:           d["note"]           as? String ?? "",
                    date:           (d["date"] as? Timestamp)?.dateValue() ?? Date(),
                    assignedPlayers: entries
                ))
            }
        }

        all.sort { $0.date > $1.date }

        await MainActor.run {
            self.allSavedLineups = all
            self.isLoadingAllLineups = false
        }
    }

    // MARK: Delete a saved lineup from Firestore
    func deleteLineup(_ lineup: SavedLineup) async {
        guard let aId = academyId else { return }
        try? await db.collection("academies").document(aId)
            .collection("categories").document(lineup.categoryId)
            .collection("lineups").document(lineup.id)
            .delete()

        await MainActor.run {
            allSavedLineups.removeAll { $0.id == lineup.id }
            savedLineups.removeAll  { $0.id == lineup.id }
        }
    }
}

// MARK: - Main View

struct LineupBuilderView: View {
    @EnvironmentObject var session: AppSession
    @StateObject private var vm = LineupBuilderViewModel()

    // Formation
    @State private var selectedFormation: Formation? = nil
    // Slots keyed by index in formation.positions
    @State private var slots: [AssignedSlot] = []
    // Which slot is awaiting player pick
    @State private var selectedSlotIndex: Int? = nil

    // Sheet flags
    @State private var showPlayerPanel    = false
    @State private var showPositionGuide  = false   // position abbreviation guide (ⓘ beside lineup header)
    @State private var showFormationInfo  = false   // formation structure guide (ⓘ beside "Select a Formation")
    @State private var showResetConfirmation = false // reset players confirmation

    // Lineup metadata the coach fills in
    @State private var lineupTitle = ""
    @State private var lineupNote  = ""

    // Past lineups toggle
    @State private var showPastLineups = true
    @State private var showRosterPanel  = false

    // Navigation: home → category picker → builder
    @State private var isCreatingNewLineup = false

    // Delete confirmation (managed at top level so overlay covers full screen)
    @State private var lineupPendingDelete: SavedLineup? = nil

    // Save lineup confirmation (same InfoOverlay pattern as EditProfileView)
    @State private var showSaveOverlay    = false
    @State private var saveOverlayIsError = false
    @State private var saveOverlayMessage = ""

    // Home page search & filter (same pattern as DiscoveryView)
    @State private var homeSearchText      = ""
    @State private var homeFilterFormation: String? = nil
    @State private var showHomeFiltersSheet = false

    private let accent     = BrandColors.darkTeal
    private let pitchGreen = Color(hex: "#2D7A3A")

    /// Save is available as long as a formation is selected, at least one player is placed, and a board name has been entered.
    private var canSave: Bool {
        selectedFormation != nil &&
        slots.contains { $0.assignedPlayer != nil } &&
        !lineupTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                if vm.isLoadingCategories {
                    loadingView
                } else if vm.coachCategories.isEmpty {
                    noCategoryView
                } else if vm.selectedCategory == nil && !isCreatingNewLineup {
                    lineupHomeView
                } else if vm.selectedCategory == nil {
                    categoryPickerView
                } else {
                    builderContent
                }

                // Reset players confirmation overlay
                if showResetConfirmation {
                    StyledConfirmationOverlay(
                        isPresented: $showResetConfirmation,
                        title: "Reset Players",
                        message: "This will remove all assigned players from the pitch. Are you sure you want to proceed?",
                        confirmButtonTitle: "Reset",
                        onConfirm: {
                            if let formation = selectedFormation {
                                withAnimation { resetSlots(for: formation) }
                            }
                        }
                    )
                }

                // Delete lineup confirmation overlay (full-screen, above everything)
                if let lineup = lineupPendingDelete {
                    StyledConfirmationOverlay(
                        isPresented: Binding(
                            get: { lineupPendingDelete != nil },
                            set: { if !$0 { lineupPendingDelete = nil } }
                        ),
                        title: "Delete Lineup",
                        message: "This lineup will be permanently deleted and cannot be recovered. Are you sure?",
                        confirmButtonTitle: "Delete",
                        onConfirm: { Task { await vm.deleteLineup(lineup) } }
                    )
                }

                // Save lineup success / error overlay (InfoOverlay — same as EditProfileView)
                if showSaveOverlay {
                    InfoOverlay(
                        primary: accent,
                        title: saveOverlayMessage,
                        isError: saveOverlayIsError,
                        onOk: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showSaveOverlay = false
                            }
                        }
                    )
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(3)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showSaveOverlay)
            .toolbar {
                // Back from builder → category picker
                if vm.selectedCategory != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                vm.selectedCategory = nil
                                selectedFormation = nil
                                slots = []
                                selectedSlotIndex = nil
                                showPlayerPanel = false
                                lineupTitle = ""
                                lineupNote  = ""
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(accent)
                        }
                    }
                }
                // Back from category picker → home
                if vm.selectedCategory == nil && isCreatingNewLineup {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isCreatingNewLineup = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(accent)
                        }
                    }
                }
            }
        }
        .onAppear {
            guard let uid = session.user?.uid else { return }
            Task {
                await vm.loadCoachCategories(coachUID: uid, sessionAcademyId: session.academyId)
                await vm.loadAllSavedLineups()
            }
        }
        // Player picker sheet
        .sheet(isPresented: $showPlayerPanel) {
            if let idx = selectedSlotIndex {
                PlayerPickerSheet(
                    slotLabel: slots[idx].label,
                    players: vm.players,
                    assignedPlayerIds: slots.compactMap { $0.assignedPlayer?.id },
                    currentAssigned: slots[idx].assignedPlayer,
                    isLoading: vm.isLoadingPlayers,
                    onSelect: { player in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            slots[idx].assignedPlayer = player
                        }
                        showPlayerPanel = false
                        selectedSlotIndex = nil
                    },
                    onClear: {
                        withAnimation { slots[idx].assignedPlayer = nil }
                        showPlayerPanel = false
                        selectedSlotIndex = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationBackground(BrandColors.background)
                .presentationCornerRadius(28)
                .presentationDragIndicator(.visible)
            }
        }
        // Position abbreviation guide sheet
        .sheet(isPresented: $showPositionGuide) {
            PositionGuideSheet()
                .presentationDetents([.medium, .large])
                .presentationBackground(BrandColors.background)
                .presentationCornerRadius(28)
                .presentationDragIndicator(.visible)
        }
        // Formation structure guide sheet
        .sheet(isPresented: $showFormationInfo) {
            FormationInfoSheet()
                .presentationDetents([.medium, .large])
                .presentationBackground(BrandColors.background)
                .presentationCornerRadius(28)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Loading
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(accent).scaleEffect(1.3)
            Text("Loading your categories…")
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - No Categories
    private var noCategoryView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sportscourt")
                .font(.system(size: 60))
                .foregroundColor(accent.opacity(0.4))
            Text("No Academy")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(accent)
            Text("You need to be assigned to a category in an academy to build a lineup.")
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Home page search & filter helpers
    private var isHomeFiltering: Bool {
        !homeSearchText.isEmpty || homeFilterFormation != nil
    }

    private var filteredHomeLineups: [SavedLineup] {
        vm.allSavedLineups.filter { lineup in
            let nameMatch = homeSearchText.isEmpty ||
                lineup.title.localizedCaseInsensitiveContains(homeSearchText)
            let formationMatch = homeFilterFormation == nil ||
                lineup.formationLabel == homeFilterFormation
            return nameMatch && formationMatch
        }
    }

    // MARK: - Lineup Home View (new main entry page)
    private var lineupHomeView: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // ── Page header ──
                VStack(spacing: 6) {
                    Text("Lineup Board")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundColor(accent)
                        .padding(.top, 10)
                    Text("All your saved formations in one place.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 16)

                // ── Search bar + filter button (DiscoveryView style) ──
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(accent)
                        TextField("Search lineups by name…", text: $homeSearchText)
                            .font(.system(size: 16, design: .rounded))
                            .tint(accent)
                        if !homeSearchText.isEmpty {
                            Button {
                                homeSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(BrandColors.background)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)

                    // Filter button — filled icon when a filter is active
                    Button { showHomeFiltersSheet = true } label: {
                        Image(systemName: isHomeFiltering
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(accent)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .animation(.easeInOut(duration: 0.2), value: homeSearchText.isEmpty)

                // ── Content ──
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if vm.isLoadingAllLineups {
                            VStack(spacing: 14) {
                                ProgressView().tint(accent)
                                Text("Loading lineups…")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 60)
                        } else if vm.allSavedLineups.isEmpty {
                            // Truly empty — no lineups saved yet
                            VStack(spacing: 16) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 52))
                                    .foregroundColor(accent.opacity(0.25))
                                Text("No saved lineups yet")
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                Text("Tap \"Create New Lineup\" below to build and save your first formation.")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else if filteredHomeLineups.isEmpty {
                            // Lineups exist but search/filter returned nothing
                            VStack(spacing: 16) {
                                Image(systemName: "sportscourt")
                                    .font(.system(size: 48))
                                    .foregroundColor(accent.opacity(0.25))
                                Text("No Lineups Found")
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                if let formation = homeFilterFormation, homeSearchText.isEmpty {
                                    Text("You haven't saved any lineups using the \(formation) formation yet.")
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                } else {
                                    Text("Try adjusting your search or filter settings.")
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Saved Lineups")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .textCase(.uppercase)
                                    .tracking(0.8)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 4)

                                VStack(spacing: 10) {
                                    ForEach(filteredHomeLineups) { lineup in
                                        SavedLineupCard(lineup: lineup, accent: accent) {
                                            lineupPendingDelete = lineup
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }

                        // Space so last card clears the pinned button + tab bar
                        Spacer().frame(height: 180)
                    }
                }
            }

            // ── Create New Lineup button pinned above the tab bar ──
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [BrandColors.backgroundGradientEnd.opacity(0), BrandColors.backgroundGradientEnd],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)
                .allowsHitTesting(false)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isCreatingNewLineup = true
                    }
                } label: {
                    Text("Create New Lineup")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: accent.opacity(0.3), radius: 8, y: 3)
                }
                .padding(.horizontal, 20)
                // 120 = custom tab bar frame height (see PlayerProfileView CustomTabBar)
                .padding(.bottom, 120)
                .background(BrandColors.backgroundGradientEnd)
            }
        }
        .sheet(isPresented: $showHomeFiltersSheet) {
            LineupFilterSheet(
                selectedFormation: $homeFilterFormation,
                accent: accent
            )
        }
    }

    // MARK: - Category Picker (with description)
    private var categoryPickerView: some View {
        ScrollView {
            VStack(spacing: 8) {
                // ── Centered title like Challenges ──
                Text("Lineup Board")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundColor(accent)
                    .padding(.top, 10)

                Text("Arrange your players on the board, create formations, and track which strategies work best!")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)

                VStack(alignment: .leading, spacing: 8) {
                Text("Select Category")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)

                VStack(spacing: 12) {
                    ForEach(vm.coachCategories, id: \.self) { cat in
                        CategoryCard(category: cat, accent: accent) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                vm.selectedCategory = cat
                            }
                            Task {
                                await vm.loadPlayers(for: cat)
                                await vm.loadSavedLineups()
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
                }
            }
        }
    }

    // MARK: - Builder Content
    private var builderContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {

                // ── Category tag ──
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(vm.selectedCategory ?? "")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer()
                }
                .foregroundColor(accent)
                .padding(.horizontal, 20)

                // ── Formation picker with ⓘ info button ──
                formationPickerSection

                if selectedFormation != nil {
                    // ── Lineup name input ──
                    lineupTitleSection
                        .padding(.horizontal, 20)

                    // ── Lineup header: player count + position-guide ⓘ + roster toggle ──
                    lineupHeaderSection
                        .padding(.horizontal, 20)

                    // ── Roster panel (above pitch, revealed by ? tap) ──
                    if showRosterPanel {
                        assignedRosterSection
                            .padding(.horizontal, 20)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                // ── Pitch ──
                if let formation = selectedFormation {
                    pitchView(formation: formation)
                        .padding(.horizontal, 20)

                    // ── Formation note ──
                    lineupNoteSection
                        .padding(.horizontal, 20)

                    // ── Save button ──
                    saveLineupButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 120)

                } else {
                    Spacer().frame(height: 60)
                    Text("Select a formation above to start building your lineup")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 120)
                }
            }
        }
    }

    // MARK: - Formation Picker
    private var formationPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── "Select a Formation" label + ⓘ button (explains the formation structure) ──
            HStack(spacing: 6) {
                Text("Select a Formation")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Button {
                    showFormationInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(accent.opacity(0.75))
                }

                Spacer()
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Formation.all) { formation in
                        FormationCard(
                            formation: formation,
                            isSelected: selectedFormation?.id == formation.id,
                            accent: accent
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                selectedFormation = formation
                                resetSlots(for: formation)
                                lineupTitle = ""
                                lineupNote  = ""
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Lineup Title Input (Admin-style, char limit, sanitized)
    private let titleLimit = 30
    private var lineupTitleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Board Name")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text("*")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.red)
                Spacer()
                Text("\(lineupTitle.count)/\(titleLimit)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(lineupTitle.count >= titleLimit ? .orange : .secondary)
            }

            TextField("", text: $lineupTitle)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.sentences)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background))
                .onChange(of: lineupTitle) { _, new in
                    // Sanitize: allow letters, numbers, spaces, and basic punctuation only
                    let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -.,'"))
                    let sanitized = new.unicodeScalars
                        .filter { allowed.contains($0) }
                        .map(String.init).joined()
                    // Enforce char limit
                    let clamped = sanitized.count > titleLimit
                        ? String(sanitized.prefix(titleLimit)) : sanitized
                    if clamped != new { lineupTitle = clamped }
                }
        }
    }

    // MARK: - Lineup Header (above pitch) — ⓘ + roster toggle (Past Lineups style)
    private var lineupHeaderSection: some View {
        let assigned = slots.filter { $0.assignedPlayer != nil }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Lineup (\(assigned.count)/\(slots.count))")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                // ⓘ Position abbreviation guide
                Button {
                    showPositionGuide = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accent.opacity(0.7))
                }
                Button {
                    showResetConfirmation = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accent)
                }

                Spacer()

                // Players toggle — styled like Past Lineups header
                if !assigned.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showRosterPanel.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("View Assigned Players")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                            Image(systemName: showRosterPanel ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if assigned.count == slots.count && !slots.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Full Lineup")
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(BrandColors.actionGreen)
                    .clipShape(Capsule())
                }
            }
            if assigned.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Tap a position on the pitch to assign a player.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Formation Note (Admin-style, char limit, sanitized)
    private let noteLimit = 300
    private var lineupNoteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Formation Notes")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(lineupNote.count)/\(noteLimit)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(lineupNote.count >= noteLimit ? .orange : .secondary)
            }

            ZStack(alignment: .topLeading) {
                if lineupNote.isEmpty {
                    Text("Write strategy insights, what worked, what to improve…")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.gray.opacity(0.6))
                        .padding(.top, 10)
                        .padding(.leading, 6)
                }
                TextEditor(text: $lineupNote)
                    .font(.system(size: 14, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .frame(height: 110)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background))
                    .onChange(of: lineupNote) { _, new in
                        // Sanitize: allow letters, numbers, spaces, and basic punctuation
                        let allowed = CharacterSet.alphanumerics
                            .union(.init(charactersIn: " -.,'!?():\n"))
                        let sanitized = new.unicodeScalars
                            .filter { allowed.contains($0) }
                            .map(String.init).joined()
                        let clamped = sanitized.count > noteLimit
                            ? String(sanitized.prefix(noteLimit)) : sanitized
                        if clamped != new { lineupNote = clamped }
                    }
            }
        }
    }

    // MARK: - Save Lineup Button
    private var saveLineupButton: some View {
        Button {
            Task {
                await vm.saveLineup(
                    title: lineupTitle,
                    slots: slots,
                    formationId:    selectedFormation?.id    ?? "",
                    formationLabel: selectedFormation?.label ?? "",
                    note: lineupNote
                )
                lineupTitle = ""
                lineupNote  = ""
                // Show save confirmation overlay (InfoOverlay pattern from EditProfileView)
                saveOverlayMessage = "Lineup saved successfully!"
                saveOverlayIsError = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showSaveOverlay = true
                }
            }
        } label: {
            HStack(spacing: 8) {
                if vm.isSavingLineup {
                    ProgressView().tint(.white)
                }
                Text(vm.isSavingLineup ? "Saving…" : "Save Lineup")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canSave ? accent : Color.gray.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: canSave ? accent.opacity(0.3) : .clear, radius: 8, y: 3)
        }
        .disabled(!canSave || vm.isSavingLineup)
        .animation(.easeInOut(duration: 0.2), value: canSave)
    }

    // MARK: - Pitch View
    private func pitchView(formation: Formation) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = w * 1.1

            ZStack {
                PitchBackground()
                    .frame(width: w, height: h)

                ForEach(slots.indices, id: \.self) { idx in
                    let slot = slots[idx]
                    let x = slot.relX * w
                    let y = slot.relY * h

                    PositionDot(
                        slot: slot,
                        isSelected: selectedSlotIndex == idx,
                        accent: accent
                    )
                    .position(x: x, y: y)
                    .onTapGesture {
                        selectedSlotIndex = idx
                        showPlayerPanel = true
                    }
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        }
        .aspectRatio(CGFloat(1)/CGFloat(1.1), contentMode: .fit)
    }

    // MARK: - Assigned Roster Section
    private var assignedRosterSection: some View {
        let assigned   = slots.filter { $0.assignedPlayer != nil }
        let unassigned = slots.filter { $0.assignedPlayer == nil }
        return VStack(alignment: .leading, spacing: 8) {
            if !assigned.isEmpty {
                VStack(spacing: 8) {
                    ForEach(assigned) { slot in
                        if let player = slot.assignedPlayer {
                            AssignedPlayerRow(slot: slot, player: player, accent: accent) {
                                if let idx = slots.firstIndex(where: { $0.id == slot.id }) {
                                    withAnimation { slots[idx].assignedPlayer = nil }
                                }
                            }
                        }
                    }
                }
                if !unassigned.isEmpty {
                    Text("\(unassigned.count) position(s) still need a player.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Past Lineups Section
    private var pastLineupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().padding(.vertical, 4)

            // Collapsible header
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showPastLineups.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Past Lineups")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Review and compare your previous formations")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !vm.savedLineups.isEmpty {
                        Text("\(vm.savedLineups.count)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(accent)
                            .clipShape(Circle())
                    }
                    Image(systemName: showPastLineups ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
            }
            .buttonStyle(.plain)

            if showPastLineups {
                if vm.isLoadingSavedLineups {
                    HStack { Spacer(); ProgressView().tint(accent); Spacer() }
                        .padding(.vertical, 20)
                } else if vm.savedLineups.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 30))
                            .foregroundColor(accent.opacity(0.3))
                        Text("No saved lineups yet.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.secondary)
                        Text("Save your first lineup above to start tracking your strategies.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    VStack(spacing: 10) {
                        ForEach(vm.savedLineups) { lineup in
                            SavedLineupCard(lineup: lineup, accent: accent) {
                                lineupPendingDelete = lineup
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers
    private func resetSlots(for formation: Formation) {
        var labelCount: [String: Int] = [:]
        var newSlots: [AssignedSlot] = []
        for pos in formation.positions {
            let count = labelCount[pos.label, default: 0]
            labelCount[pos.label] = count + 1
            let uniqueId = count == 0 ? pos.label : "\(pos.label)-\(count + 1)"
            newSlots.append(AssignedSlot(id: uniqueId, label: pos.label, relX: pos.relX, relY: pos.relY))
        }
        slots = newSlots
        selectedSlotIndex = nil
    }
}

// MARK: - CategoryCard

struct CategoryCard: View {
    let category: String
    let accent: Color
    let onTap: () -> Void

    private var icon: String {
        let c = category.lowercased()
        if c.contains("goalkeeper") || c.contains("gk") { return "figure.stand" }
        if c.contains("defense") || c.contains("defender") { return "shield.fill" }
        if c.contains("midfield") { return "arrow.left.arrow.right" }
        if c.contains("forward") || c.contains("attack") || c.contains("striker") { return "bolt.fill" }
        if c.contains("fitness") || c.contains("physical") { return "figure.run" }
        return "sportscourt.fill"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Tap to build lineup")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(BrandColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FormationCard

struct FormationCard: View {
    let formation: Formation
    let isSelected: Bool
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Mini pitch preview
                MiniPitchPreview(formation: formation, accent: accent, isSelected: isSelected)
                    .frame(width: 130, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(formation.label)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(isSelected ? accent : .primary)
                    .padding(.vertical, 8)
            }
            .frame(width: 130)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.08) : BrandColors.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? accent : Color.gray.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                    )
            )
            .shadow(color: .black.opacity(isSelected ? 0.1 : 0.05), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MiniPitchPreview

struct MiniPitchPreview: View {
    let formation: Formation
    let accent: Color
    let isSelected: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Pitch green
                Rectangle().fill(Color(hex: "#2D7A3A"))

                // Centre circle
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.8)
                    .frame(width: w * 0.28, height: w * 0.28)
                    .position(x: w * 0.5, y: h * 0.5)

                // Half-way line
                Rectangle().fill(Color.white.opacity(0.3)).frame(width: w, height: 0.8)
                    .position(x: w * 0.5, y: h * 0.5)

                // Dots
                ForEach(formation.positions.indices, id: \.self) { i in
                    let pos = formation.positions[i]
                    Circle()
                        .fill(isSelected ? accent : Color.white.opacity(0.85))
                        .frame(width: 5, height: 5)
                        .position(x: pos.relX * w, y: pos.relY * h)
                }
            }
        }
    }
}

// MARK: - PitchBackground

struct PitchBackground: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Base green
                Rectangle().fill(Color(hex: "#2A7230"))

                // Alternating stripes
                ForEach(0..<8) { i in
                    Rectangle()
                        .fill(Color.black.opacity(i % 2 == 0 ? 0.06 : 0))
                        .frame(width: w, height: h / 8)
                        .offset(y: (CGFloat(i) - 3.5) * h / 8)
                }

                // Field markings
                Group {
                    // Outer boundary
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                        .padding(10)

                    // Half-way line
                    Rectangle().fill(Color.white.opacity(0.7)).frame(width: w - 20, height: 1.5)
                        .position(x: w / 2, y: h / 2)

                    // Centre circle
                    Circle()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                        .frame(width: w * 0.22, height: w * 0.22)
                        .position(x: w / 2, y: h / 2)

                    // Centre spot
                    Circle().fill(Color.white.opacity(0.7)).frame(width: 4, height: 4)
                        .position(x: w / 2, y: h / 2)

                    // Top penalty box
                    Rectangle()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                        .frame(width: w * 0.55, height: h * 0.15)
                        .position(x: w / 2, y: h * 0.075 + 10)

                    // Top goal box
                    Rectangle()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                        .frame(width: w * 0.28, height: h * 0.07)
                        .position(x: w / 2, y: h * 0.035 + 10)

                    // Bottom penalty box
                    Rectangle()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                        .frame(width: w * 0.55, height: h * 0.15)
                        .position(x: w / 2, y: h - h * 0.075 - 10)

                    // Bottom goal box
                    Rectangle()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                        .frame(width: w * 0.28, height: h * 0.07)
                        .position(x: w / 2, y: h - h * 0.035 - 10)
                }
            }
        }
    }
}

// MARK: - PositionDot

struct PositionDot: View {
    let slot: AssignedSlot
    let isSelected: Bool
    let accent: Color

    private let dotSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                // Glow ring for selected
                if isSelected {
                    Circle()
                        .stroke(Color.white, lineWidth: 2.5)
                        .frame(width: dotSize + 6, height: dotSize + 6)
                        .opacity(0.9)
                }

                if let player = slot.assignedPlayer {
                    // Show player avatar
                    AsyncImage(url: URL(string: player.profilePicURL ?? "")) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                                .frame(width: dotSize, height: dotSize)
                                .clipShape(Circle())
                        } else {
                            playerInitialsView(name: player.name)
                        }
                    }
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                } else {
                    // Empty slot
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: dotSize, height: dotSize)
                        .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1.5))
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                        )
                }
            }

            // Label pill
            Text(slot.label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(slot.assignedPlayer != nil ? accent : Color.black.opacity(0.45)))
        }
    }

    private func playerInitialsView(name: String) -> some View {
        let initials = name.split(separator: " ").prefix(2).compactMap { $0.first }.map { String($0) }.joined()
        return ZStack {
            Circle().fill(accent).frame(width: dotSize, height: dotSize)
            Text(initials)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

// MARK: - AssignedPlayerRow

struct AssignedPlayerRow: View {
    let slot: AssignedSlot
    let player: LineupPlayer
    let accent: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Position label
            Text(slot.label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 42)
                .padding(.vertical, 5)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            // Avatar
            AsyncImage(url: URL(string: player.profilePicURL ?? "")) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill().frame(width: 36, height: 36).clipShape(Circle())
                } else {
                    Circle().fill(accent.opacity(0.15)).frame(width: 36, height: 36)
                        .overlay(Image(systemName: "person.fill").foregroundColor(accent).font(.system(size: 14)))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let pos = player.position, !pos.isEmpty {
                    Text(pos)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Score badge
            if player.score > 0 {
                Text("\(Int(player.score))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding(12)
        .background(BrandColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

// MARK: - LineupFilterSheet
// A filter sheet for the Lineup home page — styled consistently with FiltersSheetView in DiscoveryView

struct LineupFilterSheet: View {
    @Binding var selectedFormation: String?
    let accent: Color
    @Environment(\.dismiss) private var dismiss

    // Always show all 5 formations regardless of what's saved
    private let allFormations = ["4-4-2", "4-3-3", "4-2-3-1", "3-5-2", "5-3-2"]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Formation filter
                Section("Formation") {
                    Picker(selection: $selectedFormation, label: EmptyView()) {
                        Text("All").tag(String?.none)
                        ForEach(allFormations, id: \.self) { f in
                            Text(f).tag(String?.some(f))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                // MARK: Clear all
                if selectedFormation != nil {
                    Section {
                        Button(role: .destructive) {
                            selectedFormation = nil
                        } label: {
                            Label("Clear Filters", systemImage: "xmark.circle")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Filter Lineups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(accent)
                }
            }
        }
    }
}

// MARK: - SavedLineupCard

struct SavedLineupCard: View {
    let lineup: SavedLineup
    let accent: Color
    var onDelete: (() -> Void)? = nil

    @State private var isExpanded = false

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: lineup.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tappable header row
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(lineup.formationLabel)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(lineup.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(formattedDate)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Delete button (only shown when onDelete is provided)
                    if onDelete != nil {
                        Button {
                            onDelete?()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.red.opacity(0.7))
                                .padding(6)
                                .background(Color.red.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 10) {
                    // Coach note
                    if !lineup.note.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "quote.bubble.fill")
                                .font(.system(size: 12))
                                .foregroundColor(accent.opacity(0.6))
                                .padding(.top, 2)
                            Text(lineup.note)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.primary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Player grid
                    if !lineup.assignedPlayers.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Players")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.6)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                                ForEach(lineup.assignedPlayers) { entry in
                                    HStack(spacing: 5) {
                                        Text(entry.label)
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 3)
                                            .background(accent.opacity(0.75))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                        Text(entry.playerName)
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
        }
        .background(BrandColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

// MARK: - Player Picker Sheet

struct PlayerPickerSheet: View {
    let slotLabel: String
    let players: [LineupPlayer]
    let assignedPlayerIds: [String]
    let currentAssigned: LineupPlayer?
    let isLoading: Bool
    let onSelect: (LineupPlayer) -> Void
    let onClear: () -> Void

    @State private var searchText = ""
    private let accent = BrandColors.darkTeal

    private var filteredPlayers: [LineupPlayer] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return players }
        return players.filter {
            $0.name.lowercased().contains(q) || ($0.position?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                VStack(spacing: 4) {
                    Text("Choose Player")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Filling: \(positionFullName(slotLabel))  ·  Sorted by score")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Clear button if someone is assigned
            if currentAssigned != nil {
                Button(action: onClear) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                        Text("Remove Current Player")
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.08))
                    .clipShape(Capsule())
                }
                .padding(.bottom, 12)
            }

            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search players…", text: $searchText)
                    .font(.system(size: 15, design: .rounded))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(BrandColors.lightGray)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            if isLoading {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView().tint(accent)
                    Text("Loading players…")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if filteredPlayers.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "person.slash")
                        .font(.system(size: 36))
                        .foregroundColor(accent.opacity(0.3))
                    Text(players.isEmpty ? "No accepted players in this category." : "No players match your search.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    Spacer()
                }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(filteredPlayers.enumerated()), id: \.element.id) { rank, player in
                            let isAssigned = assignedPlayerIds.contains(player.id) && currentAssigned?.id != player.id
                            let isCurrent  = currentAssigned?.id == player.id

                            PlayerPickerRow(
                                rank: rank + 1,
                                player: player,
                                isAlreadyAssigned: isAssigned,
                                isCurrent: isCurrent,
                                slotLabel: slotLabel,
                                accent: accent
                            ) {
                                if !isAssigned { onSelect(player) }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .padding(.bottom, 30)
                }
            }
        }
    }
}

// MARK: - PlayerPickerRow

struct PlayerPickerRow: View {
    let rank: Int
    let player: LineupPlayer
    let isAlreadyAssigned: Bool
    let isCurrent: Bool
    let slotLabel: String
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {

                // Rank badge
                ZStack {
                    Circle()
                        .fill(rank <= 3 ? accent.opacity(0.12) : Color.gray.opacity(0.08))
                        .frame(width: 28, height: 28)
                    Text("\(rank)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(rank <= 3 ? accent : .secondary)
                }

                // Avatar
                AsyncImage(url: URL(string: player.profilePicURL ?? "")) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    } else {
                        initialsCircle
                    }
                }
                .overlay(Circle().stroke(isCurrent ? accent : Color.clear, lineWidth: 2))

                // Name + position (full name shown beneath player name)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(player.name)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(isAlreadyAssigned ? .secondary : .primary)
                            .lineLimit(1)
                        if isCurrent {
                            Text("Current")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(accent)
                                .clipShape(Capsule())
                        }
                        if isAlreadyAssigned {
                            Text("Assigned")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.gray.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    // Full position name shown here instead of abbreviation
                    if let pos = player.position, !pos.isEmpty {
                        Text(pos)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    } else if player.score == 0 {
                        Text("No score yet")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }

                Spacer()

                // Score
                if player.score > 0 {
                    Text("\(Int(player.score))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(isAlreadyAssigned ? .secondary : accent)
                        .frame(width: 44)
                } else {
                    Text("—")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.3))
                        .frame(width: 44)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isCurrent ? accent.opacity(0.05) : BrandColors.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isCurrent ? accent.opacity(0.3) : Color.gray.opacity(0.1), lineWidth: 1.5)
                    )
            )
            .opacity(isAlreadyAssigned ? 0.55 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isAlreadyAssigned)
        .shadow(color: .black.opacity(0.04), radius: 5, y: 2)
    }

    private var initialsCircle: some View {
        let initials = player.name
            .split(separator: " ").prefix(2)
            .compactMap { $0.first }.map { String($0) }.joined()
        return ZStack {
            Circle().fill(accent.opacity(0.12)).frame(width: 48, height: 48)
            Text(initials)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(accent)
        }
    }
}

// MARK: - Formation Info Sheet (explains each formation's structure)

struct FormationInfoSheet: View {
    private let accent = BrandColors.darkTeal

    private struct FormationInfo: Identifiable {
        let id: String
        let label: String
        let tagline: String
        let breakdown: [(count: Int, role: String)]
        let strengths: String
        let weaknesses: String
    }

    private let infos: [FormationInfo] = [
        FormationInfo(
            id: "4-4-2", label: "4-4-2",
            tagline: "",
            breakdown: [(1,"Goalkeeper"), (4,"Defenders"), (4,"Midfielders"), (2,"Strikers")],
            strengths: "Two banks of four are compact and hard to break. Dual strikers maintain a constant threat up top.",
            weaknesses: "Easily outnumbered by a three-man midfield. Wide mids cover massive ground both ways."
        ),
        FormationInfo(
            id: "4-3-3", label: "4-3-3",
            tagline: "",
            breakdown: [(1,"Goalkeeper"), (4,"Defenders"), (3,"Midfielders"), (3,"Forwards")],
            strengths: "Midfield overload against most defensive shapes. Three forwards enable a high press and constant wide threat.",
            weaknesses: "Full-backs are exposed when wingers don't track back. High press breaks down fast without full squad discipline."
        ),
        FormationInfo(
            id: "4-2-3-1", label: "4-2-3-1",
            tagline: "",
            breakdown: [(1,"Goalkeeper"), (4,"Defenders"), (2,"Def. Midfielders"), (3,"Att. Midfielders"), (1,"Striker")],
            strengths: "Double pivot shields defence and allows full-backs to push up. The No.10 is a free creator between lines.",
            weaknesses: "Lone striker gets isolated without close support. Nullifying the No.10 can shut down the whole attack."
        ),
        FormationInfo(
            id: "3-5-2", label: "3-5-2",
            tagline: "",
            breakdown: [(1,"Goalkeeper"), (3,"Centre-Backs"), (2,"Wing-Backs"), (3,"Midfielders"), (2,"Strikers")],
            strengths: "Dominates central midfield. Wing-backs add width without losing a centre-back.",
            weaknesses: "Wide channels are exposed if wing-backs push high simultaneously."
        ),
        FormationInfo(
            id: "5-3-2", label: "5-3-2",
            tagline: "",
            breakdown: [(1,"Goalkeeper"), (3,"Centre-Backs"), (2,"Wing-Backs"), (3,"Midfielders"), (2,"Strikers")],
            strengths: "Five defenders make it extremely hard to break down. Wing-backs burst forward as quick counter outlets.",
            weaknesses: "Gives up possession by design. Relies on clinical finishers — few chances are created."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text("Formation Guide")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("What each formation means on the pitch")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    ForEach(infos) { info in
                        formationCard(info)
                    }
                }
                .padding(16)
                .padding(.bottom, 30)
            }
        }
    }

    private func formationCard(_ info: FormationInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title row only — no tagline
            HStack(spacing: 10) {
                Text(info.label)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Spacer()
            }

            // Player count breakdown (e.g. 1 GK · 4 Defenders · …)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(info.breakdown.indices, id: \.self) { i in
                        let item = info.breakdown[i]
                        HStack(spacing: 3) {
                            Text("\(item.count)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(accent)
                            Text(item.role)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        if i < info.breakdown.count - 1 {
                            Text("·")
                                .foregroundColor(.secondary.opacity(0.4))
                                .font(.system(size: 12))
                        }
                    }
                }
            }

            Divider()

            // Strengths & weaknesses
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 13))
                        .padding(.top, 1)
                    Text(info.strengths)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                        .padding(.top, 1)
                    Text(info.weaknesses)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(BrandColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

// MARK: - Position Guide Sheet

struct PositionGuideSheet: View {
    private let accent = BrandColors.darkTeal

    private struct PositionEntry: Identifiable {
        let id = UUID()
        let abbr: String
        let name: String
        let description: String
        let category: String
    }

    private let entries: [PositionEntry] = [
        // Goalkeeper
        PositionEntry(abbr: "GK",  name: "Goalkeeper",           description: "Guards the goal and directs the defence.",                        category: "Goalkeeper"),
        // Defenders
        PositionEntry(abbr: "CB",  name: "Centre-Back",          description: "Central defender who blocks and intercepts attacks.",              category: "Defenders"),
        PositionEntry(abbr: "RB",  name: "Right-Back",           description: "Defends the right flank and supports attacks.",                   category: "Defenders"),
        PositionEntry(abbr: "LB",  name: "Left-Back",            description: "Defends the left flank and supports attacks.",                    category: "Defenders"),
        PositionEntry(abbr: "RWB", name: "Right Wing-Back",      description: "Combines wide defence with attacking runs on the right.",         category: "Defenders"),
        PositionEntry(abbr: "LWB", name: "Left Wing-Back",       description: "Combines wide defence with attacking runs on the left.",          category: "Defenders"),
        // Midfielders
        PositionEntry(abbr: "CDM", name: "Defensive Midfielder", description: "Shields the defence and breaks up opposition play.",              category: "Midfielders"),
        PositionEntry(abbr: "CM",  name: "Central Midfielder",   description: "Links defence and attack through the centre of the pitch.",       category: "Midfielders"),
        PositionEntry(abbr: "CAM", name: "Attacking Midfielder", description: "Creates chances and plays behind the strikers.",                  category: "Midfielders"),
        PositionEntry(abbr: "RM",  name: "Right Midfielder",     description: "Operates on the right side of midfield, wide and box-to-box.",   category: "Midfielders"),
        PositionEntry(abbr: "LM",  name: "Left Midfielder",      description: "Operates on the left side of midfield, wide and box-to-box.",    category: "Midfielders"),
        // Forwards
        PositionEntry(abbr: "RW",  name: "Right Winger",         description: "Attacks from the right flank and cuts inside to shoot.",         category: "Forwards"),
        PositionEntry(abbr: "LW",  name: "Left Winger",          description: "Attacks from the left flank and cuts inside to shoot.",          category: "Forwards"),
        PositionEntry(abbr: "ST",  name: "Striker",              description: "Central forward whose primary job is to score goals.",            category: "Forwards"),
        PositionEntry(abbr: "CF",  name: "Centre-Forward",       description: "Leads the attack, holds up play, and brings others into game.",  category: "Forwards"),
    ]

    private var categories: [String] {
        var seen = Set<String>()
        return entries.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text("Position Guide")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("What each abbreviation means")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(categories, id: \.self) { cat in
                        VStack(alignment: .leading, spacing: 8) {
                            // Category label
                            HStack(spacing: 6) {
                                Image(systemName: categoryIcon(cat))
                                    .font(.system(size: 12, weight: .bold))
                                Text(cat.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .tracking(1)
                            }
                            .foregroundColor(accent)
                            .padding(.horizontal, 20)

                            // Entries
                            VStack(spacing: 6) {
                                ForEach(entries.filter { $0.category == cat }) { entry in
                                    HStack(alignment: .top, spacing: 12) {
                                        // Abbreviation badge beside the full name
                                        Text(entry.abbr)
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .frame(width: 42)
                                            .padding(.vertical, 6)
                                            .background(accent)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.name)
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundColor(.primary)
                                            Text(entry.description)
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundColor(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
    }

    private func categoryIcon(_ cat: String) -> String {
        switch cat {
        case "Goalkeeper":  return "figure.stand"
        case "Defenders":   return "shield.fill"
        case "Midfielders": return "arrow.left.arrow.right"
        case "Forwards":    return "bolt.fill"
        default:            return "sportscourt"
        }
    }
}
