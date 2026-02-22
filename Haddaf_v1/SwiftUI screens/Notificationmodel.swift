import Foundation
import FirebaseFirestore

// MARK: - Notification Type
enum NotificationType: String, Codable {
    case adminMonthlyReminder = "admin_monthly_reminder"
    case playerChallengeSubmitted = "player_challenge_submitted"
    case challengeEnded = "challenge_ended"
    case newChallengeAvailable = "new_challenge_available"
    case teamInvitation = "team_invitation"
    case invitationAccepted = "invitation_accepted"
    case invitationDeclined = "invitation_declined"
    case removedFromTeam = "removed_from_team"
    case goalAchieved = "goal_achieved"
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
        teamName: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.type = type
        self.title = title
        self.message = message
        self.createdAt = createdAt
        self.isRead = isRead
        self.challengeId = challengeId
        self.challengeTitle = challengeTitle
        self.monthName = monthName
        self.invitationId = invitationId
        self.teamId = teamId
        self.teamName = teamName
    }

    var asDictionary: [String: Any] {
        var dict: [String: Any] = [
            "userId": userId,
            "type": type.rawValue,
            "title": title,
            "message": message,
            "createdAt": Timestamp(date: createdAt),
            "isRead": isRead
        ]
        if let v = challengeId { dict["challengeId"] = v }
        if let v = challengeTitle { dict["challengeTitle"] = v }
        if let v = monthName { dict["monthName"] = v }
        if let v = invitationId { dict["invitationId"] = v }
        if let v = teamId { dict["teamId"] = v }
        if let v = teamName { dict["teamName"] = v }
        return dict
    }

    static func from(doc: QueryDocumentSnapshot) -> HaddafNotification? {
        let data = doc.data()
        guard
            let userId = data["userId"] as? String,
            let typeRaw = data["type"] as? String,
            let type = NotificationType(rawValue: typeRaw),
            let title = data["title"] as? String,
            let message = data["message"] as? String,
            let timestamp = data["createdAt"] as? Timestamp
        else { return nil }

        return HaddafNotification(
            id: doc.documentID,
            userId: userId,
            type: type,
            title: title,
            message: message,
            createdAt: timestamp.dateValue(),
            isRead: data["isRead"] as? Bool ?? false,
            challengeId: data["challengeId"] as? String,
            challengeTitle: data["challengeTitle"] as? String,
            monthName: data["monthName"] as? String,
            invitationId: data["invitationId"] as? String,
            teamId: data["teamId"] as? String,
            teamName: data["teamName"] as? String
        )
    }
}
