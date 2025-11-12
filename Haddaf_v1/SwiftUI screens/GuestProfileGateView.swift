import SwiftUI

struct GuestProfileGateView: View {
    @EnvironmentObject var session: AppSession
    @State private var showSignIn = false
    @State private var showSignUp = false

    private let primary = BrandColors.darkTeal

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 24)

            Text("Create your profile to start using Haddaf app")
                .multilineTextAlignment(.center)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.horizontal, 24)

            // Sign In
            Button {
                showSignIn = true
            } label: {
                Text("Sign In")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(primary)
                    .clipShape(Capsule())
                    .shadow(color: primary.opacity(0.22), radius: 12, y: 6)
                    .padding(.horizontal, 20)
            }

            // Sign Up (outline)
            Button {
                showSignUp = true
            } label: {
                Text("Sign Up")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(BrandColors.background)
                            .shadow(color: .black.opacity(0.05), radius: 10, y: 6)
                    )
                    .overlay(
                        Capsule().stroke(primary.opacity(0.6), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
            }

            Spacer()
        }
        // نفتح الشاشات كـ fullScreenCover بغضّ النظر عن الـ NavigationStack الخارجي
        .fullScreenCover(isPresented: $showSignIn) {
            NavigationStack { SignInView() }
        }
        .fullScreenCover(isPresented: $showSignUp) {
            NavigationStack { SignUpView() }
        }
        // لو تغيّر حال المستخدم (سجّل دخول) نقفل أي شاشات مفتوحة
        .onChange(of: session.isGuest) { _, isGuest in
            if !isGuest {
                showSignIn = false
                showSignUp = false
            }
        }
    }
}
