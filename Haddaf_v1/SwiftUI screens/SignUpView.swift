
import SwiftUI

enum UserRole: String { case player = "Player", coach = "Coach" }

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss

    // Colors
    private let primary = Color(hexv: "#36796C")
    private let bg = Color(hexv: "#EFF5EC")

    // Role
    @State private var role: UserRole = .player

    // Fields
    @State private var fullName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var isHidden = true  // 👈 نفس SignIn

    // DOB (starts empty)
    @State private var dob: Date? = nil
    @State private var showDOBPicker = false
    @State private var tempDOB = Date()

    // Nav
    @State private var goToPlayerSetup = false

    // Validation
    private var isFormValid: Bool {
        let nameOK = !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let emailOK = !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let phoneOK = !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let passOK  = password.count >= 6
        let dobOK   = dob != nil
        return nameOK && emailOK && phoneOK && passOK && dobOK
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Title
                    Text("Sign Up")
                        .font(.custom("Poppins", size: 34))
                        .fontWeight(.medium)
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    // Role
                    HStack(spacing: 28) {
                        rolePill(.player)
                        rolePill(.coach)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    // Full name
                    fieldLabel("Full Name")
                    roundedField {
                        TextField("", text: $fullName)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                    }

                    // Email
                    fieldLabel("Email")
                    roundedField {
                        TextField("", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                    }

                    // DOB
                    fieldLabel("Date of birth")
                    buttonLikeField(action: {
                        // تعيين القيمة المؤقتة قبل فتح الشيت
                        if let d = dob { tempDOB = d } else { tempDOB = Date() }
                        showDOBPicker = true
                    }) {
                        HStack {
                            Text(dob.map { formatDate($0) } ?? "Select date")
                                .font(.custom("Poppins", size: 16))
                                .foregroundColor(dob == nil ? .gray : primary)
                            Spacer()
                            Image(systemName: "calendar")
                                .foregroundColor(primary.opacity(0.85))
                        }
                    }
                    // ✅ تم تطبيق تعديلات الـ Sheet هنا
                    .sheet(isPresented: $showDOBPicker) {
                        DateWheelPickerSheet(
                            selection: $dob,
                            tempSelection: $tempDOB,
                            showSheet: $showDOBPicker
                        )
                        .presentationDetents([.height(300)]) // حجم النافذة مناسب (مثل Position)
                        .presentationBackground(.white) // ✅ الخلفية البيضاء تغطي الحواف
                        .presentationCornerRadius(28)  // ✅ الزوايا الدائرية
                    }

                    // Phone
                    fieldLabel("Phone Number")
                    roundedField {
                        TextField("", text: $phone)
                            .keyboardType(.phonePad)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                    }

                    // Password  ✅ نفس منطق SignIn
                    fieldLabel("Password")
                    roundedField {
                        ZStack(alignment: .trailing) {
                            if isHidden {
                                SecureField("", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .font(.custom("Poppins", size: 16))
                                    .foregroundColor(primary)
                                    .tint(primary)
                                    .textContentType(.password)
                                    .padding(.trailing, 44)
                            } else {
                                TextField("", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .font(.custom("Poppins", size: 16))
                                    .foregroundColor(primary)
                                    .tint(primary)
                                    .textContentType(.password)
                                    .padding(.trailing, 44)
                            }

                            Button { withAnimation { isHidden.toggle() } } label: {
                                Image(systemName: isHidden ? "eye.slash" : "eye")
                                    .foregroundColor(.gray)
                            }
                        }
                    }

                    // Sign Up
                    Button {
                        if isFormValid, role == .player {
                            goToPlayerSetup = true
                        }
                    } label: {
                        Text("Sign Up")
                            .font(.custom("Poppins", size: 18))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(primary)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 8)
                    .disabled(!isFormValid)
                    .opacity(isFormValid ? 1.0 : 0.5)

                    // Footer
                    HStack(spacing: 6) {
                        Text("Already have an account?")
                            .font(.custom("Poppins", size: 15))
                            .foregroundColor(.gray)
                        NavigationLink { /* SignInView() */ } label: { // تأكد من وجود SignInView
                            Text("Sign in")
                                .font(.custom("Poppins", size: 15))
                                .fontWeight(.semibold)
                                .foregroundColor(primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
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
        .navigationDestination(isPresented: $goToPlayerSetup) {
            PlayerSetupView() // تأكد من وجود PlayerSetupView
        }
    }

    // MARK: - Helpers
    private func rolePill(_ r: UserRole) -> some View {
        Button { role = r } label: {
            HStack(spacing: 8) {
                Image(systemName: role == r ? "circle.inset.filled" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                Text(r.rawValue)
                    .font(.custom("Poppins", size: 16))
            }
            .foregroundColor(primary)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.custom("Poppins", size: 14))
            .foregroundColor(.gray)
    }

    private func roundedField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
            )
    }

    private func buttonLikeField<Content: View>(
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white)
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                )
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: date)
    }
}

// MARK: - Wheel sheet for DOB (New Structure)
private struct DateWheelPickerSheet: View {
    @Binding var selection: Date? // التاريخ النهائي
    @Binding var tempSelection: Date // القيمة المؤقتة لاختيار DatePicker
    @Binding var showSheet: Bool // لغلق الشيت

    private let primary = Color(hexv: "#36796C")

    var body: some View {
        VStack(spacing: 16) {
            
            // العنوان باللون الأخضر
            Text("Select your birth date")
                .font(.custom("Poppins", size: 18))
                .foregroundColor(primary) // اللون الأخضر
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            
            // الـ DatePicker
            DatePicker("", selection: $tempSelection, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .tint(primary)
                .frame(height: 180)
            
            // زر Done الأخضر بشكل كبسولة
            Button("Done") {
                selection = tempSelection // حفظ القيمة
                showSheet = false
            }
            .font(.custom("Poppins", size: 18))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(primary)
            .clipShape(Capsule())
            .padding(.bottom, 16)
            
        }
        // ✅ إضافة Padding أفقي على الـ VStack بالكامل لضبط محتوى الـ Sheet
        .padding(.horizontal, 20)
        // ❌ تم حذف .background و .cornerRadius ليعتمد على .presentationBackground في الـ SignUpView
    }
}

// Hex color (Unchanged)
extension Color {
    init(hexv: String) {
        let hexv = hexv.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexv).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexv.count {
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
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}
