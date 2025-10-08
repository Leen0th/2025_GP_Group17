import SwiftUI

struct NotificationsView: View {
    private let primary = Color(hex: "#36796C")
    private let dividerColor = Color.black.opacity(0.12)

    // القيم الافتراضية
    @State private var newChallenge = true
    @State private var upcomingMatch = true
    @State private var goalAchievement1 = false
    @State private var newChallenge2 = false
    @State private var goalAchievement2 = true
    @State private var goalAchievement3 = true

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Tab = .profile
    @State private var showVideoUpload = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // ✅ العنوان بالنص تمامًا
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

                // ✅ قائمة النوتفيكيشن مرتبة مع مسافات أكبر ومحاذاة بالنص
                VStack(spacing: 18) {
                    notifRow(title: "New Challenge", isOn: $newChallenge)
                    divider
                    notifRow(title: "Upcoming Match Reminders", isOn: $upcomingMatch)
                    divider
                    notifRow(title: "Goal Achievement", isOn: $goalAchievement1)
                    divider
                    notifRow(title: "New Challenge", isOn: $newChallenge2)
                    divider
                    notifRow(title: "Goal Achievement", isOn: $goalAchievement2)
                    divider
                    notifRow(title: "Goal Achievement", isOn: $goalAchievement3)
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)

                Spacer(minLength: 0)
                    .padding(.bottom, 100)
            }

            // ✅ Footer
            CustomTabBar(selectedTab: $selectedTab, showVideoUpload: $showVideoUpload)
        }
        .sheet(isPresented: $showVideoUpload) { VideoUploadView() }
        .ignoresSafeArea(.all, edges: .bottom)
        .navigationBarBackButtonHidden(true)
    }

    private var divider: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: 1)
            .padding(.leading, 6)
    }

    // ✅ صف واحد لكل نوتفيكيشن (مع تصغير السويتش)
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
                .scaleEffect(0.8) // 👈 تصغير السويتش
        }
        .padding(.horizontal, 8)
    }
}


