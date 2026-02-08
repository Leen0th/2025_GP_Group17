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
    let rejectionCategory: String?
    let previousRequests: [PreviousRequest]
}

struct PreviousRequest: Identifiable {
    let id: String
    let submittedAt: Date?
    let reviewedAt: Date?
    let status: String
    let rejectionReason: String?
    let rejectionCategory: String?
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
    @State private var expandedHistoryIDs: Set<String> = []
    @State private var expandedCommentIDs: Set<String> = [] // Track which history items have expanded comments
    @State private var selectedTab: RequestTab = .pending // Tab selection
    @State private var statusFilter: String = "all" // "all", "approved", "rejected"
    @State private var reviewed: [CoachRequestItem] = [] // For approved/rejected requests

    enum RequestTab: String, CaseIterable {
        case pending = "Pending"
        case reviewed = "Reviewed"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                VStack(spacing: 14) {
                    
                    // Search and Sort Controls
                    VStack(spacing: 10) {
                        // Search + Sort + Filter in one horizontal row
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
                            
                            // Filter icon (only for reviewed tab)
                            if selectedTab == .reviewed {
                                Menu {
                                    Button {
                                        statusFilter = "all"
                                    } label: {
                                        Label("All Requests", systemImage: statusFilter == "all" ? "checkmark" : "")
                                    }
                                    
                                    Button {
                                        statusFilter = "approved"
                                    } label: {
                                        Label("Approved Only", systemImage: statusFilter == "approved" ? "checkmark" : "")
                                    }
                                    
                                    Button {
                                        statusFilter = "rejected"
                                    } label: {
                                        Label("Rejected Only", systemImage: statusFilter == "rejected" ? "checkmark" : "")
                                    }
                                } label: {
                                    Image(systemName: statusFilter == "all" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(statusFilter != "all" ? BrandColors.darkTeal : .secondary)
                                        .padding(8)
                                }
                            }
                            
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

                    // Tabs - Discovery Style
                    HStack(spacing: 0) {
                        ForEach(RequestTab.allCases, id: \.self) { tab in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTab = tab
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    Text(tab.rawValue)
                                        .font(.system(size: 16, weight: .medium, design: .rounded))
                                        .foregroundColor(selectedTab == tab ? primary : .secondary)
                                    
                                    if selectedTab == tab {
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
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)

                    if loading {
                        ProgressView().tint(primary)
                    } else if let errorText {
                        Text(errorText)
                            .foregroundColor(.red)
                            .font(.system(size: 13, design: .rounded))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                    } else if displayedRequests.isEmpty {
                        Text(emptyStateMessage)
                            .foregroundColor(.secondary)
                            .font(.system(size: 14, design: .rounded))
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(displayedRequests) { item in
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
                    onConfirm: { category, reason in
                        if let coach = selectedCoachForRejection {
                            Task {
                                await rejectWithReason(uid: coach.uid, requestId: coach.id, category: category, reason: reason)
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

    private var filteredAndSortedReviewed: [CoachRequestItem] {
        let s = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Filter by status first
        let statusFiltered: [CoachRequestItem]
        if statusFilter == "all" {
            statusFiltered = reviewed
        } else {
            statusFiltered = reviewed.filter { $0.status == statusFilter }
        }
        
        // Filter by search
        let filtered: [CoachRequestItem]
        if s.isEmpty {
            filtered = statusFiltered
        } else {
            filtered = statusFiltered.filter {
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
    
    private var displayedRequests: [CoachRequestItem] {
        switch selectedTab {
        case .pending:
            return filteredAndSortedPending
        case .reviewed:
            return filteredAndSortedReviewed
        }
    }
    
    private var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "No results found."
        }
        
        switch selectedTab {
        case .pending:
            return "No pending coach requests."
        case .reviewed:
            if statusFilter == "approved" {
                return "No approved requests."
            } else if statusFilter == "rejected" {
                return "No rejected requests."
            } else {
                return "No reviewed requests."
            }
        }
    }

    private func coachCard(_ item: CoachRequestItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Clickable Name
            NavigationLink {
                CoachProfileContentView(
                    userID: item.uid,
                    isAdminViewing: true,
                    onAdminApprove: {
                        Task { await approve(uid: item.uid, requestId: item.id) }
                    },
                    onAdminReject: {
                        selectedCoachForRejection = item
                        showRejectionSheet = true
                    }
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.fullName.isEmpty ? "Coach" : item.fullName)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(primary)
                    
                    Text(item.email)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            
            // Previous Requests History
            if !item.previousRequests.isEmpty {
                Button {
                    if expandedHistoryIDs.contains(item.id) {
                        expandedHistoryIDs.remove(item.id)
                    } else {
                        expandedHistoryIDs.insert(item.id)
                    }
                } label: {
                    HStack {
                        Image(systemName: expandedHistoryIDs.contains(item.id) ? "chevron.up.circle.fill" : "clock.arrow.circlepath")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                        
                        Text(expandedHistoryIDs.contains(item.id) ? "Hide Request History" : "View Request History (\(item.previousRequests.count))")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.orange)
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                if expandedHistoryIDs.contains(item.id) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(item.previousRequests) { prev in
                            VStack(alignment: .leading, spacing: 8) {
                                // Header with status
                                HStack {
                                    Text("Previous Request")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(prev.status.capitalized)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(prev.status == "rejected" ? .red : .green)
                                }
                                
                                // Submitted date
                                if let date = prev.submittedAt {
                                    Text("Submitted: \(formatDate(date))")
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                                
                                // Category (if rejected)
                                if prev.status == "rejected", let category = prev.rejectionCategory {
                                    HStack(spacing: 4) {
                                        Image(systemName: "tag.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.orange)
                                        Text(categoryDisplayName(for: category))
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.orange.opacity(0.15))
                                    )
                                }
                                
                                // Rejection reason with expand/collapse
                                if let reason = prev.rejectionReason, !reason.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Admin's Comment:")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundColor(.secondary)
                                        
                                        // Check if comment is long
                                        if reason.count > 80 {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(expandedCommentIDs.contains(prev.id) ? reason : String(reason.prefix(80)) + "...")
                                                    .font(.system(size: 12, design: .rounded))
                                                    .foregroundColor(.primary)
                                                    .lineLimit(expandedCommentIDs.contains(prev.id) ? nil : 2)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                
                                                Button {
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        if expandedCommentIDs.contains(prev.id) {
                                                            expandedCommentIDs.remove(prev.id)
                                                        } else {
                                                            expandedCommentIDs.insert(prev.id)
                                                        }
                                                    }
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Text(expandedCommentIDs.contains(prev.id) ? "Show Less" : "Read More")
                                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                        Image(systemName: expandedCommentIDs.contains(prev.id) ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                                            .font(.system(size: 11))
                                                    }
                                                    .foregroundColor(primary)
                                                }
                                            }
                                        } else {
                                            Text(reason)
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundColor(.primary)
                                        }
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.red.opacity(0.1))
                                    )
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(UIColor.systemGray6))
                            )
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

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

            coachApprovalButtons(item: item)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BrandColors.background)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
    }
    
    private func coachApprovalButtons(item: CoachRequestItem) -> some View {
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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(BrandColors.background)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func categoryDisplayName(for category: String) -> String {
        switch category {
        case "insufficient_docs":
            return "Insufficient Documentation"
        case "invalid_credentials":
            return "Invalid Credentials"
        case "policy_violation":
            return "Policy Violation"
        default:
            return "Other"
        }
    }

private func loadPending() async {
        loading = true
        errorText = nil
        do {
            // Fetch pending requests
            let pendingSnap = try await Firestore.firestore().collection("coachRequests")
                .whereField("status", isEqualTo: "pending")
                .order(by: "submittedAt", descending: true)
                .getDocuments()

            // Fetch reviewed requests (approved and rejected)
            let reviewedSnap = try await Firestore.firestore().collection("coachRequests")
                .whereField("status", in: ["approved", "rejected"])
                .order(by: "reviewedAt", descending: true)
                .limit(to: 100)
                .getDocuments()

            // Process pending requests
            var pendingItems: [CoachRequestItem] = []
            for d in pendingSnap.documents {
                let item = try await buildCoachRequestItem(from: d)
                pendingItems.append(item)
            }
            
            // Process reviewed requests
            var reviewedItems: [CoachRequestItem] = []
            for d in reviewedSnap.documents {
                let item = try await buildCoachRequestItem(from: d)
                reviewedItems.append(item)
            }
            
            await MainActor.run {
                pending = pendingItems
                reviewed = reviewedItems
                loading = false
            }
        } catch {
            await MainActor.run {
                loading = false
                errorText = error.localizedDescription
            }
        }
    }
    
    private func buildCoachRequestItem(from d: QueryDocumentSnapshot) async throws -> CoachRequestItem {
        let data = d.data()
        let uid = data["uid"] as? String ?? ""
        let ts = data["submittedAt"] as? Timestamp
        
        // Fetch previous requests for this coach
        let historySnap = try await Firestore.firestore().collection("coachRequests")
            .whereField("uid", isEqualTo: uid)
            .whereField("status", in: ["rejected", "approved"])
            .order(by: "submittedAt", descending: true)
            .getDocuments()
        
        let previousRequests = historySnap.documents.compactMap { prevDoc -> PreviousRequest? in
            // Don't include current request in history
            guard prevDoc.documentID != d.documentID else { return nil }
            
            let prevData = prevDoc.data()
            return PreviousRequest(
                id: prevDoc.documentID,
                submittedAt: (prevData["submittedAt"] as? Timestamp)?.dateValue(),
                reviewedAt: (prevData["reviewedAt"] as? Timestamp)?.dateValue(),
                status: prevData["status"] as? String ?? "",
                rejectionReason: prevData["rejectionReason"] as? String,
                rejectionCategory: prevData["rejectionCategory"] as? String
            )
        }
        
        return CoachRequestItem(
            id: d.documentID,
            uid: uid,
            fullName: data["fullName"] as? String ?? "",
            email: data["email"] as? String ?? "",
            status: data["status"] as? String ?? "pending",
            submittedAt: ts?.dateValue(),
            verificationFile: data["verificationFile"] as? String ?? "",
            rejectionReason: data["rejectionReason"] as? String,
            rejectionCategory: data["rejectionCategory"] as? String,
            previousRequests: previousRequests
        )
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

    private func rejectWithReason(uid: String, requestId: String, category: String, reason: String) async {
        errorText = nil
        isRejecting = true
        
        do {
            let db = Firestore.firestore()
            let batch = db.batch()

            let reqRef = db.collection("coachRequests").document(requestId)
            batch.updateData([
                "status": "rejected",
                "rejectionCategory": category,
                "rejectionReason": reason.trimmingCharacters(in: .whitespacesAndNewlines),
                "reviewedAt": FieldValue.serverTimestamp()
            ], forDocument: reqRef)

            let userRef = db.collection("users").document(uid)
            batch.updateData([
                "coachStatus": "rejected",
                "rejectionCategory": category,
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
    let name: String
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
    @State private var filterStatus: String = "all" // "all", "active", "inactive"
    
    @State private var showConfirmDialog = false
    @State private var pendingAction: (() -> Void)?
    @State private var confirmMessage = ""
    @State private var confirmTitle = ""
    @State private var isDestructive = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                
                VStack(spacing: 12) {
                    searchBox

                    
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
            .overlay {
                if showConfirmDialog {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    
                    GeometryReader { geometry in
                        VStack {
                            Spacer()
                            VStack(spacing: 20) {
                                Text(confirmTitle)
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                
                                Text(confirmMessage)
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                                
                                HStack(spacing: 16) {
                                    Button("Cancel") {
                                        withAnimation { showConfirmDialog = false }
                                        pendingAction = nil
                                    }
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundColor(BrandColors.darkGray)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(BrandColors.lightGray)
                                    .cornerRadius(12)
                                    
                                    Button("Confirm") {
                                        withAnimation { showConfirmDialog = false }
                                        pendingAction?()
                                        pendingAction = nil
                                    }
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(isDestructive ? Color.red : primary)
                                    .cornerRadius(12)
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
            .animation(.easeInOut, value: showConfirmDialog)
        }
    }
    
    private var searchBox: some View {
        HStack(spacing: 12) {
            // Search field
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
            
            // Status Filter Icon
            Menu {
                Button {
                    filterStatus = "all"
                } label: {
                    Label("All Accounts", systemImage: filterStatus == "all" ? "checkmark" : "")
                }
                
                Button {
                    filterStatus = "active"
                } label: {
                    Label("Active Only", systemImage: filterStatus == "active" ? "checkmark" : "")
                }
                
                Button {
                    filterStatus = "inactive"
                } label: {
                    Label("Inactive Only", systemImage: filterStatus == "inactive" ? "checkmark" : "")
                }
            } label: {
                Image(systemName: filterStatus == "all" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(filterStatus != "all" ? primary : .secondary)
                    .padding(8)
            }
            
            // Sort menu
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
                .foregroundColor(primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(BrandColors.background)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.07), radius: 4, y: 2)
            }
        }
        .padding(.horizontal, 18)
    }
    
    private var filteredUsers: [UserRowItem] {
        let s = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Filter by role first
        let roleFiltered = users.filter { $0.role.lowercased() == selectedRole.lowercased() }
        
        // Filter by status
        let statusFiltered: [UserRowItem]
        if filterStatus == "all" {
            statusFiltered = roleFiltered
        } else if filterStatus == "active" {
            statusFiltered = roleFiltered.filter { $0.isActive }
        } else {
            statusFiltered = roleFiltered.filter { !$0.isActive }
        }
        
        // Then filter by search
        let searchFiltered: [UserRowItem]
        if s.isEmpty {
            searchFiltered = statusFiltered
        } else {
            searchFiltered = statusFiltered.filter {
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
                CoachProfileContentView(userID: u.id, isAdminViewing: true, onAdminApprove: nil, onAdminReject: nil)
            } else {
                PlayerProfileContentView(userID: u.id, isAdminViewing: true)
            }
        } label: {
            accountCardContent(u)
        }
        .buttonStyle(.plain)
    }
    
    private func accountCardContent(_ u: UserRowItem) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink {
                    if u.role.lowercased() == "coach" {
                        CoachProfileContentView(userID: u.id, isAdminViewing: true, onAdminApprove: nil, onAdminReject: nil)
                    } else {
                        PlayerProfileContentView(userID: u.id, isAdminViewing: true)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(u.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(primary)
                            .padding(.trailing, 70)
                        
                        Text(u.email)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }

                Text("Role: \(u.role)")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Button {
                    confirmTitle = "Activate Account?"
                    confirmMessage = "Are you sure you want to activate this account? The user will regain full access."
                    isDestructive = false
                    pendingAction = {
                        Task { await setActive(uid: u.id, active: true) }
                    }
                    showConfirmDialog = true
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
                    confirmTitle = "Deactivate Account?"
                    confirmMessage = "Are you sure you want to deactivate this account? The user will lose access to their account."
                    isDestructive = true
                    pendingAction = {
                        Task { await setActive(uid: u.id, active: false) }
                    }
                    showConfirmDialog = true
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
        
            // Status Badge - Top Right
            Text(u.isActive ? "Active" : "Inactive")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(u.isActive ? Color.green : Color.red)
                .clipShape(Capsule())
                .padding([.top, .trailing], 12)
        }
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
                let firstName = data["firstName"] as? String ?? ""
                let lastName = data["lastName"] as? String ?? ""
                let fullName = [firstName, lastName].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                return UserRowItem(
                    id: d.documentID,
                    email: data["email"] as? String ?? "",
                    name: fullName.isEmpty ? "User" : fullName,
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

// =======================================================
// MARK: - 3) Admin Challenges - FIXED VERSION
// =======================================================

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI

struct AdminChallengeItem: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let criteria: [String]
    let startAt: Date?
    let endAt: Date?
    let imageURL: String
    let yearMonth: String
}

private enum AdminChallengeStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case upcoming = "Upcoming"  // ✨ NEW
    case current = "Current"
    case past = "Past"
    var id: String { rawValue }
}

private struct AdminChallengeFilters: Equatable {
    var status: AdminChallengeStatusFilter = .all
    var year: Int? = nil
    var month: Int? = nil

    var isActive: Bool {
        status != .all || year != nil || month != nil
    }

    mutating func reset() {
        status = .all
        year = nil
        month = nil
    }
}

struct AdminChallengesView: View {
    private let primary = BrandColors.darkTeal

    @State private var loading = true
    @State private var errorText: String?
    @State private var challenges: [AdminChallengeItem] = []
    @State private var listener: ListenerRegistration? = nil

    @State private var searchText = ""
    @State private var showFiltersSheet = false
    @State private var filters = AdminChallengeFilters()
    @State private var appliedFilters = AdminChallengeFilters()

    @State private var showCreateSheet = false
    @State private var selectedChallenge: AdminChallengeItem? = nil
    @State private var showDetailsSheet = false

    @State private var editingChallenge: AdminChallengeItem? = nil
    @State private var showEditSheet = false

    @State private var showDeletePopup = false
    @State private var deletingChallenge: AdminChallengeItem? = nil
    @State private var isDeleting = false
    @State private var deleteError: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                VStack(spacing: 14) {

                    // ✅ Search + Filter button with green background when active
                    HStack(spacing: 12) {
                        searchBox
                        Button {
                            filters = appliedFilters
                            showFiltersSheet = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(appliedFilters.isActive ? .white : primary)
                                .padding(10)
                                .background(appliedFilters.isActive ? primary : Color.clear)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)

                    // Add Challenge Button
                    Button { showCreateSheet = true } label: {
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
                    } else if filteredChallenges.isEmpty {
                        Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? "No challenges found."
                             : "No results found.")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14, design: .rounded))
                        .padding(.top, 16)
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(filteredChallenges) { ch in
                                    AdminChallengeHeroCard(challenge: ch, primary: primary)
                                        .onTapGesture {
                                            selectedChallenge = ch
                                            showDetailsSheet = true
                                        }
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.bottom, 20)
                        }
                    }

                    Spacer()
                }

                if showDeletePopup, let deletingChallenge {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    AdminConfirmPopup(
                        title: "Delete challenge?",
                        message: "This will permanently delete the challenge and all its submissions and ratings. This action cannot be undone.",
                        primary: primary,
                        isLoading: isDeleting,
                        errorText: deleteError,
                        cancelTitle: "No",
                        confirmTitle: "Yes",
                        confirmColor: .red,
                        onCancel: {
                            withAnimation {
                                showDeletePopup = false
                                self.deletingChallenge = nil
                                deleteError = nil
                            }
                        },
                        onConfirm: {
                            Task { await deleteChallengeCascade(deletingChallenge) }
                        }
                    )
                    .transition(.scale)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { startListening() }
            .onDisappear { listener?.remove(); listener = nil }

            // ✅ Filters sheet with "Apply Filters" button that turns green when active
            .sheet(isPresented: $showFiltersSheet) {
                AdminChallengeFiltersSheet(
                    challenges: challenges,
                    primary: primary,
                    filters: $filters,
                    onApply: {
                        appliedFilters = filters
                        showFiltersSheet = false
                    },
                    onReset: {
                        filters.reset()
                        appliedFilters.reset()
                        showFiltersSheet = false
                    },
                    onDone: {
                        showFiltersSheet = false
                    }
                )
                .presentationDetents([.height(360)])
                .presentationCornerRadius(28)
                .presentationBackground(BrandColors.background)
            }

            .sheet(isPresented: $showCreateSheet) {
                AdminCreateMonthlyChallengeSheet(primary: primary) {
                    showCreateSheet = false
                }
            }

            .sheet(isPresented: $showDetailsSheet, onDismiss: {
                selectedChallenge = nil
            }) {
                if let ch = selectedChallenge {
                    AdminChallengeDetailsSheet(
                        challenge: ch,
                        primary: primary,
                        onClose: { showDetailsSheet = false },
                        onEdit: {
                            editingChallenge = ch
                            showDetailsSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                showEditSheet = true
                            }
                        },
                        onDelete: {
                            self.deletingChallenge = ch
                            self.deleteError = nil
                            self.showDetailsSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation { self.showDeletePopup = true }
                            }
                        }
                    )
                } else {
                    Text("No challenge selected")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding()
                }
            }

            .sheet(isPresented: $showEditSheet, onDismiss: { editingChallenge = nil }) {
                if let ch = editingChallenge {
                    AdminEditMonthlyChallengeSheet(primary: primary, challenge: ch) {
                        showEditSheet = false
                        editingChallenge = nil
                    }
                } else {
                    Text("No challenge selected")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }
    }

    private var searchBox: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search challenge by name...", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(BrandColors.background)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        )
    }

    private var filteredChallenges: [AdminChallengeItem] {
        let s = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let now = Date()

        var list = challenges
        if !s.isEmpty {
            list = list.filter { $0.title.lowercased().contains(s) }
        }

        list = list.filter { ch in
            let startAt = ch.startAt ?? .distantPast
            let endAt = ch.endAt ?? .distantPast
            
            // ✨ NEW: 3 states instead of 2
            let isUpcoming = now < startAt
            let isCurrent = now >= startAt && now < endAt
            let isPast = now >= endAt
            
            switch appliedFilters.status {
            case .all:
                break
            case .upcoming:
                if !isUpcoming { return false }
            case .current:
                if !isCurrent { return false }
            case .past:
                if !isPast { return false }
            }

            if let year = appliedFilters.year {
                if !ch.yearMonth.hasPrefix(String(format: "%04d", year)) { return false }
            }
            if let month = appliedFilters.month {
                let m = String(format: "-%02d", month)
                if !ch.yearMonth.contains(m) { return false }
            }

            return true
        }

        return list.sorted { $0.yearMonth > $1.yearMonth }
    }

    // ✨ NEW: Helper function
    private func canEditOrDelete(_ challenge: AdminChallengeItem) -> Bool {
        let now = Date()
        let startAt = challenge.startAt ?? .distantPast
        
        // Only allow editing/deleting if challenge hasn't started yet (Upcoming)
        return now < startAt
    }

    private func startListening() {
        loading = true
        errorText = nil
        listener?.remove()

        listener = Firestore.firestore()
            .collection("challenges")
            .order(by: "yearMonth", descending: true)
            .addSnapshotListener { snap, err in
                if let err {
                    loading = false
                    errorText = err.localizedDescription
                    return
                }
                guard let snap else { loading = false; return }

                challenges = snap.documents.map { d in
                    let data = d.data()
                    let startAt = (data["startAt"] as? Timestamp)?.dateValue()
                    let endAt   = (data["endAt"] as? Timestamp)?.dateValue()
                    let criteriaArr = data["criteria"] as? [String] ?? []
                    let ym = data["yearMonth"] as? String ?? ""

                    return AdminChallengeItem(
                        id: d.documentID,
                        title: data["title"] as? String ?? "",
                        description: data["description"] as? String ?? "",
                        criteria: criteriaArr,
                        startAt: startAt,
                        endAt: endAt,
                        imageURL: data["imageURL"] as? String ?? "",
                        yearMonth: ym
                    )
                }

                loading = false
            }
    }

    private func deleteChallengeCascade(_ challenge: AdminChallengeItem) async {
        await MainActor.run {
            isDeleting = true
            deleteError = nil
        }

        do {
            let db = Firestore.firestore()
            let challengeRef = db.collection("challenges").document(challenge.id)

            let submissionsSnap = try await challengeRef.collection("submissions").getDocuments()
            for subDoc in submissionsSnap.documents {
                let storagePath = subDoc.data()["storagePath"] as? String ?? ""

                let ratingsSnap = try await subDoc.reference.collection("ratings").getDocuments()
                for ratingDoc in ratingsSnap.documents {
                    try await ratingDoc.reference.delete()
                }

                if !storagePath.isEmpty {
                    try? await Storage.storage().reference().child(storagePath).delete()
                }

                try await subDoc.reference.delete()
            }

            try await challengeRef.delete()

            await MainActor.run {
                isDeleting = false
                showDeletePopup = false
                deletingChallenge = nil
            }

        } catch {
            await MainActor.run {
                isDeleting = false
                deleteError = "Failed to delete: \(error.localizedDescription)"
            }
        }
    }
}

// =======================================================
// MARK: - Card UI
// =======================================================

private struct AdminChallengeHeroCard: View {
    let challenge: AdminChallengeItem
    let primary: Color

    // ✨ NEW: 3 states
    private var challengeStatus: String {
        let now = Date()
        guard let start = challenge.startAt, let end = challenge.endAt else {
            return "Unknown"
        }
        
        if now < start { return "Upcoming" }
        if now >= start && now < end { return "Current" }
        return "Past"
    }
    
    private var isPast: Bool {
        if let end = challenge.endAt { return Date() > end }
        return false
    }

    private var dateText: String {
        let now = Date()
        guard let start = challenge.startAt, let end = challenge.endAt else {
            return ""
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy"
        
        if now < start {
            return "Starts \(formatter.string(from: start))"
        } else if now >= end {
            return "Ended \(formatter.string(from: end))"
        } else {
            return "Ends \(formatter.string(from: end))"
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(UIColor.systemGray5))
                .frame(height: 160)

            if let url = URL(string: challenge.imageURL), !challenge.imageURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(UIColor.systemGray5))
                            .frame(height: 160)
                            .overlay(ProgressView().tint(primary))
                    case .success(let image):
                        image.resizable()
                            .scaledToFill()
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .clipped()
                    default:
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(UIColor.systemGray5))
                            .frame(height: 160)
                            .overlay(Text("Image failed").foregroundColor(.secondary))
                    }
                }
            }

            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(height: 160)

            HStack(alignment: .bottom) {
                Text(challenge.title.isEmpty ? "Challenge" : challenge.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(challengeStatus)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(isPast ? .gray : primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.85))
                        .clipShape(Capsule())

                    if !dateText.isEmpty {
                        Text(dateText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                    }
                }
            }
            .padding(16)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 8)
        .opacity(isPast ? 0.75 : 1)
    }
}

// =======================================================
// MARK: - Details Sheet
// =======================================================

private struct AdminChallengeDetailsSheet: View {
    let challenge: AdminChallengeItem
    let primary: Color
    let onClose: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    // ✨ NEW: 3 states
    private var challengeStatus: String {
        let now = Date()
        guard let start = challenge.startAt, let end = challenge.endAt else {
            return "Unknown"
        }
        
        if now < start { return "Upcoming" }
        if now >= start && now < end { return "Current" }
        return "Past"
    }
    
    private var statusColor: Color {
        switch challengeStatus {
        case "Upcoming": return .orange
        case "Current": return primary
        case "Past": return .gray
        default: return .gray
        }
    }
    
    // ✨ NEW: Can only edit Upcoming
    private var canEdit: Bool {
        let now = Date()
        guard let start = challenge.startAt else { return false }
        return now < start
    }

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(challenge.title.isEmpty ? "Challenge" : challenge.title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(primary)

                        Spacer()

                        // ✨ Updated badge
                        Text(challengeStatus)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(statusColor)
                            .clipShape(Capsule())
                    }

                    if let url = URL(string: challenge.imageURL), !challenge.imageURL.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color(UIColor.systemGray5))
                                    .frame(height: 190)
                                    .overlay(ProgressView().tint(primary))
                            case .success(let image):
                                image.resizable()
                                    .scaledToFill()
                                    .frame(height: 190)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                    .clipped()
                            default:
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color(UIColor.systemGray5))
                                    .frame(height: 190)
                                    .overlay(Text("Image failed").foregroundColor(.secondary))
                            }
                        }
                    }

                    sectionTitle("Description")
                    Text(challenge.description.isEmpty ? "-" : challenge.description)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(.secondary)

                    sectionTitle("Criteria")
                    if challenge.criteria.isEmpty {
                        Text("-")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(challenge.criteria, id: \.self) { c in
                                Text("• \(c)")
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if let start = challenge.startAt, let end = challenge.endAt {
                        sectionTitle("Start / End")
                        Text("\(formattedDate(start))  →  \(formattedDate(end))")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    // ✨ NEW: Conditional buttons
                    if canEdit {
                        HStack(spacing: 14) {
                            Button {
                                onDelete()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "trash")
                                    Text("Delete")
                                }
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.9))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Button {
                                onEdit()
                            } label: {
                                Text("Edit")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 14)
                                    .frame(maxWidth: .infinity)
                                    .background(primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 8)
                    } else {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.orange)
                                Text("Cannot edit or delete")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            
                            Text("Active and past challenges are locked to preserve data integrity")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 8)
                    }

                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") {
                    dismiss()
                    onClose()
                }
                .foregroundColor(primary)
            }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundColor(.primary)
            .padding(.top, 6)
    }
    
    private func formattedDate(_ date: Date) -> String {
          let formatter = DateFormatter()
          formatter.locale = Locale(identifier: "en_US_POSIX")
          formatter.dateFormat = "dd/MM/yyyy"
          return formatter.string(from: date)
      }
}

// =======================================================
// MARK: - ✅ Filters Sheet with ALL years from challenges + Apply turns green
// =======================================================

private struct AdminChallengeFiltersSheet: View {
    let challenges: [AdminChallengeItem]
    let primary: Color
    @Binding var filters: AdminChallengeFilters

    let onApply: () -> Void
    let onReset: () -> Void
    let onDone: () -> Void

    // ✅ Get ALL unique years from existing challenges
    private var years: [Int] {
        let cal = Calendar.current
        let allYears = challenges.compactMap { ch -> Int? in
            guard let start = ch.startAt else { return nil }
            return cal.component(.year, from: start)
        }
        return Array(Set(allYears)).sorted(by: >)
    }

    private let months: [(Int, String)] = [
        (1,"Jan"),(2,"Feb"),(3,"Mar"),(4,"Apr"),(5,"May"),(6,"Jun"),
        (7,"Jul"),(8,"Aug"),(9,"Sep"),(10,"Oct"),(11,"Nov"),(12,"Dec")
    ]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()
                Button("Done") { onDone() }
                    .foregroundColor(primary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            Text("Filters")
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            VStack(spacing: 10) {
                filterRow(title: "Challenge") {
                    Picker("", selection: $filters.status) {
                        ForEach(AdminChallengeStatusFilter.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                }

                filterRow(title: "Year") {
                    Picker("", selection: Binding(
                        get: { filters.year ?? 0 },
                        set: { newVal in filters.year = (newVal == 0 ? nil : newVal) }
                    )) {
                        Text("Any").tag(0)
                        ForEach(years, id: \.self) { y in
                            Text("\(y)").tag(y)
                        }
                    }
                    .pickerStyle(.menu)
                }

                filterRow(title: "Month") {
                    Picker("", selection: Binding(
                        get: { filters.month ?? 0 },
                        set: { newVal in filters.month = (newVal == 0 ? nil : newVal) }
                    )) {
                        Text("Any").tag(0)
                        ForEach(months, id: \.0) { m in
                            Text(m.1).tag(m.0)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(.horizontal, 18)

            // ✅ Button turns green when filters are active
            Button {
                onApply()
            } label: {
                Text("Apply Filters")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(filters.isActive ? .white : primary)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(filters.isActive ? primary : Color(UIColor.systemGray6))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)

            Button {
                onReset()
            } label: {
                Text("Reset All")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.red)
                    .padding(.vertical, 10)
            }

            Spacer(minLength: 4)
        }
        .padding(.bottom, 10)
    }

    private func filterRow(title: String, @ViewBuilder right: () -> some View) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
            Spacer()
            right()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.systemGray6)))
    }
}

// =======================================================
// MARK: - ✅ Create Challenge Sheet - Image REQUIRED + Character counter like description
// =======================================================

private struct AdminCreateMonthlyChallengeSheet: View {
    let primary: Color
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var criteria: [String] = ["", "", "", ""]

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var showMonthYearPicker = false

    // ✅ Image is REQUIRED now
    @State private var pickedItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil

    @State private var uploading = false
    @State private var errorText: String?
    @State private var showAlert = false
    @State private var alertMsg = ""

    private let titleLimit = 30
    private let descLimit = 500
    private let criteriaLimit = 200

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        Text("Add Monthly Challenge")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(primary)
                            .padding(.top, 8)

                        Text("This is a monthly challenge. You can't add two challenges in the same month.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)

                        // ✅ Image REQUIRED (with asterisk)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text("Challenge Image")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Text("*").foregroundColor(.red)
                            }
                            .padding(.horizontal, 22)
                            
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
                                        VStack(spacing: 8) {
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.system(size: 22, weight: .medium))
                                                .foregroundColor(primary.opacity(0.9))
                                            Text("Upload image (required)")
                                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                                .foregroundColor(.secondary)
                                        }
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
                        }

                        requiredField(label: "Title", value: $title, limit: titleLimit)
                            .onChange(of: title) { _, nv in
                                if nv.count > titleLimit { title = String(nv.prefix(titleLimit)) }
                            }

                        requiredTextEditor(label: "Description", text: $description, placeholder: "Write a short description (max 500)", limit: descLimit)

                        // ✅ Criteria with character counter like description
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text("Evaluation Criteria")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                Text("*")
                                    .foregroundColor(.red)
                            }
                            Text("Exactly 4 criteria. Each one max 200 characters.")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(.secondary)

                            ForEach(0..<4, id: \.self) { i in
                                VStack(spacing: 4) {
                                    HStack {
                                        Text("Criteria \(i+1)")
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        // ✅ Character counter like description
                                        Text("\(criteria[i].count)/\(criteriaLimit)")
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(primary.opacity(0.9))
                                            .frame(width: 8, height: 8)

                                        TextField("Enter criteria...", text: Binding(
                                            get: { criteria[i] },
                                            set: { newVal in
                                                var v = newVal
                                                if v.count > criteriaLimit { v = String(v.prefix(criteriaLimit)) }
                                                criteria[i] = v
                                            }
                                        ))
                                        .textInputAutocapitalization(.sentences)
                                        .autocorrectionDisabled(true)
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background))
                                }
                            }
                        }
                        .padding(.horizontal, 22)

                        VStack(spacing: 10) {
                            monthYearRow(
                                label: "Month / Year",
                                primary: primary,
                                displayed: "\(monthName(selectedMonth)) \(selectedYear)"
                            ) {
                                showMonthYearPicker = true
                            }
                        }
                        .padding(.horizontal, 22)

                        Button {
                            Task { await createMonthlyChallenge() }
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
                        .disabled(uploading)
                        .buttonStyle(.plain)

                        if let errorText {
                            Text(errorText)
                                .foregroundColor(.red)
                                .font(.system(size: 13, design: .rounded))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 22)
                        }

                        Spacer(minLength: 18)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showMonthYearPicker) {
                AdminMonthYearPickerSheet(
                    primary: primary,
                    year: $selectedYear,
                    month: $selectedMonth,
                    minYear: 2025,
                    maxYear: 2035,
                    onDone: { showMonthYearPicker = false }
                )
            }
            .alert("Notice", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMsg)
            }
        }
    }

    private func createMonthlyChallenge() async {
        guard let user = Auth.auth().currentUser else {
            alertMsg = "User not authenticated"
            showAlert = true
            return
        }
        
        uploading = true
        errorText = nil

        do {
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let d = description.trimmingCharacters(in: .whitespacesAndNewlines)

            // ✅ Validate image is required
            guard pickedImage != nil else {
                throw NSError(domain: "validation", code: 0, userInfo: [NSLocalizedDescriptionKey: "Challenge image is required."])
            }

            if t.isEmpty || d.isEmpty {
                throw NSError(domain: "validation", code: 0, userInfo: [NSLocalizedDescriptionKey: "Please fill all required fields."])
            }

            if t.count > titleLimit {
                throw NSError(domain: "validation", code: 0, userInfo: [NSLocalizedDescriptionKey: "Title must be max 30 characters."])
            }

            if d.count > descLimit {
                throw NSError(domain: "validation", code: 0, userInfo: [NSLocalizedDescriptionKey: "Description must be max 500 characters."])
            }

            let cArr = criteria.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if cArr.contains(where: { $0.isEmpty }) {
                throw NSError(domain: "validation", code: 0, userInfo: [NSLocalizedDescriptionKey: "Please fill all 4 criteria."])
            }
            if cArr.contains(where: { $0.count > criteriaLimit }) {
                throw NSError(domain: "validation", code: 0, userInfo: [NSLocalizedDescriptionKey: "Each criteria must be max 200 characters."])
            }

            let ym = String(format: "%04d-%02d", selectedYear, selectedMonth)
            let startAt = firstDayOfMonth(year: selectedYear, month: selectedMonth)
            let endAt = lastDayOfMonth(year: selectedYear, month: selectedMonth)

            let exists = try await monthAlreadyHasChallenge(yearMonth: ym, excludeId: nil)
            if exists {
                await MainActor.run {
                    uploading = false
                    alertMsg = "Only one monthly challenge is allowed per month. This month already has a challenge."
                    showAlert = true
                }
                return
            }

            let imageURL = try await uploadChallengeImage(pickedImage!)

            let data: [String: Any] = [
                "title": t,
                "description": d,
                "criteria": cArr,
                "imageURL": imageURL,
                "yearMonth": ym,
                "startAt": Timestamp(date: startAt),
                "endAt": Timestamp(date: endAt),
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "createdBy": user.uid
            ]
            let docRef = try await Firestore.firestore()
                .collection("challenges")
                .addDocument(data: data)

            // ✨ Send notification ONLY if challenge is Current
            // ✨ Send notification ONLY if challenge is Current (not Upcoming, not Past)
            let challengeId = docRef.documentID
            let challengeMonth = startAt.formatted(.dateTime.month(.wide))
            let now = Date()

            // Check if challenge is Current: started AND not ended
            let isCurrent = now >= startAt && now < endAt

            // Only send if Current (started and not ended)
            if isCurrent {
                Task {
                    do {
                        // Get all players
                        let usersSnapshot = try await Firestore.firestore()
                            .collection("users")
                            .whereField("role", isEqualTo: "player")
                            .getDocuments()
                        
                        // Send notification to each player
                        for userDoc in usersSnapshot.documents {
                            let playerId = userDoc.documentID
                            
                            await NotificationService.sendNewChallengeNotification(
                                userId: playerId,
                                challengeId: challengeId,
                                challengeTitle: t,
                                monthName: challengeMonth
                            )
                        }
                        
                        print("✅ Sent challenge notifications to \(usersSnapshot.documents.count) players")
                    } catch {
                        print("⚠️ Failed to send notifications: \(error.localizedDescription)")
                    }
                }
            } else {
                print("ℹ️ Challenge is Upcoming - notification will be sent automatically when it starts")
            }

            await MainActor.run {
                uploading = false
                onDone()
                dismiss()
            }

        } catch {
            await MainActor.run {
                uploading = false
                errorText = error.localizedDescription
            }
        }
    }

    private func monthAlreadyHasChallenge(yearMonth: String, excludeId: String?) async throws -> Bool {
        let db = Firestore.firestore()
        var q = db.collection("challenges").whereField("yearMonth", isEqualTo: yearMonth)
        let snap = try await q.getDocuments()
        if let excludeId {
            return snap.documents.contains(where: { $0.documentID != excludeId })
        } else {
            return !snap.documents.isEmpty
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

    private func requiredField(label: String, value: Binding<String>, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("*").foregroundColor(.red)
                Spacer()
                // ✅ إضافة عداد الحروف
                Text("\(value.wrappedValue.count)/\(limit)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }

            TextField("", text: value)                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(true)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background))
        }
        .padding(.horizontal, 22)
    }

    private func requiredTextEditor(label: String, text: Binding<String>, placeholder: String, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("*").foregroundColor(.red)
                Spacer()
                Text("\(text.wrappedValue.count)/\(limit)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.gray.opacity(0.6))
                        .padding(.top, 10)
                        .padding(.leading, 6)
                }
                TextEditor(text: text)
                    .frame(height: 110)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background))
                    .scrollContentBackground(.hidden)
                    .onChange(of: text.wrappedValue) { _, nv in
                        if nv.count > limit {
                            text.wrappedValue = String(nv.prefix(limit))
                        }
                    }
            }
        }
        .padding(.horizontal, 22)
    }

    private func monthYearRow(label: String, primary: Color, displayed: String, onTap: @escaping () -> Void) -> some View {
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

    private func monthName(_ m: Int) -> String {
        let df = DateFormatter()
        return df.shortMonthSymbols[(m - 1).clamped(to: 0...11)]
    }

    private func firstDayOfMonth(year: Int, month: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = 1
        return Calendar.current.date(from: c) ?? Date()
    }

    private func lastDayOfMonth(year: Int, month: Int) -> Date {
        let start = firstDayOfMonth(year: year, month: month)
        let range = Calendar.current.range(of: .day, in: .month, for: start) ?? 1..<29
        var c = Calendar.current.dateComponents([.year, .month], from: start)
        c.day = range.count
        return Calendar.current.date(from: c) ?? start
    }
}

// =======================================================
// MARK: - ✅ Edit Challenge Sheet - Same fixes as Create
// =======================================================

private struct AdminEditMonthlyChallengeSheet: View {
    let primary: Color
    let challenge: AdminChallengeItem
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var criteria: [String] = ["", "", "", ""]

    @State private var selectedYear: Int = 2025
    @State private var selectedMonth: Int = 1
    @State private var showMonthYearPicker = false

    @State private var pickedItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil

    @State private var saving = false
    @State private var errorText: String?
    @State private var showAlert = false
    @State private var alertMsg = ""

    private let titleLimit = 30
    private let descLimit = 500
    private let criteriaLimit = 200

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        Text("Edit Monthly Challenge")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(primary)
                            .padding(.top, 8)

                        Text("This is a monthly challenge. You can't add two challenges in the same month.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)

                        // ✅ Image REQUIRED (with asterisk)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text("Challenge Image")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Text("*").foregroundColor(.red)
                            }
                            .padding(.horizontal, 22)
                            
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
                                                RoundedRectangle(cornerRadius: 16)
                                                    .fill(Color(UIColor.systemGray5))
                                                    .frame(height: 140)
                                                    .overlay(Text("Image failed").foregroundColor(.secondary))
                                            }
                                        }
                                    } else {
                                        VStack(spacing: 8) {
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.system(size: 22, weight: .medium))
                                                .foregroundColor(primary.opacity(0.9))
                                            Text("Upload image (required)")
                                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                                .foregroundColor(.secondary)
                                        }
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
                        }

                        requiredField(label: "Title", value: $title, placeholder: "Challenge title (max 30)")
                            .onChange(of: title) { _, nv in
                                if nv.count > titleLimit { title = String(nv.prefix(titleLimit)) }
                            }

                        requiredTextEditor(label: "Description", text: $description, placeholder: "Write a short description (max 500)", limit: descLimit)

                        // ✅ Criteria with character counter
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text("Evaluation Criteria")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Text("*").foregroundColor(.red)
                            }
                            Text("Exactly 4 criteria. Each one max 200 characters.")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(.secondary)

                            ForEach(0..<4, id: \.self) { i in
                                VStack(spacing: 4) {
                                    HStack {
                                        Text("Criteria \(i+1)")
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(criteria[i].count)/\(criteriaLimit)")
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(primary.opacity(0.9))
                                            .frame(width: 8, height: 8)

                                        TextField("Enter criteria...", text: Binding(
                                            get: { criteria[i] },
                                            set: { newVal in
                                                var v = newVal
                                                if v.count > criteriaLimit { v = String(v.prefix(criteriaLimit)) }
                                                criteria[i] = v
                                            }
                                        ))
                                        .textInputAutocapitalization(.sentences)
                                        .autocorrectionDisabled(true)
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background))
                                }
                            }
                        }
                        .padding(.horizontal, 22)

                        VStack(spacing: 10) {
                            monthYearRow(
                                label: "Month / Year",
                                primary: primary,
                                displayed: "\(monthName(selectedMonth)) \(selectedYear)"
                            ) { showMonthYearPicker = true }
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
                        .disabled(saving)
                        .buttonStyle(.plain)

                        if let errorText {
                            Text(errorText)
                                .foregroundColor(.red)
                                .font(.system(size: 13, design: .rounded))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 22)
                        }

                        Spacer(minLength: 18)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showMonthYearPicker) {
                AdminMonthYearPickerSheet(
                    primary: primary,
                    year: $selectedYear,
                    month: $selectedMonth,
                    minYear: 2025,
                    maxYear: 2035,
                    onDone: { showMonthYearPicker = false }
                )
            }
            .alert("Notice", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMsg)
            }
            .onAppear { preload() }
        }
    }

    private func preload() {
        title = challenge.title
        description = challenge.description

        var c = challenge.criteria
        if c.count < 4 { c.append(contentsOf: Array(repeating: "", count: 4 - c.count)) }
        if c.count > 4 { c = Array(c.prefix(4)) }
        criteria = c

        let parts = challenge.yearMonth.split(separator: "-").map(String.init)
        if parts.count == 2 {
            selectedYear = Int(parts[0]) ?? Calendar.current.component(.year, from: Date())
            selectedMonth = Int(parts[1]) ?? Calendar.current.component(.month, from: Date())
        } else {
            selectedYear = Calendar.current.component(.year, from: Date())
            selectedMonth = Calendar.current.component(.month, from: Date())
        }
    }

    private func save() async {
        await MainActor.run {
            saving = true
            errorText = nil
        }

        do {
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let d = description.trimmingCharacters(in: .whitespacesAndNewlines)

            if t.isEmpty || d.isEmpty {
                throw NSError(domain: "validation", code: 0, userInfo: [NSLocalizedDescriptionKey: "Please fill all required fields."])
            }
            if t.count > titleLimit {
                throw NSError(domain: "validation", code: 0, userInfo: [NSLocalizedDescriptionKey: "Title must be max 30 characters."])
            }
            if d.count > descLimit {
                throw NSError(domain: "validation", code: 0, userInfo: [NSLocalizedDescriptionKey: "Description must be max 500 characters."])
            }

            let cArr = criteria.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if cArr.contains(where: { $0.isEmpty }) {
                throw NSError(domain: "validation", code: 0, userInfo: [NSLocalizedDescriptionKey: "Please fill all 4 criteria."])
            }
            if cArr.contains(where: { $0.count > criteriaLimit }) {
                throw NSError(domain: "validation", code: 0, userInfo: [NSLocalizedDescriptionKey: "Each criteria must be max 200 characters."])
            }

            let ym = String(format: "%04d-%02d", selectedYear, selectedMonth)
            let startAt = firstDayOfMonth(year: selectedYear, month: selectedMonth)
            let endAt = lastDayOfMonth(year: selectedYear, month: selectedMonth)

            let exists = try await monthAlreadyHasChallenge(yearMonth: ym, excludeId: challenge.id)
            if exists {
                await MainActor.run {
                    saving = false
                    alertMsg = "Only one monthly challenge is allowed per month. This month already has a challenge."
                    showAlert = true
                }
                return
            }

            var update: [String: Any] = [
                "title": t,
                "description": d,
                "criteria": cArr,
                "yearMonth": ym,
                "startAt": Timestamp(date: startAt),
                "endAt": Timestamp(date: endAt),
                "updatedAt": FieldValue.serverTimestamp()
            ]

            if let pickedImage {
                let newURL = try await uploadChallengeImage(pickedImage)
                update["imageURL"] = newURL
            }

            try await Firestore.firestore()
                .collection("challenges")
                .document(challenge.id)
                .setData(update, merge: true)

            await MainActor.run {
                saving = false
                onDone()
                dismiss()
            }

        } catch {
            await MainActor.run {
                saving = false
                errorText = error.localizedDescription
            }
        }
    }

    private func monthAlreadyHasChallenge(yearMonth: String, excludeId: String?) async throws -> Bool {
        let db = Firestore.firestore()
        let snap = try await db.collection("challenges")
            .whereField("yearMonth", isEqualTo: yearMonth)
            .getDocuments()

        if let excludeId {
            return snap.documents.contains(where: { $0.documentID != excludeId })
        } else {
            return !snap.documents.isEmpty
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

    private func requiredField(label: String, value: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("*").foregroundColor(.red)
            }
            TextField(placeholder, text: value)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(true)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background))
        }
        .padding(.horizontal, 22)
    }

    private func requiredTextEditor(label: String, text: Binding<String>, placeholder: String, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("*").foregroundColor(.red)
                Spacer()
                Text("\(text.wrappedValue.count)/\(limit)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.gray.opacity(0.6))
                        .padding(.top, 10)
                        .padding(.leading, 6)
                }
                TextEditor(text: text)
                    .frame(height: 110)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background))
                    .scrollContentBackground(.hidden)
                    .onChange(of: text.wrappedValue) { _, nv in
                        if nv.count > limit {
                            text.wrappedValue = String(nv.prefix(limit))
                        }
                    }
            }
        }
        .padding(.horizontal, 22)
    }

    private func monthYearRow(label: String, primary: Color, displayed: String, onTap: @escaping () -> Void) -> some View {
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

    private func monthName(_ m: Int) -> String {
        let df = DateFormatter()
        return df.shortMonthSymbols[(m - 1).clamped(to: 0...11)]
    }

    private func firstDayOfMonth(year: Int, month: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = 1
        return Calendar.current.date(from: c) ?? Date()
    }

    private func lastDayOfMonth(year: Int, month: Int) -> Date {
        let start = firstDayOfMonth(year: year, month: month)
        let range = Calendar.current.range(of: .day, in: .month, for: start) ?? 1..<29
        var c = Calendar.current.dateComponents([.year, .month], from: start)
        c.day = range.count
        return Calendar.current.date(from: c) ?? start
    }
}

// =======================================================
// MARK: - Month/Year Picker
// =======================================================

private struct AdminMonthYearPickerSheet: View {
    let primary: Color
    @Binding var year: Int
    @Binding var month: Int

    let minYear: Int
    let maxYear: Int
    let onDone: () -> Void

    private let months: [(Int, String)] = [
        (1,"Jan"),(2,"Feb"),(3,"Mar"),(4,"Apr"),(5,"May"),(6,"Jun"),
        (7,"Jul"),(8,"Aug"),(9,"Sep"),(10,"Oct"),(11,"Nov"),(12,"Dec")
    ]

    var body: some View {
        VStack(spacing: 14) {
            Text("Select Month & Year")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(primary)
                .padding(.top, 10)

            HStack(spacing: 0) {
                Picker("Month", selection: $month) {
                    ForEach(months, id: \.0) { m in
                        Text(m.1).tag(m.0)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("Year", selection: $year) {
                    ForEach(minYear...maxYear, id: \.self) { y in
                        Text("\(y)").tag(y)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 180)

            Button {
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
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .background(BrandColors.background.ignoresSafeArea())
    }
}

// =======================================================
// MARK: - Confirm Popup
// =======================================================

private struct AdminConfirmPopup: View {
    let title: String
    let message: String
    let primary: Color

    let isLoading: Bool
    let errorText: String?

    let cancelTitle: String
    let confirmTitle: String
    let confirmColor: Color

    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        GeometryReader { geo in
            VStack {
                Spacer()

                VStack(spacing: 16) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)

                    if isLoading {
                        ProgressView().tint(primary)
                    }

                    if let errorText, !errorText.isEmpty {
                        Text(errorText)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                    }

                    HStack(spacing: 14) {
                        Button(cancelTitle) { onCancel() }
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(BrandColors.darkGray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(BrandColors.lightGray)
                            .cornerRadius(12)

                        Button(confirmTitle) { onConfirm() }
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(confirmColor)
                            .cornerRadius(12)
                            .disabled(isLoading)
                    }
                }
                .padding(24)
                .frame(width: min(340, geo.size.width - 40))
                .background(BrandColors.background)
                .cornerRadius(20)
                .shadow(radius: 12)

                Spacer()
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// =======================================================
// MARK: - Helper
// =======================================================

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
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
    @State private var showNotifications = false
    @State private var showEditProfile = false
    @State private var refreshTrigger = false
    @State private var profileImageURL: String?
    
    @State private var isLoadingProfile = true
    
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
                        if isLoadingProfile {
                            ProgressView()
                                .frame(width: 100, height: 100)
                        } else {
                            AsyncImage(url: profileImageURL.flatMap(URL.init)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                case .failure(_), .empty:
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .foregroundColor(primary.opacity(0.6))
                                @unknown default:
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .foregroundColor(primary.opacity(0.6))
                                }
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                        }
                        
                        if isLoadingProfile {
                            Text("Loading...")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(primary.opacity(0.5))
                        } else {
                            Text(adminName)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(primary)
                        }
                        
                        Text(currentEmail)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.secondary)
                            .opacity(isLoadingProfile ? 0.5 : 1.0)
                    }
                    .padding(.bottom, 30)
                    
                    // Settings List
                    VStack(spacing: 0) {
                        NavigationLink {
                            AdminEditProfileView(adminName: adminName, adminEmail: adminEmail)
                        } label: {
                            settingsRow(icon: "person.circle", title: "Edit Profile",
                                        iconColor: primary, showChevron: true, showDivider: true)
                        }
                        
                        NavigationLink {
                            AdminChangeEmailView()
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNotifications = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(primary)
                            
                            // Unread badge
                            if NotificationService.shared.unreadCount > 0 {
                                ZStack {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 18, height: 18)
                                    
                                    Text("\(min(NotificationService.shared.unreadCount, 9))")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                .offset(x: 8, y: -8)
                            }
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showNotifications) {
                NotificationsView()
                    .environmentObject(session)
            }
            .onAppear {
                loadAdminData()
                
                // Start listening to notifications
                if let adminId = Auth.auth().currentUser?.uid {
                    NotificationService.shared.startListening(for: adminId)
                }
            }
            .onChange(of: refreshTrigger) { _ in
                loadAdminData()
            }
            .onReceive(NotificationCenter.default.publisher(for: .profileUpdated)) { _ in
                loadAdminData()
            }
            .onDisappear {
                NotificationService.shared.stopListening()
            }
        }
    }
    
    private func loadAdminData() {
        isLoadingProfile = true  // Add this at the start
        
        Task {
            // Reload user to get latest data from Auth
            try? await Auth.auth().currentUser?.reload()
            
            guard let user = Auth.auth().currentUser else {
                await MainActor.run { isLoadingProfile = false }
                return
            }
            
            await MainActor.run {
                adminEmail = user.email ?? ""
                
                // Load admin name from display name
                if let displayName = user.displayName, !displayName.isEmpty {
                    adminName = displayName
                }
            }
            
            // Load additional data from Firestore
            do {
                let doc = try await Firestore.firestore()
                    .collection("users")
                    .document(user.uid)
                    .getDocument()
                
                if let data = doc.data() {
                    let firestoreName = [
                        data["firstName"] as? String ?? "",
                        data["lastName"] as? String ?? ""
                    ].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    
                    let urlString = data["profilePic"] as? String
                    
                    await MainActor.run {
                        // Use Firestore name if display name is empty
                        if adminName.isEmpty && !firestoreName.isEmpty {
                            adminName = firestoreName
                        }
                        // Set to "Admin" only if still empty
                        if adminName.isEmpty {
                            adminName = "Admin"
                        }
                        profileImageURL = urlString
                        isLoadingProfile = false  // Add this
                    }
                } else {
                    await MainActor.run {
                        if adminName.isEmpty {
                            adminName = "Admin"
                        }
                        isLoadingProfile = false  // Add this
                    }
                }
            } catch {
                print("Error loading admin profile: \(error)")
                await MainActor.run {
                    if adminName.isEmpty {
                        adminName = "Admin"
                    }
                    isLoadingProfile = false  // Add this
                }
            }
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
    var onConfirm: (String, String) -> Void
    @State private var rejectionCategory: String = "other"
    
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
                
                HStack(spacing: 4) {
                    Text("Please provide a reason")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                    Text("for rejecting \(coachName)'s application.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                    Text("*")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            }
            
            // Category Selection
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("Category")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    Text("*")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                }
                
                Menu {
                    Button {
                        rejectionCategory = "insufficient_docs"
                    } label: {
                        HStack {
                            Text("Insufficient Documentation")
                            Spacer()
                            if rejectionCategory == "insufficient_docs" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button {
                        rejectionCategory = "other"
                    } label: {
                        HStack {
                            Text("Other")
                            Spacer()
                            if rejectionCategory == "other" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(categoryDisplayName)
                            .font(.system(size: 15, design: .rounded))
                            .foregroundColor(primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(BrandColors.background)
                            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                    )
                }
            }
            .padding(.horizontal)
            
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
                
                Button(action: {
                    onConfirm(rejectionCategory, rejectionReason)
                }) {
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
    
    private var categoryDisplayName: String {
        switch rejectionCategory {
        case "insufficient_docs":
            return "Insufficient Documentation"
        default:
            return "Other"
        }
    }
    
}

// =======================================================
// MARK: - Admin Edit Profile View
// =======================================================

struct AdminEditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    
    let adminEmail: String
    private let primary = BrandColors.darkTeal
    private let db = Firestore.firestore()
    
    @State private var name: String
    @State private var profileImage: UIImage?
    @State private var originalProfileImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var alertIsError = false
    
    init(adminName: String, adminEmail: String) {
        self.adminEmail = adminEmail
        _name = State(initialValue: adminName)
    }
    
    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    Text("Edit Profile")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                    
                    // Profile Picture Section
                    VStack {
                        Image(uiImage: profileImage ?? UIImage(systemName: "person.circle.fill")!)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .foregroundColor(.gray.opacity(0.5))
                        
                        HStack(spacing: 20) {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                                Text("Change Picture")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(primary)
                            }
                            
                            if profileImage != nil {
                                Button(role: .destructive) {
                                    withAnimation {
                                        self.profileImage = nil
                                        self.selectedPhotoItem = nil
                                    }
                                } label: {
                                    Text("Remove Picture")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                    
                    // Name Field
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Name")
                        
                        roundedField {
                            TextField("", text: $name)
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(primary)
                                .tint(primary)
                                .textInputAutocapitalization(.words)
                        }
                    }
                    
                    // Save Button
                    Button {
                        Task { await saveProfile() }
                    } label: {
                        HStack {
                            Text("Save Changes")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                            if isSaving { ProgressView().colorInvert().scaleEffect(0.9) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(primary)
                        .clipShape(Capsule())
                    }
                    .disabled(isSaving || name.isEmpty)
                    .opacity((isSaving || name.isEmpty) ? 0.5 : 1.0)
                    .padding(.top, 20)
                    
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
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
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let newImage = UIImage(data: data) {
                    await MainActor.run {
                        self.profileImage = newImage
                    }
                }
            }
        }
        .task {
            await loadCurrentProfile()
        }
    }
    
    private func loadCurrentProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            if let data = doc.data() {
                if let urlString = data["profilePic"] as? String, !urlString.isEmpty, let url = URL(string: urlString) {
                    let (imageData, _) = try await URLSession.shared.data(from: url)
                    if let image = UIImage(data: imageData) {
                        await MainActor.run {
                            self.profileImage = image
                            self.originalProfileImage = image
                        }
                    }
                }
            }
        } catch {
            print("Error loading profile: \(error)")
        }
    }
    
    private func saveProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSaving = true
        
        do {
            var updates: [String: Any] = [:]
            
            // Update display name in Auth
            if let user = Auth.auth().currentUser {
                let changeRequest = user.createProfileChangeRequest()
                changeRequest.displayName = name
                try await changeRequest.commitChanges()
            }
            
            // Update name in Firestore
            let parts = name.split(separator: " ").map(String.init)
            updates["firstName"] = parts.first ?? name
            updates["lastName"] = parts.count > 1 ? parts[1...].joined(separator: " ") : ""
            
            // Handle profile picture (same logic as EditCoachProfileView)
            let oldImage = originalProfileImage
            if let newImage = profileImage, newImage != oldImage {
                // New image selected or image changed
                if let imageData = newImage.jpegData(compressionQuality: 0.8) {
                    let fileName = "\(UUID().uuidString).jpg"
                    let ref = Storage.storage().reference().child("profile/\(uid)/\(fileName)")
                    
                    let metadata = StorageMetadata()
                    metadata.contentType = "image/jpeg"
                    
                    _ = try await ref.putDataAsync(imageData, metadata: metadata)
                    let url = try await ref.downloadURL()
                    updates["profilePic"] = url.absoluteString
                }
            } else if profileImage == nil, oldImage != nil {
                // Image was removed
                updates["profilePic"] = ""
            }
            
            updates["updatedAt"] = FieldValue.serverTimestamp()
            
            try await db.collection("users").document(uid).setData(updates, merge: true)
            
            await MainActor.run {
                isSaving = false
                alertMessage = "Profile updated successfully!"
                alertIsError = false
                showAlert = true
                
                // Post notification to refresh admin profile
                NotificationCenter.default.post(name: .profileUpdated, object: nil)
            }
        } catch {
            await MainActor.run {
                isSaving = false
                alertMessage = "Failed to update profile: \(error.localizedDescription)"
                alertIsError = true
                showAlert = true
            }
        }
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
