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
    @State private var creatorProfilePicURL: String? = nil

    // ✅ جديد: للـ navigation للبروفايل
    @State private var navigateToProfile: String? = nil

    private let accent = BrandColors.darkTeal
    private let headerGray = Color(red: 0.953, green: 0.953, blue: 0.953)
    private let closedColor = Color(red: 0.72, green: 0.12, blue: 0.12)

    private var isOrganizer: Bool {
        currentUserId == match.createdBy
    }

    private var badgeColor: Color {
        match.isClosed ? closedColor : accent
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Header
            HStack(spacing: 10) {
                // ✅ صورة المنشئ — تفتح البروفايل
                Button {
                    navigateToProfile = match.createdBy
                } label: {
                    RemoteProfileImage(
                        imageURL: creatorProfilePicURL,
                        size: 38,
                        placeholderTint: .gray
                    )
                }
                .buttonStyle(.plain)

                // ✅ اسم المنشئ — أيضاً يفتح البروفايل
                Button {
                    navigateToProfile = match.createdBy
                } label: {
                    Text(match.createdByName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                }
                .buttonStyle(.plain)

                Spacer()

                statusBadge
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(headerGray)

            // MARK: - Body
            VStack(alignment: .leading, spacing: 12) {

                // Date + location
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
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                // Player status strip
                if !isOrganizer {
                    statusIndicator
                }

                // Expanded content
                if isExpanded {
                    VStack(alignment: .leading, spacing: 12) {

                        Text("Positions Available")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(accent)

                        positionsGrid

                        if isOrganizer {
                            organizerActions
                        } else {
                            playerActionArea
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
        .task {
            await loadCreatorProfilePic()
        }
        // ✅ sheet الريكوستات — مع تمرير navigateToProfile
        .sheet(isPresented: $showRequestsSheet) {
            MatchRequestsSheet(match: match, onProfileTap: { userId in
                showRequestsSheet = false
                // بعد ما يُغلق الشيت، افتح البروفايل
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    navigateToProfile = userId
                }
            })
        }
        // ✅ NavigationLink مخفي للبروفايل
        .background(
            NavigationLink(
                destination: Group {
                    if let userId = navigateToProfile {
                        NavigationStack {
                            PlayerProfileContentView(userID: userId)
                                .environmentObject(session)
                        }
                    }
                },
                isActive: Binding(
                    get: { navigateToProfile != nil },
                    set: { if !$0 { navigateToProfile = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
        )
        .confirmationDialog(
            "Leave Match?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave Match", role: .destructive) {
                guard let req = myRequest else {
                    print("❌ myRequest is nil!")
                    return
                }
                print("✅ Leaving with request: \(req.id), position: \(req.requestedPosition), status: \(req.status)")
                Task {
                    isProcessing = true
                    do {
                        try await MatchService.shared.cancelApprovedRequest(
                            request: req,
                            match: match
                        )
                        print("✅ cancelApprovedRequest succeeded")
                    } catch {
                        print("❌ cancelApprovedRequest failed: \(error)")
                    }
                    await MainActor.run {
                        isProcessing = false
                        selectedPosition = nil
                        isExpanded = false
                    }
                    onRefresh()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to leave this match?")
        }
    }

    // MARK: - Header Badge
    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(badgeColor)
                .frame(width: 7, height: 7)

            Text(match.isClosed ? "Closed" : "Open")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(badgeColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(badgeColor.opacity(0.12))
        )
    }

    // MARK: - Status Indicator
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
            HStack {
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

        default:
            EmptyView()
        }
    }

    // MARK: - Positions Grid
    private var positionsGrid: some View {
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
                                .foregroundColor(.black)

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
    }

    // MARK: - Organizer Actions
    @ViewBuilder
    private var organizerActions: some View {
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
    }

    // MARK: - Player Actions
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
                .foregroundColor(closedColor)

        } else {
            requestButton(title: "Request")
        }
    }

    // MARK: - Request Button
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
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
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

    // MARK: - Helpers
    private func openInMaps() {
        if let lat = match.locationLat, let lng = match.locationLng {
            let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lng)")
            if let url {
                UIApplication.shared.open(url)
            }
        } else {
            let query = match.locationName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(query)")
            if let url {
                UIApplication.shared.open(url)
            }
        }
    }

    private func currentDisplayName() -> String? {
        guard let user = session.user else { return nil }
        return user.displayName?.isEmpty == false ? user.displayName : "Player"
    }

    private func fetchProfilePic(uid: String) async -> String? {
        let doc = try? await Firestore.firestore()
            .collection("users")
            .document(uid)
            .getDocument()

        return doc?.data()?["profilePic"] as? String
    }

    private func loadCreatorProfilePic() async {
        let doc = try? await Firestore.firestore()
            .collection("users")
            .document(match.createdBy)
            .getDocument()

        await MainActor.run {
            creatorProfilePicURL = doc?.data()?["profilePic"] as? String
        }
    }
}

// MARK: - Reusable Remote Image
private struct RemoteProfileImage: View {
    let imageURL: String?
    let size: CGFloat
    let placeholderTint: Color

    var body: some View {
        Group {
            if let imageURL,
               !imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()

                    case .empty:
                        placeholder

                    case .failure:
                        placeholder

                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.18))
            .overlay(
                Image(systemName: "person.fill")
                    .foregroundColor(placeholderTint.opacity(0.8))
            )
    }
}
