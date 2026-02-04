import SwiftUI
import FirebaseAuth

// MARK: - Notifications View
struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var notificationService = NotificationService.shared
    @EnvironmentObject var session: AppSession
    
    @State private var showDeleteConfirm = false
    @State private var notificationToDelete: HaddafNotification?
    
    private let accentColor = BrandColors.darkTeal
    
    var body: some View {
        NavigationStack {
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                
                if notificationService.isLoading {
                    ProgressView()
                        .tint(accentColor)
                } else if notificationService.notifications.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(notificationService.notifications) { notification in
                                NotificationCard(
                                    notification: notification,
                                    onTap: {
                                        Task {
                                            await notificationService.markAsRead(notificationId: notification.id)
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
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
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
            .confirmationDialog(
                "Delete this notification?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let notification = notificationToDelete {
                        Task {
                            await notificationService.deleteNotification(notificationId: notification.id)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onAppear {
            if let userId = session.user?.uid {
                notificationService.startListening(for: userId)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No Notifications")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
            
            Text("You're all caught up!")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.secondary)
        }
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
            // Icon based on notification type
            ZStack {
                Circle()
                    .fill(notification.isRead ? Color.gray.opacity(0.2) : accentColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: iconForNotificationType)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(notification.isRead ? .gray : accentColor)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(notification.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                // Message
                Text(notification.message)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                
                // Time ago
                Text(timeAgoText(from: notification.createdAt))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            Spacer()
            
            // Unread indicator
            if !notification.isRead {
                Circle()
                    .fill(accentColor)
                    .frame(width: 10, height: 10)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(notification.isRead ? Color.white : Color.white)
                .shadow(color: .black.opacity(notification.isRead ? 0.05 : 0.1), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(notification.isRead ? Color.clear : accentColor.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            onTap()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var iconForNotificationType: String {
        switch notification.type {
        case .adminMonthlyReminder:
            return "calendar.badge.plus"
        case .playerChallengeSubmitted:
            return "checkmark.circle.fill"
        case .challengeEnded:
            return "trophy.fill"
        case .newChallengeAvailable:
            return "star.circle.fill"
        }
    }
    
    private func timeAgoText(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.minute, .hour, .day, .weekOfYear], from: date, to: now)
        
        if let weeks = components.weekOfYear, weeks > 0 {
            return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
        } else if let days = components.day, days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        } else if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else {
            return "Just now"
        }
    }
}

#Preview {
    NotificationsView()
        .environmentObject(AppSession())
}
