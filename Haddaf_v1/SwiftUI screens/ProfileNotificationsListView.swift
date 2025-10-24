//
//  ProfileNotificationsListView.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 24/10/2025.
//

import SwiftUI

struct ProfileNotificationsListView: View {
    @Environment(\.dismiss) private var dismiss
    private let primary = Color(hex: "#36796C")

    // The filter category selected at the top
    @State private var selectedFilter: AppNotificationType = .all

    // Mock data for demonstration
    @State private var allNotifications: [AppNotification] = [
        .init(type: .likes, title: "New Like", message: "Ahmed liked your latest video.", date: .now.addingTimeInterval(-300)),
        .init(type: .comments, title: "New Comment", message: "Sara commented: 'Great skills!'", date: .now.addingTimeInterval(-1800)),
        .init(type: .newChallenge, title: "Challenge Issued", message: "Coach Karim has issued a new dribbling challenge.", date: .now.addingTimeInterval(-3600)),
        .init(type: .upcomingMatch, title: "Match Reminder", message: "Your match against 'Riyadh FC' is tomorrow at 7:00 PM.", date: .now.addingTimeInterval(-7200)),
        .init(type: .personalMilestones, title: "Milestone Reached!", message: "Congratulations! You've reached 1000 views on your posts.", date: .now.addingTimeInterval(-14400)),
        .init(type: .endorsements, title: "New Endorsement", message: "Coach Jesus left you a 5-star endorsement.", date: .now.addingTimeInterval(-86400)),
        .init(type: .likes, title: "New Like", message: "Fahad liked your video.", date: .now.addingTimeInterval(-90000)),
        .init(type: .comments, title: "New Comment", message: "Ali replied to your comment.", date: .now.addingTimeInterval(-100000))
    ]

    // Computed property to filter the list based on the selection
    private var filteredNotifications: [AppNotification] {
        if selectedFilter == .all {
            return allNotifications
        }
        return allNotifications.filter { $0.type == selectedFilter }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                ZStack {
                    Text("Notifications")
                        .font(.custom("Poppins", size: 28))
                        .fontWeight(.medium)
                        .foregroundColor(primary)

                    HStack {
                        Spacer()
                        Button("Done") {
                            dismiss()
                        }
                        .font(.custom("Poppins", size: 16))
                        .foregroundColor(primary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)
                
                // Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(AppNotificationType.allCases) { type in
                            FilterPill(type: type, isSelected: selectedFilter == type) {
                                withAnimation {
                                    selectedFilter = type
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                // List of Notifications
                List(filteredNotifications) { notification in
                    notificationRow(notification: notification)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
                .overlay {
                    if filteredNotifications.isEmpty {
                        Text("No notifications for this category.")
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // A single row in the notification list
    @ViewBuilder
    private func notificationRow(notification: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: notification.type.iconName)
                .font(.title3)
                .foregroundColor(primary)
                .frame(width: 30, alignment: .center)
                .padding(.top, 2)

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title)
                    .font(.custom("Poppins", size: 16))
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(notification.message)
                    .font(.custom("Poppins", size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                Text(notification.timeAgo)
                    .font(.custom("Poppins", size: 12))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            
            Spacer()
            
            // Unread dot
            if !notification.isRead {
                Circle()
                    .fill(primary)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// A view for the tappable filter pill
private struct FilterPill: View {
    let type: AppNotificationType
    let isSelected: Bool
    let action: () -> Void
    
    private let primary = Color(hex: "#36796C")

    var body: some View {
        Button(action: action) {
            Text(type.rawValue)
                .font(.custom("Poppins", size: 14))
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? primary : Color.black.opacity(0.05))
                .foregroundColor(isSelected ? .white : .primary.opacity(0.8))
                .clipShape(Capsule())
        }
    }
}
