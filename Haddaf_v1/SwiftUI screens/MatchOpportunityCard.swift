import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct MatchOpportunityCard: View {
    let match: MatchOpportunity
    let currentUserId: String
    let myRequest: MatchJoinRequest?
    let pendingCount: Int
    let onRefresh: () -> Void

    @EnvironmentObject var session: AppSession
    @State private var isExpanded = false
    @State private var selectedPosition: MatchPosition? = nil
    @State private var isProcessing = false
    @State private var showRequestsSheet = false
    @State private var showLeaveConfirm = false

    private let accent = BrandColors.darkTeal
    private let headerGray = Color(red: 0.953, green: 0.953, blue: 0.953)
    private var isOrganizer: Bool { currentUserId == match.createdBy }

    var body: some View {
        // ─── CARD (كل شيء داخل الكارد) ──────────────────────────
        VStack(spacing: 0) {

            // ── TOP: رمادي F3F3F3 (بروفايل + اسم + badge) ──────
            HStack(spacing: 10) {
                Button {
                    openUserProfile()
                } label: {
                    Circle()
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 36, height: 36)
                        .overlay(Image(systemName: "person.fill").foregroundColor(.gray))
                }
                .buttonStyle(.plain)

                Text(match.createdByName)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                // ── OPEN / CLOSED BADGE ──────────────────────────
                HStack(spacing: 4) {
                    Circle()
                        .fill(match.isClosed ? Color.red : Color.green)
                        .frame(width: 6, height: 6)
                    Text(match.isClosed ? "Closed" : "Open")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(match.isClosed ? .red : .green)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(match.isClosed ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(headerGray)

            // ── BOTTOM: أبيض ────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {

                // 📅 DATE + 📍 LOCATION
                HStack(spacing: 16) {
                    Label(
                        match.dateTime.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "calendar"
                    )
                    .font(.system(size: 12))
                    .foregroundColor(.gray)

                    Button {
                        openInMaps()
                    } label: {
                        Label(match.locationName, systemImage: "mappin.and.ellipse")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                // ── STATUS INDICATOR (داخل الكارد تماماً) ───────
                if !isOrganizer {
                    statusIndicator
                }

                // ── EXPAND SECTION ───────────────────────────────
                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {

                        Text("Positions Available")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(accent)

                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 8
                        ) {
                            ForEach(MatchPosition.allCases) { position in
                                let count = match.availableCount(for: position)

                                Button {
                                    guard !isOrganizer, count > 0 else { return }
                                    selectedPosition = position
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(count) \(count == 1 ? position.title : position.pluralTitle)")
                                                .font(.system(size: 12, weight: .semibold))
                                            Text(count > 0 ? "Available" : "Unavailable")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if selectedPosition == position {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(accent)
                                                .font(.system(size: 13))
                                        }
                                    }
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.gray.opacity(0.05))
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(
                                    count <= 0 || isOrganizer
                                    || myRequest?.status == .pending
                                    || myRequest?.status == .approved
                                )
                            }
                        }

                        if isOrganizer {
                            Button {
                                showRequestsSheet = true
                            } label: {
                                HStack {
                                    Text("Manage Requests")
                                    Spacer()
                                    if pendingCount > 0 {
                                        Text("\(pendingCount)")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 20, height: 20)
                                            .background(Circle().fill(accent))
                                    }
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(accent)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(accent.opacity(0.08))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            playerActionArea
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
        .sheet(isPresented: $showRequestsSheet) {
            MatchRequestsSheet(match: match)
        }
        .confirmationDialog(
            "Leave Match?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave Match", role: .destructive) {
                guard let req = myRequest else { return }
                Task {
                    isProcessing = true
                    try? await MatchService.shared.cancelApprovedRequest(
                        request: req,
                        match: match
                    )
                    isProcessing = false
                    selectedPosition = nil   // reset position selection
                    isExpanded = false       // collapse card back to default
                    onRefresh()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to leave this match?")
        }
    }

    // ── STATUS INDICATOR داخل الكارد ────────────────────────────
    @ViewBuilder
    private var statusIndicator: some View {
        switch myRequest?.status {

        case .pending:
            Text("Pending approval...")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.08))
                .clipShape(Capsule())

        case .approved:
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 13))
                Text("Accepted")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.green)

                Spacer()

                Button {
                    showLeaveConfirm = true
                } label: {
                    Text("Leave Match")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))

        default:
            EmptyView()
        }
    }

    // ── PLAYER ACTIONS (في expanded) ────────────────────────────
    @ViewBuilder
    private var playerActionArea: some View {
        if let myRequest {
            switch myRequest.status {

            case .pending:
                Button {
                    Task {
                        isProcessing = true
                        try? await MatchService.shared.cancelPendingRequest(requestId: myRequest.id)
                        isProcessing = false
                        onRefresh()
                    }
                } label: {
                    Text("Cancel Request")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

            case .approved:
                EmptyView()

            case .rejected:
                requestButton(title: "Request Again")

            case .cancelled:
                requestButton(title: "Request")
            }

        } else if match.isClosed {
            Text("Closed")
                .font(.system(size: 12))
                .foregroundColor(.red)

        } else {
            requestButton(title: "Request")
        }
    }

    // ── REQUEST BUTTON ───────────────────────────────────────────
    private func requestButton(title: String) -> some View {
        Button {
            guard let uid = session.user?.uid,
                  let selectedPosition,
                  let fullName = currentDisplayName()
            else { return }

            Task {
                isProcessing = true
                let profilePic = await fetchProfilePic(uid: uid)
                try? await MatchService.shared.requestJoin(
                    match: match,
                    playerId: uid,
                    playerName: fullName,
                    playerProfilePic: profilePic,
                    position: selectedPosition
                )
                isProcessing = false
                onRefresh()
            }
        } label: {
            HStack {
                if isProcessing {
                    ProgressView().tint(.white).scaleEffect(0.8)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selectedPosition == nil ? Color.gray.opacity(0.4) : accent)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(selectedPosition == nil || isProcessing)
    }

    // ── HELPERS ──────────────────────────────────────────────────
    private func openInMaps() {
        if let lat = match.locationLat, let lng = match.locationLng {
            let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lng)")
            if let url { UIApplication.shared.open(url) }
        } else {
            let query = match.locationName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(query)")
            if let url { UIApplication.shared.open(url) }
        }
    }

    private func openUserProfile() {
        print("Go to profile of \(match.createdBy)")
    }

    private func currentDisplayName() -> String? {
        guard let user = session.user else { return nil }
        return user.displayName?.isEmpty == false ? user.displayName : "Player"
    }

    private func fetchProfilePic(uid: String) async -> String? {
        let doc = try? await Firestore.firestore().collection("users").document(uid).getDocument()
        return doc?.data()?["profilePic"] as? String
    }
}
