import SwiftUI
import FirebaseAuth

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss

    // UI state
    @State private var email: String = ""
    @State private var isLoading: Bool = false
    @State private var message: String? = nil   // success or error under the button

    // Local color (scoped extension name to avoid collisions)
    private let primary = Color(hexVal_fp: "#36796C")

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // Title
                    Text("Forgot password")
                        .font(.custom("Poppins", size: 34))
                        .fontWeight(.medium)
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    // Email
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.custom("Poppins", size: 14))
                            .foregroundColor(.gray)

                        TextField("", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.custom("Poppins", size: 16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray3), lineWidth: 1)
                                    .background(.white)
                            )
                    }

                    // Submit
                    Button {
                        Task { await sendResetEmail() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView().tint(.white) }
                            Text("Request Reset Code")
                        }
                        .font(.custom("Poppins", size: 18))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(primary)
                        .clipShape(Capsule())
                    }
                    .disabled(isLoading || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity((isLoading || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.6 : 1)

                    // Inline result
                    if let message {
                        let isSuccess = message.lowercased().hasPrefix("a reset link has been sent")
                        Text(message)
                            .font(.system(size: 14))
                            .foregroundColor(isSuccess ? .green : .red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

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
    }

    // MARK: - Reset Logic

    /// Sends a password reset email and maps Firebase errors by domain + code (version-agnostic).
    private func sendResetEmail() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(trimmed) else {
            message = "Please enter a valid email address."
            return
        }

        isLoading = true
        message = nil

        do {
            try await Auth.auth().sendPasswordReset(withEmail: trimmed)
            message = "A reset link has been sent to your email."
        } catch {
            let ns = error as NSError
            // Handle only Firebase Auth errors; otherwise show system message.
            if ns.domain == AuthErrorDomain {
                switch ns.code {
                case AuthErrorCode.userNotFound.rawValue:
                    message = "No account found with this email."
                case AuthErrorCode.invalidEmail.rawValue:
                    message = "The email address is invalid."
                case AuthErrorCode.tooManyRequests.rawValue:
                    message = "Too many attempts. Try again later."
                case AuthErrorCode.networkError.rawValue:
                    message = "Network error. Please check your connection."
                default:
                    message = ns.localizedDescription
                }
            } else {
                message = ns.localizedDescription
            }
        }

        isLoading = false
    }

    // MARK: - Helpers

    /// Simple email validation.
    private func isValidEmail(_ value: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

// MARK: - Hex Color (scoped name to avoid collisions with other files)
extension Color {
    init(hexVal_fp: String) {
        let s = hexVal_fp.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: s).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch s.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17,
                                (int >> 4 & 0xF) * 17,
                                (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16,
                                int >> 8 & 0xFF,
                                int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24,
                                int >> 16 & 0xFF,
                                int >> 8 & 0xFF,
                                int & 0xFF)
        default:(a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red:   Double(r) / 255,
                  green: Double(g) / 255,
                  blue:  Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}
