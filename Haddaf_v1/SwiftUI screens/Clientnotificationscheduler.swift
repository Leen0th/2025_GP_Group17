import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Client-Side Notification Scheduler
class ClientNotificationScheduler {
    static let shared = ClientNotificationScheduler()
    private let db = Firestore.firestore()
    
    private init() {}
    
    // MARK: - Check and Send Monthly Admin Reminder (Smart Version)
    func checkAndSendMonthlyAdminReminder() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        do {
            // Check if current user is admin
            let userDoc = try await db.collection("users").document(currentUserId).getDocument()
            guard let role = userDoc.data()?["role"] as? String, role == "admin" else {
                return
            }
            
            let calendar = Calendar.current
            let now = Date()
            let currentDay = calendar.component(.day, from: now)
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)
            
            // ✨ Only send reminder on day 25 of each month
            guard currentDay == 25 else {
                return
            }
            
            // Calculate next month
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) ?? now
            let nextMonthInt = calendar.component(.month, from: nextMonth)
            let nextYear = calendar.component(.year, from: nextMonth)
            
            // Check if next month already has a challenge
            let ym = String(format: "%04d-%02d", nextYear, nextMonthInt)
            let challengeExists = try await db.collection("challenges")
                .whereField("yearMonth", isEqualTo: ym)
                .limit(to: 1)
                .getDocuments()
            
            // If challenge already exists for next month, don't send reminder
            if !challengeExists.documents.isEmpty {
                print("ℹ️ Challenge already exists for next month (\(ym))")
                return
            }
            
            // Check if we already sent notification this month
            let lastNotifications = try await db.collection("notifications")
                .whereField("userId", isEqualTo: currentUserId)
                .whereField("type", isEqualTo: "admin_monthly_reminder")
                .order(by: "createdAt", descending: true)
                .limit(to: 1)
                .getDocuments()
            
            if let lastNotif = lastNotifications.documents.first,
               let timestamp = lastNotif.data()["createdAt"] as? Timestamp {
                let lastDate = timestamp.dateValue()
                let lastMonth = calendar.component(.month, from: lastDate)
                let lastYear = calendar.component(.year, from: lastDate)
                
                // If already sent this month, skip
                if lastMonth == currentMonth && lastYear == currentYear {
                    print("ℹ️ Admin reminder already sent this month")
                    return
                }
            }
            
            // Send notification for next month
            await NotificationService.sendAdminMonthlyReminder(adminId: currentUserId)
            print("✅ Admin monthly reminder sent")
            
        } catch {
            print("❌ Error checking admin reminder: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Check Ended Challenges
    func checkEndedChallenges() async {
        do {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            
            // Get challenges that ended in last 24 hours
            let challengesSnapshot = try await db.collection("challenges")
                .whereField("endAt", isLessThan: Timestamp(date: Date()))
                .whereField("endAt", isGreaterThan: Timestamp(date: yesterday))
                .getDocuments()
            
            for challengeDoc in challengesSnapshot.documents {
                let challengeId = challengeDoc.documentID
                let challengeTitle = challengeDoc.data()["title"] as? String ?? "Challenge"
                
                // ✨ Get month name from startAt
                let startTimestamp = challengeDoc.data()["startAt"] as? Timestamp
                let startDate = startTimestamp?.dateValue() ?? Date()
                let monthName = startDate.formatted(.dateTime.month(.wide))
                
                // Check if we already sent notifications
                let existingNotifs = try await db.collection("notifications")
                    .whereField("type", isEqualTo: "challenge_ended")
                    .whereField("challengeId", isEqualTo: challengeId)
                    .limit(to: 1)
                    .getDocuments()
                
                if !existingNotifs.documents.isEmpty {
                    print("⏭️ Notifications already sent for: \(challengeTitle)")
                    continue
                }
                
                // Get all participants
                let submissionsSnapshot = try await db.collection("challenges")
                    .document(challengeId)
                    .collection("submissions")
                    .getDocuments()
                
                let userIds = Set(submissionsSnapshot.documents.compactMap { $0.data()["uid"] as? String })
                
                // Send notification to each user
                for userId in userIds {
                    await NotificationService.sendChallengeEndedNotification(
                        userId: userId,
                        challengeId: challengeId,
                        challengeTitle: challengeTitle,
                        monthName: monthName  // ✨ أضف اسم الشهر
                    )
                }
                
                print("✅ Sent \(userIds.count) notifications for: \(challengeTitle)")
            }
        } catch {
            print("❌ Error checking ended challenges: \(error.localizedDescription)")
        }
    }
    
    
    // MARK: - Check and Send Notifications for Newly Current Challenges
    // MARK: - Check New Challenges That Just Started
    func checkAndSendNewChallengeNotifications() async {
        do {
            let now = Date()
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
            
            // Get challenges that started in last 24 hours
            let challengesSnapshot = try await db.collection("challenges")
                .whereField("startAt", isLessThanOrEqualTo: Timestamp(date: now))
                .whereField("startAt", isGreaterThan: Timestamp(date: yesterday))
                .getDocuments()
            
            for challengeDoc in challengesSnapshot.documents {
                let challengeId = challengeDoc.documentID
                let challengeTitle = challengeDoc.data()["title"] as? String ?? "Challenge"
                let startTimestamp = challengeDoc.data()["startAt"] as? Timestamp
                let startDate = startTimestamp?.dateValue() ?? Date()
                let monthName = startDate.formatted(.dateTime.month(.wide))
                
                // Check if already sent
                let notificationExists = try await db.collection("notifications")
                    .whereField("type", isEqualTo: "new_challenge_available")
                    .whereField("challengeId", isEqualTo: challengeId)
                    .limit(to: 1)
                    .getDocuments()
                
                if !notificationExists.documents.isEmpty {
                    print("⏭️ Already sent for: \(challengeTitle)")
                    continue
                }
                
                // Get all players
                let usersSnapshot = try await db.collection("users")
                    .whereField("role", isEqualTo: "player")
                    .getDocuments()
                
                // Send to each player
                for userDoc in usersSnapshot.documents {
                    let playerId = userDoc.documentID
                    
                    await NotificationService.sendNewChallengeNotification(
                        userId: playerId,
                        challengeId: challengeId,
                        challengeTitle: challengeTitle,
                        monthName: monthName
                    )
                }
                
                print("✅ Sent \(usersSnapshot.documents.count) notifications for: \(challengeTitle)")
            }
        } catch {
            print("❌ Error: \(error.localizedDescription)")
        }
    }
    
    func startPeriodicChecks() {
        Task {
            await checkAndSendMonthlyAdminReminder()
            await checkEndedChallenges()
        }
        
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task {
                await self?.checkAndSendMonthlyAdminReminder()
                await self?.checkEndedChallenges()
            }
        }
        
        print("✅ Periodic notification checks started")
    }
}
