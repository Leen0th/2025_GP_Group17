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
    let reportedUserRole: String
    let reportedUserId: String         // author/owner UID stored at report creation
    // Snapshot saved at deletion time so resolved view can still show the content
    let snapshotThumbnail: String?
    let snapshotVideoURL: String?
    let snapshotCaption: String?
    let snapshotAuthorName: String?
}

struct ContentReportGroup: Identifiable, Hashable {
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

    var snapshotThumbnail: String? { reports.compactMap(\.snapshotThumbnail).first(where: { !$0.isEmpty }) }
    var snapshotVideoURL: String?  { reports.compactMap(\.snapshotVideoURL).first(where: { !$0.isEmpty }) }
    var snapshotCaption: String?   { reports.compactMap(\.snapshotCaption).first(where: { !$0.isEmpty }) }
    var snapshotAuthorName: String? { reports.compactMap(\.snapshotAuthorName).first(where: { !$0.isEmpty }) }
    var wasDeleted: Bool { groupActionTaken == "deleted" }

    static func == (lhs: ContentReportGroup, rhs: ContentReportGroup) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var groupActionTaken: String? {
        reports.compactMap(\.actionTaken).filter { $0 != "dismissed" }.first
            ?? reports.compactMap(\.actionTaken).first
    }

    /// All unique reason titles in this group
    var uniqueReasons: [String] {
        Array(Set(reports.map(\.reasonTitle))).sorted()
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
                        actionTaken: d["actionTaken"] as? String,
                        reportedUserRole: d["reportedUserRole"] as? String ?? "player",
                        reportedUserId: (d["reportedUserId"] as? String)
                            ?? (d["reportedItem"] as? DocumentReference)?.documentID
                            ?? "",
                        snapshotThumbnail: d["snapshotThumbnail"] as? String,
                        snapshotVideoURL: d["snapshotVideoURL"] as? String,
                        snapshotCaption: d["snapshotCaption"] as? String,
                        snapshotAuthorName: d["snapshotAuthorName"] as? String
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

    func deleteContent(group: ContentReportGroup, reason: String) async {
        isActioning = true
        defer { isActioning = false }
        guard let ref = group.reportedItemRef else { actionError = "Could not locate content reference."; return }
        do {
            // Snapshot content data before deletion so resolved view can still show it
            var snapshotData: [String: Any] = [:]
            if group.itemType == "Discovery Post" || group.itemType == "Challenge Post" {
                let doc = try? await ref.getDocument()
                if let d = doc?.data() {
                    snapshotData["snapshotThumbnail"]  = d["thumbnailURL"] as? String ?? ""
                    snapshotData["snapshotVideoURL"]   = d["url"] as? String ?? ""
                    snapshotData["snapshotCaption"]    = d["caption"] as? String ?? ""
                    snapshotData["snapshotAuthorName"] = d["authorUsername"] as? String ?? ""
                }
            } else if group.itemType == "Comment" {
                // For comments: decrement parent post's commentCount before deleting
                let postRef = ref.parent.parent
                if let postRef = postRef {
                    try await postRef.updateData(["commentCount": FieldValue.increment(Int64(-1))])
                }
            }
            try await ref.delete()
            // Send notification to the content author
            await sendDeletionNotification(group: group, reason: reason)
            for report in group.reports {
                await updateReportStatusWithSnapshot(reportId: report.id, status: "resolved", actionTaken: "deleted", snapshot: snapshotData)
            }
        } catch { actionError = "Failed to delete content: \(error.localizedDescription)" }
    }

    private func updateReportStatusWithSnapshot(reportId: String, status: String, actionTaken: String, snapshot: [String: Any]) async {
        do {
            var data: [String: Any] = [
                "status": status, "actionTaken": actionTaken,
                "resolvedAt": FieldValue.serverTimestamp(),
                "resolvedBy": Auth.auth().currentUser?.uid ?? "admin"
            ]
            for (k, v) in snapshot { data[k] = v }
            try await db.collection("reports").document(reportId).updateData(data)
        } catch { print("updateReportStatusWithSnapshot error: \(error)") }
    }

    private func sendDeletionNotification(group: ContentReportGroup, reason: String) async {
        do {
            // Try resolving from document first, fall back to stored UID on reports
            let uid: String
            do {
                uid = try await resolveAuthorUID(group: group)
            } catch {
                let fallback = group.reports.first?.reportedUserId ?? ""
                guard !fallback.isEmpty else {
                    print("Failed to send deletion notification: could not resolve author UID")
                    return
                }
                uid = fallback
            }

            let preview = group.contentPreview.isEmpty ? "your content" : "\"\(group.contentPreview)\""
            let (title, message): (String, String)
            switch group.itemType {
            case "Comment":
                title = "🗑️ Your Comment Was Removed"
                message = "Your comment \(preview) was removed by an admin.\nReason: \(reason)"
            case "Discovery Post", "Challenge Post":
                title = "🗑️ Your Post Was Removed"
                message = "Your post \(preview) was removed by an admin.\nReason: \(reason)"
            default:
                title = "🗑️ Content Removed"
                message = "Your \(group.itemType.lowercased()) was removed by an admin.\nReason: \(reason)"
            }

            let docRef = db.collection("notifications").document()
            try await docRef.setData([
                "userId": uid,
                "type": "content_deleted",
                "title": title,
                "message": message,
                "createdAt": FieldValue.serverTimestamp(),
                "isRead": false
            ])
        } catch {
            print("Failed to send deletion notification: \(error)")
        }
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
            
            // ✅ Context-aware title based on content type
            let title: String
            switch group.itemType {
            case "Comment":
                title = "⚠️ Warning About Your Comment"
            case "Discovery Post":
                title = "⚠️ Warning About Your Post"
            case "Challenge Post":
                title = "⚠️ Warning About Your Challenge Post"
            default:
                title = "⚠️ Warning About Your Account"
            }
            
            let docRef = db.collection("notifications").document()
            try await docRef.setData([
                "userId": uid,
                "type": "warning",
                "title": title,
                "message": message,
                "relatedReportId": group.reports[0].id,
                "createdAt": FieldValue.serverTimestamp(),
                "isRead": false
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
        let data = doc.data()
        // String UID fields
        if let uid = data?["authorUid"] as? String, !uid.isEmpty { return uid }
        if let uid = data?["userId"] as? String, !uid.isEmpty { return uid }
        // DocumentReference fields (e.g. videoPosts stores authorId as a reference)
        if let ref = data?["authorId"] as? DocumentReference { return ref.documentID }
        if let ref = data?["authorRef"] as? DocumentReference { return ref.documentID }
        // For comments, try userId on parent post via parentId
        if let uid = data?["uid"] as? String, !uid.isEmpty { return uid }
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
    @State private var navigateToPost: DocumentReference? = nil
    @State private var navigateToUID: String? = nil
    @State private var navigateToCoachUID: String? = nil
    @State private var selectedGroup: ContentReportGroup? = nil

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
            // Navigate to report detail page (replaces sheet)
            .navigationDestination(item: $selectedGroup) { group in
                GroupDetailPage(
                    group: group, vm: vm,
                    onViewPost: { ref in navigateToPost = ref },
                    onViewProfile: { uid in
                        Task {
                            let doc = try? await Firestore.firestore()
                                .collection("users").document(uid).getDocument()
                            let data = doc?.data()
                            // Check both "role" and "userType" in case your schema uses either
                            let role = (data?["role"] as? String)
                                    ?? (data?["userType"] as? String)
                                    ?? "player"
                            if role == "coach" { navigateToCoachUID = uid } else { navigateToUID = uid }
                        }
                    }
                )
                .environmentObject(session)
            }
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
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
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

                Menu {
                    Picker("Sort", selection: $vm.sortOrder) {
                        Text("Newest first").tag(AdminReportedContentViewModel.SortOrder.newest)
                        Text("Oldest first").tag(AdminReportedContentViewModel.SortOrder.oldest)
                        Text("Most reported").tag(AdminReportedContentViewModel.SortOrder.mostReported)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 13, weight: .medium))
                        Text(vm.sortOrder == .newest ? "Newest" : vm.sortOrder == .oldest ? "Oldest" : "Most Reported")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(primary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(BrandColors.background).clipShape(Capsule())
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
                            Rectangle().frame(height: 2).foregroundColor(primary)
                        } else {
                            Color.clear.frame(height: 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 4)
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
                            ContentGroupCard(group: group)
                                .onTapGesture { selectedGroup = group }
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
            VStack(alignment: .leading, spacing: 6) {
                Text(group.contentPreview.isEmpty ? "(No preview available)" : group.contentPreview)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(primary).lineLimit(2)
                Spacer(minLength: 0)
                if let ts = group.latestTimestamp {
                    Text(ts.relativeString)
                        .font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                typePill(group.itemType)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: "flag.fill").font(.system(size: 10, weight: .bold))
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
// MARK: - Group Detail Page (replaces sheet)
// =======================================================

struct GroupDetailPage: View {
    let group: ContentReportGroup
    @ObservedObject var vm: AdminReportedContentViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AppSession

    var onViewPost: (DocumentReference) -> Void
    var onViewProfile: (String) -> Void

    // Report filter
    @State private var selectedReasonFilter: String = "all"

    @State private var expandedReportID: String? = nil
    @State private var showDeleteReason = false
    @State private var showWarnCompose = false
    @State private var warnSent = false
    @State private var showDeactivateSheet = false
    @State private var deactivateReason = ""
    @State private var isDeactivating = false
    @State private var warnMessage = ""
    @State private var commenterUID: String? = nil
    @State private var commenterName: String = ""

    private let primary = BrandColors.darkTeal

    // Reports filtered by selected reason
    private var filteredReports: [ReportedItem] {
        let sorted = group.reports.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
        if selectedReasonFilter == "all" { return sorted }
        return sorted.filter { $0.reasonTitle == selectedReasonFilter }
    }

    var body: some View {
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
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDeleteReason) {
            DeleteReasonSheet(
                itemType: group.itemType,
                contentPreview: group.contentPreview,
                onCancel: { showDeleteReason = false },
                onConfirm: { reason in
                    showDeleteReason = false
                    Task { await vm.deleteContent(group: group, reason: reason); dismiss() }
                }
            )
        }
        .sheet(isPresented: $showWarnCompose, onDismiss: {
            if warnSent { dismiss() }
        }) { warnComposeSheet }
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
        .task { await loadUserInfo() }
    }

    // MARK: - Load User Info
    private func loadUserInfo() async {
        if group.itemType == "Account" {
            guard let uid = group.reportedItemRef?.documentID else { return }
            do {
                let userDoc = try await Firestore.firestore().collection("users").document(uid).getDocument()
                let first = userDoc.data()?["firstName"] as? String ?? ""
                let last  = userDoc.data()?["lastName"]  as? String ?? ""
                let full  = [first, last].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                commenterUID = uid
                commenterName = full.isEmpty ? "User" : full
            } catch {}
            return
        }
        guard group.itemType == "Comment" else { return }
        var uid = ""
        if let ref = group.reportedItemRef,
           let doc = try? await ref.getDocument(),
           let data = doc.data() {
            // Try all possible field names for the author UID in comment documents
            uid = (data["userId"] as? String)
               ?? (data["uid"] as? String)
               ?? (data["authorUid"] as? String)
               ?? ""
        }
        // Fall back to the UID stored on the report itself
        if uid.isEmpty {
            uid = group.reports.first?.reportedUserId ?? ""
        }
        guard !uid.isEmpty else { return }
        commenterUID = uid
        do {
            let userDoc = try await Firestore.firestore().collection("users").document(uid).getDocument()
            let first = userDoc.data()?["firstName"] as? String ?? ""
            let last  = userDoc.data()?["lastName"]  as? String ?? ""
            let full  = [first, last].joined(separator: " ").trimmingCharacters(in: .whitespaces)
            commenterName = full.isEmpty ? "Unknown User" : full
        } catch { print("Failed to load commenter user info: \(error)") }
    }

    // MARK: - Content Info Card
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

            if group.itemType == "Discovery Post" || group.itemType == "Challenge Post" {
                if group.wasDeleted, let videoURL = group.snapshotVideoURL, !videoURL.isEmpty {
                    // Post is deleted — navigate to snapshot view
                    NavigationLink {
                        DeletedPostView(
                            videoURL: videoURL,
                            thumbnailURL: group.snapshotThumbnail ?? "",
                            caption: group.snapshotCaption ?? group.contentPreview,
                            authorName: group.snapshotAuthorName ?? ""
                        ).environmentObject(session)
                    } label: {
                        HStack {
                            Image(systemName: "play.rectangle.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("View Deleted Post")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Text("Snapshot preserved")
                                    .font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                        .foregroundColor(.red).padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                } else if let ref = group.reportedItemRef, !group.wasDeleted {
                    Button { onViewPost(ref) } label: {
                        HStack {
                            Image(systemName: "play.rectangle.fill")
                            Text("View Post").font(.system(size: 15, weight: .semibold, design: .rounded))
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                        .foregroundColor(primary).padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
            } else if group.itemType == "Account", let ref = group.reportedItemRef {
                Button { onViewProfile(ref.documentID) } label: {
                    HStack {
                        Image(systemName: "person.fill")
                        Text("View Account").font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary)
                    }
                    .foregroundColor(primary).padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }

            if group.itemType == "Comment" {
                if let uid = commenterUID, !commenterName.isEmpty {
                    Button {
                        onViewProfile(uid)
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

    // MARK: - Reports Section with Filter
    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: label + filter chips (only if multiple reasons exist)
            HStack(alignment: .center) {
                sectionLabel(group.reportCount > 1 ? "All Reports (\(group.reportCount))" : "Report")
                Spacer()
            }

            // Reason filter chips — always shown
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    reasonFilterChip(title: "All", count: group.reportCount, isSelected: selectedReasonFilter == "all") {
                        selectedReasonFilter = "all"
                    }
                    ForEach(group.reasonSummary, id: \.title) { item in
                        reasonFilterChip(title: item.title, count: item.count, isSelected: selectedReasonFilter == item.title) {
                            selectedReasonFilter = selectedReasonFilter == item.title ? "all" : item.title
                        }
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 4)
            }

            // Report rows or empty state
            if filteredReports.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 28)).foregroundColor(.secondary.opacity(0.4))
                    Text("No reports with this reason")
                        .font(.system(size: 14, design: .rounded)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
                .background(RoundedRectangle(cornerRadius: 12).fill(BrandColors.background))
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredReports) { report in
                        reportRow(report)
                    }
                }
            }
        }
    }

    private func reasonFilterChip(title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.3) : primary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(isSelected ? .white : primary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isSelected ? primary : primary.opacity(0.08))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isSelected ? Color.clear : primary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            sectionLabel("Take Action")
            if group.reportCount > 1 {
                Text("Action will be applied to all \(group.reportCount) reports for this content.")
                    .font(.system(size: 12, design: .rounded)).foregroundColor(.secondary)
            }

            switch group.itemType {
            case "Account":
                actionButton(icon: "checkmark.circle", title: "Dismiss Report",
                             subtitle: "No action needed", color: BrandColors.actionGreen) {
                    Task { await vm.dismissGroup(group); dismiss() }
                }
                actionButton(icon: "bell.badge", title: "Send Warning",
                             subtitle: "Notify the user about their account", color: primary) {
                    warnMessage = ""
                    showWarnCompose = true
                }
                actionButton(icon: "person.fill.xmark", title: "Deactivate Account",
                             subtitle: "Prevent user from posting or interacting", color: .red) {
                    showDeactivateSheet = true
                }

            case "Discovery Post", "Challenge Post":
                actionButton(icon: "checkmark.circle", title: "Dismiss Report",
                             subtitle: "No action needed", color: BrandColors.actionGreen) {
                    Task { await vm.dismissGroup(group); dismiss() }
                }
                actionButton(icon: "bell.badge", title: "Send Warning",
                             subtitle: "Notify the user about their post", color: primary) {
                    warnMessage = ""
                    showWarnCompose = true
                }
                actionButton(icon: "trash", title: "Delete Post",
                             subtitle: "Permanently remove this post", color: .red) {
                    showDeleteReason = true
                }

            default: // Comment
                actionButton(icon: "checkmark.circle", title: "Dismiss Report",
                             subtitle: "No action needed", color: BrandColors.actionGreen) {
                    Task { await vm.dismissGroup(group); dismiss() }
                }
                actionButton(icon: "bell.badge", title: "Send Warning",
                             subtitle: "Notify the user about their comment", color: primary) {
                    warnMessage = ""
                    showWarnCompose = true
                }
                actionButton(icon: "trash", title: "Delete Comment",
                             subtitle: "Permanently remove this comment", color: .red) {
                    showDeleteReason = true
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

    // MARK: - Resolved Banner
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

    // MARK: - Warn Compose Sheet
    private var warnComposeSheet: some View {
        VStack(spacing: 20) {
            // Drag handle
            Capsule()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 12)

            // Header
            VStack(spacing: 8) {
                Text("Send Warning")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(primary)

                Text("\(group.itemType): \"\(group.contentPreview)\"")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Label
            HStack(spacing: 4) {
                Text("Warning message")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Text("*")
                    .foregroundColor(.red)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            .padding(.horizontal)

            // Text Editor
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 4)

                TextEditor(text: $warnMessage)
                    .font(.system(size: 16, design: .rounded))
                    .padding(12)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .onChange(of: warnMessage) { _, newValue in
                        if newValue.count > 300 {
                            warnMessage = String(newValue.prefix(300))
                        }
                    }
            }
            .frame(height: 120)
            .padding(.horizontal)

            // Character count
            HStack {
                Spacer()
                Text("\(warnMessage.count)/300")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(warnMessage.count >= 300 ? .red : .secondary)
            }
            .padding(.horizontal)

            // Required field note
            HStack {
                Image(systemName: "asterisk")
                    .font(.system(size: 8))
                    .foregroundColor(.red)
                Text("Required field")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            // Send button
            Button {
                Task {
                    await vm.warnUser(group: group, message: warnMessage)
                    warnSent = true
                    showWarnCompose = false
                }
            } label: {
                Text("Send Warning")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(warnMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : primary)
                    .clipShape(Capsule())
            }
            .disabled(warnMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Helpers
    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.secondary).textCase(.uppercase)
    }

    private var pageTitle: String {
        switch group.itemType {
        case "Discovery Post", "Challenge Post": return "Reported Post"
        case "Account":                          return "Reported Account"
        case "Comment":                          return "Reported Comment"
        default:                                 return "Reported Content"
        }
    }
}

// =======================================================
// MARK: - Delete Reason Sheet
// =======================================================

struct DeleteReasonSheet: View {
    let itemType: String
    let contentPreview: String
    var onCancel: () -> Void
    var onConfirm: (String) -> Void

    @State private var reason = ""
    @State private var isProcessing = false
    private let primary = BrandColors.darkTeal
    private let charLimit = 300

    var body: some View {
        VStack(spacing: 20) {
            // Drag handle
            Capsule()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 12)

            // Header
            VStack(spacing: 8) {
                Text("Delete \(itemType)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(primary)

                if !contentPreview.isEmpty {
                    Text("\"\(contentPreview)\"")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            // Label
            HStack(spacing: 4) {
                Text("Reason for deletion")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Text("*")
                    .foregroundColor(.red)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            .padding(.horizontal)

            // Text Editor
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 4)

                TextEditor(text: $reason)
                    .font(.system(size: 16, design: .rounded))
                    .padding(12)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .onChange(of: reason) { _, newValue in
                        if newValue.count > charLimit {
                            reason = String(newValue.prefix(charLimit))
                        }
                    }
            }
            .frame(height: 120)
            .padding(.horizontal)

            // Character count
            HStack {
                Spacer()
                Text("\(reason.count)/\(charLimit)")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(reason.count >= charLimit ? .red : .secondary)
            }
            .padding(.horizontal)

            // Required field note
            HStack {
                Image(systemName: "asterisk")
                    .font(.system(size: 8))
                    .foregroundColor(.red)
                Text("Required field")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            // Delete button
            Button {
                isProcessing = true
                onConfirm(reason)
            } label: {
                HStack {
                    Text("Delete & Notify User")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing ? Color.gray : Color.red)
                .clipShape(Capsule())
            }
            .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
            .padding(.horizontal)

            Spacer()
        }
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

// =======================================================
// MARK: - Deleted Post View (snapshot from report data)
// =======================================================

struct DeletedPostView: View {
    let videoURL: String
    let thumbnailURL: String
    let caption: String
    let authorName: String
    @EnvironmentObject var session: AppSession
    @State private var showAuthSheet = false

    var body: some View {
        let post = Post(
            authorUid: nil,
            id: nil,
            imageName: thumbnailURL,
            videoURL: videoURL,
            caption: caption,
            timestamp: "",
            isPrivate: false,
            authorName: authorName,
            authorImageName: "",
            likeCount: 0,
            commentCount: 0,
            likedBy: [],
            isLikedByUser: false,
            stats: nil,
            matchDate: nil
        )
        PostDetailView(post: post, showAuthSheet: $showAuthSheet, isAdminViewing: true)
            .environmentObject(session)
            .navigationBarTitleDisplayMode(.inline)
    }
}

// =======================================================
// MARK: - Reported Post View
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
