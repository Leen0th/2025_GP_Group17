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
// MARK: - Admin Root (Custom Footer)
// =======================================================

enum AdminTab: Int {
    case coaches, accounts, challenges, profile
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
                case .profile:
                    AdminProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer
            VStack {
                Spacer()

                AdminFooterBar(selected: $selected, primary: primary)
                    // Make the pill closer to screen edges (less empty sides)
                    .padding(.horizontal, 2)
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
// MARK: - Footer Bar UI
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
            
            tabItem(tab: .profile,
                    icon: "person.circle",
                    title: "Admin Profile")
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 8)
        )
    }

    private func tabItem(tab: AdminTab, icon: String, title: String) -> some View {
        let isSelected = (selected == tab)

        return Button {
            selected = tab
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
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
    let verificationFile: String
    let rejectionReason: String?
}

struct AdminCoachesApprovalView: View {
    private let primary = BrandColors.darkTeal

    @State private var loading = true
    @State private var errorText: String?
    @State private var pending: [CoachRequestItem] = []
    @State private var searchText = ""
    @State private var sortByNew = true // true = recent first, false = older first
    @State private var showRejectionSheet = false
    @State private var selectedCoachForRejection: CoachRequestItem? = nil
    @State private var rejectionReason = ""
    @State private var isRejecting = false

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                VStack(spacing: 14) {
                    
                    // Search and Sort Controls
                    VStack(spacing: 10) {
                        // Search + Sort in one horizontal row
                        HStack(spacing: 12) {
                            // Search field (takes available space)
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                
                                TextField("Search by name or email...", text: $searchText)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(BrandColors.background)
                                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
                            )
                            
                            // Sort menu – compact capsule
                            Menu {
                                Picker("Sort by date", selection: $sortByNew) {
                                    Text("Newest first").tag(true)
                                    Text("Oldest first").tag(false)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .font(.system(size: 13, weight: .medium))
                                    
                                    Text(sortByNew ? "Newest" : "Oldest")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                }
                                .foregroundColor(BrandColors.darkTeal)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(BrandColors.background)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.07), radius: 4, y: 2)
                            }
                        }
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
                    } else if filteredAndSortedPending.isEmpty {
                        Text(searchText.isEmpty ? "No pending coach requests." : "No results found.")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14, design: .rounded))
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(filteredAndSortedPending) { item in
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
            .sheet(isPresented: $showRejectionSheet) {
                RejectionReasonSheet(
                    coachName: selectedCoachForRejection?.fullName ?? "Coach",
                    rejectionReason: $rejectionReason,
                    isRejecting: $isRejecting,
                    onCancel: {
                        showRejectionSheet = false
                        rejectionReason = ""
                        selectedCoachForRejection = nil
                    },
                    onConfirm: {
                        if let coach = selectedCoachForRejection {
                            Task {
                                await rejectWithReason(uid: coach.uid, requestId: coach.id, reason: rejectionReason)
                            }
                        }
                    }
                )
                .presentationDetents([.height(400)])
                .presentationBackground(BrandColors.background)
                .presentationCornerRadius(28)
            }
        }
    }
    
    private var filteredAndSortedPending: [CoachRequestItem] {
        let s = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Filter
        let filtered: [CoachRequestItem]
        if s.isEmpty {
            filtered = pending
        } else {
            filtered = pending.filter {
                $0.fullName.lowercased().contains(s) || $0.email.lowercased().contains(s)
            }
        }
        
        // Sort
        return filtered.sorted { item1, item2 in
            guard let date1 = item1.submittedAt, let date2 = item2.submittedAt else {
                return false
            }
            return sortByNew ? (date1 > date2) : (date1 < date2)
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

            if let url = URL(string: item.verificationFile), !item.verificationFile.isEmpty {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("View Verification Document")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(.vertical, 4)
                }
            }

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
                    selectedCoachForRejection = item
                    showRejectionSheet = true
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
            let snap = try await Firestore.firestore().collection("coachRequests")
                .whereField("status", isEqualTo: "pending")
                .order(by: "submittedAt", descending: true)
                .getDocuments()

            pending = snap.documents.map { d in
                let data = d.data()
                let ts = data["submittedAt"] as? Timestamp
                return CoachRequestItem(
                    id: d.documentID,
                    uid: data["uid"] as? String ?? "",
                    fullName: data["fullName"] as? String ?? "",
                    email: data["email"] as? String ?? "",
                    status: data["status"] as? String ?? "pending",
                    submittedAt: ts?.dateValue(),
                    verificationFile: data["verificationFile"] as? String ?? "",
                    rejectionReason: data["rejectionReason"] as? String
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
                "coachStatus": "approved",
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: userRef, merge: true)

            try await batch.commit()
            await loadPending()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func rejectWithReason(uid: String, requestId: String, reason: String) async {
        errorText = nil
        isRejecting = true
        
        do {
            let db = Firestore.firestore()
            let batch = db.batch()

            let reqRef = db.collection("coachRequests").document(requestId)
            batch.updateData([
                "status": "rejected",
                "rejectionReason": reason.trimmingCharacters(in: .whitespacesAndNewlines),
                "reviewedAt": FieldValue.serverTimestamp()
            ], forDocument: reqRef)

            let userRef = db.collection("users").document(uid)
            batch.updateData([
                "coachStatus": "rejected",
                "rejectionReason": reason.trimmingCharacters(in: .whitespacesAndNewlines)
            ], forDocument: userRef)

            try await batch.commit()
            
            await MainActor.run {
                isRejecting = false
                showRejectionSheet = false
                rejectionReason = ""
                selectedCoachForRejection = nil
            }
            
            await loadPending()
        } catch {
            await MainActor.run {
                isRejecting = false
                errorText = error.localizedDescription
            }
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
    let createdAt: Date?
}

struct AdminManageAccountsView: View {
    private let primary = BrandColors.darkTeal
    
    @State private var loading = true
    @State private var errorText: String?
    @State private var users: [UserRowItem] = []
    @State private var search = ""
    @State private var selectedRole: String = "coach" // "coach" or "player"
    @State private var sortByNew = true // true = newest first, false = oldest first
    
    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                
                VStack(spacing: 12) {
                    
                    // Role Tabs
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedRole = "coach"
                            }
                        } label: {
                            VStack(spacing: 8) {
                                Text("Coaches")
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundColor(selectedRole == "coach" ? primary : .secondary)
                                
                                if selectedRole == "coach" {
                                    Rectangle()
                                        .frame(height: 2)
                                        .foregroundColor(primary)
                                } else {
                                    Color.clear.frame(height: 2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedRole = "player"
                            }
                        } label: {
                            VStack(spacing: 8) {
                                Text("Players")
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundColor(selectedRole == "player" ? primary : .secondary)
                                
                                if selectedRole == "player" {
                                    Rectangle()
                                        .frame(height: 2)
                                        .foregroundColor(primary)
                                } else {
                                    Color.clear.frame(height: 2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
                    
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
            TextField("Search by name or email...", text: $search)
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
        
        // Filter by role first
        let roleFiltered = users.filter { $0.role.lowercased() == selectedRole.lowercased() }
        
        // Then filter by search
        let searchFiltered: [UserRowItem]
        if s.isEmpty {
            searchFiltered = roleFiltered
        } else {
            searchFiltered = roleFiltered.filter {
                $0.email.lowercased().contains(s) || $0.role.lowercased().contains(s)
            }
        }
        
        // Finally sort by creation date
        return searchFiltered.sorted { user1, user2 in
            guard let date1 = user1.createdAt, let date2 = user2.createdAt else {
                return false
            }
            return sortByNew ? (date1 > date2) : (date1 < date2)
        }
    }
    
    private func accountCard(_ u: UserRowItem) -> some View {
        NavigationLink {
            if u.role.lowercased() == "coach" {
                CoachProfileContentView(userID: u.id)
            } else {
                PlayerProfileContentView(userID: u.id)
            }
        } label: {
            accountCardContent(u)
        }
        .buttonStyle(.plain)
    }
    
    private func accountCardContent(_ u: UserRowItem) -> some View {
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
                    Task { await setActive(uid: u.id, active: true) }
                } label: {
                    Text("Activate")
                        .foregroundColor(.white)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(primary)
                        .clipShape(Capsule())
                }
                .disabled(u.isActive)
                
                Button {
                    Task { await setActive(uid: u.id, active: false) }
                } label: {
                    Text("Deactivate")
                        .foregroundColor(.red)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color(UIColor.systemGray6))
                        .clipShape(Capsule())
                }
                .disabled(!u.isActive)
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
                let createdAtTimestamp = data["createdAt"] as? Timestamp
                return UserRowItem(
                    id: d.documentID,
                    email: data["email"] as? String ?? "",
                    role: data["role"] as? String ?? "player",
                    isActive: data["isActive"] as? Bool ?? true,
                    createdAt: createdAtTimestamp?.dateValue()
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
// MARK: - 3) Challenges (List + Create + Edit)
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

    // ✅ FIX: use isPresented sheet to avoid listener canceling the sheet
    @State private var editingChallenge: AdminChallengeItem? = nil
    @State private var showEditSheet = false

    // Delete confirmation
    @State private var challengeToDelete: AdminChallengeItem? = nil
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    @State private var listener: ListenerRegistration? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                VStack(spacing: 14) {
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
                    .buttonStyle(.plain)

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
                                        onEdit: {
                                            // ✅ FIX: stable open even if listener updates list
                                            editingChallenge = ch
                                            showEditSheet = true
                                        },
                                        onDelete: {
                                            challengeToDelete = ch
                                            showDeleteConfirm = true
                                        }
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

            // ✅ FIXED Edit Sheet
            .sheet(isPresented: $showEditSheet, onDismiss: {
                editingChallenge = nil
            }) {
                if let ch = editingChallenge {
                    EditChallengeSheet(challenge: ch) {
                        showEditSheet = false
                        editingChallenge = nil
                    }
                } else {
                    Text("No challenge selected")
                }
            }

            // Delete confirmation
            .confirmationDialog(
                "Delete this challenge?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let ch = challengeToDelete {
                        Task { await deleteChallenge(ch) }
                    }
                }
                Button("Cancel", role: .cancel) {
                    challengeToDelete = nil
                }
            } message: {
                Text("This will permanently delete the challenge and all its submissions. This action cannot be undone.")
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

    private func deleteChallenge(_ challenge: AdminChallengeItem) async {
        isDeleting = true

        do {
            let db = Firestore.firestore()
            let challengeRef = db.collection("challenges").document(challenge.id)

            // 1) Delete submissions + their storage + ratings
            let submissionsSnap = try await challengeRef.collection("submissions").getDocuments()

            for subDoc in submissionsSnap.documents {
                let storagePath = subDoc.data()["storagePath"] as? String ?? ""

                if !storagePath.isEmpty {
                    try? await Storage.storage().reference().child(storagePath).delete()
                }

                let ratingsSnap = try await subDoc.reference.collection("ratings").getDocuments()
                for ratingDoc in ratingsSnap.documents {
                    try await ratingDoc.reference.delete()
                }

                try await subDoc.reference.delete()
            }

            // 2) Delete challenge image from storage (best effort)
            if !challenge.imageURL.isEmpty, let url = URL(string: challenge.imageURL) {
                let fileName = url.lastPathComponent
                if !fileName.isEmpty {
                    try? await Storage.storage()
                        .reference()
                        .child("challenges/\(challenge.id)/\(fileName)")
                        .delete()
                }
            }

            // 3) Delete challenge doc
            try await challengeRef.delete()

            isDeleting = false
            challengeToDelete = nil

        } catch {
            isDeleting = false
            errorText = "Failed to delete: \(error.localizedDescription)"
        }
    }
}

struct AdminChallengeCard: View {
    let challenge: AdminChallengeItem
    let primary: Color
    let onEdit: () -> Void
    let onDelete: () -> Void

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

            HStack(spacing: 12) {
                Spacer()

                Button {
                    onDelete()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Delete")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.85))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onEdit()
                } label: {
                    Text("Edit")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 10)
                        .background(primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
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
// MARK: - Wheel Date Picker Sheet
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
// MARK: - Create Challenge Sheet
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
                        .buttonStyle(.plain)

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
                        .fill(BrandColors.background)
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
// MARK: - Edit Challenge Sheet
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
                        .buttonStyle(.plain)

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

// =======================================================
// MARK: - 4) Admin Profile
// =======================================================

struct AdminProfileView: View {
    @EnvironmentObject var session: AppSession
    @Environment(\.presentationMode) var presentationMode
    
    private let primary = BrandColors.darkTeal
    private let dividerColor = Color.black.opacity(0.15)
    
    @State private var showLogoutPopup = false
    @State private var isSigningOut = false
    @State private var signOutError: String?
    @State private var adminEmail: String = ""
    @State private var adminName: String = ""
    
    private var currentEmail: String {
        Auth.auth().currentUser?.email ?? "No email"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    // Profile Header
                    VStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .foregroundColor(primary.opacity(0.6))
                        
                        Text(adminName.isEmpty ? "Admin" : adminName)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(primary)
                        
                        Text(currentEmail)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 30)
                    
                    // Settings List
                    VStack(spacing: 0) {
                        NavigationLink {
                            AdminChangeEmailView()
                            .onDisappear {
                                        // Refresh when we come back
                                        if let user = Auth.auth().currentUser {
                                            adminEmail = user.email ?? ""
                                        }
                                    }
                        } label: {
                            settingsRow(icon: "envelope", title: "Change Email",
                                        iconColor: primary, showChevron: true, showDivider: true)
                        }
                        
                        NavigationLink {
                            ChangePasswordView()
                        } label: {
                            settingsRow(icon: "lock", title: "Change Password",
                                        iconColor: primary, showChevron: true, showDivider: true)
                        }
                        
                        Button {
                            showLogoutPopup = true
                        } label: {
                            settingsRow(icon: "rectangle.portrait.and.arrow.right", title: "Logout",
                                        iconColor: primary, showChevron: false, showDivider: false)
                        }
                    }
                    .background(BrandColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
                    .padding(.horizontal, 16)
                    
                    Spacer()
                }
                .padding(.top, 6)
                
                // Logout Popup
                if showLogoutPopup {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    
                    GeometryReader { geometry in
                        VStack {
                            Spacer()
                            VStack(spacing: 20) {
                                Text("Logout?")
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                
                                Text("Are you sure you want to log out from this device?")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                                
                                if isSigningOut {
                                    ProgressView().tint(primary).padding(.top, 4)
                                }
                                
                                if let signOutError {
                                    Text(signOutError)
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundColor(.red)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 16)
                                }
                                
                                HStack(spacing: 16) {
                                    Button("No") {
                                        withAnimation { showLogoutPopup = false }
                                    }
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundColor(BrandColors.darkGray)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(BrandColors.lightGray)
                                    .cornerRadius(12)
                                    
                                    Button("Yes") {
                                        performLogout()
                                    }
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.red)
                                    .cornerRadius(12)
                                    .disabled(isSigningOut)
                                }
                                .padding(.top, 4)
                            }
                            .padding(EdgeInsets(top: 24, leading: 24, bottom: 20, trailing: 24))
                            .frame(width: 320)
                            .background(BrandColors.background)
                            .cornerRadius(20)
                            .shadow(radius: 12)
                            Spacer()
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .transition(.scale)
                }
            }
            .animation(.easeInOut, value: showLogoutPopup)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            loadAdminName()
        }
    }
    
    private func loadAdminName() {
        if let user = Auth.auth().currentUser {
            adminName = user.displayName ?? "Admin"
        }
    }
    
    private func performLogout() {
        isSigningOut = true
        signOutError = nil
        
        clearLocalCaches()
        signOutFirebase()
    }
    
    private func signOutFirebase() {
        do {
            // 1. Send notification to force logout
            NotificationCenter.default.post(name: .forceLogout, object: nil)
            
            // 2. Clear session
            session.user = nil
            session.role = nil
            session.isVerifiedCoach = false
            session.coachStatus = nil
            session.isGuest = false
            session.userListener?.remove()
            
            // 3. Sign out from Firebase
            try Auth.auth().signOut()
            
            isSigningOut = false
            showLogoutPopup = false
            
        } catch {
            isSigningOut = false
            signOutError = "Failed to sign out: \(error.localizedDescription)"
        }
    }
    
    private func clearLocalCaches() {
        UserDefaults.standard.removeObject(forKey: "signup_profile_draft")
        UserDefaults.standard.removeObject(forKey: "current_user_profile")
        UserDefaults.standard.synchronize()
        ReportStateService.shared.reset()
    }
    
    private func settingsRow(icon: String, title: String,
                             iconColor: Color, showChevron: Bool, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
                    .frame(width: 28, height: 28)
                
                Text(title)
                    .font(.system(size: 17, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)
                
                Spacer()
                
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            if showDivider {
                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)
                    .padding(.leading, 60)
            }
        }
    }
}

// =======================================================
// MARK: - Admin Change Email View
// =======================================================

struct AdminChangeEmailView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let primary = BrandColors.darkTeal
    private let db = Firestore.firestore()
    
    @State private var newEmail = ""
    @State private var password = ""
    @State private var isPasswordHidden = true
    
    @FocusState private var emailFocused: Bool
    
    // Email validation
    @State private var emailExists = false
    @State private var emailCheckError: String? = nil
    @State private var emailCheckTask: Task<Void, Never>? = nil
    @State private var isCheckingEmail = false
    
    // Operation states
    @State private var isSaving = false
    @State private var showVerifyPrompt = false
    @State private var verifyTask: Task<Void, Never>? = nil
    @State private var inlineVerifyError: String? = nil
    
    // Resend cooldown
    @State private var resendCooldown = 0
    @State private var resendTimerTask: Task<Void, Never>? = nil
    private let resendCooldownSeconds = 60
    private let emailActionURL = "https://haddaf-db.web.app/__/auth/action"
    
    // Alert states
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var alertIsError = false
    
    private var isEmailValid: Bool { isValidEmail(newEmail) }
    
    private var canSubmit: Bool {
        isEmailValid && !password.isEmpty && !emailExists && !isCheckingEmail && !isSaving
    }
    
    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    Text("Change Email")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                    
                    Text("Enter your new email address and current password to proceed.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // New Email Field
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("New Email")
                        
                        roundedField {
                            HStack {
                                TextField("", text: $newEmail)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundColor(primary)
                                    .tint(primary)
                                    .focused($emailFocused)
                                    .onSubmit { checkEmailImmediately() }
                                
                                if isCheckingEmail {
                                    ProgressView().scaleEffect(0.8)
                                }
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(!newEmail.isEmpty && (emailExists || !isEmailValid) ? Color.red : Color.clear, lineWidth: 1)
                        )
                        .onChange(of: emailFocused) { focused in
                            if !focused { checkEmailImmediately() }
                        }
                        .onChange(of: newEmail) { _, newValue in
                            if newValue.isEmpty {
                                emailExists = false
                                emailCheckError = nil
                            }
                        }
                        
                        // Email Errors
                        if !newEmail.isEmpty {
                            if !isEmailValid {
                                Text("Please enter a valid email address (name@domain).")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.red)
                            } else if emailExists {
                                Text("This email is already in use by another account.")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.red)
                            } else if let err = emailCheckError {
                                Text(err)
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.top, 10)
                    
                    // Current Password Field
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Current Password")
                        
                        roundedField {
                            HStack {
                                if isPasswordHidden {
                                    SecureField("", text: $password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .font(.system(size: 16, design: .rounded))
                                        .foregroundColor(primary)
                                } else {
                                    TextField("", text: $password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .font(.system(size: 16, design: .rounded))
                                        .foregroundColor(primary)
                                }
                                
                                Button {
                                    withAnimation { isPasswordHidden.toggle() }
                                } label: {
                                    Image(systemName: isPasswordHidden ? "eye.slash" : "eye")
                                        .foregroundColor(primary.opacity(0.6))
                                }
                            }
                        }
                    }
                    
                    // Submit Button
                    Button {
                        Task { await changeEmail() }
                    } label: {
                        HStack {
                            Text("Change Email")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                            if isSaving { ProgressView().colorInvert().scaleEffect(0.9) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(primary)
                        .clipShape(Capsule())
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1.0 : 0.5)
                    .padding(.top, 20)
                    
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .opacity(showVerifyPrompt ? 0.2 : 1.0)
            
            // Verification Overlay
            if showVerifyPrompt {
                Color.black.opacity(0.4).ignoresSafeArea()
                
                AdminEmailVerifySheet(
                    email: newEmail,
                    primary: primary,
                    resendCooldown: $resendCooldown,
                    errorText: $inlineVerifyError,
                    onResend: { Task { await resendVerification() } },
                    onClose: {
                        withAnimation { showVerifyPrompt = false }
                        isSaving = false
                        verifyTask?.cancel()
                        dismiss()
                    }
                )
                .transition(.scale)
                .zIndex(3)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert(alertIsError ? "Error" : "Success", isPresented: $showAlert) {
            Button("OK", role: .cancel) {
                if !alertIsError { dismiss() }
            }
        } message: {
            Text(alertMessage)
        }
        .onDisappear {
            verifyTask?.cancel()
            resendTimerTask?.cancel()
            emailCheckTask?.cancel()
        }
    }
    
    // MARK: - Helper Functions
    
    private func checkEmailImmediately() {
        emailCheckTask?.cancel()
        emailExists = false
        emailCheckError = nil
        isCheckingEmail = false
        
        let trimmed = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentEmail = Auth.auth().currentUser?.email ?? ""
        
        if trimmed.isEmpty || trimmed == currentEmail { return }
        guard isValidEmail(trimmed) else { return }
        
        let mail = trimmed.lowercased()
        isCheckingEmail = true
        
        emailCheckTask = Task {
            let testPassword = UUID().uuidString + "Aa1!"
            do {
                let result = try await Auth.auth().createUser(withEmail: mail, password: testPassword)
                try? await result.user.delete()
                await MainActor.run {
                    if !Task.isCancelled {
                        emailExists = false
                        isCheckingEmail = false
                    }
                }
            } catch {
                let ns = error as NSError
                await MainActor.run {
                    if !Task.isCancelled {
                        emailExists = (ns.code == AuthErrorCode.emailAlreadyInUse.rawValue)
                        isCheckingEmail = false
                    }
                }
            }
        }
    }
    
    private func changeEmail() async {
        guard let user = Auth.auth().currentUser else {
            alertMessage = "User not authenticated"
            alertIsError = true
            showAlert = true
            return
        }
        
        isSaving = true
        
        // Re-authenticate
        let credential = EmailAuthProvider.credential(withEmail: user.email ?? "", password: password)
        
        do {
            try await user.reauthenticate(with: credential)
            
            // Update email
            try await user.updateEmail(to: newEmail)
            
            // Send verification email
            try await sendVerificationEmail(to: user)
            markVerificationSentNow()
            startResendCooldown(seconds: resendCooldownSeconds)
            
            await MainActor.run {
                isSaving = false
                withAnimation { showVerifyPrompt = true }
            }
            
            startVerificationWatcher()
            
        } catch {
            await MainActor.run {
                isSaving = false
                let ns = error as NSError
                
                if ns.code == AuthErrorCode.wrongPassword.rawValue {
                    alertMessage = "Incorrect password. Please try again."
                } else if ns.code == AuthErrorCode.emailAlreadyInUse.rawValue {
                    emailExists = true
                    alertMessage = "This email is already in use."
                } else {
                    alertMessage = "Failed to update email: \(error.localizedDescription)"
                }
                
                alertIsError = true
                showAlert = true
            }
        }
    }
    
    private func sendVerificationEmail(to user: User) async throws {
        let acs = ActionCodeSettings()
        acs.handleCodeInApp = true
        acs.url = URL(string: emailActionURL)
        if let bundleID = Bundle.main.bundleIdentifier {
            acs.setIOSBundleID(bundleID)
        }
        
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            user.sendEmailVerification(with: acs) { err in
                if let err { cont.resume(throwing: err) }
                else { cont.resume() }
            }
        }
    }
    
    private func startVerificationWatcher() {
        verifyTask?.cancel()
        verifyTask = Task {
            let deadline = Date().addingTimeInterval(600)
            while !Task.isCancelled && Date() < deadline {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let user = Auth.auth().currentUser else { break }
                try? await user.reload()
                
                if user.isEmailVerified {
                    await finalizeEmailUpdate(for: user)
                    break
                }
            }
        }
    }
    
    @MainActor
    private func finalizeEmailUpdate(for user: User) async {
        try? await user.getIDToken(forcingRefresh: true)
        
        showVerifyPrompt = false
        isSaving = false
        
        alertMessage = "Email verified and updated successfully!"
        alertIsError = false
        showAlert = true
    }
    
    private func resendVerification() async {
        guard let user = Auth.auth().currentUser else { return }
        if resendCooldown > 0 { return }
        
        do {
            try await sendVerificationEmail(to: user)
            markVerificationSentNow()
            startResendCooldown(seconds: resendCooldownSeconds)
            inlineVerifyError = nil
        } catch {
            inlineVerifyError = error.localizedDescription
        }
    }
    
    private func startResendCooldown(seconds: Int) {
        resendTimerTask?.cancel()
        resendCooldown = seconds
        resendTimerTask = Task {
            while !Task.isCancelled && resendCooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { resendCooldown -= 1 }
            }
        }
    }
    
    private func markVerificationSentNow() {
        UserDefaults.standard.set(Int(Date().timeIntervalSince1970), forKey: "admin_email_verification_sent")
    }
    
    private func isValidEmail(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        if value.contains("..") { return false }
        let pattern = #"^(?![.])([A-Za-z0-9._%+-]{1,64})(?<![.])@([A-Za-z0-9-]{1,63}\.)+[A-Za-z]{2,63}$"#
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: value)
    }
    
    private func fieldLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 14, design: .rounded)).foregroundColor(.gray)
    }
    
    private func roundedField<Content: View>(@ViewBuilder c: () -> Content) -> some View {
        c()
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(BrandColors.background)
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
            )
    }
}

// Admin Email Verification Sheet
struct AdminEmailVerifySheet: View {
    let email: String
    let primary: Color
    @Binding var resendCooldown: Int
    @Binding var errorText: String?
    var onResend: () -> Void
    var onClose: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                
                Text("Verify your new email")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("We've sent a verification link to \(email).\n\nOpen the link to verify your new email address.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                
                Button(action: { if resendCooldown == 0 { onResend() } }) {
                    Text(resendCooldown > 0 ? "Resend (\(resendCooldown)s)" : "Resend")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(resendCooldown > 0)
                
                if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                }
                
                Spacer().frame(height: 8)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(BrandColors.background)
                    .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 10)
            )
            Spacer()
        }
        .padding()
        .background(Color.clear)
        .allowsHitTesting(true)
    }
}

// =======================================================
// MARK: - Rejection Reason Sheet
// =======================================================

struct RejectionReasonSheet: View {
    let coachName: String
    @Binding var rejectionReason: String
    @Binding var isRejecting: Bool
    var onCancel: () -> Void
    var onConfirm: () -> Void
    
    private let primary = BrandColors.darkTeal
    private let charLimit = 500
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            
            VStack(spacing: 8) {
                Text("Reject Coach Application")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(primary)
                
                Text("Please provide a reason for rejecting \(coachName)'s application.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Text Editor
            VStack(alignment: .trailing, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    if rejectionReason.isEmpty {
                        Text("Explain why the application was rejected...")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundColor(.gray.opacity(0.6))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    
                    TextEditor(text: $rejectionReason)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(primary)
                        .frame(height: 120)
                        .scrollContentBackground(.hidden)
                        .onChange(of: rejectionReason) { _, newValue in
                            if newValue.count > charLimit {
                                rejectionReason = String(newValue.prefix(charLimit))
                            }
                        }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor.systemGray6))
                )
                
                Text("\(rejectionReason.count)/\(charLimit)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            // Action Buttons
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(BrandColors.darkGray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(BrandColors.lightGray)
                        .clipShape(Capsule())
                }
                
                Button(action: onConfirm) {
                    HStack {
                        Text("Reject")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        if isRejecting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.red.opacity(0.5) : Color.red)
                    .clipShape(Capsule())
                }
                .disabled(rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRejecting)
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding(.vertical, 10)
        .background(BrandColors.background)
    }
}
