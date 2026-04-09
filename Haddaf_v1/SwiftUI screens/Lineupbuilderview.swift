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

// MARK: - ViewModel

class LineupBuilderViewModel: ObservableObject {
    @Published var coachCategories: [String] = []
    @Published var selectedCategory: String? = nil
    @Published var players: [LineupPlayer] = []
    @Published var isLoadingCategories = true
    @Published var isLoadingPlayers = false

    private let db = Firestore.firestore()
    private var academyId: String? = nil

    // MARK: Load coach's categories from their academy
    func loadCoachCategories(coachUID: String, sessionAcademyId: String?) async {
        await MainActor.run { isLoadingCategories = true }

        // Use session academyId if available, else query
        var resolvedAcademyId = sessionAcademyId

        if resolvedAcademyId == nil {
            // Find the coach's academy by scanning academies
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

        // Fetch categories where this coach is listed
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
                let lastName  = d["lastName"] as? String ?? ""
                let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                let pos  = d["position"] as? String
                let pic  = d["profilePic"] as? String

                // Calculate score from positionStats.
                // The map keys match positionAtUpload values (e.g. "Attacker", "Midfielder").
                // Priority: 1) player's current position key  2) highest-scoring position  3) weighted total
                var avgScore = 0.0
                if let statsMap = d["positionStats"] as? [String: [String: Any]] {
                    // 1. Try the player's current position key directly
                    if let pos = pos,
                       let statData = statsMap[pos],
                       let ts = statData["totalScore"] as? Double,
                       let pc = statData["postCount"] as? Int,
                       pc > 0 {
                        avgScore = ts / Double(pc)
                    } else {
                        // 2. Fall back: find the position with the highest average score
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

                list.append(LineupPlayer(id: uid, name: name, profilePicURL: pic, position: pos, score: avgScore))
            }
        }

        // Sort by score descending
        list.sort { $0.score > $1.score }

        await MainActor.run {
            self.players = list
            self.isLoadingPlayers = false
        }
    }
}

// MARK: - Main View

struct LineupBuilderView: View {
    @EnvironmentObject var session: AppSession
    @StateObject private var vm = LineupBuilderViewModel()

    // Formation
    @State private var selectedFormation: Formation? = nil
    // Slots: keyed by index in formation.positions
    @State private var slots: [AssignedSlot] = []
    // Which slot is awaiting player pick
    @State private var selectedSlotIndex: Int? = nil
    // Panel state
    @State private var showPlayerPanel = false
    @State private var showPositionGuide = false

    private let accent = BrandColors.darkTeal
    private let pitchGreen = Color(hex: "#2D7A3A")

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                if vm.isLoadingCategories {
                    loadingView
                } else if vm.coachCategories.isEmpty {
                    noCategoryView
                } else if vm.selectedCategory == nil {
                    categoryPickerView
                } else {
                    builderContent
                }
            }
            .navigationTitle("Lineup Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Back to category picker
                if vm.selectedCategory != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                vm.selectedCategory = nil
                                selectedFormation = nil
                                slots = []
                                selectedSlotIndex = nil
                                showPlayerPanel = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Categories")
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(accent)
                        }
                    }
                }

                // Reset lineup
                if selectedFormation != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 14) {
                            // Position guide button
                            Button {
                                showPositionGuide = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(accent)
                            }
                            // Reset button
                            Button {
                                withAnimation {
                                    resetSlots(for: selectedFormation!)
                                }
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(accent)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            guard let uid = session.user?.uid else { return }
            Task { await vm.loadCoachCategories(coachUID: uid, sessionAcademyId: session.academyId) }
        }
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
                        withAnimation {
                            slots[idx].assignedPlayer = nil
                        }
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
        .sheet(isPresented: $showPositionGuide) {
            PositionGuideSheet()
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

    // MARK: - Category Picker
    private var categoryPickerView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Select Category")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                VStack(spacing: 12) {
                    ForEach(vm.coachCategories, id: \.self) { cat in
                        CategoryCard(category: cat, accent: accent) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                vm.selectedCategory = cat
                            }
                            Task { await vm.loadPlayers(for: cat) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
        }
    }

    // MARK: - Builder Content (Formation + Pitch)
    private var builderContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Category badge
                HStack {
                    Text(vm.selectedCategory ?? "")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(accent)
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Formation picker
                formationPickerSection

                // Lineup header + hint — shown above pitch once a formation is chosen
                if selectedFormation != nil {
                    lineupHeaderSection
                        .padding(.horizontal, 20)
                }

                // Pitch
                if let formation = selectedFormation {
                    pitchView(formation: formation)
                        .padding(.horizontal, 20)

                    // Player roster summary (no header/hint here anymore)
                    assignedRosterSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 120)
                } else {
                    Spacer().frame(height: 60)
                    Text("Select a formation above to start building")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 120)
                }
            }
        }
    }

    // MARK: - Lineup Header (above pitch)
    private var lineupHeaderSection: some View {
        let assigned = slots.filter { $0.assignedPlayer != nil }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Lineup (\(assigned.count)/\(slots.count))")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(accent)
                Spacer()
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

    // MARK: - Formation Picker
    private var formationPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select a Formation")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
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
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Pitch View
    private func pitchView(formation: Formation) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = w * 1.1   // compact pitch ratio

            ZStack {
                // Pitch background
                PitchBackground()
                    .frame(width: w, height: h)

                // Position dots
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
        let assigned = slots.filter { $0.assignedPlayer != nil }
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

// MARK: - Sub-views

struct CategoryCard: View {
    let category: String
    let accent: Color
    let onTap: () -> Void

    // Map common football categories to an icon
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
                    .overlay(
                        Circle().stroke(Color.white, lineWidth: 2)
                    )
                } else {
                    // Empty slot
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: dotSize, height: dotSize)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                        )
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
                .background(
                    Capsule().fill(slot.assignedPlayer != nil ? accent : Color.black.opacity(0.45))
                )
        }
    }

    private func playerInitialsView(name: String) -> some View {
        let initials = name.split(separator: " ").prefix(2).compactMap { $0.first }.map { String($0) }.joined()
        return ZStack {
            Circle()
                .fill(accent)
                .frame(width: dotSize, height: dotSize)
            Text(initials)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

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
                Text(String(format: "%.1f", player.score))
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
        return players.filter { $0.name.lowercased().contains(q) || ($0.position?.lowercased().contains(q) ?? false) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                VStack(spacing: 4) {
                    Text("Choose Player")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Filling: \(slotLabel)  ·  Sorted by score")
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
                            let isCurrent = currentAssigned?.id == player.id

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
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {

                    // ── Rank badge ──
                    ZStack {
                        Circle()
                            .fill(rank <= 3 ? accent.opacity(0.12) : Color.gray.opacity(0.08))
                            .frame(width: 28, height: 28)
                        Text("\(rank)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(rank <= 3 ? accent : .secondary)
                    }

                    // ── Avatar ──
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

                    // ── Name + score subtitle ──
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
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(accent)
                                    .clipShape(Capsule())
                            }
                            if isAlreadyAssigned {
                                Text("Assigned")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }

                        if player.score > 0 {
                            Text("Score: \(String(format: "%.1f", player.score))")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.secondary)
                        } else {
                            Text("No score yet")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }

                    Spacer()

                    // ── Score number ──
                    if player.score > 0 {
                        Text(String(format: "%.1f", player.score))
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

                // ── Score bar ──
                if player.score > 0 && !isAlreadyAssigned {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 3)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(LinearGradient(
                                    colors: [accent.opacity(0.45), accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .frame(width: geo.size.width * min(player.score / 10.0, 1.0), height: 3)
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
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
                            // Category header
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
                                        // Abbreviation badge
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
        case "Goalkeeper": return "figure.stand"
        case "Defenders":  return "shield.fill"
        case "Midfielders": return "arrow.left.arrow.right"
        case "Forwards":   return "bolt.fill"
        default:           return "sportscourt"
        }
    }
}
