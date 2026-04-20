import Foundation
import FirebaseFirestore

enum MatchPosition: String, CaseIterable, Codable, Identifiable {
    case attacker
    case midfielder
    case defender

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attacker: return "Attacker"
        case .midfielder: return "Midfielder"
        case .defender: return "Defender"
        }
    }

    var pluralTitle: String {
        switch self {
        case .attacker: return "Attackers"
        case .midfielder: return "Midfielders"
        case .defender: return "Defenders"
        }
    }
}

enum MatchStatus: String, Codable {
    case open
    case closed
    case cancelled
}

enum MatchRequestStatus: String, Codable {
    case pending
    case approved
    case rejected
    case cancelled
}

struct MatchOpportunity: Identifiable, Hashable {
    let id: String
    let title: String          // ✅ جديد
    let createdBy: String
    let createdByName: String
    let createdByRole: String

    let dateTime: Date
    let locationName: String
    let locationAddress: String
    let locationLat: Double?
    let locationLng: Double?
    let status: MatchStatus
    let openPositions: [String: Int]
    let totalPositions: [String: Int]
    let acceptedCounts: [String: Int]
    let participantIds: [String]
    let createdAt: Date
    let updatedAt: Date

    var isClosed: Bool { status != .open || remainingSlots == 0 }

    var remainingSlots: Int {
        MatchPosition.allCases.reduce(0) {
            $0 + (openPositions[$1.rawValue] ?? 0)
        }
    }

    func availableCount(for position: MatchPosition) -> Int {
        openPositions[position.rawValue] ?? 0
    }

    func totalCount(for position: MatchPosition) -> Int {
        totalPositions[position.rawValue] ?? 0
    }

    static func from(doc: QueryDocumentSnapshot) -> MatchOpportunity? {
        let data = doc.data()

        guard let createdBy = data["createdBy"] as? String,
              let createdByName = data["createdByName"] as? String,
              let createdByRole = data["createdByRole"] as? String,
              let ts = data["dateTime"] as? Timestamp,
              let locationName = data["locationName"] as? String,
              let locationAddress = data["locationAddress"] as? String,
              let statusRaw = data["status"] as? String,
              let status = MatchStatus(rawValue: statusRaw),
              let createdAtTS = data["createdAt"] as? Timestamp,
              let updatedAtTS = data["updatedAt"] as? Timestamp
        else { return nil }

        return MatchOpportunity(
            id: doc.documentID,
            title: data["title"] as? String ?? "",   // ✅ جديد — fallback فارغ للماتشات القديمة
            createdBy: createdBy,
            createdByName: createdByName,
            createdByRole: createdByRole,
            dateTime: ts.dateValue(),
            locationName: locationName,
            locationAddress: locationAddress,
            locationLat: data["locationLat"] as? Double,
            locationLng: data["locationLng"] as? Double,
            status: status,
            openPositions: data["openPositions"] as? [String: Int] ?? [:],
            totalPositions: data["totalPositions"] as? [String: Int] ?? [:],
            acceptedCounts: data["acceptedCounts"] as? [String: Int] ?? [:],
            participantIds: data["participantIds"] as? [String] ?? [],
            createdAt: createdAtTS.dateValue(),
            updatedAt: updatedAtTS.dateValue()
        )
    }
}

struct MatchJoinRequest: Identifiable, Hashable {
    let id: String
    let matchId: String
    let organizerId: String
    let playerId: String
    let playerName: String
    let playerProfilePic: String?
    let requestedPosition: String
    let status: MatchRequestStatus
    let createdAt: Date
    let updatedAt: Date

    static func from(doc: QueryDocumentSnapshot) -> MatchJoinRequest? {
        let data = doc.data()

        guard let matchId = data["matchId"] as? String,
              let organizerId = data["organizerId"] as? String,
              let playerId = data["playerId"] as? String,
              let playerName = data["playerName"] as? String,
              let requestedPosition = data["requestedPosition"] as? String,
              let statusRaw = data["status"] as? String,
              let status = MatchRequestStatus(rawValue: statusRaw),
              let createdAtTS = data["createdAt"] as? Timestamp,
              let updatedAtTS = data["updatedAt"] as? Timestamp
        else { return nil }

        return MatchJoinRequest(
            id: doc.documentID,
            matchId: matchId,
            organizerId: organizerId,
            playerId: playerId,
            playerName: playerName,
            playerProfilePic: data["playerProfilePic"] as? String,
            requestedPosition: requestedPosition,
            status: status,
            createdAt: createdAtTS.dateValue(),
            updatedAt: updatedAtTS.dateValue()
        )
    }
}

struct MatchPlace: Identifiable {
    var id = UUID()
    var name: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var placeID: String?
}
