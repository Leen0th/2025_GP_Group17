import Foundation
import FirebaseFirestore

// MARK: - Notification Type
enum NotificationType: String, Codable {
    case adminMonthlyReminder    = "admin_monthly_reminder"
    case playerChallengeSubmitted = "player_challenge_submitted"
    case challengeEnded          = "challenge_ended"
    case newChallengeAvailable   = "new_challenge_available"
    case academyInvitation       = "academy_invitation"
    case invitationAccepted      = "invitation_accepted"
    case invitationDeclined      = "invitation_declined"
    case removedFromTeam         = "removed_from_team"
    case goalAchieved            = "goal_achieved"
    case warning                 = "warning"
    case contentDeleted          = "content_deleted"
    case matchJoinRequested      = "match_join_requested"
    case matchJoinApproved       = "match_join_approved"
    case matchJoinRejected       = "match_join_rejected"
    case matchCancelled          = "match_cancelled"
    case upcomingMatchReminder   = "upcoming_match_reminder"
}

// MARK: - Notification Model
struct HaddafNotification: Identifiable, Codable {
    let id: String
    let userId: String
    let type: NotificationType
    let title: String
    let message: String
    let createdAt: Date
    var isRead: Bool

    // Optional fields
    let challengeId: String?
    let challengeTitle: String?
    let monthName: String?
    let invitationId: String?
    let teamId: String?
    let teamName: String?
    let academyId: String?
    let category: String?
    // Match-related
    let matchId: String?
    let requestedPosition: String?
    let senderId: String?
    let senderName: String?

    init(
        id: String = UUID().uuidString,
        userId: String,
        type: NotificationType,
        title: String,
        message: String,
        createdAt: Date = Date(),
        isRead: Bool = false,
        challengeId: String? = nil,
        challengeTitle: String? = nil,
        monthName: String? = nil,
        invitationId: String? = nil,
        teamId: String? = nil,
        teamName: String? = nil,
        academyId: String? = nil,
        category: String? = nil,
        matchId: String? = nil,
        requestedPosition: String? = nil,
        senderId: String? = nil,
        senderName: String? = nil
    ) {
        self.id               = id
        self.userId           = userId
        self.type             = type
        self.title            = title
        self.message          = message
        self.createdAt        = createdAt
        self.isRead           = isRead
        self.challengeId      = challengeId
        self.challengeTitle   = challengeTitle
        self.monthName        = monthName
        self.invitationId     = invitationId
        self.teamId           = teamId
        self.teamName         = teamName
        self.academyId        = academyId
        self.category         = category
        self.matchId          = matchId
        self.requestedPosition = requestedPosition
        self.senderId         = senderId
        self.senderName       = senderName
    }

    var asDictionary: [String: Any] {
        var dict: [String: Any] = [
            "userId":    userId,
            "type":      type.rawValue,
            "title":     title,
            "message":   message,
            "createdAt": Timestamp(date: createdAt),
            "isRead":    isRead
        ]
        if let v = challengeId      { dict["challengeId"]       = v }
        if let v = challengeTitle   { dict["challengeTitle"]    = v }
        if let v = monthName        { dict["monthName"]         = v }
        if let v = invitationId     { dict["invitationId"]      = v }
        if let v = teamId           { dict["teamId"]            = v }
        if let v = teamName         { dict["teamName"]          = v }
        if let v = academyId        { dict["academyId"]         = v }
        if let v = category         { dict["category"]          = v }
        if let v = matchId          { dict["matchId"]           = v }
        if let v = requestedPosition { dict["requestedPosition"] = v }
        if let v = senderId         { dict["senderId"]          = v }
        if let v = senderName       { dict["senderName"]        = v }
        return dict
    }

    static func from(doc: QueryDocumentSnapshot) -> HaddafNotification? {
        let data = doc.data()
        guard let userId = data["userId"] as? String else {
            print("❌ notif \(doc.documentID): missing userId"); return nil
        }
        guard let typeRaw = data["type"] as? String else {
            print("❌ notif \(doc.documentID): missing type"); return nil
        }
        guard let type = NotificationType(rawValue: typeRaw) else {
            print("❌ notif \(doc.documentID): unknown type '\(typeRaw)'"); return nil
        }
        guard let title = data["title"] as? String else {
            print("❌ notif \(doc.documentID): missing title"); return nil
        }
        guard let message = data["message"] as? String ?? data["body"] as? String else {
            print("❌ notif \(doc.documentID): missing message/body"); return nil
        }
        guard let timestamp = data["createdAt"] as? Timestamp else {
            print("❌ notif \(doc.documentID): missing createdAt"); return nil
        }

        return HaddafNotification(
            id:                doc.documentID,
            userId:            userId,
            type:              type,
            title:             title,
            message:           message,
            createdAt:         timestamp.dateValue(),
            isRead:            data["isRead"]            as? Bool   ?? false,
            challengeId:       data["challengeId"]       as? String,
            challengeTitle:    data["challengeTitle"]    as? String,
            monthName:         data["monthName"]         as? String,
            invitationId:      data["invitationId"]      as? String,
            teamId:            data["teamId"]            as? String,
            teamName:          data["teamName"]          as? String,
            academyId:         data["academyId"]         as? String,
            category:          data["category"]          as? String,
            matchId:           data["matchId"]           as? String,
            requestedPosition: data["requestedPosition"] as? String,
            senderId:          data["senderId"]          as? String,
            senderName:        data["senderName"]        as? String
        )
    }
}
