//
//  ProfileNotificationsListView.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 24/10/2025.
//

import SwiftUI

struct ProfileNotificationsListView: View {
    @Environment(\.dismiss) private var dismiss
    
    // MODIFIED: Use new BrandColors
    private let primary = BrandColors.darkTeal

    // The filter category selected at the top
    @State private var selectedFilter: AppNotificationType = .all

    // Mock data for demonstration
    // --- MODIFIED: Set to empty by default to show the new empty state ---
    @State private var allNotifications: [AppNotification] = [
        // .init(type: .likes, title: "New Like", message: "Ahmed liked your latest video.", date: .now.addingTimeInterval(-300)),
        // .init(type: .comments, title: "New Comment", message: "Sara commented: 'Great skills!'", date: .now.addingTimeInterval(-1800)),
        // .init(type: .newChallenge, title: "Challenge Issued", message: "Coach Karim has issued a new dribbling challenge.", date: .now.addingTimeInterval(-3600)),
        // .init(type: .upcomingMatch, title: "Match Reminder", message: "Your match against 'Riyadh FC' is tomorrow at 7:00 PM.", date: .now.addingTimeInterval(-7200)),
        // .init(type: .personalMilestones, title: "Milestone Reached!", message: "Congratulations! You've reached 1000 views on your posts.", date: .now.addingTimeInterval(-14400)),
        // .init(type: .endorsements, title: "New Endorsement", message: "Coach Jesus left you a 5-star endorsement.", date: .now.addingTimeInterval(-86400)),
        // .init(type: .likes, title: "New Like", message: "Fahad liked your video.", date: .now.addingTimeInterval(-90000)),
        // .init(type: .comments, title: "New Comment", message: "Ali replied to your comment.", date: .now.addingTimeInterval(-100000))
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
            // MODIFIED: Use new gradient background
            ZStack {
                BrandColors.backgroundGradientEnd.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    ZStack {
                        Text("Notifications")
                            // MODIFIED: Use new font
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .foregroundColor(primary)

                        HStack {
                            Spacer()
                            Button("Done") {
                                dismiss()
                            }
                            // MODIFIED: Use new font
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(primary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                    
                    if !allNotifications.isEmpty {
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
                    }

                    // List of Notifications
                    List(filteredNotifications) { notification in
                        notificationRow(notification: notification)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            // MODIFIED: Make list rows transparent
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    // MODIFIED: Make list background transparent
                    .scrollContentBackground(.hidden)
                    .overlay {
                        if allNotifications.isEmpty {
                            EmptyStateView(
                                imageName: "bell.badge",
                                message: "You have no notifications yet. We'll let you know when something important happens!"
                            )
                        } else if filteredNotifications.isEmpty {
                            EmptyStateView(
                                imageName: "tray",
                                message: "No notifications found in this category."
                            )
                        }
                    }
                }
            }
        }
    }
    
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
                    // MODIFIED: Use new font
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(BrandColors.darkGray) // MODIFIED
                
                Text(notification.message)
                    // MODIFIED: Use new font
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                Text(notification.timeAgo)
                    // MODIFIED: Use new font
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            
            Spacer()
            
            if !notification.isRead {
                Circle()
                    .fill(primary)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(12)
        // MODIFIED: Use new card style
        .background(BrandColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }
}

private struct FilterPill: View {
    let type: AppNotificationType
    let isSelected: Bool
    let action: () -> Void
    
    // MODIFIED: Use new BrandColors
    private let primary = BrandColors.darkTeal

    var body: some View {
        Button(action: action) {
            Text(type.rawValue)
                // MODIFIED: Use new font
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                // MODIFIED: Use new colors
                .background(isSelected ? primary : BrandColors.lightGray)
                .foregroundColor(isSelected ? .white : BrandColors.darkGray)
                .clipShape(Capsule())
                // MODIFIED: Add shadow to selected
                .shadow(color: isSelected ? primary.opacity(0.3) : .clear, radius: 8, y: 4)
        }
    }
}
