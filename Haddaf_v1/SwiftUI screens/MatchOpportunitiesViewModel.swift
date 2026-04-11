import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class MatchOpportunitiesViewModel: ObservableObject {
    @Published var matches: [MatchOpportunity] = []
    @Published var myRequests: [String: MatchJoinRequest] = [:]
    @Published var incomingRequests: [String: [MatchJoinRequest]] = [:]      // pending only (for badge)
    @Published var approvedRequests: [String: [MatchJoinRequest]] = [:]      // approved players per match
    @Published var isLoading = true
    @Published var errorMessage: String? = nil

    @Published var searchLocation = ""
    @Published var selectedPositionFilter: MatchPosition? = nil
    @Published var selectedDate: Date? = nil

    private let db = Firestore.firestore()
    private var matchListener: ListenerRegistration?
    private var myRequestsListener: ListenerRegistration?
    private var incomingRequestsListener: ListenerRegistration?
    private var approvedRequestsListener: ListenerRegistration?

    func startListening(currentUserId: String) {
        stopListening()
        isLoading = true

        // ── Matches ───────────────────────────────────────────────
        matchListener = db.collection("matches")
            .order(by: "dateTime", descending: false)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                self.isLoading = false
                if let err {
                    self.errorMessage = err.localizedDescription
                    return
                }
                self.matches = snap?.documents.compactMap { MatchOpportunity.from(doc: $0) } ?? []

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.objectWillChange.send()
                }
            }

        // ── My requests (as player) ───────────────────────────────
        myRequestsListener = db.collection("match_requests")
            .whereField("playerId", isEqualTo: currentUserId)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                let requests = snap?.documents.compactMap { MatchJoinRequest.from(doc: $0) } ?? []
                // Keep only the latest request per match (highest updatedAt wins)
                var dict: [String: MatchJoinRequest] = [:]
                for req in requests {
                    if let existing = dict[req.matchId] {
                        if req.updatedAt > existing.updatedAt { dict[req.matchId] = req }
                    } else {
                        dict[req.matchId] = req
                    }
                }
                self.myRequests = dict

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.objectWillChange.send()
                }
            }

        // ── Incoming PENDING requests (as organizer — for badge) ──
        incomingRequestsListener = db.collection("match_requests")
            .whereField("organizerId", isEqualTo: currentUserId)
            .whereField("status", isEqualTo: MatchRequestStatus.pending.rawValue)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                let items = snap?.documents.compactMap { MatchJoinRequest.from(doc: $0) } ?? []
                self.incomingRequests = Dictionary(grouping: items, by: { $0.matchId })

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.objectWillChange.send()
                }
            }

        // ── Incoming APPROVED requests (as organizer — for accepted list) ──
        approvedRequestsListener = db.collection("match_requests")
            .whereField("organizerId", isEqualTo: currentUserId)
            .whereField("status", isEqualTo: MatchRequestStatus.approved.rawValue)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                let items = snap?.documents.compactMap { MatchJoinRequest.from(doc: $0) } ?? []
                self.approvedRequests = Dictionary(grouping: items, by: { $0.matchId })

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.objectWillChange.send()
                }
            }
    }

    func stopListening() {
        matchListener?.remove()
        myRequestsListener?.remove()
        incomingRequestsListener?.remove()
        approvedRequestsListener?.remove()
    }

    func requestState(for matchId: String) -> MatchJoinRequest? {
        myRequests[matchId]
    }

    func pendingRequests(for matchId: String) -> [MatchJoinRequest] {
        incomingRequests[matchId] ?? []
    }

    func acceptedPlayers(for matchId: String) -> [MatchJoinRequest] {
        approvedRequests[matchId] ?? []
    }

    var filteredMatches: [MatchOpportunity] {
        var result = matches.filter { $0.status != .cancelled }

        let trimmedLocation = searchLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLocation.isEmpty {
            result = result.filter {
                $0.locationName.localizedCaseInsensitiveContains(trimmedLocation)
                || $0.locationAddress.localizedCaseInsensitiveContains(trimmedLocation)
                || $0.createdByName.localizedCaseInsensitiveContains(trimmedLocation)
            }
        }

        if let position = selectedPositionFilter {
            result = result.filter { ($0.openPositions[position.rawValue] ?? 0) > 0 }
        }

        if let selectedDate {
            result = result.filter {
                Calendar.current.isDate($0.dateTime, inSameDayAs: selectedDate)
            }
        }

        return result
    }
}
