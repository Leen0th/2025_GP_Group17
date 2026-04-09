import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Notifications View (Full Page with NavigationStack)
struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var notificationService = NotificationService.shared
    @EnvironmentObject var session: AppSession

    @State private var showDeleteConfirm = false
    @State private var notificationToDelete: HaddafNotification?
    @State private var selectedInvitationID: String? = nil
    @State private var showInvitationSheet = false
    // Academy invitation
    @State private var selectedAcademyNotif: HaddafNotification? = nil
    @State private var showAcademyInvitePopup = false

    private let accentColor = BrandColors.darkTeal

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()

            VStack(spacing: 0) {

                ZStack {
                    Text("Notifications")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundColor(accentColor)
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(accentColor)
                                .padding(10)
                                .background(Circle().fill(BrandColors.lightGray.opacity(0.7)))
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // ── Mark All Read ──────────────────────────────────────
                if !notificationService.notifications.isEmpty {
                    HStack {
                        Spacer()
                        Button {
                            Task {
                                guard let userId = session.user?.uid else { return }
                                await notificationService.markAllAsRead(userId: userId)
                            }
                        } label: {
                            Text("Clear All")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(accentColor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(accentColor.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                    }
                    .padding(.top, 6)
                }

                if notificationService.isLoading {
                    Spacer()
                    ProgressView().tint(accentColor)
                    Spacer()
                } else if notificationService.notifications.isEmpty {
                    Spacer()
                    emptyStateView
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(notificationService.notifications) { notification in
                                NotificationCard(
                                    notification: notification,
                                    onTap: {
                                        Task { await notificationService.markAsRead(notificationId: notification.id) }
                                        if notification.type == .academyInvitation && !notification.isRead {
                                            selectedAcademyNotif = notification
                                            showAcademyInvitePopup = true
                                        }
                                    },
                                    onDelete: {
                                        notificationToDelete = notification
                                        showDeleteConfirm = true
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }

            // Academy invitation popup — inside ZStack to cover full screen including footer
            if showAcademyInvitePopup, let notif = selectedAcademyNotif {
                AcademyInvitePopup(
                    notification: notif,
                    playerUID: session.user?.uid ?? "",
                    onDismiss: { showAcademyInvitePopup = false; selectedAcademyNotif = nil }
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: showAcademyInvitePopup)
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showInvitationSheet) {
            if let invID = selectedInvitationID {
                SingleInvitationSheet(invitationID: invID)
                    .environmentObject(session)
            }
        }
        .confirmationDialog("Delete this notification?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let n = notificationToDelete {
                    Task { await notificationService.deleteNotification(notificationId: n.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            guard let user = Auth.auth().currentUser, !user.isAnonymous else { return }
            if let userId = session.user?.uid { notificationService.startListening(for: userId) }
        }
    }
}

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash").font(.system(size: 60)).foregroundColor(.secondary.opacity(0.5))
            Text("No Notifications")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text("You're all caught up!")
                .font(.system(size: 14, design: .rounded)).foregroundColor(.secondary)
        }
    }


// MARK: - Notification Card
struct NotificationCard: View {
    let notification: HaddafNotification
    let onTap: () -> Void
    let onDelete: () -> Void
    private let accentColor = BrandColors.darkTeal

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(notification.isRead ? Color.gray.opacity(0.15) : iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(notification.isRead ? .gray : iconColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(notification.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.primary)
                Text(notification.message)
                    .font(.system(size: 14, design: .rounded)).foregroundColor(.secondary).lineLimit(3)
                Text(timeAgoText(from: notification.createdAt))
                    .font(.system(size: 12, design: .rounded)).foregroundColor(.secondary.opacity(0.7))
                if notification.type == .academyInvitation && !notification.isRead {
                    Text("Tap to accept or decline →")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(accentColor)
                }
            }

            Spacer()
            if !notification.isRead {
                Circle().fill(accentColor).frame(width: 10, height: 10)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(notification.isRead ? 0.05 : 0.1), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(notification.isRead ? Color.clear : iconColor.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture { onTap() }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var iconName: String {
        switch notification.type {

        case .adminMonthlyReminder:
            return "calendar.badge.plus"

        case .playerChallengeSubmitted:
            return "checkmark.circle.fill"

        case .challengeEnded:
            return "trophy.fill"

        case .newChallengeAvailable:
            return "star.circle.fill"

        case .academyInvitation:
            return "building.2.fill"

        case .invitationAccepted:
            return "person.badge.checkmark.fill"

        case .invitationDeclined:
            return "person.badge.minus"

        case .removedFromTeam:
            return "xmark.circle.fill"

        case .goalAchieved:
            return "target"

        case .warning:
            return "exclamationmark.triangle.fill"

        case .contentDeleted:
            return "trash.fill"

        case .matchJoinRequested:
            return "person.crop.circle.badge.plus"

        case .matchJoinApproved:
            return "checkmark.seal.fill"

        case .matchJoinRejected:
            return "xmark.seal.fill"

        // 🔥🔥🔥 اللي ناقصين
        case .matchCancelled:
            return "xmark.octagon.fill"

        case .upcomingMatchReminder:
            return "clock.badge.checkmark.fill"
        }
    }

    private var iconColor: Color {
        switch notification.type {

        case .invitationAccepted:
            return .green

        case .invitationDeclined,
             .removedFromTeam,
             .matchJoinRejected,
             .matchCancelled:
            return .red

        case .warning:
            return .orange

        case .contentDeleted:
            return .red

        case .matchJoinApproved:
            return .green

        case .matchJoinRequested,
             .upcomingMatchReminder:
            return BrandColors.darkTeal

        default:
            return BrandColors.darkTeal
        }
    }

    private func timeAgoText(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.minute, .hour, .day, .weekOfYear], from: date, to: Date())
        if let w = c.weekOfYear, w > 0 { return w == 1 ? "1 week ago" : "\(w) weeks ago" }
        if let d = c.day, d > 0 { return d == 1 ? "1 day ago" : "\(d) days ago" }
        if let h = c.hour, h > 0 { return h == 1 ? "1 hour ago" : "\(h) hours ago" }
        if let m = c.minute, m > 0 { return m == 1 ? "1 minute ago" : "\(m) minutes ago" }
        return "Just now"
    }
}

// MARK: - Academy Invite Popup
struct AcademyInvitePopup: View {
    let notification: HaddafNotification
    let playerUID: String
    let onDismiss: () -> Void

    @State private var isProcessing = false
    @State private var isDone = false
    @State private var result: Bool? = nil
    @State private var academyName = ""
    @State private var coachName = ""
    @State private var logoURL: String? = nil
    @State private var showDeclineConfirm = false
    private let accent = BrandColors.darkTeal
    private let db = Firestore.firestore()

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { if !isProcessing && !isDone { onDismiss() } }

            // Centered popup
            VStack(spacing: 0) {
                if isDone {
                    VStack(spacing: 16) {
                        Image(systemName: result == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 52))
                            .foregroundColor(result == true ? BrandColors.actionGreen : .red)
                        Text(result == true ? "Joined!" : "Declined")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        if result == true {
                            Text("You joined \(academyName)")
                                .font(.system(size: 14, design: .rounded)).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Button("Close") { onDismiss() }
                            .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14).background(accent).clipShape(Capsule())
                    }.padding(28)
                } else {
                    VStack(spacing: 12) {
                        // Academy logo
                        AcademyLogoView(logoURL: logoURL, size: 72)

                        // Academy name
                        Text(academyName.isEmpty ? "Academy Invitation" : academyName)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(accent).multilineTextAlignment(.center)

                        // Category badge
                        if let cat = notification.category {
                            Text(cat).font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 6)
                                .background(accent).clipShape(Capsule())
                        }

                        Divider().padding(.horizontal, 8)

                        // Coach name
                        if !coachName.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "person.fill").foregroundColor(.secondary).font(.system(size: 12))
                                Text("Invited by \(coachName)")
                                    .font(.system(size: 13, design: .rounded)).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 28).padding(.horizontal, 20).padding(.bottom, 8)

                    Divider().padding(.top, 8)

                    HStack(spacing: 12) {
                        // Decline — confirmation first
                        Button { showDeclineConfirm = true } label: {
                            Text("Decline")
                                .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(.red)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.red.opacity(0.1)).clipShape(Capsule())
                        }.disabled(isProcessing)

                        Button { Task { await respond(accept: true) } } label: {
                            HStack {
                                if isProcessing { ProgressView().tint(.white).scaleEffect(0.8) }
                                Text("Accept")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(accent).clipShape(Capsule())
                        }.disabled(isProcessing)
                    }.padding(.horizontal, 20).padding(.vertical, 16)
                }
            }
            .background(BrandColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 32)
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)

            // Decline confirmation popup
            if showDeclineConfirm {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { showDeclineConfirm = false }
                VStack(spacing: 20) {
                    Text("Are you sure?")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Do you want to decline the invitation to join \(academyName.isEmpty ? "this academy" : academyName)?")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Button { showDeclineConfirm = false } label: {
                            Text("No")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color(UIColor.systemGray5)).clipShape(Capsule())
                        }
                        Button {
                            showDeclineConfirm = false
                            Task { await respond(accept: false) }
                        } label: {
                            Text("Yes, Decline")
                                .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.red).clipShape(Capsule())
                        }
                    }
                }
                .padding(28)
                .background(BrandColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 32)
                .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showDeclineConfirm)
            }
        }
        .onAppear { Task { await loadInfo() } }
    }

    private func loadInfo() async {
        // Step 1: teamName from notification
        if let tn = notification.teamName, !tn.isEmpty {
            await MainActor.run { academyName = tn }
        }

        // Step 2: load invitation doc to get coachID
        var resolvedCoachUID: String? = nil
        if let invId = notification.invitationId, !invId.isEmpty,
           let invDoc = try? await db.collection("invitations").document(invId).getDocument(),
           let coachID = invDoc.data()?["coachID"] as? String, !coachID.isEmpty {
            resolvedCoachUID = coachID
        }

        guard let academyId = notification.academyId, !academyId.isEmpty else {
            // No academyId — load coach name only
            if let uid = resolvedCoachUID,
               let userDoc = try? await db.collection("users").document(uid).getDocument(),
               let d = userDoc.data() {
                let name = "\(d["firstName"] as? String ?? "") \(d["lastName"] as? String ?? "")".trimmingCharacters(in: .whitespaces)
                await MainActor.run { coachName = name }
            }
            return
        }

        // Step 3: load academy doc for name + logo
        if let doc = try? await db.collection("academies").document(academyId).getDocument(),
           let d = doc.data() {
            let name = d["name"] as? String ?? ""
            let logo = d["logoURL"] as? String
            await MainActor.run {
                if !name.isEmpty { academyName = name }
                logoURL = logo
            }
        }

        // Step 4: if academy name still empty, get from coach's users doc currentAcademy
        if (academyName.isEmpty || academyName == "Academy Invitation"),
           let uid = resolvedCoachUID,
           let cDoc = try? await db.collection("users").document(uid).getDocument(),
           let n = cDoc.data()?["currentAcademy"] as? String, !n.isEmpty {
            await MainActor.run { academyName = n }
        }

        // Step 5: also try category coaches array if invitation not found
        if resolvedCoachUID == nil,
           let cat = notification.category,
           let catDoc = try? await db.collection("academies").document(academyId)
               .collection("categories").document(cat).getDocument(),
           let coaches = catDoc.data()?["coaches"] as? [String] {
            resolvedCoachUID = coaches.first
        }

        // Step 6: load coach name
        if let uid = resolvedCoachUID,
           let userDoc = try? await db.collection("users").document(uid).getDocument(),
           let d = userDoc.data() {
            let name = "\(d["firstName"] as? String ?? "") \(d["lastName"] as? String ?? "")".trimmingCharacters(in: .whitespaces)
            await MainActor.run { coachName = name }
        }
    }

    private func respond(accept: Bool) async {
        guard let academyId = notification.academyId,
              let category = notification.category else { onDismiss(); return }
        isProcessing = true

        // Fetch coach UID and player name once — needed in both branches
        let coachUID = await fetchCoachUID(academyId: academyId, category: category)
        let playerName = await fetchPlayerName()

        if accept {
            // 1. Update player status ONLY in the specific category from this notification
            // First verify the player doc actually exists in this category
            let playerRef = db.collection("academies").document(academyId)
                .collection("categories").document(category)
                .collection("players").document(playerUID)
            let playerDoc = try? await playerRef.getDocument()
            if playerDoc?.exists == true {
                try? await playerRef.updateData([
                    "status": "accepted",
                    "acceptedAt": FieldValue.serverTimestamp()
                ])
            }

            // 2. Resolve academy name using multiple fallback sources:
            //    a) Already loaded in the popup UI (academyName state)
            //    b) notification.teamName field
            //    c) Firestore academy doc "name" field
            //    d) Coach's users doc "currentAcademy" field (most reliable for old accounts)
            var nameToSave = academyName.isEmpty || academyName == "Academy Invitation" ? "" : academyName
            if nameToSave.isEmpty, let tn = notification.teamName, !tn.isEmpty { nameToSave = tn }
            if nameToSave.isEmpty {
                if let aDoc = try? await db.collection("academies").document(academyId).getDocument(),
                   let n = aDoc.data()?["name"] as? String, !n.isEmpty {
                    nameToSave = n
                }
            }
            // Last resort: get from coach's users doc currentAcademy
            if nameToSave.isEmpty, let cUID = coachUID,
               let cDoc = try? await db.collection("users").document(cUID).getDocument(),
               let n = cDoc.data()?["currentAcademy"] as? String, !n.isEmpty {
                nameToSave = n
            }
            if !nameToSave.isEmpty { await MainActor.run { academyName = nameToSave } }

            // 3. Write to player's users doc
            var playerUpdate: [String: Any] = [
                "academyId": academyId,
                "isInAcademy": true,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            if !nameToSave.isEmpty { playerUpdate["currentAcademy"] = nameToSave }
            try? await db.collection("users").document(playerUID).updateData(playerUpdate)

            // 4. Update invitation
            if let invId = notification.invitationId, !invId.isEmpty {
                try? await db.collection("invitations").document(invId).updateData(["status": "accepted"])
            }

            // 6. Notify coach with full player name and academy name
            if let uid = coachUID {
                let displayAcademy = nameToSave.isEmpty ? "the academy" : nameToSave
                let notif: [String: Any] = [
                    "userId": uid,
                    "title": "✅ Invitation Accepted",
                    "message": "\(playerName) accepted your invitation to join \(displayAcademy) — \(category).",
                    "type": "invitation_accepted",
                    "isRead": false,
                    "createdAt": FieldValue.serverTimestamp()
                ]
                try? await db.collection("notifications").addDocument(data: notif)
            }
        } else {
            // 1. Delete player from academy subcollection
            do {
                try await db.collection("academies").document(academyId)
                    .collection("categories").document(category)
                    .collection("players").document(playerUID).delete()
                print("✅ Player deleted from academy")
            } catch {
                print("❌ Failed to delete player: \(error.localizedDescription)")
            }
            // 2. Update invitation status
            if let invId = notification.invitationId, !invId.isEmpty {
                try? await db.collection("invitations").document(invId).updateData(["status": "declined"])
            }
            // 3. Set currentAcademy to "Unassigned"
            try? await db.collection("users").document(playerUID).updateData([
                "currentAcademy": "Unassigned",
                "updatedAt": FieldValue.serverTimestamp()
            ])
            // 4. Notify coach
            if let uid = coachUID {
                print("✅ Sending decline notification to coach: \(uid)")
                let notif: [String: Any] = [
                    "userId": uid,
                    "title": "❌ Invitation Declined",
                    "message": "\(playerName) declined your invitation to join \(category) — \(academyName).",
                    "type": "invitation_declined",
                    "isRead": false,
                    "createdAt": FieldValue.serverTimestamp()
                ]
                do {
                    try await db.collection("notifications").addDocument(data: notif)
                    print("✅ Coach notification sent")
                } catch {
                    print("❌ Failed to send coach notification: \(error.localizedDescription)")
                }
            } else {
                print("❌ coachUID is nil — notification not sent")
            }
        }
        // Delete the notification doc after action
        try? await db.collection("notifications").document(notification.id).delete()
        await MainActor.run { isProcessing = false; result = accept; isDone = true }
    }

    private func fetchCoachUID(academyId: String, category: String) async -> String? {
        // First try: get coachID directly from the invitation doc (most reliable)
        if let invId = notification.invitationId, !invId.isEmpty {
            if let doc = try? await db.collection("invitations").document(invId).getDocument(),
               let coachID = doc.data()?["coachID"] as? String, !coachID.isEmpty {
                return coachID
            }
        }
        // Fallback: get first coach from academy category
        let doc = try? await db.collection("academies").document(academyId)
            .collection("categories").document(category).getDocument()
        return (doc?.data()?["coaches"] as? [String])?.first
    }

    private func fetchPlayerName() async -> String {
        guard let doc = try? await db.collection("users").document(playerUID).getDocument(),
              let d = doc.data() else { return "A player" }
        return "\(d["firstName"] as? String ?? "") \(d["lastName"] as? String ?? "")".trimmingCharacters(in: .whitespaces)
    }
}
