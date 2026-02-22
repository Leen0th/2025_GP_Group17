import SwiftUI
import FirebaseAuth

// MARK: - Notifications View (Full Page with NavigationStack)
struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var notificationService = NotificationService.shared
    @EnvironmentObject var session: AppSession

    @State private var showDeleteConfirm = false
    @State private var notificationToDelete: HaddafNotification?
    @State private var navigateToInvitations = false

    private let accentColor = BrandColors.darkTeal

    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()

            if notificationService.isLoading {
                ProgressView().tint(accentColor)
                } else if notificationService.notifications.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(notificationService.notifications) { notification in
                                NotificationCard(
                                    notification: notification,
                                    onTap: {
                                        Task { await notificationService.markAsRead(notificationId: notification.id) }
                                        if notification.type == .teamInvitation {
                                            navigateToInvitations = true
                                        }
                                    },
                                    onDelete: {
                                        notificationToDelete = notification
                                        showDeleteConfirm = true
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Notifications")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(accentColor)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color(.systemGray6)))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !notificationService.notifications.isEmpty {
                        Button {
                            Task {
                                guard let userId = session.user?.uid else { return }
                                await notificationService.markAllAsRead(userId: userId)
                            }
                        } label: {
                            Text("Mark All Read")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(accentColor)
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $navigateToInvitations) {
                InvitationsView()
            }
            .confirmationDialog("Delete this notification?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let n = notificationToDelete {
                        Task { await notificationService.deleteNotification(notificationId: n.id) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear {
                if let userId = session.user?.uid { notificationService.startListening(for: userId) }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash").font(.system(size: 60)).foregroundColor(.secondary.opacity(0.5))
            Text("No Notifications")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text("You're all caught up!")
                .font(.system(size: 14, design: .rounded)).foregroundColor(.secondary)
        }
    }


// MARK: - Notification Card
struct NotificationCard: View {
    let notification: HaddafNotification
    let onTap: () -> Void
    let onDelete: () -> Void
    private let accentColor = BrandColors.darkTeal

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(notification.isRead ? Color.gray.opacity(0.15) : iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(notification.isRead ? .gray : iconColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(notification.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.primary)
                Text(notification.message)
                    .font(.system(size: 14, design: .rounded)).foregroundColor(.secondary).lineLimit(3)
                Text(timeAgoText(from: notification.createdAt))
                    .font(.system(size: 12, design: .rounded)).foregroundColor(.secondary.opacity(0.7))
                if notification.type == .teamInvitation {
                    Text("Tap to view invitation →")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(accentColor)
                }
            }

            Spacer()
            if !notification.isRead {
                Circle().fill(accentColor).frame(width: 10, height: 10)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(notification.isRead ? 0.05 : 0.1), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(notification.isRead ? Color.clear : iconColor.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture { onTap() }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var iconName: String {
        switch notification.type {
        case .adminMonthlyReminder: return "calendar.badge.plus"
        case .playerChallengeSubmitted: return "checkmark.circle.fill"
        case .challengeEnded: return "trophy.fill"
        case .newChallengeAvailable: return "star.circle.fill"
        case .teamInvitation: return "envelope.fill"
        case .invitationAccepted: return "person.badge.checkmark.fill"
        case .invitationDeclined: return "person.badge.minus"
        case .removedFromTeam: return "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch notification.type {
        case .invitationAccepted: return .green
        case .invitationDeclined, .removedFromTeam: return .red
        default: return BrandColors.darkTeal
        }
    }

    private func timeAgoText(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.minute, .hour, .day, .weekOfYear], from: date, to: Date())
        if let w = c.weekOfYear, w > 0 { return w == 1 ? "1 week ago" : "\(w) weeks ago" }
        if let d = c.day, d > 0 { return d == 1 ? "1 day ago" : "\(d) days ago" }
        if let h = c.hour, h > 0 { return h == 1 ? "1 hour ago" : "\(h) hours ago" }
        if let m = c.minute, m > 0 { return m == 1 ? "1 minute ago" : "\(m) minutes ago" }
        return "Just now"
    }
}
