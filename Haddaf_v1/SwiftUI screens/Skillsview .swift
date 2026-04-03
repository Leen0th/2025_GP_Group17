import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Models

struct PlayerSkill: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var endorserIDs: [String] = []
    var endorserNames: [String] = []
    var endorserImages: [String] = []
}

// MARK: - ViewModel

@MainActor
class SkillsViewModel: ObservableObject {
    @Published var skills: [PlayerSkill] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private let profileUserID: String
    private var listener: ListenerRegistration?

    init(profileUserID: String) {
        self.profileUserID = profileUserID
    }

    deinit { listener?.remove() }

    // Real-time listener — fixes "endorse not showing" bug
    func startListening() {
        listener?.remove()
        isLoading = true
        listener = db.collection("users").document(profileUserID)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let data = snapshot?.data() else {
                    Task { @MainActor [weak self] in self?.isLoading = false }
                    return
                }
                Task { @MainActor in
                    if let raw = data["skills"] as? [[String: Any]] {
                        self.skills = raw.compactMap { dict -> PlayerSkill? in
                            guard let name = dict["name"] as? String else { return nil }
                            return PlayerSkill(
                                id: dict["id"] as? String ?? UUID().uuidString,
                                name: name,
                                endorserIDs: dict["endorserIDs"] as? [String] ?? [],
                                endorserNames: dict["endorserNames"] as? [String] ?? [],
                                endorserImages: dict["endorserImages"] as? [String] ?? []
                            )
                        }
                    } else {
                        self.skills = []
                    }
                    self.isLoading = false
                }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }

    func fetchSkills() async { startListening() }

    private func saveSkills() async {
        let raw: [[String: Any]] = skills.map {
            ["id": $0.id, "name": $0.name,
             "endorserIDs": $0.endorserIDs,
             "endorserNames": $0.endorserNames,
             "endorserImages": $0.endorserImages]
        }
        do {
            try await db.collection("users").document(profileUserID).updateData(["skills": raw])
        } catch {
            try? await db.collection("users").document(profileUserID).setData(["skills": raw], merge: true)
        }
    }

    func addSkills(_ names: [String]) async {
        for name in names {
            let t = name.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !skills.contains(where: { $0.name.lowercased() == t.lowercased() }) else { continue }
            skills.append(PlayerSkill(id: UUID().uuidString, name: t))
        }
        await saveSkills()
    }

    func removeSkill(_ skill: PlayerSkill) async {
        skills.removeAll { $0.id == skill.id }
        await saveSkills()
    }

    func toggleEndorse(skillID: String, endorserUID: String, endorserName: String, endorserImage: String) async {
        guard let idx = skills.firstIndex(where: { $0.id == skillID }) else { return }
        if let ex = skills[idx].endorserIDs.firstIndex(of: endorserUID) {
            skills[idx].endorserIDs.remove(at: ex)
            skills[idx].endorserNames.remove(at: ex)
            skills[idx].endorserImages.remove(at: ex)
        } else {
            skills[idx].endorserIDs.append(endorserUID)
            skills[idx].endorserNames.append(endorserName)
            skills[idx].endorserImages.append(endorserImage)
        }
        await saveSkills()
    }
}

// MARK: - Main Skills Tab View

struct SkillsTabView: View {

    let profileUserID: String
    let isCurrentUser: Bool

    @EnvironmentObject var session: AppSession
    @StateObject private var vm: SkillsViewModel
    @State private var showSetSkillsSheet = false

    // ⭐ NEW
    @State private var showDeletePopup = false
    @State private var selectedSkill: PlayerSkill? = nil

    init(profileUserID: String, isCurrentUser: Bool) {
        self.profileUserID = profileUserID
        self.isCurrentUser = isCurrentUser
        _vm = StateObject(wrappedValue: SkillsViewModel(profileUserID: profileUserID))
    }

    var body: some View {
        ZStack {

            VStack(spacing: 0) {
                if vm.isLoading {
                    ProgressView()
                        .tint(BrandColors.darkTeal)
                        .padding(.top, 40)
                } else if vm.skills.isEmpty {
                    emptyState
                } else {
                    skillsList
                }
            }

            // ⭐ DELETE POPUP (الحل النهائي)
            if let skill = selectedSkill {
                ZStack {
                    // الخلفية
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    // البوب اب
                    VStack {
                        Spacer()

                        VStack(spacing: 20) {

                            Text("Delete \(skill.name) Skill?")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .multilineTextAlignment(.center)

                            Text("Your \(skill.name) skill will be permanently deleted. You can add it again anytime.")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            HStack(spacing: 16) {

                                Button("No") {
                                    selectedSkill = nil
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(BrandColors.lightGray)
                                .cornerRadius(12)

                                Button("Yes") {
                                    Task { await vm.removeSkill(skill) }
                                    selectedSkill = nil
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.red)
                                .cornerRadius(12)
                            }
                        }
                        .padding(24)
                        .frame(width: 320)
                        .background(BrandColors.background)
                        .cornerRadius(20)
                        .shadow(radius: 12)

                        Spacer()
                    }
                }
                .zIndex(1000)
            }
        }
        .task { await vm.fetchSkills() }
        .onDisappear { vm.stopListening() }

        // add skills sheet
        .sheet(isPresented: $showSetSkillsSheet) {
            SetSkillsSheet(existingSkills: vm.skills.map { $0.name }) { newNames in
                Task { await vm.addSkills(newNames) }
            }
        }
    }

    // MARK: Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 30)

            Circle()
                .fill(BrandColors.darkTeal.opacity(0.1))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "star.circle")
                        .font(.system(size: 36))
                        .foregroundColor(BrandColors.darkTeal.opacity(0.6))
                )

            Text("No Skills Yet")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(BrandColors.darkGray)

            Text(isCurrentUser
                 ? "Add your football skills so coaches\ncan endorse you."
                 : "This player hasn't added any skills yet.")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            if isCurrentUser { addSkillButton }

            Spacer()
        }
        .padding()
    }

    // MARK: Skills List
    private var skillsList: some View {
        VStack(spacing: 0) {
            if isCurrentUser {
                HStack {
                    Spacer()
                    addSkillButton
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }

            VStack(spacing: 12) {
                ForEach(vm.skills) { skill in

                    let deleteAction: (() -> Void)? = isCurrentUser
                        ? {
                            selectedSkill = skill

                            DispatchQueue.main.async {
                                showDeletePopup = true
                            }
                        }
                        : nil

                    SkillRowView(
                        skill: skill,
                        isCurrentUser: isCurrentUser,
                        currentUserRole: session.role ?? "player",
                        currentUserUID: session.user?.uid ?? "",
                        currentUserName: session.user?.displayName ?? "Unknown",
                        onEndorse: { uid, name, image in
                            Task {
                                await vm.toggleEndorse(
                                    skillID: skill.id,
                                    endorserUID: uid,
                                    endorserName: name,
                                    endorserImage: image
                                )
                            }
                        },
                        onDelete: deleteAction
                    )
                }
            }
            .padding(.horizontal)
        }
    }

    private var addSkillButton: some View {
        Button { showSetSkillsSheet = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Add Skill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundColor(BrandColors.darkTeal)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay(Capsule().stroke(BrandColors.darkTeal, lineWidth: 1.5))
        }
    }
}

// MARK: - Skill Row View

struct SkillRowView: View {
    let skill: PlayerSkill
    let isCurrentUser: Bool
    let currentUserRole: String
    let currentUserUID: String
    let currentUserName: String
    let onEndorse: (String, String, String) -> Void
    var onDelete: (() -> Void)?

    @State private var showEndorsers = false
    private let accent = BrandColors.darkTeal

    private var hasEndorsed: Bool { skill.endorserIDs.contains(currentUserUID) }
    private var isCoach: Bool { currentUserRole == "coach" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 10) {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: skillIcon(for: skill.name))
                            .font(.system(size: 16))
                            .foregroundColor(accent)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(BrandColors.darkGray)
                    
                }
                Spacer()

                // ── Delete button: red circle with trash icon (matches screenshot) ──
                if let del = onDelete {
                    Button(action: del) {
                        ZStack {
                            Circle()
                                .stroke(Color.red.opacity(0.4), lineWidth: 1.5)
                                .frame(width: 32, height: 32)
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red.opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Endorsers preview
            if !skill.endorserIDs.isEmpty {
                Button { showEndorsers = true } label: {
                    HStack(spacing: 6) {
                        ZStack {
                            ForEach(Array(skill.endorserImages.prefix(3).enumerated()), id: \.offset) { i, url in
                                endorserAvatar(urlString: url, name: skill.endorserNames[safe: i] ?? "")
                                    .offset(x: CGFloat(i) * 18)
                            }
                        }
                        .frame(width: CGFloat(min(skill.endorserIDs.count, 3)) * 18 + 24, height: 28)
                        .padding(.leading, 4)

                        endorserText
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
            }

            // Endorse button — coaches only, not on own profile
            if isCoach && !isCurrentUser {
                endorseButton
            }
        }
        .padding(16)
        .background(BrandColors.background)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(hasEndorsed ? accent.opacity(0.35) : Color.clear, lineWidth: 1.5)
        )
        .sheet(isPresented: $showEndorsers) {
            EndorsersListSheet(skill: skill)
        }
    }

    private func endorserAvatar(urlString: String, name: String) -> some View {
        Group {
            if let url = URL(string: urlString), !urlString.isEmpty {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                    else { placeholderAvatar(name: name) }
                }
            } else { placeholderAvatar(name: name) }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(Circle().stroke(BrandColors.background, lineWidth: 2))
    }

    private func placeholderAvatar(name: String) -> some View {
        Circle()
            .fill(accent.opacity(0.2))
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(accent)
            )
    }

    private var endorserDescription: String {
        let names = skill.endorserNames
        let count = names.count
        if count == 1 { return "\(names[0]) endorsed this" }
        else if count == 2 { return "\(names[0]) and \(names[1]) endorsed this" }
        else { return "\(names[0]) and \(count - 1) others endorsed this" }
    }

    private var endorserText: Text {
        Text("\(skill.endorserIDs.count) endorsements")
    }

    private var endorseButton: some View {
        Button {
            Task {
                let info = await fetchCurrentCoachInfo()
                onEndorse(currentUserUID, info.name, info.imageURL)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: hasEndorsed ? "checkmark.seal.fill" : "checkmark.seal")
                    .font(.system(size: 14, weight: .semibold))
                Text(hasEndorsed ? "Unendorse" : "Endorse")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundColor(hasEndorsed ? .white : accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(hasEndorsed ? accent : accent.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(hasEndorsed ? Color.clear : accent.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func fetchCurrentCoachInfo() async -> (name: String, imageURL: String) {
        guard !currentUserUID.isEmpty else { return (currentUserName, "") }
        do {
            let doc = try await Firestore.firestore().collection("users").document(currentUserUID).getDocument()
            let d = doc.data()
            return (d?["name"] as? String ?? currentUserName,
                    d?["profileImageURL"] as? String ?? "")
        } catch { return (currentUserName, "") }
    }

    private func skillIcon(for name: String) -> String {
        let l = name.lowercased()
        if l.contains("dribbl") { return "figure.run" }
        if l.contains("pass")   { return "arrow.up.right" }
        if l.contains("shoot") || l.contains("shot") { return "scope" }
        if l.contains("defend") { return "shield" }
        if l.contains("head")   { return "person.bust" }
        if l.contains("speed") || l.contains("sprint") { return "bolt" }
        if l.contains("tackl")  { return "figure.soccer" }
        if l.contains("vision") || l.contains("aware") { return "eye" }
        return "star"
    }
}

// MARK: - Endorsers List Sheet

struct EndorsersListSheet: View {
    let skill: PlayerSkill
    @Environment(\.dismiss) private var dismiss
    private let accent = BrandColors.darkTeal

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                Group {
                    if skill.endorserIDs.isEmpty {
                        VStack {
                            Spacer()
                            Text("No endorsements yet")
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(Array(skill.endorserIDs.enumerated()), id: \.element) { index, uid in
                                    NavigationLink {
                                        CoachProfileContentView(userID: uid)
                                    } label: {
                                        endorserRow(
                                            name: skill.endorserNames[safe: index] ?? "Coach",
                                            imageURL: skill.endorserImages[safe: index] ?? ""
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle("\(skill.name) · Endorsers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(accent)
                }
            }
        }
    }

    private func endorserRow(name: String, imageURL: String) -> some View {
        HStack(spacing: 12) {
            Group {
                if let url = URL(string: imageURL), !imageURL.isEmpty {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                        else { placeholderCircle(name: name) }
                    }
                } else { placeholderCircle(name: name) }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            Text(name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(BrandColors.darkGray)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.secondary.opacity(0.4))
        }
        .padding(12)
        .background(BrandColors.background)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
    }

    private func placeholderCircle(name: String) -> some View {
        Circle()
            .fill(accent.opacity(0.15))
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(accent)
            )
    }
}

// MARK: - Set Skills Sheet

struct SetSkillsSheet: View {
    let existingSkills: [String]
    let onSave: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    private let accent: Color = BrandColors.darkTeal

    private let presetSkills: [(name: String, icon: String)] = [
        ("Dribble", "figure.run"),
        ("Pass",    "arrow.up.right"),
        ("Shoot",   "scope")
    ]

    @State private var selected: Set<String> = []
    @State private var customSkills: [String] = [""]
    @State private var showCustomSection: Bool = false
    private let maxLength: Int = 30

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Choose the skills you want to add")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(presetSkills.filter { p in
                                !existingSkills.contains(where: { $0.lowercased() == p.name.lowercased() })
                            }, id: \.name) { skill in
                                skillRow(name: skill.name, icon: skill.icon)
                            }
                            customSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }

                    Button {
                        var allNew = Array(selected)
                        let customs = customSkills
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        allNew.append(contentsOf: customs)
                        onSave(allNew)
                        dismiss()
                    } label: {
                        Text("Save Skills")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(canSave ? accent : Color.gray.opacity(0.3))
                            .cornerRadius(14)
                    }
                    .disabled(!canSave)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Set Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(accent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(25)
        .presentationBackground(BrandColors.backgroundGradientEnd)
    }

    private var canSave: Bool {
        !selected.isEmpty ||
        customSkills.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    // MARK: Preset row
    private func skillRow(name: String, icon: String) -> some View {
        let isSelected: Bool = selected.contains(name)
        let strokeColor: Color = isSelected ? accent.opacity(0.4) : Color.clear
        return Button {
            withAnimation(.spring(response: 0.25)) {
                if isSelected { selected.remove(name) } else { selected.insert(name) }
            }
        } label: {
            HStack(spacing: 14) {
                checkBox(isChecked: isSelected)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? accent : Color(BrandColors.darkGray).opacity(0.6))
                    .frame(width: 24)
                Text(name)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(BrandColors.background)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(strokeColor, lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: Checkbox
    private func checkBox(isChecked: Bool) -> some View {
        let strokeColor: Color = isChecked ? accent : Color.gray.opacity(0.4)
        let fillColor: Color   = isChecked ? accent : Color.clear
        return RoundedRectangle(cornerRadius: 6)
            .stroke(strokeColor, lineWidth: 1.5)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(fillColor)
            )
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.white)
                    .opacity(isChecked ? 1 : 0)
            )
    }

    // MARK: Custom section
    private var customSection: some View {
        let headerStroke: Color  = showCustomSection ? accent : Color.gray.opacity(0.4)
        let headerFill: Color    = showCustomSection ? accent : Color.clear
        let sectionStroke: Color = showCustomSection ? accent.opacity(0.4) : Color.clear
        let iconName: String     = showCustomSection ? "minus" : "plus"
        let iconColor: Color     = showCustomSection ? Color.white : accent
        let pencilColor: Color   = showCustomSection ? accent : Color(BrandColors.darkGray).opacity(0.6)

        return VStack(spacing: 0) {
            // Toggle header button
            Button {
                withAnimation { showCustomSection.toggle() }
                if !showCustomSection { customSkills = [""] }
            } label: {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(headerStroke, lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 6).fill(headerFill))
                        .overlay(
                            Image(systemName: iconName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(iconColor)
                        )
                    Image(systemName: "pencil")
                        .font(.system(size: 18))
                        .foregroundColor(pencilColor)
                        .frame(width: 24)
                    Text("Add custom skill")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(BrandColors.darkGray)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(BrandColors.background)
                .cornerRadius(showCustomSection ? 0 : 14)
                .cornerRadius(14, corners: [.topLeft, .topRight])
            }
            .buttonStyle(.plain)

            if showCustomSection {
                VStack(spacing: 8) {
                    ForEach(customSkills.indices, id: \.self) { index in
                        let atMax: Bool = customSkills[index].count >= maxLength
                        let counterColor: Color = atMax ? Color.red : Color.secondary
                        HStack(spacing: 8) {
                            TextField("e.g. Free Kicks", text: Binding(
                                get: { customSkills[index] },
                                set: { customSkills[index] = String($0.prefix(maxLength)) }
                            ))
                            .font(.system(size: 15, design: .rounded))
                            .tint(accent)
                            Text("\(customSkills[index].count)/\(maxLength)")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(counterColor)
                                .frame(width: 40)
                            if customSkills.count > 1 {
                                Button {
                                    withAnimation { _ = customSkills.remove(at: index as Int) }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(Color.red.opacity(0.7))
                                        .font(.system(size: 18))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(BrandColors.background)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(BrandColors.lightGray, lineWidth: 1)
                        )
                    }
                    Button {
                        withAnimation { customSkills.append("") }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle").font(.system(size: 14))
                            Text("Add another skill").font(.system(size: 14, design: .rounded))
                        }
                        .foregroundColor(accent)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(BrandColors.background)
                .cornerRadius(14, corners: [.bottomLeft, .bottomRight])
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(BrandColors.lightGray),
                    alignment: .top
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(sectionStroke, lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
    }
}

// MARK: - Helpers

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }
}

struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
extension View {
    func centerInScreen() -> some View {
        GeometryReader { geo in
            self
                .position(
                    x: geo.size.width / 2,
                    y: geo.size.height / 2
                )
        }
    }
}
