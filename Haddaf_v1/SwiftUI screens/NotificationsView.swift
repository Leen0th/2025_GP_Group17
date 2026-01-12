import SwiftUI
struct NotificationsView: View {
    // Theme
    private let primary = BrandColors.darkTeal
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            BrandColors.backgroundGradientEnd.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                ZStack {
                    Text("Notification")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(primary)
                                .padding(10)
                                .background(
                                    Circle()
                                        .fill(BrandColors.lightGray.opacity(0.7))
                                )
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
                Spacer()
                VStack(spacing: 8) {
                    Text("Notifications")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.gray)
                    Text("To be developed in upcoming sprints")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(Color.gray.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}
