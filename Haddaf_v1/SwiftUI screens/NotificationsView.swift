import SwiftUI

struct NotificationsView: View {
    // MODIFIED:new BrandColors
    private let primary = BrandColors.darkTeal
    private let dividerColor = Color.black.opacity(0.12)

    // Default Values for notification settings
    @State private var newChallenge = true
    @State private var upcomingMatch = true
    @State private var personalMilestones = false
    @State private var endorsements = false
    @State private var likes = true
    @State private var comments = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // MODIFIED: new gradient background
            BrandColors.backgroundGradientEnd.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                ZStack {
                    Text("Notification")
                        // MODIFIED: Use new font
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(primary)
                                .padding(10)
                                // MODIFIED: Use new background
                                .background(Circle().fill(BrandColors.lightGray.opacity(0.7)))
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)

                // MODIFIED: Wrap list in a card
                VStack(spacing: 18) {
                    notifRow(title: "New Challenge", isOn: $newChallenge)
                    divider
                    notifRow(title: "Upcoming Match Reminders", isOn: $upcomingMatch)
                    divider
                    notifRow(title: "Performance Milestones", isOn: $personalMilestones)
                    divider
                    notifRow(title: "Endorsements", isOn: $endorsements)
                    divider
                    notifRow(title: "Likes", isOn: $likes)
                    divider
                    notifRow(title: "Comments", isOn: $comments)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(BrandColors.background)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
                .padding(.horizontal)

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private var divider: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: 1)
            .padding(.leading, 6)
    }

    @ViewBuilder
    private func notifRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 18, design: .rounded))
                .foregroundColor(primary)
                .padding(.vertical, 10)

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: primary))
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 8)
    }
}
