import Foundation
import FirebaseFirestore
import FirebaseAuth
import UserNotifications

// MARK: - Client-Side Notification Scheduler
class ClientNotificationScheduler {
    static let shared = ClientNotificationScheduler()
    private let db = Firestore.firestore()

    // Fixed identifier so we can cancel and reschedule the same reminder
    private let localNotifIdentifier = "admin_challenge_reminder"

    private init() {}

    // MARK: - Schedule Local Reminder
    // Called every time the app opens.
    // Schedules a local notification on the admin's device for the 25th of next month.
    // If a challenge already exists for next month, cancels any pending reminder instead.
    func scheduleAdminLocalReminder() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        // Make sure the logged-in user is an admin
        guard let userDoc = try? await db.collection("users").document(currentUserId).getDocument(),
              let role = userDoc.data()?["role"] as? String, role == "admin" else { return }

        let calendar = Calendar.current
        let now = Date()

        // Calculate next month's year and month
        guard let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: now) else { return }
        let nextMonthInt = calendar.component(.month, from: nextMonthDate)
        let nextYear     = calendar.component(.year,  from: nextMonthDate)
        let ym = String(format: "%04d-%02d", nextYear, nextMonthInt)

        // If a challenge already exists for next month, cancel the pending reminder and bail out
        if let snap = try? await db.collection("challenges")
            .whereField("yearMonth", isEqualTo: ym)
            .limit(to: 1)
            .getDocuments(), !snap.documents.isEmpty {
            cancelLocalReminder()
            print("ℹ️ Challenge exists for \(ym) — local reminder cancelled")
            return
        }

        // Request notification permission if not already granted
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else {
            print("⚠️ Notification permission denied — can't schedule reminder")
            return
        }

        // Build the fire date: the 25th of next month at 9:00 AM
        var components = DateComponents()
        components.year   = nextYear
        components.month  = nextMonthInt
        components.day    = 25
        components.hour   = 9
        components.minute = 0
        components.second = 0

        guard let fireDate = calendar.date(from: components) else { return }

        // If the 25th has already passed (e.g. admin opened the app on the 26th+), skip scheduling
        guard fireDate > now else {
            print("ℹ️ Day 25 already passed this month — no reminder scheduled")
            return
        }

        // Remove any previously scheduled reminder before adding a fresh one
        cancelLocalReminder()

        // Build the notification content
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM"
        let monthName = formatter.string(from: nextMonthDate)

        let content = UNMutableNotificationContent()
        content.title = "Challenge Reminder 🏆"
        content.body  = "Don't forget to add the \(monthName) challenge!"
        content.sound = .default

        // Trigger: fires once at the exact calendar date/time
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            ),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: localNotifIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            print("✅ Local admin reminder scheduled for \(fireDate)")
        } catch {
            print("❌ Failed to schedule local reminder: \(error.localizedDescription)")
        }
    }

    // MARK: - Cancel Local Reminder
    // Removes the pending local notification from the system queue
    func cancelLocalReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [localNotifIdentifier])
    }

    // MARK: - Check Ended Challenges
    // Sends in-app notifications to all participants when a challenge ends
    func checkEndedChallenges() async {
        do {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()

            // Fetch challenges that ended within the last 24 hours
            let challengesSnapshot = try await db.collection("challenges")
                .whereField("endAt", isLessThan: Timestamp(date: Date()))
                .whereField("endAt", isGreaterThan: Timestamp(date: yesterday))
                .getDocuments()

            for challengeDoc in challengesSnapshot.documents {
                let challengeId    = challengeDoc.documentID
                let challengeTitle = challengeDoc.data()["title"] as? String ?? "Challenge"
                let startTimestamp = challengeDoc.data()["startAt"] as? Timestamp
                let startDate      = startTimestamp?.dateValue() ?? Date()
                let monthName      = startDate.formatted(.dateTime.month(.wide))

                // Skip if notifications were already sent for this challenge
                let existingNotifs = try await db.collection("notifications")
                    .whereField("type",        isEqualTo: "challenge_ended")
                    .whereField("challengeId", isEqualTo: challengeId)
                    .limit(to: 1)
                    .getDocuments()

                if !existingNotifs.documents.isEmpty {
                    print("⏭️ Notifications already sent for: \(challengeTitle)")
                    continue
                }

                // Get all users who submitted to this challenge
                let submissionsSnapshot = try await db.collection("challenges")
                    .document(challengeId)
                    .collection("submissions")
                    .getDocuments()

                let userIds = Set(submissionsSnapshot.documents.compactMap {
                    $0.data()["uid"] as? String
                })

                for userId in userIds {
                    await NotificationService.sendChallengeEndedNotification(
                        userId: userId,
                        challengeId: challengeId,
                        challengeTitle: challengeTitle,
                        monthName: monthName
                    )
                }

                print("✅ Sent \(userIds.count) ended-challenge notifications for: \(challengeTitle)")
            }
        } catch {
            print("❌ Error checking ended challenges: \(error.localizedDescription)")
        }
    }

    // MARK: - Check New Challenges That Just Started
    // Sends in-app notifications to all players when a challenge becomes active
    func checkAndSendNewChallengeNotifications() async {
        do {
            let now       = Date()
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now

            // Fetch challenges that started within the last 24 hours
            let challengesSnapshot = try await db.collection("challenges")
                .whereField("startAt", isLessThanOrEqualTo: Timestamp(date: now))
                .whereField("startAt", isGreaterThan: Timestamp(date: yesterday))
                .getDocuments()

            for challengeDoc in challengesSnapshot.documents {
                let challengeId    = challengeDoc.documentID
                let challengeTitle = challengeDoc.data()["title"] as? String ?? "Challenge"
                let startTimestamp = challengeDoc.data()["startAt"] as? Timestamp
                let startDate      = startTimestamp?.dateValue() ?? Date()
                let monthName      = startDate.formatted(.dateTime.month(.wide))

                // Skip if notifications were already sent for this challenge
                let notificationExists = try await db.collection("notifications")
                    .whereField("type",        isEqualTo: "new_challenge_available")
                    .whereField("challengeId", isEqualTo: challengeId)
                    .limit(to: 1)
                    .getDocuments()

                if !notificationExists.documents.isEmpty {
                    print("⏭️ Already sent for: \(challengeTitle)")
                    continue
                }

                // Send to every player
                let usersSnapshot = try await db.collection("users")
                    .whereField("role", isEqualTo: "player")
                    .getDocuments()

                for userDoc in usersSnapshot.documents {
                    await NotificationService.sendNewChallengeNotification(
                        userId: userDoc.documentID,
                        challengeId: challengeId,
                        challengeTitle: challengeTitle,
                        monthName: monthName
                    )
                }

                print("✅ Sent \(usersSnapshot.documents.count) new-challenge notifications for: \(challengeTitle)")
            }
        } catch {
            print("❌ Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Check Upcoming Matches (Reminder 24h Before)
    // Sends a reminder to all match participants 24 hours before the match starts
    func checkUpcomingMatchReminders() async {
        do {
            let now   = Date()
            let in24h = Calendar.current.date(byAdding: .hour, value: 24, to: now) ?? now
            let in23h = Calendar.current.date(byAdding: .hour, value: 23, to: now) ?? now

            // Fetch open matches starting within the next 23–24 hours
            let matchesSnapshot = try await db.collection("matches")
                .whereField("dateTime", isGreaterThan:       Timestamp(date: in23h))
                .whereField("dateTime", isLessThanOrEqualTo: Timestamp(date: in24h))
                .whereField("status",   isEqualTo: "open")
                .getDocuments()

            for matchDoc in matchesSnapshot.documents {
                let matchId        = matchDoc.documentID
                let data           = matchDoc.data()
                let locationName   = data["locationName"]   as? String ?? "Unknown location"
                let organizerId    = data["createdBy"]      as? String ?? ""
                let participantIds = data["participantIds"] as? [String] ?? []
                let matchDate      = (data["dateTime"] as? Timestamp)?.dateValue() ?? now

                // Skip if reminder was already sent for this match
                let existingNotifs = try await db.collection("notifications")
                    .whereField("type",    isEqualTo: "upcoming_match_reminder")
                    .whereField("matchId", isEqualTo: matchId)
                    .limit(to: 1)
                    .getDocuments()

                if !existingNotifs.documents.isEmpty {
                    print("⏭️ Reminder already sent for match: \(matchId)")
                    continue
                }

                // Notify both the organizer and all participants
                var userIds = Set(participantIds)
                if !organizerId.isEmpty { userIds.insert(organizerId) }

                for userId in userIds {
                    // Respect the user's notification preference
                    let userDoc      = try? await db.collection("users").document(userId).getDocument()
                    let notifEnabled = userDoc?.data()?["notif_upcomingMatch"] as? Bool ?? true
                    guard notifEnabled else { continue }

                    await NotificationService.sendUpcomingMatchReminderNotification(
                        userId: userId,
                        matchId: matchId,
                        locationName: locationName,
                        date: matchDate
                    )
                }

                print("✅ Sent upcoming match reminders for match: \(matchId) to \(userIds.count) users")
            }
        } catch {
            print("❌ Error checking upcoming matches: \(error.localizedDescription)")
        }
    }

    // MARK: - 🧪 TEST ONLY — Delete this function after testing
    // Schedules a reminder to fire 2 minutes from now so you can verify
    // local notifications work without waiting until the 25th.
    // Usage: call from any onAppear temporarily, then remove.
    func scheduleTestReminder() async {
        let center = UNUserNotificationCenter.current()

        // Request permission
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else {
            print("⚠️ Permission denied")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Challenge Reminder 🏆"
        content.body  = "Don't forget to add next month's challenge!"
        content.sound = .default

        // Fires 2 minutes from now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 120, repeats: false)

        let request = UNNotificationRequest(
            identifier: "admin_challenge_reminder_test",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            print("✅ Test reminder scheduled — will fire in 2 minutes")
        } catch {
            print("❌ Failed: \(error.localizedDescription)")
        }
    }
    // MARK: - END TEST

    // MARK: - Start Periodic Checks
    // Called once when the app launches.
    // Schedules the admin local reminder (works even when the app is closed),
    // then starts an hourly timer for the checks that require the app to be open.
    func startPeriodicChecks() {
        Task {
            // Schedule the local reminder for the admin (fires even when app is closed)
            await scheduleAdminLocalReminder()

            // These checks only run while the app is open
            await checkEndedChallenges()
            await checkUpcomingMatchReminders()
        }

        // Re-check every hour to keep everything up to date
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task {
                await self?.scheduleAdminLocalReminder()
                await self?.checkEndedChallenges()
                await self?.checkUpcomingMatchReminders()
            }
        }

        print("✅ Periodic notification checks started")
    }
}
