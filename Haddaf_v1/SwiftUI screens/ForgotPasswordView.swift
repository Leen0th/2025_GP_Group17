import SwiftUI
import FirebaseAuth

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - Theme
    private let primary = BrandColors.darkTeal
    private let bg = BrandColors.backgroundGradientEnd

    // MARK: - Fields
    @State private var email = ""
    @State private var isSubmitting = false
    
    // MARK: - Alerts / Success State
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showSuccess = false

    // MARK: - Validation Logic
    private func isValidEmail(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        if value.contains("..") { return false }
        let pattern = #"^(?![.])([A-Za-z0-9._%+-]{1,64})(?<![.])@([A-Za-z0-9-]{1,63}\.)+[A-Za-z]{2,63}$"#
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: value)
    }

    // Form is valid only if email passes regex
    private var isFormValid: Bool {
        isValidEmail(email)
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    
                    // Title
                    Text("Reset Password")
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)
                    
                    Text("Enter the email associated with your account and we'll send you a link to reset your password.")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)

                    // Email Field
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Email", required: true)
                        
                        roundedField {
                            TextField("", text: $email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .font(.system(size: 16, design: .rounded))
                                .foregroundColor(primary)
                                .tint(primary)
                        }
                        
                        // REAL-TIME VALIDATION
                        if !email.isEmpty && !isValidEmail(email) {
                            Text("Please enter a valid email address (name@domain).")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.red)
                                .transition(.opacity)
                        }
                    }

                    // Submit Button
                    Button {
                        Task { await handlePasswordReset() }
                    } label: {
                        HStack(spacing: 10) {
                            Text("Send Reset Link")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                            
                            if isSubmitting {
                                ProgressView().colorInvert().scaleEffect(0.9)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(primary)
                        .clipShape(Capsule())
                        .shadow(color: primary.opacity(0.3), radius: 10, y: 5)
                    }
                    .disabled(!isFormValid || isSubmitting)
                    .opacity((isFormValid && !isSubmitting) ? 1.0 : 0.5)
                    .padding(.top, 12)
                }
                .padding(.horizontal, 22)
            }
            
            // Success Overlay
            if showSuccess {
                SuccessOverlay(
                    primary: primary,
                    title: "Reset link sent!",
                    okAction: {
                        dismiss() // Go back to Login
                    }
                )
                .transition(.opacity.combined(with: .scale))
                .zIndex(1)
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
        .alert("Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Actions
    private func handlePasswordReset() async {
        guard isFormValid else { return }
        isSubmitting = true
        
        // Firebase Auth handles Sending the ctual password reset email to the user.
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines))
            withAnimation {
                showSuccess = true
            }
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
        
        isSubmitting = false
    }

    // MARK: - UI Helpers (Copied from SignUpView style)
    private func fieldLabel(_ title: String, required: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(primary.opacity(0.75))
            if required {
                Text("*")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.red).padding(.top, -2)
            }
        }
    }
    
    private func roundedField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(BrandColors.background)
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.1), lineWidth: 1))
            )
    }
}
