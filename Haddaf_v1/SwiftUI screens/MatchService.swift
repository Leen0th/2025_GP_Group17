import Foundation
import FirebaseFirestore
import FirebaseAuth

final class MatchService {
    static let shared = MatchService()
    private let db = Firestore.firestore()
    private init() {}

    func createMatch(
        organizerId: String,
        organizerName: String,
        organizerRole: String,
        title: String,                 // ✅ جديد
        dateTime: Date,
        place: MatchPlace,
        positions: [String: Int]
    ) async throws {
        let cleaned = positions.filter { $0.value > 0 }

        var data: [String: Any] = [
            "title":            title,                         // ✅ جديد
            "createdBy":        organizerId,
            "createdByName":    organizerName,
            "createdByRole":    organizerRole,
            "dateTime":         Timestamp(date: dateTime),
            "locationName":     place.name,
            "locationAddress":  place.address,
            "status":           MatchStatus.open.rawValue,
            "openPositions":    cleaned,
            "totalPositions":   cleaned,
            "acceptedCounts":   cleaned.mapValues { _ in 0 },
            "participantIds":   [],
            "createdAt":        FieldValue.serverTimestamp(),
            "updatedAt":        FieldValue.serverTimestamp()
        ]

        if let lat = place.latitude  { data["locationLat"] = lat }
        if let lng = place.longitude { data["locationLng"] = lng }

        try await db.collection("matches").addDocument(data: data)
    }

    func requestJoin(
        match: MatchOpportunity,
        playerId: String,
        playerName: String,
        playerProfilePic: String?,
        position: MatchPosition
    ) async throws {
        let existing = try await db.collection("match_requests")
            .whereField("matchId", isEqualTo: match.id)
            .whereField("playerId", isEqualTo: playerId)
            .whereField("status", in: [MatchRequestStatus.pending.rawValue, MatchRequestStatus.approved.rawValue])
            .getDocuments()

        guard existing.documents.isEmpty else { return }

        var requestData: [String: Any] = [
            "matchId":           match.id,
            "organizerId":       match.createdBy,
            "playerId":          playerId,
            "playerName":        playerName,
            "requestedPosition": position.rawValue,
            "status":            MatchRequestStatus.pending.rawValue,
            "createdAt":         FieldValue.serverTimestamp(),
            "updatedAt":         FieldValue.serverTimestamp()
        ]
        if let pic = playerProfilePic { requestData["playerProfilePic"] = pic }

        let requestRef = try await db.collection("match_requests").addDocument(data: requestData)

        await NotificationService.sendMatchJoinRequestedNotification(
            organizerId:  match.createdBy,
            senderId:     playerId,
            senderName:   playerName,
            matchId:      match.id,
            locationName: match.locationName,
            position:     position.title,
            requestId:    requestRef.documentID
        )
    }

    func cancelPendingRequest(requestId: String) async throws {
        try await db.collection("match_requests").document(requestId).updateData([
            "status":    MatchRequestStatus.cancelled.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    func rejectRequest(_ request: MatchJoinRequest, match: MatchOpportunity) async throws {
        try await db.collection("match_requests").document(request.id).updateData([
            "status":    MatchRequestStatus.rejected.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])

        await NotificationService.sendMatchJoinRejectedNotification(
            userId:       request.playerId,
            organizerName: match.createdByName,
            matchId:      match.id,
            locationName: match.locationName,
            position:     request.requestedPosition
        )
    }

    func cancelApprovedRequest(
        request: MatchJoinRequest,
        match: MatchOpportunity
    ) async throws {

        let matchRef   = db.collection("matches").document(match.id)
        let requestRef = db.collection("match_requests").document(request.id)

        try await db.runTransaction { (transaction, errorPointer) -> Any? in

            let snap: DocumentSnapshot
            do {
                snap = try transaction.getDocument(matchRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            guard var openPositions  = snap.data()?["openPositions"]  as? [String: Int],
                  var acceptedCounts = snap.data()?["acceptedCounts"] as? [String: Int]
            else { return nil }

            let position = request.requestedPosition

            openPositions[position]  = (openPositions[position]  ?? 0) + 1
            acceptedCounts[position] = max((acceptedCounts[position] ?? 1) - 1, 0)

            let hasOpenSlots = openPositions.values.contains { $0 > 0 }

            transaction.updateData([
                "openPositions":  openPositions,
                "acceptedCounts": acceptedCounts,
                "participantIds": FieldValue.arrayRemove([request.playerId]),
                "status": hasOpenSlots ? MatchStatus.open.rawValue : MatchStatus.closed.rawValue,
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: matchRef)

            transaction.updateData([
                "status":    MatchRequestStatus.cancelled.rawValue,
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: requestRef)

            return nil
        }
    }

    func approveRequest(_ request: MatchJoinRequest, match: MatchOpportunity) async throws {
        let matchRef   = db.collection("matches").document(match.id)
        let requestRef = db.collection("match_requests").document(request.id)

        try await db.runTransaction { (transaction, errorPointer) -> Any? in

            let snap: DocumentSnapshot
            do {
                snap = try transaction.getDocument(matchRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            guard let data = snap.data(),
                  var openPositions  = data["openPositions"]  as? [String: Int],
                  var acceptedCounts = data["acceptedCounts"] as? [String: Int]
            else {
                return nil
            }

            let position = request.requestedPosition
            let currentOpen = openPositions[position] ?? 0

            if currentOpen <= 0 {
                transaction.updateData([
                    "status": MatchStatus.closed.rawValue
                ], forDocument: matchRef)

                transaction.updateData([
                    "status": MatchRequestStatus.rejected.rawValue
                ], forDocument: requestRef)

                return nil
            }

            openPositions[position] = currentOpen - 1
            acceptedCounts[position] = (acceptedCounts[position] ?? 0) + 1

            let allClosed = openPositions.values.allSatisfy { $0 <= 0 }

            transaction.updateData([
                "openPositions": openPositions,
                "acceptedCounts": acceptedCounts,
                "participantIds": FieldValue.arrayUnion([request.playerId]),
                "status": allClosed ? MatchStatus.closed.rawValue : MatchStatus.open.rawValue
            ], forDocument: matchRef)

            transaction.updateData([
                "status": MatchRequestStatus.approved.rawValue
            ], forDocument: requestRef)

            return nil
        }

        await NotificationService.sendMatchJoinApprovedNotification(
            userId: request.playerId,
            organizerName: match.createdByName,
            matchId: match.id,
            locationName: match.locationName,
            position: request.requestedPosition
        )
    }

    func cancelMatch(_ match: MatchOpportunity) async throws {
        let matchRef = db.collection("matches").document(match.id)

        // 1. Mark match as cancelled
        try await matchRef.updateData([
            "status":    MatchStatus.cancelled.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])

        // 2. Get all accepted/pending requests for this match
        let requestsSnap = try await db.collection("match_requests")
            .whereField("matchId", isEqualTo: match.id)
            .whereField("status", in: [
                MatchRequestStatus.approved.rawValue,
                MatchRequestStatus.pending.rawValue
            ])
            .getDocuments()

        // 3. Cancel all requests in a batch
        let batch = db.batch()
        for doc in requestsSnap.documents {
            batch.updateData([
                "status":    MatchRequestStatus.cancelled.rawValue,
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: doc.reference)
        }
        try await batch.commit()

        // 4. Send cancellation notification to each affected player
        for doc in requestsSnap.documents {
            if let playerId = doc.data()["playerId"] as? String {
                await NotificationService.sendMatchCancelledNotification(
                    userId:        playerId,
                    organizerName: match.createdByName,
                    matchId:       match.id,
                    locationName:  match.locationName,
                    dateTime:      match.dateTime
                )
            }
        }
    }
}
