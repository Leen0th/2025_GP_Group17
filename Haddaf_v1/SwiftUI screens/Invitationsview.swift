import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Invitation Model
struct TeamInvitation: Identifiable {
    let id: String
    let coachID: String
    let teamID: String
    let teamName: String
    let status: String
    let createdAt: Date
    var coachName: String = ""
    var teamLogoURL: String? = nil
}

// MARK: - InvitationsViewModel
class InvitationsViewModel: ObservableObject {
    @Published var invitations: [TeamInvitation] = []
    @Published var isLoading = true

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func startListening(playerUID: String) {
        listener?.remove()
        isLoading = true
        listener = db.collection("invitations")
            .whereField("playerID", isEqualTo: playerUID)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self = self else { return }
                Task {
                    var invites: [TeamInvitation] = []
                    for doc in snap?.documents ?? [] {
                        let data = doc.data()
                        let coachID = data["coachID"] as? String ?? ""
                        let teamID = data["teamID"] as? String ?? ""
                        let teamName = data["teamName"] as? String ?? ""
                        let ts = data["createdAt"] as? Timestamp
                        var inv = TeamInvitation(
                            id: doc.documentID, coachID: coachID, teamID: teamID,
                            teamName: teamName, status: data["status"] as? String ?? "pending",
                            createdAt: ts?.dateValue() ?? Date()
                        )
                        if let cd = try? await self.db.collection("users").document(coachID).getDocument(),
                           let cdata = cd.data() {
                            inv.coachName = "\(cdata["firstName"] as? String ?? "") \(cdata["lastName"] as? String ?? "")".trimmingCharacters(in: .whitespaces)
                        }
                        if let td = try? await self.db.collection("teams").document(teamID).getDocument() {
                            inv.teamLogoURL = td.data()?["logoURL"] as? String
                        }
                        invites.append(inv)
                    }
                    await MainActor.run { self.invitations = invites; self.isLoading = false }
                }
            }
    }

    func acceptInvitation(_ inv: TeamInvitation, playerUID: String) async throws {
        let batch = db.batch()
        batch.updateData(["status": "accepted"], forDocument: db.collection("invitations").document(inv.id))
        batch.setData(["joinedAt": FieldValue.serverTimestamp()],
                      forDocument: db.collection("teams").document(inv.teamID).collection("players").document(playerUID))
        batch.updateData(["teamId": inv.teamID, "teamName": inv.teamName],
                         forDocument: db.collection("users").document(playerUID))
        try await batch.commit()
        await NotificationService.sendInvitationResponseNotification(
            coachUID: inv.coachID, playerUID: playerUID, teamName: inv.teamName, accepted: true
        )
    }

    func declineInvitation(_ inv: TeamInvitation, playerUID: String) async throws {
        try await db.collection("invitations").document(inv.id).updateData(["status": "declined"])
        await NotificationService.sendInvitationResponseNotification(
            coachUID: inv.coachID, playerUID: playerUID, teamName: inv.teamName, accepted: false
        )
    }

    deinit { listener?.remove() }
}

// MARK: - Invitations View - Full Page
struct InvitationsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AppSession
    @StateObject private var viewModel = InvitationsViewModel()

    @State private var showDeclineConfirm = false
    @State private var invitationToDecline: TeamInvitation?
    @State private var showWelcome = false
    @State private var welcomeTeamName = ""
    @State private var processingID: String? = nil

    private let accentColor = BrandColors.darkTeal

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView().tint(accentColor)
            } else if viewModel.invitations.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "envelope.open")
                        .font(.system(size: 50)).foregroundColor(.secondary.opacity(0.4))
                    Text("No Pending Invitations")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("You'll see team invitations here.")
                        .font(.system(size: 14, design: .rounded)).foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(viewModel.invitations) { inv in
                            InvitationCard(
                                invitation: inv,
                                isProcessing: processingID == inv.id
                            ) { accepted in
                                if accepted { handleAccept(inv) }
                                else { invitationToDecline = inv; showDeclineConfirm = true }
                            }
                        }
                    }
                    .padding()
                }
            }

            // ✅ Welcome overlay
            if showWelcome {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60)).foregroundColor(.green)
                    Text("Welcome to the team!")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("You've joined \(welcomeTeamName)")
                        .font(.system(size: 16, design: .rounded)).foregroundColor(.secondary)
                    Button {
                        withAnimation { showWelcome = false }
                        dismiss()
                    } label: {
                        Text("Great!")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(accentColor).clipShape(Capsule())
                    }
                    .padding(.horizontal, 20)
                }
                .padding(30)
                .background(RoundedRectangle(cornerRadius: 24).fill(BrandColors.background))
                .padding(.horizontal, 30)
                .transition(.scale.combined(with: .opacity))
            }

            // ✅ Decline confirmation popup - نفس ستايل Logout
            if showDeclineConfirm {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { withAnimation { showDeclineConfirm = false } }
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Text("Decline Invitation?")
                            .font(.system(size: 18, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text("Are you sure you want to decline this invitation?")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24).padding(.horizontal, 20).padding(.bottom, 20)

                    Divider()

                    HStack(spacing: 0) {
                        Button {
                            withAnimation { showDeclineConfirm = false }
                        } label: {
                            Text("No")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Spacer().frame(width: 12)

                        Button {
                            withAnimation { showDeclineConfirm = false }
                            if let inv = invitationToDecline { handleDecline(inv) }
                        } label: {
                            Text("Yes")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.red).clipShape(RoundedRectangle(cornerRadius: 12))
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Invitations")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
            }
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
        .animation(.spring(response: 0.3), value: showDeclineConfirm)
        .animation(.spring(response: 0.3), value: showWelcome)
        .onAppear {
            if let uid = session.user?.uid { viewModel.startListening(playerUID: uid) }
        }
    }

    private func handleAccept(_ inv: TeamInvitation) {
        guard let uid = session.user?.uid else { return }
        processingID = inv.id
        Task {
            do {
                try await viewModel.acceptInvitation(inv, playerUID: uid)
                await MainActor.run {
                    processingID = nil
                    welcomeTeamName = inv.teamName
                    withAnimation { showWelcome = true }
                }
            } catch {
                await MainActor.run { processingID = nil }
            }
        }
    }

    private func handleDecline(_ inv: TeamInvitation) {
        guard let uid = session.user?.uid else { return }
        processingID = inv.id
        Task {
            try? await viewModel.declineInvitation(inv, playerUID: uid)
            await MainActor.run { processingID = nil }
        }
    }
}

// MARK: - Invitation Card
struct InvitationCard: View {
    let invitation: TeamInvitation
    let isProcessing: Bool
    let onRespond: (Bool) -> Void
    private let accentColor = BrandColors.darkTeal

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                TeamLogoCircle(logoURL: invitation.teamLogoURL, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text(invitation.teamName)
                        .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundColor(accentColor)
                    if !invitation.coachName.isEmpty {
                        Text("Coach: \(invitation.coachName)")
                            .font(.system(size: 13, design: .rounded)).foregroundColor(.secondary)
                    }
                    Text(timeAgo(from: invitation.createdAt))
                        .font(.system(size: 12, design: .rounded)).foregroundColor(.secondary.opacity(0.7))
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button { onRespond(false) } label: {
                    Text("Decline")
                        .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(.red)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.red.opacity(0.1)).clipShape(Capsule())
                }
                Button { onRespond(true) } label: {
                    HStack(spacing: 6) {
                        if isProcessing { ProgressView().scaleEffect(0.8).tint(.white) }
                        Text("Accept")
                            .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(accentColor).clipShape(Capsule())
                }
            }
            .disabled(isProcessing).opacity(isProcessing ? 0.6 : 1)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BrandColors.background)
                .shadow(color: accentColor.opacity(0.1), radius: 10, y: 4)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(accentColor.opacity(0.2), lineWidth: 1))
        )
    }

    private func timeAgo(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .hour, .minute], from: date, to: Date())
        if let d = c.day, d > 0 { return d == 1 ? "1 day ago" : "\(d) days ago" }
        if let h = c.hour, h > 0 { return h == 1 ? "1 hour ago" : "\(h) hours ago" }
        return "Just now"
    }
}

// MARK: - Single Invitation Sheet (opened from notification tap)
struct SingleInvitationSheet: View {
    let invitationID: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AppSession

    @State private var invitation: TeamInvitation? = nil
    @State private var isLoading = true
    @State private var isProcessing = false
    @State private var showDeclineConfirm = false
    @State private var showWelcome = false

    private let db = Firestore.firestore()
    private let accentColor = BrandColors.darkTeal

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(accentColor)

            } else if let inv = invitation {
                // ── Main Content ──────────────────────────────────────
                VStack(spacing: 24) {
                    Spacer()

                    TeamLogoCircle(logoURL: inv.teamLogoURL, size: 90)
                        .shadow(color: accentColor.opacity(0.15), radius: 12, y: 4)

                    VStack(spacing: 6) {
                        Text(inv.teamName)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(accentColor)
                            .multilineTextAlignment(.center)
                        if !inv.coachName.isEmpty {
                            Text("Coach: \(inv.coachName)")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 24)

                    Text("You've been invited to join this team.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    HStack(spacing: 16) {
                        Button { showDeclineConfirm = true } label: {
                            Text("Decline")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.red.opacity(0.1)).clipShape(Capsule())
                        }
                        Button { handleAccept(inv) } label: {
                            HStack(spacing: 6) {
                                if isProcessing { ProgressView().scaleEffect(0.8).tint(.white) }
                                Text("Accept")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(accentColor).clipShape(Capsule())
                        }
                    }
                    .disabled(isProcessing).opacity(isProcessing ? 0.6 : 1)
                    .padding(.horizontal, 24)

                    Spacer()
                }

            } else {
                // Invitation already handled
                VStack(spacing: 14) {
                    Image(systemName: "envelope.open")
                        .font(.system(size: 44)).foregroundColor(.secondary.opacity(0.4))
                    Text("Already handled")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("This invitation was already accepted or declined.")
                        .font(.system(size: 13, design: .rounded)).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                    Button { dismiss() } label: {
                        Text("Close")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(accentColor).clipShape(Capsule())
                    }
                    .padding(.horizontal, 32).padding(.top, 4)
                }
            }

            // ── Welcome Overlay (زي Profile updated) ────────────────────
            if showWelcome, let inv = invitation {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 64, height: 64)
                        Image(systemName: "checkmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text("Welcome to")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    Text(inv.teamName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor)
                        .multilineTextAlignment(.center)

                    Button {
                        withAnimation { showWelcome = false }
                        dismiss()
                    } label: {
                        Text("OK")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(accentColor).clipShape(Capsule())
                    }
                }
                .padding(28)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(BrandColors.background)
                        .shadow(color: .black.opacity(0.15), radius: 24, y: 8)
                )
                .padding(.horizontal, 30)
                .transition(.scale.combined(with: .opacity))
            }

            // ── Decline Confirm ──────────────────────────────────────────
            if showDeclineConfirm {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { withAnimation { showDeclineConfirm = false } }
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Text("Decline Invitation?")
                            .font(.system(size: 18, weight: .bold))
                        Text("Are you sure?")
                            .font(.system(size: 14)).foregroundColor(.secondary)
                    }
                    .padding(.top, 24).padding(.horizontal, 20).padding(.bottom, 20)
                    Divider()
                    HStack(spacing: 12) {
                        Button { withAnimation { showDeclineConfirm = false } } label: {
                            Text("No")
                                .font(.system(size: 16, weight: .semibold)).foregroundColor(.primary)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Button {
                            withAnimation { showDeclineConfirm = false }
                            if let inv = invitation { handleDecline(inv) }
                        } label: {
                            Text("Yes")
                                .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.red).clipShape(RoundedRectangle(cornerRadius: 12))
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
        .presentationDetents([.medium])
        .presentationCornerRadius(28)
        .animation(.spring(response: 0.3), value: showWelcome)
        .animation(.spring(response: 0.3), value: showDeclineConfirm)
        .onAppear { loadInvitation() }
    }

    private func loadInvitation() {
        Task {
            guard let doc = try? await db.collection("invitations").document(invitationID).getDocument(),
                  doc.exists, let data = doc.data() else {
                await MainActor.run { isLoading = false }
                return
            }
            // Only show if still pending
            let status = data["status"] as? String ?? "pending"
            guard status == "pending" else {
                await MainActor.run { isLoading = false }
                return
            }
            let coachID  = data["coachID"]  as? String ?? ""
            let teamID   = data["teamID"]   as? String ?? ""
            let teamName = data["teamName"] as? String ?? ""
            let ts = data["createdAt"] as? Timestamp
            var inv = TeamInvitation(
                id: doc.documentID, coachID: coachID, teamID: teamID,
                teamName: teamName, status: status,
                createdAt: ts?.dateValue() ?? Date()
            )
            if let cd = try? await db.collection("users").document(coachID).getDocument(),
               let cdata = cd.data() {
                inv.coachName = "\(cdata["firstName"] as? String ?? "") \(cdata["lastName"] as? String ?? "")".trimmingCharacters(in: .whitespaces)
            }
            if let td = try? await db.collection("teams").document(teamID).getDocument() {
                inv.teamLogoURL = td.data()?["logoURL"] as? String
            }
            await MainActor.run { self.invitation = inv; self.isLoading = false }
        }
    }

    private func handleAccept(_ inv: TeamInvitation) {
        guard let uid = session.user?.uid else { return }
        isProcessing = true
        Task {
            do {
                let vm = InvitationsViewModel()
                try await vm.acceptInvitation(inv, playerUID: uid)
                await MainActor.run {
                    isProcessing = false
                    withAnimation { showWelcome = true }
                }
            } catch {
                await MainActor.run { isProcessing = false }
            }
        }
    }

    private func handleDecline(_ inv: TeamInvitation) {
        guard let uid = session.user?.uid else { return }
        isProcessing = true
        Task {
            let vm = InvitationsViewModel()
            try? await vm.declineInvitation(inv, playerUID: uid)
            await MainActor.run { isProcessing = false; dismiss() }
        }
    }
}
