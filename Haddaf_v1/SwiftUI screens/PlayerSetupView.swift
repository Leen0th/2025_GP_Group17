import SwiftUI

struct PlayerSetupView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var position = ""
    @State private var weight = ""
    @State private var height = ""
    @State private var location = ""

    // Navigation to Profile
    @State private var goToProfile = false

    private let primary = Color(hexV: "#36796C")
    private let bg = Color(hexV: "#EFF5EC")

    // ✅ التحقق: كل الحقول لازم تكون غير فاضية
    private var isFormValid: Bool {
        !position.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !height.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // العنوان بالنص
                    Text("Set up your profile")
                        .font(.custom("Poppins", size: 28))
                        .fontWeight(.medium)
                        .foregroundColor(primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    // Position
                    fieldLabel("Position")
                    roundedField {
                        TextField("", text: $position)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                    }

                    // Weight
                    fieldLabel("Weight")
                    roundedField {
                        TextField("", text: $weight)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                    }

                    // Height
                    fieldLabel("Height")
                    roundedField {
                        TextField("", text: $height)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                    }

                    // Location
                    fieldLabel("Location")
                    roundedField {
                        TextField("", text: $location)
                            .font(.custom("Poppins", size: 16))
                            .foregroundColor(primary)
                            .tint(primary)
                    }

                    // Done → PlayerProfile (مفعّل فقط إذا الحقول كاملة)
                    Button {
                        if isFormValid {
                            goToProfile = true
                        }
                    } label: {
                        Text("Done")
                            .font(.custom("Poppins", size: 18))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(primary)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 6)
                    .disabled(!isFormValid)              // تعطيل الزر
                    .opacity(isFormValid ? 1.0 : 0.5)    // توضيح حالة التعطيل

                    Spacer(minLength: 20)
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
        // وجهة التنقل لصفحة البروفايل
        .navigationDestination(isPresented: $goToProfile) {
            PlayerProfile()
        }
    }

    // MARK: - Helpers
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
}

// لو ما عندك امتداد الألوان هذا مكرر، احذفيه
extension Color {
    init(hexV: String) {
        let hexV = hexV.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexV).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexV.count {
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



