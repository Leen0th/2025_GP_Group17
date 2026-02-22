import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Notification Service
class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published var notifications: [HaddafNotification] = []
    @Published var unreadCount: Int = 0
    @Published var isLoading = false

    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Check User Notification Settings
    private static func shouldSendNotification(userId: String, type: NotificationType) async -> Bool {
        do {
            let userDoc = try await Firestore.firestore().collection("users").document(userId).getDocument()
            guard let data = userDoc.data() else { return true }
            switch type {
            case .newChallengeAvailable: return data["notif_newChallenge"] as? Bool ?? true
            case .challengeEnded: return data["notif_challengeEnded"] as? Bool ?? true
            default: return true
            }
        } catch { return true }
    }

    // MARK: - Start Listening
    func startListening(for userId: String) {
        stopListening()
        isLoading = true
        listener = db.collection("notifications")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                self.isLoading = false
                guard let snapshot = snapshot else { return }
                self.notifications = snapshot.documents.compactMap { HaddafNotification.from(doc: $0) }
                self.unreadCount = self.notifications.filter { !$0.isRead }.count
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Mark as Read
    func markAsRead(notificationId: String) async {
        try? await db.collection("notifications").document(notificationId).updateData(["isRead": true])
    }

    func markAllAsRead(userId: String) async {
        for notification in notifications {
            await deleteNotification(notificationId: notification.id)
        }
    }

    func deleteNotification(notificationId: String) async {
        try? await db.collection("notifications").document(notificationId).delete()
    }

    // MARK: - Send Admin Monthly Reminder
    static func sendAdminMonthlyReminder(adminId: String) async {
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        let monthName = nextMonth.formatted(.dateTime.month(.wide))
        let notification = HaddafNotification(
            userId: adminId, type: .adminMonthlyReminder,
            title: "📅 Monthly Challenge Reminder",
            message: "It's time to add a new challenge for \(monthName)!",
            monthName: monthName
        )
        try? await Firestore.firestore().collection("notifications").document(notification.id).setData(notification.asDictionary)
    }

    // MARK: - Send New Challenge Notification
    static func sendNewChallengeNotification(userId: String, challengeId: String, challengeTitle: String, monthName: String) async {
        guard await shouldSendNotification(userId: userId, type: .newChallengeAvailable) else { return }
        let notification = HaddafNotification(
            userId: userId, type: .newChallengeAvailable,
            title: "🎯 New Challenge Available!",
            message: "A new challenge for \(monthName) has been added: \(challengeTitle). Check it out now!",
            challengeId: challengeId, challengeTitle: challengeTitle, monthName: monthName
        )
        try? await Firestore.firestore().collection("notifications").document(notification.id).setData(notification.asDictionary)
    }

    // MARK: - Send Challenge Submitted Notification
    static func sendChallengeSubmittedNotification(userId: String, challengeId: String, challengeTitle: String, monthName: String) async {
        let notification = HaddafNotification(
            userId: userId, type: .playerChallengeSubmitted,
            title: "✅ Challenge Submitted",
            message: "You have submitted your video for the \(monthName) challenge: \(challengeTitle)",
            challengeId: challengeId, challengeTitle: challengeTitle, monthName: monthName
        )
        try? await Firestore.firestore().collection("notifications").document(notification.id).setData(notification.asDictionary)
    }

    // MARK: - Send Challenge Ended Notification
    static func sendChallengeEndedNotification(userId: String, challengeId: String, challengeTitle: String, monthName: String) async {
        guard await shouldSendNotification(userId: userId, type: .challengeEnded) else { return }
        let notification = HaddafNotification(
            userId: userId, type: .challengeEnded,
            title: "🏆 Challenge Ended",
            message: "The \(monthName) challenge has ended and winners have been announced! Check out the results now.",
            challengeId: challengeId, challengeTitle: challengeTitle, monthName: monthName
        )
        try? await Firestore.firestore().collection("notifications").document(notification.id).setData(notification.asDictionary)
    }

    // MARK: - ✨ Send Team Invitation Notification (to player)
    static func sendInvitationNotification(playerUID: String, coachUID: String, teamName: String, invitationId: String) async {
        // Fetch coach name
        var coachName = "A coach"
        if let doc = try? await Firestore.firestore().collection("users").document(coachUID).getDocument(),
           let data = doc.data() {
            let fn = data["firstName"] as? String ?? ""
            let ln = data["lastName"] as? String ?? ""
            coachName = "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)
        }

        let notification = HaddafNotification(
            userId: playerUID,
            type: .teamInvitation,
            title: "⚽ Team Invitation",
            message: "\(coachName) has invited you to join \(teamName). Accept or decline the invitation.",
            invitationId: invitationId,
            teamName: teamName
        )
        try? await Firestore.firestore().collection("notifications").document(notification.id).setData(notification.asDictionary)
    }

    // MARK: - ✨ Send Invitation Response Notification (to coach)
    static func sendInvitationResponseNotification(coachUID: String, playerUID: String, teamName: String, accepted: Bool) async {
        // Fetch player name
        var playerName = "A player"
        if let doc = try? await Firestore.firestore().collection("users").document(playerUID).getDocument(),
           let data = doc.data() {
            let fn = data["firstName"] as? String ?? ""
            let ln = data["lastName"] as? String ?? ""
            playerName = "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)
        }

        let notification = HaddafNotification(
            userId: coachUID,
            type: accepted ? .invitationAccepted : .invitationDeclined,
            title: accepted ? "✅ Invitation Accepted" : "❌ Invitation Declined",
            message: accepted
                ? "\(playerName) accepted your invitation and joined \(teamName)!"
                : "\(playerName) declined your invitation to join \(teamName).",
            teamName: teamName
        )
        try? await Firestore.firestore().collection("notifications").document(notification.id).setData(notification.asDictionary)
    }

    // MARK: - Send Removed From Team Notification (to player)
    static func sendRemovedFromTeamNotification(playerUID: String, teamName: String) async {
        let notification = HaddafNotification(
            userId: playerUID,
            type: .removedFromTeam,
            title: "🚫 Removed from Team",
            message: "You have been removed from \(teamName).",
            teamName: teamName
        )
        try? await Firestore.firestore().collection("notifications").document(notification.id).setData(notification.asDictionary)
    }

    // MARK: - Check and Send Challenge Ended Notifications
    static func checkAndSendChallengeEndedNotifications() async {
        let db = Firestore.firestore()
        do {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            let snap = try await db.collection("challenges")
                .whereField("endAt", isLessThan: Timestamp(date: Date()))
                .whereField("endAt", isGreaterThan: Timestamp(date: yesterday))
                .getDocuments()

            for challengeDoc in snap.documents {
                let challengeId = challengeDoc.documentID
                let challengeTitle = challengeDoc.data()["title"] as? String ?? "Challenge"
                let startTimestamp = challengeDoc.data()["startAt"] as? Timestamp
                let startDate = startTimestamp?.dateValue() ?? Date()
                let monthName = startDate.formatted(.dateTime.month(.wide))

                let existing = try await db.collection("notifications")
                    .whereField("type", isEqualTo: NotificationType.challengeEnded.rawValue)
                    .whereField("challengeId", isEqualTo: challengeId)
                    .getDocuments()
                if !existing.documents.isEmpty { continue }

                let submissions = try await db.collection("challenges").document(challengeId).collection("submissions").getDocuments()
                let userIds = Set(submissions.documents.compactMap { $0.data()["uid"] as? String })
                for userId in userIds {
                    await sendChallengeEndedNotification(userId: userId, challengeId: challengeId, challengeTitle: challengeTitle, monthName: monthName)
                }
            }
        } catch { print("Error: \(error)") }
    }
}
