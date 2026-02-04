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
            let userDoc = try await Firestore.firestore()
                .collection("users")
                .document(userId)
                .getDocument()
            
            guard let data = userDoc.data() else {
                return true // Default: send if no settings found
            }
            
            // Check based on notification type
            switch type {
            case .newChallengeAvailable:
                return data["notif_newChallenge"] as? Bool ?? true
                
            case .challengeEnded:
                return data["notif_challengeEnded"] as? Bool ?? true
                
            case .adminMonthlyReminder:
                return true // Always send to admin
                
            case .playerChallengeSubmitted:
                return true // Always send (own action confirmation)
            }
        } catch {
            print("❌ Error checking notification settings: \(error)")
            return true // Default: send on error
        }
    }
    
    // MARK: - Start Listening to Notifications
    func startListening(for userId: String) {
        stopListening()
        
        isLoading = true
        
        listener = db.collection("notifications")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                self.isLoading = false
                
                if let error = error {
                    print("❌ Error fetching notifications: \(error.localizedDescription)")
                    return
                }
                
                guard let snapshot = snapshot else {
                    print("⚠️ Snapshot is nil")
                    return
                }
                
                self.notifications = snapshot.documents.compactMap { doc in
                    HaddafNotification.from(doc: doc)
                }
                
                self.unreadCount = self.notifications.filter { !$0.isRead }.count
                
                print("✅ Loaded \(self.notifications.count) notifications, \(self.unreadCount) unread")
            }
    }
    
    // MARK: - Stop Listening
    func stopListening() {
        listener?.remove()
        listener = nil
    }
    
    // MARK: - Mark Notification as Read
    func markAsRead(notificationId: String) async {
        do {
            try await db.collection("notifications")
                .document(notificationId)
                .updateData(["isRead": true])
            
            print("✅ Notification marked as read: \(notificationId)")
        } catch {
            print("❌ Error marking notification as read: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Mark All Notifications as Read (Delete them)
    func markAllAsRead(userId: String) async {
        let allNotifications = notifications
        print("🗑️ Attempting to delete \(allNotifications.count) notifications")
        
        for notification in allNotifications {
            await deleteNotification(notificationId: notification.id)
        }
        
        print("✅ Finished deleting notifications")
    }
    
    // MARK: - Delete Notification
    func deleteNotification(notificationId: String) async {
        do {
            try await db.collection("notifications")
                .document(notificationId)
                .delete()
            
            print("✅ Notification deleted: \(notificationId)")
        } catch {
            print("❌ Error deleting notification: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Send Admin Monthly Reminder
    static func sendAdminMonthlyReminder(adminId: String) async {
        let calendar = Calendar.current
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        let monthName = nextMonth.formatted(.dateTime.month(.wide))
        
        let notification = HaddafNotification(
            userId: adminId,
            type: .adminMonthlyReminder,
            title: "📅 Monthly Challenge Reminder",
            message: "It's time to add a new challenge for \(monthName)!",
            monthName: monthName
        )
        
        do {
            try await Firestore.firestore()
                .collection("notifications")
                .document(notification.id)
                .setData(notification.asDictionary)
            
            print("✅ Admin monthly reminder sent for \(monthName)")
        } catch {
            print("❌ Error sending admin reminder: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Send New Challenge Available Notification
    static func sendNewChallengeNotification(
        userId: String,
        challengeId: String,
        challengeTitle: String,
        monthName: String
    ) async {
        // ✨ Check if user has this notification enabled
        let shouldSend = await shouldSendNotification(userId: userId, type: .newChallengeAvailable)
        
        guard shouldSend else {
            print("ℹ️ User \(userId) has disabled new challenge notifications")
            return
        }
        
        let notification = HaddafNotification(
            userId: userId,
            type: .newChallengeAvailable,
            title: "🎯 New Challenge Available!",
            message: "A new challenge for \(monthName) has been added: \(challengeTitle). Check it out now!",
            challengeId: challengeId,
            challengeTitle: challengeTitle,
            monthName: monthName
        )
        
        do {
            try await Firestore.firestore()
                .collection("notifications")
                .document(notification.id)
                .setData(notification.asDictionary)
            
            print("✅ New challenge notification sent to \(userId)")
        } catch {
            print("❌ Error sending new challenge notification: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Send Player Challenge Submitted Notification
    static func sendChallengeSubmittedNotification(
        userId: String,
        challengeId: String,
        challengeTitle: String,
        monthName: String
    ) async {
        let notification = HaddafNotification(
            userId: userId,
            type: .playerChallengeSubmitted,
            title: "✅ Challenge Submitted",
            message: "You have submitted your video for the \(monthName) challenge: \(challengeTitle)",
            challengeId: challengeId,
            challengeTitle: challengeTitle,
            monthName: monthName
        )
        
        do {
            try await Firestore.firestore()
                .collection("notifications")
                .document(notification.id)
                .setData(notification.asDictionary)
            
            print("✅ Player challenge submitted notification sent")
        } catch {
            print("❌ Error sending challenge submitted notification: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Send Challenge Ended Notification
    // MARK: - Send Challenge Ended Notification
    static func sendChallengeEndedNotification(
        userId: String,
        challengeId: String,
        challengeTitle: String,
        monthName: String
    ) async {
        // ✨ Check if user has this notification enabled
        let shouldSend = await shouldSendNotification(userId: userId, type: .challengeEnded)
        
        guard shouldSend else {
            print("ℹ️ User \(userId) has disabled challenge ended notifications")
            return
        }
        
        let notification = HaddafNotification(
            userId: userId,
            type: .challengeEnded,
            title: "🏆 Challenge Ended",
            message: "The \(monthName) challenge has ended and winners have been announced! Check out the results now.",
            challengeId: challengeId,
            challengeTitle: challengeTitle,
            monthName: monthName
        )
        
        do {
            try await Firestore.firestore()
                .collection("notifications")
                .document(notification.id)
                .setData(notification.asDictionary)
            
            print("✅ Challenge ended notification sent to \(userId)")
        } catch {
            print("❌ Error sending challenge ended notification: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Check and Send Challenge Ended Notifications
    static func checkAndSendChallengeEndedNotifications() async {
        let db = Firestore.firestore()
        
        do {
            // Get all challenges that ended recently (within last 24 hours)
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            
            let challengesSnapshot = try await db.collection("challenges")
                .whereField("endAt", isLessThan: Timestamp(date: Date()))
                .whereField("endAt", isGreaterThan: Timestamp(date: yesterday))
                .getDocuments()
            
            for challengeDoc in challengesSnapshot.documents {
                let challengeId = challengeDoc.documentID
                let challengeTitle = challengeDoc.data()["title"] as? String ?? "Challenge"
                
                // ✨ Get the start date to determine month name
                let startTimestamp = challengeDoc.data()["startAt"] as? Timestamp
                let startDate = startTimestamp?.dateValue() ?? Date()
                let monthName = startDate.formatted(.dateTime.month(.wide))
                
                // Check if we already sent notifications for this challenge
                let notificationExists = try await db.collection("notifications")
                    .whereField("type", isEqualTo: NotificationType.challengeEnded.rawValue)
                    .whereField("challengeId", isEqualTo: challengeId)
                    .getDocuments()
                
                if !notificationExists.documents.isEmpty {
                    print("⚠️ Notifications already sent for challenge: \(challengeId)")
                    continue
                }
                
                // Get all users who submitted to this challenge
                let submissionsSnapshot = try await db.collection("challenges")
                    .document(challengeId)
                    .collection("submissions")
                    .getDocuments()
                
                let userIds = Set(submissionsSnapshot.documents.compactMap { $0.data()["uid"] as? String })
                
                // Send notification to each user
                for userId in userIds {
                    await sendChallengeEndedNotification(
                        userId: userId,
                        challengeId: challengeId,
                        challengeTitle: challengeTitle,
                        monthName: monthName  // ✨ أضف اسم الشهر
                    )
                }
                
                print("✅ Sent challenge ended notifications to \(userIds.count) users for: \(challengeTitle)")
            }
        } catch {
            print("❌ Error checking/sending challenge ended notifications: \(error.localizedDescription)")
        }
    }
}
