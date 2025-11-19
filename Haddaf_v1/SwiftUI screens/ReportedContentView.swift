import SwiftUI

/// A placeholder view that hides content the user has reported.
struct ReportedContentView: View {
    let type: ReportableItemType
    var onShow: () -> Void
    
    // Check if it's the compact comment version
    // to use smaller version of the placeholder when the hidden item is a comment
    private var isComment: Bool {
        type == .comment
    }

    var body: some View {
        VStack(alignment: .center, spacing: isComment ? 8 : 16) {
            Image(systemName: "flag.fill")
                .font(isComment ? .body : .title)
                .foregroundColor(.secondary)
            
            Text("You reported this \(type.rawValue.lowercased()).")
                .font(.system(size: isComment ? 14 : 16, weight: .medium, design: .rounded))                .foregroundColor(.secondary)
            
            Button("View Content") {
                onShow()
            }
            .font(.system(size: isComment ? 13 : 14, weight: .bold, design: .rounded))
            .foregroundColor(BrandColors.darkTeal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isComment ? 10 : 20) 
        .padding(.horizontal)
        .background(BrandColors.lightGray.opacity(0.7))
        .cornerRadius(isComment ? 12 : 20)
    }
}
