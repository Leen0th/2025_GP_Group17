import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// =======================================================
// MARK: - Models
// =======================================================

struct ReportedItem: Identifiable {
    let id: String
    let itemType: String               // "Discovery Post", "Account", "Comment", "Challenge Post"
    let contentPreview: String
    let reasonTitle: String
    let reasonDescription: String
    let reporterId: String
    let reportedItemRef: DocumentReference?
    let timestamp: Date?
    let status: String
    let actionTaken: String?
}

struct ContentReportGroup: Identifiable {
    let id: String
    let itemType: String
    let contentPreview: String
    let reportedItemRef: DocumentReference?
    let reports: [ReportedItem]

    var reportCount: Int { reports.count }

    var reasonSummary: [(title: String, count: Int)] {
        let counts = Dictionary(grouping: reports, by: \.reasonTitle).mapValues { $0.count }
        return counts.sorted { $0.value > $1.value }.map { (title: $0.key, count: $0.value) }
    }

    var latestTimestamp: Date? {
        reports.compactMap(\.timestamp).max()
    }

    var isFullyResolved: Bool {
        reports.allSatisfy { $0.status != "pending" }
    }

    var groupActionTaken: String? {
        reports.compactMap(\.actionTaken).filter { $0 != "dismissed" }.first
            ?? reports.compactMap(\.actionTaken).first
    }
}

// =======================================================
// MARK: - ViewModel
// =======================================================

@MainActor
final class AdminReportedContentViewModel: ObservableObject {

    @Published var allReports: [ReportedItem] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var isActioning = false
    @Published var actionError: String?

    @Published var typeFilter: String = "all"
    @Published var sortOrder: SortOrder = .newest

    enum SortOrder { case newest, oldest, mostReported }

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    init() { startListening() }
    deinit { listener?.remove() }

    func startListening() {
        isLoading = true
        listener?.remove()
        listener = db.collection("reports")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error = error {
                    self.errorText = error.localizedDescription
                    self.isLoading = false
                    return
                }
                guard let docs = snapshot?.documents else { self.isLoading = false; return }

                self.allReports = docs.compactMap { doc in
                    let d = doc.data()
                    let rawType = d["itemType"] as? String ?? "Unknown"
                    // Normalise legacy values
                    let itemType: String
                    switch rawType {
                    case "Post":    itemType = "Discovery Post"
                    case "Profile": itemType = "Account"
                    default:        itemType = rawType
                    }
                    return ReportedItem(
                        id: doc.documentID,
                        itemType: itemType,
                        contentPreview: d["contentPreview"] as? String ?? "",
                        reasonTitle: d["reasonTitle"] as? String ?? "",
                        reasonDescription: d["reasonDescription"] as? String ?? "",
                        reporterId: (d["reporterId"] as? DocumentReference)?.documentID ?? "",
                        reportedItemRef: d["reportedItem"] as? DocumentReference,
                        timestamp: (d["timestamp"] as? Timestamp)?.dateValue(),
                        status: d["status"] as? String ?? "pending",
                        actionTaken: d["actionTaken"] as? String
                    )
                }
                self.isLoading = false
            }
    }

    func groups(pending: Bool, search: String) -> [ContentReportGroup] {
        let statusFiltered = allReports.filter { pending ? $0.status == "pending" : $0.status != "pending" }

        var buckets: [String: [ReportedItem]] = [:]
        for r in statusFiltered {
            let key = r.reportedItemRef?.path ?? r.id
            buckets[key, default: []].append(r)
        }

        var result: [ContentReportGroup] = buckets.map { key, items in
            let rep = items.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }[0]
            return ContentReportGroup(
                id: key, itemType: rep.itemType, contentPreview: rep.contentPreview,
                reportedItemRef: rep.reportedItemRef, reports: items
            )
        }

        if typeFilter != "all" { result = result.filter { $0.itemType == typeFilter } }

        let s = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !s.isEmpty {
            result = result.filter {
                $0.contentPreview.lowercased().contains(s) ||
                $0.itemType.lowercased().contains(s) ||
                $0.reports.contains { $0.reasonTitle.lowercased().contains(s) }
            }
        }

        switch sortOrder {
        case .newest:       return result.sorted { ($0.latestTimestamp ?? .distantPast) > ($1.latestTimestamp ?? .distantPast) }
        case .oldest:       return result.sorted { ($0.latestTimestamp ?? .distantPast) < ($1.latestTimestamp ?? .distantPast) }
        case .mostReported: return result.sorted { $0.reportCount > $1.reportCount }
        }
    }

    // MARK: - Actions

    func dismissGroup(_ group: ContentReportGroup) async {
        for report in group.reports {
            await updateReportStatus(reportId: report.id, status: "dismissed", actionTaken: "dismissed")
        }
    }

    func deleteContent(group: ContentReportGroup) async {
        isActioning = true
        defer { isActioning = false }
        guard let ref = group.reportedItemRef else { actionError = "Could not locate content reference."; return }
        do {
            try await ref.delete()
            for report in group.reports {
                await updateReportStatus(reportId: report.id, status: "resolved", actionTaken: "deleted")
            }
        } catch { actionError = "Failed to delete content: \(error.localizedDescription)" }
    }

    func deactivateAccount(group: ContentReportGroup, reason: String) async {
        isActioning = true
        defer { isActioning = false }
        do {
            let uid = try await resolveAuthorUID(group: group)
            try await db.collection("users").document(uid).updateData([
                "isActive": false, "deactivationReason": reason
            ])
            for report in group.reports {
                await updateReportStatus(reportId: report.id, status: "resolved", actionTaken: "deactivated")
            }
        } catch { actionError = "Failed to deactivate account: \(error.localizedDescription)" }
    }

    func warnUser(group: ContentReportGroup, message: String) async {
        isActioning = true
        defer { isActioning = false }
        do {
            let uid = try await resolveAuthorUID(group: group)
            try await db.collection("users").document(uid).collection("notifications").addDocument(data: [
                "type": "warning", "message": message,
                "relatedReportId": group.reports[0].id,
                "timestamp": FieldValue.serverTimestamp(), "isRead": false
            ])
            for report in group.reports {
                await updateReportStatus(reportId: report.id, status: "resolved", actionTaken: "warned")
            }
        } catch { actionError = "Failed to send warning: \(error.localizedDescription)" }
    }

    func resolveAuthorUID(group: ContentReportGroup) async throws -> String {
        if group.itemType == "Account", let uid = group.reportedItemRef?.documentID { return uid }
        guard let ref = group.reportedItemRef else {
            throw NSError(domain: "AdminReport", code: 0, userInfo: [NSLocalizedDescriptionKey: "No item reference."])
        }
        let doc = try await ref.getDocument()
        if let uid = doc.data()?["authorUid"] as? String { return uid }
        if let uid = doc.data()?["userId"] as? String { return uid }
        throw NSError(domain: "AdminReport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find author UID."])
    }

    private func updateReportStatus(reportId: String, status: String, actionTaken: String) async {
        do {
            try await db.collection("reports").document(reportId).updateData([
                "status": status, "actionTaken": actionTaken,
                "resolvedAt": FieldValue.serverTimestamp(),
                "resolvedBy": Auth.auth().currentUser?.uid ?? "admin"
            ])
        } catch { print("Failed to update report \(reportId): \(error)") }
    }
}

// =======================================================
// MARK: - Main View
// =======================================================

struct AdminReportedContentView: View {
    private let primary = BrandColors.darkTeal
    @StateObject private var vm = AdminReportedContentViewModel()
    @EnvironmentObject var session: AppSession

    enum ReportTab: String, CaseIterable {
        case pending = "Needs Review"
        case resolved = "Resolved"
    }

    @State private var selectedTab: ReportTab = .pending
    @State private var searchText = ""
    @State private var selectedGroup: ContentReportGroup? = nil
    @State private var navigateToPost: DocumentReference? = nil
    @State private var navigateToUID: String? = nil
    @State private var navigateToCoachUID: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                VStack(spacing: 0) {
                    toolBar.padding(.top, 8).padding(.bottom, 12)
                    tabBar
                    Divider()
                    contentArea
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: Binding(
                get: { navigateToPost != nil }, set: { if !$0 { navigateToPost = nil } }
            )) {
                if let ref = navigateToPost {
                    ReportedPostView(postRef: ref).environmentObject(session)
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { navigateToUID != nil }, set: { if !$0 { navigateToUID = nil } }
            )) {
                if let uid = navigateToUID {
                    PlayerProfileContentView(userID: uid, isAdminViewing: true).environmentObject(session)
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { navigateToCoachUID != nil }, set: { if !$0 { navigateToCoachUID = nil } }
            )) {
                if let uid = navigateToCoachUID {
                    CoachProfileContentView(userID: uid, isAdminViewing: true).environmentObject(session)
                }
            }
            .sheet(item: $selectedGroup) { group in
                GroupDetailSheet(
                    group: group, vm: vm,
                    onViewPost: { ref in navigateToPost = ref },
                    onViewProfile: { uid in
                        Task {
                            let doc = try? await Firestore.firestore().collection("users").document(uid).getDocument()
                            let role = doc?.data()?["role"] as? String ?? "player"
                            if role == "coach" { navigateToCoachUID = uid } else { navigateToUID = uid }
                        }
                    }
                )
                .environmentObject(session)
            }
            .alert("Action Failed", isPresented: Binding(
                get: { vm.actionError != nil }, set: { if !$0 { vm.actionError = nil } }
            )) {
                Button("OK", role: .cancel) { vm.actionError = nil }
            } message: { Text(vm.actionError ?? "") }
        }
    }

    // MARK: Tool Bar
    private var toolBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search reports...", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(BrandColors.background)
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
                )

                // Type filter icon
                Menu {
                    Button { vm.typeFilter = "all" } label: {
                        Label("All Types", systemImage: vm.typeFilter == "all" ? "checkmark" : "")
                    }
                    Button { vm.typeFilter = "Discovery Post" } label: {
                        Label("Discovery Post", systemImage: vm.typeFilter == "Discovery Post" ? "checkmark" : "")
                    }
                    Button { vm.typeFilter = "Challenge Post" } label: {
                        Label("Challenge Post", systemImage: vm.typeFilter == "Challenge Post" ? "checkmark" : "")
                    }
                    Button { vm.typeFilter = "Account" } label: {
                        Label("Account", systemImage: vm.typeFilter == "Account" ? "checkmark" : "")
                    }
                    Button { vm.typeFilter = "Comment" } label: {
                        Label("Comment", systemImage: vm.typeFilter == "Comment" ? "checkmark" : "")
                    }
                } label: {
                    Image(systemName: vm.typeFilter == "all"
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(vm.typeFilter != "all" ? primary : .secondary)
                        .padding(8)
                }

                // Sort capsule
                Menu {
                    Picker("Sort", selection: $vm.sortOrder) {
                        Text("Newest first").tag(AdminReportedContentViewModel.SortOrder.newest)
                        Text("Oldest first").tag(AdminReportedContentViewModel.SortOrder.oldest)
                        Text("Most reported").tag(AdminReportedContentViewModel.SortOrder.mostReported)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .medium))
                        Text(vm.sortOrder == .newest ? "Newest" : vm.sortOrder == .oldest ? "Oldest" : "Most Reported")
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
    }

    // MARK: Tab Bar
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ReportTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
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
    }

    // MARK: Content Area
    @ViewBuilder
    private var contentArea: some View {
        if vm.isLoading {
            Spacer(); ProgressView().tint(primary); Spacer()
        } else if let err = vm.errorText {
            Spacer()
            Text(err).foregroundColor(.red).font(.system(size: 13, design: .rounded))
                .multilineTextAlignment(.center).padding(.horizontal, 20)
            Spacer()
        } else {
            let isPending = selectedTab == .pending
            let displayed = vm.groups(pending: isPending, search: searchText)

            if displayed.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: isPending ? "checkmark.shield" : "tray")
                        .font(.system(size: 36)).foregroundColor(.secondary.opacity(0.4))
                    Text(emptyMessage(isPending))
                        .foregroundColor(.secondary).font(.system(size: 14, design: .rounded))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(displayed) { group in
                            ContentGroupCard(group: group).onTapGesture { selectedGroup = group }
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 110)
                }
            }
        }
    }

    private func emptyMessage(_ isPending: Bool) -> String {
        if !searchText.isEmpty { return "No reports match your search." }
        return isPending ? "No pending reports. All clear!" : "No resolved reports yet."
    }
}

// =======================================================
// MARK: - Content Group Card
// =======================================================

struct ContentGroupCard: View {
    let group: ContentReportGroup
    private let primary = BrandColors.darkTeal

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            // ── Left: title (top) + timestamp (bottom) ──
            VStack(alignment: .leading, spacing: 6) {
                Text(group.contentPreview.isEmpty ? "(No preview available)" : group.contentPreview)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(primary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                if let ts = group.latestTimestamp {
                    Text(ts.relativeString)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

            // ── Right: type pill (top) + count (bottom) ──
            VStack(alignment: .trailing, spacing: 6) {
                typePill(group.itemType)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(group.reportCount >= 3 ? .red : .orange)
                    Text(group.reportCount == 1 ? "1 report" : "\(group.reportCount) reports")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(group.reportCount >= 3 ? .red : .orange)
                }
            }
        }
        .frame(minHeight: 54)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(BrandColors.background)
                .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
        )
    }
}

// =======================================================
// MARK: - Group Detail Sheet
// =======================================================

struct GroupDetailSheet: View {
    let group: ContentReportGroup
    @ObservedObject var vm: AdminReportedContentViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AppSession

    var onViewPost: (DocumentReference) -> Void
    var onViewProfile: (String) -> Void

    @State private var expandedReportID: String? = nil
    @State private var showDeactivateSheet = false
    @State private var showDeleteConfirm = false
    @State private var showWarnCompose = false
    @State private var deactivateReason = ""
    @State private var isDeactivating = false
    @State private var warnMessage = ""
    @State private var commenterUID: String? = nil
    @State private var commenterName: String = ""

    private let primary = BrandColors.darkTeal

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        contentInfoCard
                        reportsSection
                        if !group.isFullyResolved { actionButtons } else { resolvedBanner }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20).padding(.top, 16)
                }
            }
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }.foregroundColor(primary)
                }
            }
            .alert("Delete Content", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Task { await vm.deleteContent(group: group); dismiss() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the reported \(group.itemType.lowercased()). This cannot be undone.")
            }
            .sheet(isPresented: $showWarnCompose) { warnComposeSheet }
            .sheet(isPresented: $showDeactivateSheet) {
                DeactivationReasonSheet(
                    userName: commenterName.isEmpty ? "User" : commenterName,
                    deactivationReason: $deactivateReason,
                    isProcessing: $isDeactivating,
                    onCancel: {
                        showDeactivateSheet = false
                        deactivateReason = ""
                    },
                    onConfirm: { reason in
                        isDeactivating = true
                        Task {
                            await vm.deactivateAccount(group: group, reason: reason)
                            isDeactivating = false
                            showDeactivateSheet = false
                            deactivateReason = ""
                            dismiss()
                        }
                    }
                )
            }
            .overlay {
                if vm.isActioning {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("Processing...").padding(24).background(BrandColors.background).cornerRadius(16)
                }
            }
        }
        .tint(primary)
        .task {
            // Load commenter name (used for Comment type + deactivation sheet username)
            let refToLoad: DocumentReference?
            if group.itemType == "Comment" {
                refToLoad = group.reportedItemRef
            } else if group.itemType == "Account" {
                refToLoad = nil
                // For account type, load directly from reportedItemRef documentID
                if let uid = group.reportedItemRef?.documentID {
                    do {
                        let userDoc = try await Firestore.firestore().collection("users").document(uid).getDocument()
                        let first = userDoc.data()?["firstName"] as? String ?? ""
                        let last  = userDoc.data()?["lastName"]  as? String ?? ""
                        let full  = [first, last].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                        commenterUID = uid
                        commenterName = full.isEmpty ? "User" : full
                    } catch {}
                }
                return
            } else {
                refToLoad = nil
            }

            guard let ref = refToLoad else { return }
            do {
                let doc = try await ref.getDocument()
                let uid = doc.data()?["userId"] as? String ?? ""
                commenterUID = uid.isEmpty ? nil : uid
                if !uid.isEmpty {
                    let userDoc = try await Firestore.firestore().collection("users").document(uid).getDocument()
                    let first = userDoc.data()?["firstName"] as? String ?? ""
                    let last  = userDoc.data()?["lastName"]  as? String ?? ""
                    let full  = [first, last].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    commenterName = full.isEmpty ? "Unknown User" : full
                }
            } catch { print("Failed to load user info: \(error)") }
        }
    }

    // MARK: Content Info Card
    private var contentInfoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                typePill(group.itemType)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "flag.fill").font(.system(size: 12))
                    Text(group.reportCount == 1 ? "1 report" : "\(group.reportCount) reports")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundColor(group.reportCount >= 3 ? .red : .orange)
            }

            Divider()

            // View post / view account button
            if (group.itemType == "Discovery Post" || group.itemType == "Challenge Post" || group.itemType == "Account"),
               let ref = group.reportedItemRef {
                Button {
                    dismiss()
                    if group.itemType == "Account" { onViewProfile(ref.documentID) }
                    else { onViewPost(ref) }
                } label: {
                    HStack {
                        Image(systemName: group.itemType == "Account" ? "person.fill" : "play.rectangle.fill")
                        Text(group.itemType == "Account" ? "View Account" : "View Post")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary)
                    }
                    .foregroundColor(primary).padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }

            // Comment author + text
            if group.itemType == "Comment" {
                if let uid = commenterUID, !commenterName.isEmpty {
                    Button {
                        dismiss(); onViewProfile(uid)
                    } label: {
                        HStack {
                            Image(systemName: "person.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Comment by").font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                                Text(commenterName).font(.system(size: 15, weight: .semibold, design: .rounded))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                        .foregroundColor(primary).padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("Comment")
                    Text(group.contentPreview.isEmpty ? "(No preview)" : group.contentPreview)
                        .font(.system(size: 15, design: .rounded))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(BrandColors.lightGray.opacity(0.6)).cornerRadius(10)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(BrandColors.background)
            .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3))
    }

    // MARK: Reports Section
    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if group.reportCount > 1 {
                sectionLabel("All Reports (\(group.reportCount))")
            } else {
                sectionLabel("Report")
            }

            VStack(spacing: 8) {
                ForEach(group.reports.sorted {
                    ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
                }) { report in
                    reportRow(report)
                }
            }
        }
    }

    private func reportRow(_ report: ReportedItem) -> some View {
        let isExpanded = expandedReportID == report.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedReportID = isExpanded ? nil : report.id
                }
            } label: {
                HStack(spacing: 12) {
                    Circle().fill(reasonDotColor(report.reasonTitle)).frame(width: 8, height: 8)
                    Text(report.reasonTitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded)).foregroundColor(.primary)
                    Spacer()
                    if let ts = report.timestamp {
                        Text(ts.relativeString).font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Divider().padding(.horizontal, 14)
                    Text(report.reasonDescription)
                        .font(.system(size: 13, design: .rounded)).foregroundColor(.secondary)
                        .padding(.horizontal, 14).padding(.bottom, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(BrandColors.background)
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2))
    }

    private func reasonDotColor(_ title: String) -> Color {
        switch title {
        case "Hate Speech or Bullying":      return .red
        case "Abusive Content":              return .red
        case "Impersonation":                return .orange
        case "Spam or Scam":                 return .orange
        case "Inappropriate Content":        return .purple
        case "Video doesn't belong to user": return .yellow
        case "Video isn't about football":   return BrandColors.teal
        default:                             return .secondary
        }
    }

    // MARK: Action Buttons — context-aware per type
    private var actionButtons: some View {
        VStack(spacing: 12) {
            sectionLabel("Take Action")

            if group.reportCount > 1 {
                Text("Action will be applied to all \(group.reportCount) reports for this content.")
                    .font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
            }

            switch group.itemType {
            case "Account":
                // Dismiss → Warn → Deactivate
                actionButton(icon: "checkmark.circle", title: "Dismiss Report",
                             subtitle: "No action needed", color: BrandColors.actionGreen) {
                    Task { await vm.dismissGroup(group); dismiss() }
                }
                actionButton(icon: "bell.badge", title: "Send Warning",
                             subtitle: "Notify the user about their account", color: primary) {
                    warnMessage = defaultWarnMessage; showWarnCompose = true
                }
                actionButton(icon: "person.fill.xmark", title: "Deactivate Account",
                             subtitle: "Prevent user from posting or interacting", color: .red) {
                    showDeactivateSheet = true
                }

            case "Discovery Post", "Challenge Post":
                // Dismiss → Warn → Delete post
                actionButton(icon: "checkmark.circle", title: "Dismiss Report",
                             subtitle: "No action needed", color: BrandColors.actionGreen) {
                    Task { await vm.dismissGroup(group); dismiss() }
                }
                actionButton(icon: "bell.badge", title: "Send Warning",
                             subtitle: "Notify the user about their post", color: primary) {
                    warnMessage = defaultWarnMessage; showWarnCompose = true
                }
                actionButton(icon: "trash", title: "Delete Post",
                             subtitle: "Permanently remove this post", color: .red) {
                    showDeleteConfirm = true
                }

            default: // Comment
                // Dismiss → Warn → Delete comment
                actionButton(icon: "checkmark.circle", title: "Dismiss Report",
                             subtitle: "No action needed", color: BrandColors.actionGreen) {
                    Task { await vm.dismissGroup(group); dismiss() }
                }
                actionButton(icon: "bell.badge", title: "Send Warning",
                             subtitle: "Notify the user about their comment", color: primary) {
                    warnMessage = defaultWarnMessage; showWarnCompose = true
                }
                actionButton(icon: "trash", title: "Delete Comment",
                             subtitle: "Permanently remove this comment", color: .red) {
                    showDeleteConfirm = true
                }
            }
        }
    }

    private func actionButton(icon: String, title: String, subtitle: String,
                               color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                    .foregroundColor(color).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(subtitle).font(.system(size: 13, design: .rounded)).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundColor(.secondary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(BrandColors.background)
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: Resolved Banner
    private var resolvedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: actionIcon(group.groupActionTaken ?? "")).font(.system(size: 22))
                .foregroundColor(actionColor(group.groupActionTaken ?? ""))
            VStack(alignment: .leading, spacing: 2) {
                Text("Action Taken").font(.system(size: 13, design: .rounded)).foregroundColor(.secondary)
                Text(actionLabel(group.groupActionTaken ?? ""))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(actionColor(group.groupActionTaken ?? ""))
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(actionColor(group.groupActionTaken ?? "").opacity(0.1)))
    }

    // MARK: Warn Compose Sheet
    private var warnComposeSheet: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text("This message will be sent to the user's notification inbox.")
                        .font(.system(size: 14, design: .rounded)).foregroundColor(.secondary)
                        .padding(.horizontal, 20).padding(.top, 12)
                    TextEditor(text: $warnMessage)
                        .font(.system(size: 15, design: .rounded)).padding(12).frame(minHeight: 140)
                        .background(BrandColors.background).cornerRadius(14).padding(.horizontal, 20)
                    Button {
                        Task { await vm.warnUser(group: group, message: warnMessage); showWarnCompose = false; dismiss() }
                    } label: {
                        Text("Send Warning").font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.white).frame(maxWidth: .infinity).padding()
                            .background(primary).clipShape(Capsule())
                    }
                    .disabled(warnMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal, 20)
                    Spacer()
                }
            }
            .navigationTitle("Write Warning").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showWarnCompose = false }.foregroundColor(primary)
                }
            }
        }
    }

    // MARK: Helpers
    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.secondary).textCase(.uppercase)
    }

    private var sheetTitle: String {
        switch group.itemType {
        case "Discovery Post", "Challenge Post": return "Reported Post"
        case "Account":                          return "Reported Account"
        case "Comment":                          return "Reported Comment"
        default:                                 return "Reported Content"
        }
    }

    private var defaultWarnMessage: String {
        let reasons = group.reasonSummary.map(\.title).joined(separator: ", ")
        return "Your \(group.itemType.lowercased()) has been flagged for: \(reasons). Please review our community guidelines to avoid further action."
    }
}

// =======================================================
// MARK: - Shared Style Helpers
// =======================================================

func typePill(_ type: String) -> some View {
    Text(type).font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundColor(typeColor(type)).padding(.horizontal, 10).padding(.vertical, 5)
        .background(typeColor(type).opacity(0.12)).clipShape(Capsule())
}

private func typeColor(_ type: String) -> Color {
    switch type {
    case "Discovery Post":  return BrandColors.teal
    case "Account":         return BrandColors.darkTeal
    case "Comment":         return BrandColors.gold
    case "Challenge Post":  return Color.purple
    default:                return .secondary
    }
}

private func actionIcon(_ action: String) -> String {
    switch action {
    case "deleted":     return "trash.fill"
    case "deactivated": return "person.fill.xmark"
    case "warned":      return "bell.badge.fill"
    case "dismissed":   return "checkmark.circle.fill"
    default:            return "circle.fill"
    }
}

private func actionLabel(_ action: String) -> String {
    switch action {
    case "deleted":     return "Content Deleted"
    case "deactivated": return "Account Deactivated"
    case "warned":      return "Warning Sent to User"
    case "dismissed":   return "Dismissed — No Action"
    default:            return action.capitalized
    }
}

private func actionColor(_ action: String) -> Color {
    switch action {
    case "deleted":     return .red
    case "deactivated": return .orange
    case "warned":      return BrandColors.gold
    case "dismissed":   return BrandColors.actionGreen
    default:            return .secondary
    }
}

// =======================================================
// MARK: - Redirect View (Post)
// =======================================================

struct ReportedPostView: View {
    let postRef: DocumentReference
    @EnvironmentObject var session: AppSession
    @State private var post: Post? = nil
    @State private var isLoading = true
    @State private var showAuthSheet = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(BrandColors.darkTeal)
            } else if let post = post {
                PostDetailView(post: post, showAuthSheet: $showAuthSheet, isAdminViewing: true)
                    .environmentObject(session)
            } else {
                Text("Post not found or has been deleted.")
                    .foregroundColor(.secondary).font(.system(size: 15, design: .rounded))
            }
        }
        .task {
            do {
                let doc = try await postRef.getDocument()
                guard let d = doc.data() else { isLoading = false; return }
                let likedBy = (d["likedBy"] as? [String]) ?? []
                let uid = Auth.auth().currentUser?.uid ?? ""
                let authorIdRef = d["authorId"] as? DocumentReference
                let df = DateFormatter(); df.dateFormat = "dd/MM/yyyy HH:mm"
                post = Post(
                    authorUid: authorIdRef?.documentID ?? "",
                    id: doc.documentID,
                    imageName: (d["thumbnailURL"] as? String) ?? "",
                    videoURL: (d["url"] as? String) ?? "",
                    caption: (d["caption"] as? String) ?? "",
                    timestamp: df.string(from: (d["uploadDateTime"] as? Timestamp)?.dateValue() ?? Date()),
                    isPrivate: !((d["visibility"] as? Bool) ?? true),
                    authorName: (d["authorUsername"] as? String) ?? "",
                    authorImageName: (d["profilePic"] as? String) ?? "",
                    likeCount: (d["likeCount"] as? Int) ?? 0,
                    commentCount: (d["commentCount"] as? Int) ?? 0,
                    likedBy: likedBy,
                    isLikedByUser: likedBy.contains(uid),
                    stats: nil,
                    matchDate: (d["matchDate"] as? Timestamp)?.dateValue()
                )
            } catch { print("ReportedPostView load error: \(error)") }
            isLoading = false
        }
    }
}

// =======================================================
// MARK: - Date Helper
// =======================================================

extension Date {
    var relativeString: String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: self, relativeTo: Date())
    }
}
