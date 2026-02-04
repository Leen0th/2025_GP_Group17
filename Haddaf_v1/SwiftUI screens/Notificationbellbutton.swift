import SwiftUI

// MARK: - Notification Bell Button
struct NotificationBellButton: View {
    @Binding var showNotifications: Bool
    @StateObject private var notificationService = NotificationService.shared
    
    private let accentColor = BrandColors.darkTeal
    
    var body: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(accentColor)
                
                // Unread badge
                if notificationService.unreadCount > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 18, height: 18)
                        
                        Text("\(min(notificationService.unreadCount, 9))")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .offset(x: 8, y: -8)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Admin Notification Bell Button (with different styling)
struct AdminNotificationBellButton: View {
    @Binding var showNotifications: Bool
    @StateObject private var notificationService = NotificationService.shared
    
    private let accentColor = BrandColors.darkTeal
    
    var body: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(accentColor)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(accentColor, Color.red)
                
                // Unread count badge
                if notificationService.unreadCount > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 20, height: 20)
                        
                        Text("\(min(notificationService.unreadCount, 9))")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .offset(x: 10, y: -10)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
