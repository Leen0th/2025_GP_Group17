import SwiftUI
import FirebaseAuth

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss

    // UI state
    @State private var email: String = ""
    @State private var isLoading: Bool = false

    // Alert state
    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""

    // MODIFIED: Use new BrandColors
    private let primary = BrandColors.darkTeal

    var body: some View {
        ZStack {
            // MODIFIED: Use new background
            BrandColors.backgroundGradientEnd.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    Text("Forgot password")
                        // MODIFIED: Use new font
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            // MODIFIED: Use new font
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.gray)

                        TextField("", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            // MODIFIED: Use new font
                            .font(.system(size: 16, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            // MODIFIED: Use new card style
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(BrandColors.background)
                                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                            )
                    }

                    Button {
                        Task { await sendResetEmail() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView().tint(.white) }
                            Text("Request Reset Code")
                        }
                        // MODIFIED: Use new font
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(primary)
                        .clipShape(Capsule())
                        // MODIFIED: Add shadow
                        .shadow(color: primary.opacity(0.3), radius: 10, y: 5)
                    }
                    .disabled(isLoading || emailTrimmed.isEmpty)
                    .opacity((isLoading || emailTrimmed.isEmpty) ? 0.6 : 1)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(primary)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Computed

    private var emailTrimmed: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Reset Logic

    /// Sends a password reset email and shows result in a popup alert.
    private func sendResetEmail() async {
        let value = emailTrimmed
        guard isValidEmail(value) else {
            presentAlert(title: "Invalid Email", message: "Please enter a valid email address.")
            return
        }

        isLoading = true

        do {
            try await Auth.auth().sendPasswordReset(withEmail: value)
            presentAlert(
                title: "Email Sent",
                message: "A reset link has been sent to your email. Please set a new password and try to sign in again."
            )
        } catch {
            let ns = error as NSError
            if ns.domain == AuthErrorDomain {
                switch ns.code {
                case AuthErrorCode.userNotFound.rawValue:
                    presentAlert(title: "Reset Failed", message: "No account found with this email.")
                case AuthErrorCode.invalidEmail.rawValue:
                    presentAlert(title: "Reset Failed", message: "The email address is invalid.")
                case AuthErrorCode.tooManyRequests.rawValue:
                    presentAlert(title: "Too Many Attempts", message: "Please try again later.")
                case AuthErrorCode.networkError.rawValue:
                    presentAlert(title: "Network Error", message: "Please check your connection and try again.")
                default:
                    presentAlert(title: "Reset Failed", message: ns.localizedDescription)
                }
            } else {
                presentAlert(title: "Reset Failed", message: ns.localizedDescription)
            }
        }

        isLoading = false
    }

    // MARK: - Helpers

    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    /// Simple email validation.
    private func isValidEmail(_ value: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
