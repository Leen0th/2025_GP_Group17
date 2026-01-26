import SwiftUI

struct GuestProfileGateView: View {
    @EnvironmentObject var session: AppSession
    private let primary = BrandColors.darkTeal
    
    // ⬅️ State variables لإظهار الـ views في fullScreenCover
    @State private var showSignIn = false
    @State private var showSignUp = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 24)

            Text("Create your profile to start using Haddaf!")
                .multilineTextAlignment(.center)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundColor(primary)
                .padding(.horizontal, 24)
                .padding(.bottom, 30)

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

            // Sign Up
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
        .fullScreenCover(isPresented: $showSignIn) {
            NavigationStack {
                SignInView()
            }
        }
        .fullScreenCover(isPresented: $showSignUp) {
            NavigationStack {
                SignUpView()
            }
        }
    }
}
