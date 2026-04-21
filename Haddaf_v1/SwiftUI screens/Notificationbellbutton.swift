import SwiftUI
import FirebaseAuth

// MARK: - Notification Bell Button
struct NotificationBellButton: View {
    @Binding var showNotifications: Bool
    let userId: String
    @ObservedObject private var notificationService = NotificationService.shared
    
    private let accentColor = BrandColors.darkTeal
    
    var body: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: notificationService.unreadCount > 0 ? "bell.fill" : "bell")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(notificationService.unreadCount > 0 ? accentColor : accentColor)
                
                // Unread dot indicator
                if notificationService.unreadCount > 0 {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 10, height: 10)
                        .offset(x: 6, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            if notificationService.listener == nil {
                notificationService.startListening(for: userId)
            }
        }
    }
}

// MARK: - Admin Notification Bell Button
struct AdminNotificationBellButton: View {
    @Binding var showNotifications: Bool
    let userId: String
    @ObservedObject private var notificationService = NotificationService.shared
    
    private let accentColor = BrandColors.darkTeal
    
    var body: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: notificationService.unreadCount > 0 ? "bell.fill" : "bell")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(accentColor)
                
                // Unread dot indicator
                if notificationService.unreadCount > 0 {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 10, height: 10)
                        .offset(x: 6, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            if notificationService.listener == nil {
                notificationService.startListening(for: userId)
            }
        }
    }
}
