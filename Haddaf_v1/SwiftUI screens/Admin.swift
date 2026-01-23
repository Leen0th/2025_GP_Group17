import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI

// =======================================================
// MARK: - Helpers
// =======================================================

private extension String {
    /// Makes each word start with a capital letter (simple Title Case).
    var titleCased: String {
        self.lowercased()
            .split(separator: " ")
            .map { word -> String in
                guard let first = word.first else { return "" }
                return String(first).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}

private struct AdminTopTitle: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title.titleCased)
            .font(.system(size: 26, weight: .semibold, design: .rounded))
            .foregroundColor(color)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }
}

// =======================================================
// MARK: - Admin Root (Tabs) ✅ Fix Tab Bar (no big white / no "watery" strip)
// =======================================================



// =======================================================
// MARK: - Admin Root (Custom Footer)
// =======================================================

enum AdminTab: Int {
    case coaches, accounts, challenges
}

struct AdminTabView: View {
    private let primary = BrandColors.darkTeal
    private let bg = BrandColors.backgroundGradientEnd

    @State private var selected: AdminTab = .coaches

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            // Content
            Group {
                switch selected {
                case .coaches:
                    AdminCoachesApprovalView()
                case .accounts:
                    AdminManageAccountsView()
                case .challenges:
                    AdminChallengesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer
            VStack {
                Spacer()

                AdminFooterBar(selected: $selected, primary: primary)
                    // Make the pill closer to screen edges (less empty sides)
                    .padding(.horizontal, 2)     // ⬅️ was 16, reduce it
                    // Remove bottom gap
                    .padding(.bottom, 0)
            }
        }
        // Hide the system TabBar completely
        .toolbar(.hidden, for: .tabBar)
        // Make footer sit on the bottom edge (no safe area gap)
        .ignoresSafeArea(edges: .bottom)
    }
}

// =======================================================
// MARK: - Footer Bar UI (Bigger + Less Side Empty Space)
// =======================================================

private struct AdminFooterBar: View {
    @Binding var selected: AdminTab
    let primary: Color

    // Unselected color
    private let unselected = Color(UIColor.systemGray2)

    var body: some View {
        HStack(spacing: 0) {
            tabItem(tab: .coaches,
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Coaches Approval")

            tabItem(tab: .accounts,
                    icon: "person.2",
                    title: "Manage Account")

            tabItem(tab: .challenges,
                    icon: "chart.bar",
                    title: "Add Challenge")
        }
        // Make the footer taller and more “filled”
        .padding(.vertical, 24)     // ⬅️ bigger
        .padding(.horizontal, 10)   // ⬅️ smaller to reduce inner empty space
        .frame(maxWidth: .infinity)
        .frame(height: 92)          // ⬅️ bigger height
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white) // Solid background (no blur)
                .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 8)
        )
    }

    // Single tab item
    private func tabItem(tab: AdminTab, icon: String, title: String) -> some View {
        let isSelected = (selected == tab)

        return Button {
            selected = tab
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold)) // ⬅️ bigger icons

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded)) // ⬅️ bigger text
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(isSelected ? primary : unselected)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}




  

// =======================================================
// MARK: - 1) Coaches Approval
// =======================================================

struct CoachRequestItem: Identifiable {
    let id: String
    let uid: String
    let fullName: String
    let email: String
    let status: String
    let submittedAt: Date?
}

struct AdminCoachesApprovalView: View {
    private let primary = BrandColors.darkTeal

    @State private var loading = true
    @State private var errorText: String?
    @State private var pending: [CoachRequestItem] = []

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                VStack(spacing: 14) {
                    AdminTopTitle(title: "Coaches Approval", color: primary)

                    if loading {
                        ProgressView().tint(primary)
                    } else if let errorText {
                        Text(errorText)
                            .foregroundColor(.red)
                            .font(.system(size: 13, design: .rounded))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                    } else if pending.isEmpty {
                        Text("No pending coach requests.")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14, design: .rounded))
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(pending) { item in
                                    coachCard(item)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.bottom, 20)
                        }
                    }

                    Spacer()
                }
                .padding(.top, 6)
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { Task { await loadPending() } }
        }
    }

    private func coachCard(_ item: CoachRequestItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.fullName.isEmpty ? "Coach" : item.fullName)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(primary)

            Text(item.email)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Button {
                    Task { await approve(uid: item.uid, requestId: item.id) }
                } label: {
                    Text("Approve")
                        .foregroundColor(.white)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(primary)
                        .clipShape(Capsule())
                }

                Button {
                    Task { await reject(requestId: item.id) }
                } label: {
                    Text("Reject")
                        .foregroundColor(.red)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color(UIColor.systemGray6))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BrandColors.background)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
    }

    private func loadPending() async {
        loading = true
        errorText = nil
        do {
            let snap = try await Firestore.firestore()
                .collection("coachRequests")
                .whereField("status", isEqualTo: "pending")
                .getDocuments()

            pending = snap.documents.map { d in
                let data = d.data()
                return CoachRequestItem(
                    id: d.documentID,
                    uid: data["uid"] as? String ?? d.documentID,
                    fullName: data["fullName"] as? String ?? "",
                    email: data["email"] as? String ?? "",
                    status: data["status"] as? String ?? "pending",
                    submittedAt: (data["submittedAt"] as? Timestamp)?.dateValue()
                )
            }

            loading = false
        } catch {
            loading = false
            errorText = error.localizedDescription
        }
    }

    private func approve(uid: String, requestId: String) async {
        do {
            let db = Firestore.firestore()
            let batch = db.batch()

            let reqRef = db.collection("coachRequests").document(requestId)
            batch.setData([
                "status": "approved",
                "reviewedAt": FieldValue.serverTimestamp()
            ], forDocument: reqRef, merge: true)

            let userRef = db.collection("users").document(uid)
            batch.setData([
                "role": "coach",
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: userRef, merge: true)

            try await batch.commit()
            await loadPending()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func reject(requestId: String) async {
        do {
            try await Firestore.firestore()
                .collection("coachRequests").document(requestId)
                .setData([
                    "status": "rejected",
                    "reviewedAt": FieldValue.serverTimestamp()
                ], merge: true)

            await loadPending()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// =======================================================
// MARK: - 2) Manage Accounts
// =======================================================

struct UserRowItem: Identifiable {
    let id: String
    let email: String
    let role: String
    let isActive: Bool
}

struct AdminManageAccountsView: View {
    private let primary = BrandColors.darkTeal

    @State private var loading = true
    @State private var errorText: String?
    @State private var users: [UserRowItem] = []
    @State private var search = ""

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                VStack(spacing: 12) {
                    AdminTopTitle(title: "Manage Account", color: primary)

                    searchBox

                    if loading {
                        ProgressView().tint(primary)
                    } else if let errorText {
                        Text(errorText)
                            .foregroundColor(.red)
                            .font(.system(size: 13, design: .rounded))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                    } else if filteredUsers.isEmpty {
                        Text("No accounts found.")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14, design: .rounded))
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(filteredUsers) { u in
                                    accountCard(u)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.bottom, 20)
                        }
                    }

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { Task { await loadUsers() } }
        }
    }

    private var searchBox: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Search by email...", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(BrandColors.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        )
        .padding(.horizontal, 18)
    }

    private var filteredUsers: [UserRowItem] {
        let s = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return users }
        return users.filter {
            $0.email.lowercased().contains(s) || $0.role.lowercased().contains(s)
        }
    }

    private func accountCard(_ u: UserRowItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(u.email.isEmpty ? u.id : u.email)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(primary)

            HStack {
                Text("Role: \(u.role)")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text(u.isActive ? "Active" : "Deactivated")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(u.isActive ? .green : .red)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await setActive(uid: u.id, active: false) }
                } label: {
                    Text("Deactivate")
                        .foregroundColor(.red)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color(UIColor.systemGray6))
                        .clipShape(Capsule())
                }
                .disabled(!u.isActive)

                Button {
                    Task { await setActive(uid: u.id, active: true) }
                } label: {
                    Text("Activate")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(primary)
                        .clipShape(Capsule())
                }
                .disabled(u.isActive)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BrandColors.background)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
    }

    private func loadUsers() async {
        loading = true
        errorText = nil
        do {
            let snap = try await Firestore.firestore()
                .collection("users")
                .limit(to: 250)
                .getDocuments()

            users = snap.documents.map { d in
                let data = d.data()
                return UserRowItem(
                    id: d.documentID,
                    email: data["email"] as? String ?? "",
                    role: data["role"] as? String ?? "player",
                    isActive: data["isActive"] as? Bool ?? true
                )
            }
            loading = false
        } catch {
            loading = false
            errorText = error.localizedDescription
        }
    }

    private func setActive(uid: String, active: Bool) async {
        do {
            try await Firestore.firestore()
                .collection("users").document(uid)
                .setData([
                    "isActive": active,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)

            await loadUsers()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// =======================================================
// MARK: - 3) Challenges (List + Create + Edit) ✅ Live updates + Edit Sheet
// =======================================================

struct AdminChallengeItem: Identifiable {
    let id: String
    let title: String
    let description: String
    let criteria: [String]
    let startAt: Date?
    let endAt: Date?
    let imageURL: String
}

struct AdminChallengesView: View {
    private let primary = BrandColors.darkTeal

    @State private var showCreate = false
    @State private var loading = true
    @State private var errorText: String?
    @State private var challenges: [AdminChallengeItem] = []

    @State private var editingChallenge: AdminChallengeItem? = nil

    @State private var listener: ListenerRegistration? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                VStack(spacing: 14) {
                    AdminTopTitle(title: "Add Challenge", color: primary)

                    Button { showCreate = true } label: {
                        VStack(spacing: 10) {
                            Text("Add Challenge")
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundColor(primary)
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(primary.opacity(0.9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(BrandColors.background)
                                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
                        )
                        .padding(.horizontal, 18)
                    }

                    if loading {
                        ProgressView().tint(primary)
                    } else if let errorText {
                        Text(errorText)
                            .foregroundColor(.red)
                            .font(.system(size: 13, design: .rounded))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                    } else if challenges.isEmpty {
                        Text("No challenges yet.")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14, design: .rounded))
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(challenges) { ch in
                                    AdminChallengeCard(
                                        challenge: ch,
                                        primary: primary,
                                        onEdit: { editingChallenge = ch }
                                    )
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.bottom, 20)
                        }
                    }

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)

            // Create
            .sheet(isPresented: $showCreate) {
                CreateChallengeSheet {
                    showCreate = false
                }
            }

            // Edit
            .sheet(item: $editingChallenge) { ch in
                EditChallengeSheet(challenge: ch) {
                    editingChallenge = nil
                }
            }

            .onAppear { startListening() }
            .onDisappear { listener?.remove(); listener = nil }
        }
    }

    private func startListening() {
        loading = true
        errorText = nil
        listener?.remove()

        listener = Firestore.firestore()
            .collection("challenges")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snap, err in
                if let err {
                    loading = false
                    errorText = err.localizedDescription
                    return
                }
                guard let snap else {
                    loading = false
                    return
                }

                challenges = snap.documents.map { d in
                    let data = d.data()
                    let startAt = (data["startAt"] as? Timestamp)?.dateValue()
                    let endAt   = (data["endAt"] as? Timestamp)?.dateValue()
                    let criteriaArr = data["criteria"] as? [String] ?? []

                    return AdminChallengeItem(
                        id: d.documentID,
                        title: data["title"] as? String ?? "",
                        description: data["description"] as? String ?? "",
                        criteria: criteriaArr,
                        startAt: startAt,
                        endAt: endAt,
                        imageURL: data["imageURL"] as? String ?? ""
                    )
                }

                loading = false
            }
    }
}

struct AdminChallengeCard: View {
    let challenge: AdminChallengeItem
    let primary: Color
    let onEdit: () -> Void

    private var isPast: Bool {
        if let end = challenge.endAt { return Date() >= end }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(challenge.title.isEmpty ? "Challenge" : challenge.title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(primary)

                Spacer()

                Text(isPast ? "Past" : "New")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(isPast ? .gray : primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.systemGray6))
                    .clipShape(Capsule())
            }

            if let url = URL(string: challenge.imageURL), !challenge.imageURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor.systemGray5))
                            .frame(height: 120)
                            .overlay(ProgressView().tint(primary))
                    case .success(let image):
                        image.resizable()
                            .scaledToFill()
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .clipped()
                    default:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor.systemGray5))
                            .frame(height: 120)
                            .overlay(Text("Image failed").foregroundColor(.secondary))
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.systemGray5))
                    .frame(height: 120)
                    .overlay(Text("No Image").foregroundColor(.secondary))
            }

            if !challenge.description.isEmpty {
                Text("Description")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(challenge.description)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }

            if !challenge.criteria.isEmpty {
                Text("Criteria")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(challenge.criteria, id: \.self) { c in
                        Text("• \(c)")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let start = challenge.startAt, let end = challenge.endAt {
                Text("Start / End")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("\(start.formatted(date: .numeric, time: .omitted))  →  \(end.formatted(date: .numeric, time: .omitted))")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Edit") { onEdit() }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 10)
                    .background(primary)
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BrandColors.background)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
        .opacity(isPast ? 0.75 : 1)
    }
}

// =======================================================
// MARK: - Wheel Date Picker Sheet ✅ (مثل صورتك "Select your birth date" + Done)
// =======================================================

struct WheelDatePickerSheet: View {
    let title: String
    let primary: Color
    @Binding var date: Date
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(primary)
                .padding(.top, 10)

            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)

            Button {
                dismiss()
                onDone()
            } label: {
                Text("Done")
                    .foregroundColor(.white)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(primary)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        .background(BrandColors.background.ignoresSafeArea())
    }
}

private struct DateRow: View {
    let label: String
    let primary: Color
    let displayed: String
    let onTap: () -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
            Spacer()
            Text(displayed)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(primary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background))
        .onTapGesture { onTap() }
    }
}

// =======================================================
// MARK: - Create Challenge Sheet ✅ Boxes white + unified + wheel dates
// =======================================================

struct CreateChallengeSheet: View {
    private let primary = BrandColors.darkTeal
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var criteriaText = ""

    @State private var startAt = Date()
    @State private var endAt = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    @State private var showStartWheel = false
    @State private var showEndWheel = false

    @State private var pickedItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil

    @State private var uploading = false
    @State private var errorText: String?

    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        Text("Add Challenge")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(primary)
                            .padding(.top, 8)

                        PhotosPicker(selection: $pickedItem, matching: .images) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                                    .foregroundColor(primary.opacity(0.7))
                                    .frame(height: 140)

                                if let pickedImage {
                                    Image(uiImage: pickedImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 140)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .clipped()
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundColor(primary.opacity(0.9))
                                }
                            }
                        }
                        .padding(.horizontal, 22)
                        .onChange(of: pickedItem) { _, newValue in
                            guard let newValue else { return }
                            Task {
                                if let data = try? await newValue.loadTransferable(type: Data.self),
                                   let ui = UIImage(data: data) {
                                    await MainActor.run { pickedImage = ui }
                                }
                            }
                        }

                        // ✅ unified white boxes
                        field("Title", placeholder: "Challenge title", text: $title)
                        field("Description", placeholder: "Write a short description", text: $description)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Criteria (one per line)")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.secondary)

                            TextEditor(text: $criteriaText)
                                .frame(height: 90)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background)) // ✅ white
                        }
                        .padding(.horizontal, 22)

                        // ✅ Wheel date pickers like your image
                        VStack(spacing: 10) {
                            DateRow(
                                label: "Start Date",
                                primary: primary,
                                displayed: startAt.formatted(date: .abbreviated, time: .omitted)
                            ) { showStartWheel = true }

                            DateRow(
                                label: "End Date",
                                primary: primary,
                                displayed: endAt.formatted(date: .abbreviated, time: .omitted)
                            ) { showEndWheel = true }
                        }
                        .padding(.horizontal, 22)

                        Button {
                            Task { await createChallenge() }
                        } label: {
                            Text(uploading ? "Adding..." : "Add")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(primary)
                                .clipShape(Capsule())
                                .padding(.horizontal, 22)
                        }
                        .disabled(uploading || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let errorText {
                            Text(errorText)
                                .foregroundColor(.red)
                                .font(.system(size: 13, design: .rounded))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 22)
                        }

                        Spacer(minLength: 16)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showStartWheel) {
                WheelDatePickerSheet(
                    title: "Select start date",
                    primary: primary,
                    date: $startAt,
                    onDone: {}
                )
            }
            .sheet(isPresented: $showEndWheel) {
                WheelDatePickerSheet(
                    title: "Select end date",
                    primary: primary,
                    date: $endAt,
                    onDone: {}
                )
            }
        }
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.secondary)

            TextField(placeholder, text: text)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(true)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(BrandColors.background) // ✅ white (مو رمادي)
                )
        }
        .padding(.horizontal, 22)
    }

    private func createChallenge() async {
        uploading = true
        errorText = nil

        do {
            if endAt < startAt {
                uploading = false
                errorText = "End date must be after start date."
                return
            }

            var imageURL = ""
            if let pickedImage {
                imageURL = try await uploadChallengeImage(pickedImage)
            }

            let criteriaArr = criteriaText
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let data: [String: Any] = [
                "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
                "description": description.trimmingCharacters(in: .whitespacesAndNewlines),
                "criteria": criteriaArr,
                "imageURL": imageURL,
                "startAt": Timestamp(date: startAt),
                "endAt": Timestamp(date: endAt),
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "createdBy": Auth.auth().currentUser?.uid ?? ""
            ]

            _ = try await Firestore.firestore().collection("challenges").addDocument(data: data)

            uploading = false
            onDone()
            dismiss()
        } catch {
            uploading = false
            errorText = error.localizedDescription
        }
    }

    private func uploadChallengeImage(_ image: UIImage) async throws -> String {
        guard let adminUid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "auth", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        guard let data = image.jpegData(compressionQuality: 0.82) else {
            throw NSError(domain: "image", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Image encoding failed"])
        }

        let filePath = "challenges/\(adminUid)/\(UUID().uuidString).jpg"
        let ref = Storage.storage().reference().child(filePath)

        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(data, metadata: meta)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }
}

// =======================================================
// MARK: - Edit Challenge Sheet ✅ Admin can edit + updates reflect to users (Firestore doc update)
// =======================================================

struct EditChallengeSheet: View {
    private let primary = BrandColors.darkTeal
    @Environment(\.dismiss) private var dismiss

    let challenge: AdminChallengeItem
    var onDone: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var criteriaText = ""

    @State private var startAt = Date()
    @State private var endAt = Date()

    @State private var showStartWheel = false
    @State private var showEndWheel = false

    @State private var pickedItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil

    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        Text("Edit Challenge")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(primary)
                            .padding(.top, 8)

                        PhotosPicker(selection: $pickedItem, matching: .images) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                                    .foregroundColor(primary.opacity(0.7))
                                    .frame(height: 140)

                                if let pickedImage {
                                    Image(uiImage: pickedImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 140)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .clipped()
                                } else if let url = URL(string: challenge.imageURL), !challenge.imageURL.isEmpty {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .empty:
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(Color(UIColor.systemGray5))
                                                .frame(height: 140)
                                                .overlay(ProgressView().tint(primary))
                                        case .success(let image):
                                            image.resizable()
                                                .scaledToFill()
                                                .frame(height: 140)
                                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                                .clipped()
                                        default:
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.system(size: 22, weight: .medium))
                                                .foregroundColor(primary.opacity(0.9))
                                        }
                                    }
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundColor(primary.opacity(0.9))
                                }
                            }
                        }
                        .padding(.horizontal, 22)
                        .onChange(of: pickedItem) { _, newValue in
                            guard let newValue else { return }
                            Task {
                                if let data = try? await newValue.loadTransferable(type: Data.self),
                                   let ui = UIImage(data: data) {
                                    await MainActor.run { pickedImage = ui }
                                }
                            }
                        }

                        field("Title", placeholder: "Challenge title", text: $title)
                        field("Description", placeholder: "Write a short description", text: $description)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Criteria (one per line)")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.secondary)

                            TextEditor(text: $criteriaText)
                                .frame(height: 90)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background))
                        }
                        .padding(.horizontal, 22)

                        VStack(spacing: 10) {
                            DateRow(
                                label: "Start Date",
                                primary: primary,
                                displayed: startAt.formatted(date: .abbreviated, time: .omitted)
                            ) { showStartWheel = true }

                            DateRow(
                                label: "End Date",
                                primary: primary,
                                displayed: endAt.formatted(date: .abbreviated, time: .omitted)
                            ) { showEndWheel = true }
                        }
                        .padding(.horizontal, 22)

                        Button {
                            Task { await save() }
                        } label: {
                            Text(saving ? "Saving..." : "Save")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(primary)
                                .clipShape(Capsule())
                                .padding(.horizontal, 22)
                        }
                        .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let errorText {
                            Text(errorText)
                                .foregroundColor(.red)
                                .font(.system(size: 13, design: .rounded))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 22)
                        }

                        Spacer(minLength: 16)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showStartWheel) {
                WheelDatePickerSheet(title: "Select start date", primary: primary, date: $startAt, onDone: {})
            }
            .sheet(isPresented: $showEndWheel) {
                WheelDatePickerSheet(title: "Select end date", primary: primary, date: $endAt, onDone: {})
            }
            .onAppear { preload() }
        }
    }

    private func preload() {
        title = challenge.title
        description = challenge.description
        criteriaText = challenge.criteria.joined(separator: "\n")
        startAt = challenge.startAt ?? Date()
        endAt = challenge.endAt ?? (Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.secondary)

            TextField(placeholder, text: text)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(true)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(BrandColors.background)
                )
        }
        .padding(.horizontal, 22)
    }

    private func save() async {
        saving = true
        errorText = nil

        do {
            if endAt < startAt {
                saving = false
                errorText = "End date must be after start date."
                return
            }

            var newImageURL: String? = nil
            if let pickedImage {
                newImageURL = try await uploadChallengeImage(pickedImage)
            }

            let criteriaArr = criteriaText
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var update: [String: Any] = [
                "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
                "description": description.trimmingCharacters(in: .whitespacesAndNewlines),
                "criteria": criteriaArr,
                "startAt": Timestamp(date: startAt),
                "endAt": Timestamp(date: endAt),
                "updatedAt": FieldValue.serverTimestamp()
            ]

            if let newImageURL {
                update["imageURL"] = newImageURL
            }

            try await Firestore.firestore()
                .collection("challenges")
                .document(challenge.id)
                .setData(update, merge: true)

            saving = false
            onDone()
            dismiss()
        } catch {
            saving = false
            errorText = error.localizedDescription
        }
    }

    private func uploadChallengeImage(_ image: UIImage) async throws -> String {
        guard let adminUid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "auth", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        guard let data = image.jpegData(compressionQuality: 0.82) else {
            throw NSError(domain: "image", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Image encoding failed"])
        }

        let filePath = "challenges/\(adminUid)/\(UUID().uuidString).jpg"
        let ref = Storage.storage().reference().child(filePath)

        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(data, metadata: meta)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }
}
