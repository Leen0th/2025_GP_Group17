import SwiftUI

struct NotificationsView: View {
    private let primary = Color(hex: "#36796C")
    private let dividerColor = Color.black.opacity(0.12)

    // القيم الافتراضية
    @State private var newChallenge = true
    @State private var upcomingMatch = true
    // --- MODIFIED: Renamed state variable ---
    @State private var personalMilestones = false
    @State private var endorsements = false
    @State private var likes = true
    @State private var comments = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                ZStack {
                    Text("Notification")
                        .font(.custom("Poppins", size: 28))
                        .fontWeight(.medium)
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(primary)
                                .padding(10)
                                .background(Circle().fill(Color.black.opacity(0.05)))
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)

                // قائمة النوتفيكيشن
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
                .padding(.horizontal, 28)
                .padding(.top, 16)

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
                .font(.custom("Poppins", size: 18))
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
