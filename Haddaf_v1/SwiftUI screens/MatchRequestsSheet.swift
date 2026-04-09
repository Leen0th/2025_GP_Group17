import SwiftUI
import FirebaseFirestore

struct MatchRequestsSheet: View {
    let match: MatchOpportunity
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = MatchRequestsSheetViewModel()
    private let accent = BrandColors.darkTeal

    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()

                if vm.isLoading {
                    ProgressView().tint(accent)
                } else if vm.pendingRequests.isEmpty && vm.approvedRequests.isEmpty {
                    EmptyStateView(imageName: "person.badge.clock", message: "No requests yet")
                } else {
                    ScrollView {
                        VStack(spacing: 20) {

                            // ── ACCEPTED PLAYERS ──────────────────────────
                            if !vm.approvedRequests.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.system(size: 13))
                                        Text("Accepted Players (\(vm.approvedRequests.count))")
                                            .font(.system(size: 13, weight: .semibold))
                                    }

                                    ForEach(vm.approvedRequests) { request in
                                        HStack(spacing: 12) {
                                            Circle()
                                                .fill(Color.green.opacity(0.12))
                                                .frame(width: 40, height: 40)
                                                .overlay(
                                                    Image(systemName: "person.fill")
                                                        .foregroundColor(.green)
                                                )

                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(request.playerName)
                                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                Text(request.requestedPosition.capitalized)
                                                    .font(.system(size: 11, design: .rounded))
                                                    .foregroundColor(.secondary)
                                            }

                                            Spacer()

                                            Text("Accepted")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(.green)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(Color.green.opacity(0.1))
                                                .clipShape(Capsule())
                                        }
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                                    }
                                }
                            }

                            // ── PENDING REQUESTS ──────────────────────────
                            if !vm.pendingRequests.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "clock.fill")
                                            .foregroundColor(.orange)
                                            .font(.system(size: 13))
                                        Text("Pending Requests (\(vm.pendingRequests.count))")
                                            .font(.system(size: 13, weight: .semibold))
                                    }

                                    ForEach(vm.pendingRequests) { request in
                                        VStack(spacing: 10) {
                                            HStack(spacing: 12) {
                                                Circle()
                                                    .fill(accent.opacity(0.12))
                                                    .frame(width: 40, height: 40)
                                                    .overlay(
                                                        Image(systemName: "person.fill")
                                                            .foregroundColor(accent)
                                                    )

                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(request.playerName)
                                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                    Text(request.requestedPosition.capitalized)
                                                        .font(.system(size: 11, design: .rounded))
                                                        .foregroundColor(.secondary)
                                                }

                                                Spacer()

                                                Text("Pending")
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundColor(.orange)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 4)
                                                    .background(Color.orange.opacity(0.1))
                                                    .clipShape(Capsule())
                                            }

                                            HStack(spacing: 10) {
                                                Button("Reject") {
                                                    Task { await vm.reject(request, match: match) }
                                                }
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .foregroundColor(.red)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 9)
                                                .background(Color.red.opacity(0.08))
                                                .clipShape(Capsule())
                                                .buttonStyle(.plain)
                                                .disabled(vm.processingId == request.id)

                                                Button {
                                                    Task { await vm.approve(request, match: match) }
                                                } label: {
                                                    ZStack {
                                                        Text("Approve")
                                                            .opacity(vm.processingId == request.id ? 0 : 1)
                                                        if vm.processingId == request.id {
                                                            ProgressView().tint(.white).scaleEffect(0.7)
                                                        }
                                                    }
                                                }
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 9)
                                                .background(vm.processingId == request.id ? accent.opacity(0.5) : accent)
                                                .clipShape(Capsule())
                                                .buttonStyle(.plain)
                                                .disabled(vm.processingId == request.id)
                                            }
                                        }
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Match Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(accent)
                }
            }
            .task { await vm.load(matchId: match.id) }
        }
    }
}

// ─────────────────────────────────────────────────────────
@MainActor
final class MatchRequestsSheetViewModel: ObservableObject {
    @Published var pendingRequests:  [MatchJoinRequest] = []
    @Published var approvedRequests: [MatchJoinRequest] = []
    @Published var isLoading = true
    @Published var processingId: String? = nil

    /// Backward compat
    var requests: [MatchJoinRequest] { pendingRequests }

    private var listener: ListenerRegistration?
    deinit { listener?.remove() }

    func load(matchId: String) async {
        isLoading = true
        listener?.remove()

        // Real-time listener for both pending + approved
        listener = Firestore.firestore()
            .collection("match_requests")
            .whereField("matchId", isEqualTo: matchId)
            .whereField("status", in: [
                MatchRequestStatus.pending.rawValue,
                MatchRequestStatus.approved.rawValue
            ])
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                let all = snap?.documents.compactMap { MatchJoinRequest.from(doc: $0) } ?? []
                self.pendingRequests  = all.filter { $0.status == .pending }
                self.approvedRequests = all.filter { $0.status == .approved }
                self.isLoading = false
            }
    }

    func approve(_ request: MatchJoinRequest, match: MatchOpportunity) async {
        processingId = request.id
        try? await MatchService.shared.approveRequest(request, match: match)
        processingId = nil
        // Listener updates lists automatically
    }

    func reject(_ request: MatchJoinRequest, match: MatchOpportunity) async {
        processingId = request.id
        try? await MatchService.shared.rejectRequest(request, match: match)
        processingId = nil
    }
}
