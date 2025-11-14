import SwiftUI

// MARK: - Step Definition
/// Defines the steps in the video upload and analysis process.
enum UploadStep: Int, CaseIterable {
    case upload = 0      // NEW: The user selects a video
    case selectScene = 1 // "Select Scene" in PinpointPlayerView
    case pinpoint = 2    // "Pinpoint" in PinpointPlayerView
    case processing = 3  // ProcessingVideoView
    case feedback = 4    // PerformanceFeedbackView

    var title: String {
        switch self {
        case .upload: return "Upload"
        case .selectScene: return "Scene"
        case .pinpoint: return "Pinpoint"
        case .processing: return "Process"
        case .feedback: return "Feedback"
        }
    }
}

// MARK: - Progress Bar View
/// A timeline view that shows the user's progress through the upload flow.
struct MultiStepProgressBar: View {
    
    /// The step the user is currently on.
    let currentStep: UploadStep
    
    private let activeColor = BrandColors.darkTeal
    private let inactiveColor = BrandColors.background
    private let activeTextColor = BrandColors.darkGray
    private let inactiveTextColor = Color.secondary

    var body: some View {
        VStack {
            HStack(spacing: 0) {
                ForEach(UploadStep.allCases, id: \.self) { step in
                    StepView(
                        step: step,
                        isCurrent: currentStep == step,
                        isCompleted: currentStep.rawValue > step.rawValue
                    )

                    
                    if step != UploadStep.allCases.last {
                        Rectangle()
                            .fill(currentStep.rawValue > step.rawValue ? activeColor : inactiveColor)
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, -4)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(BrandColors.backgroundGradientEnd)
    }

    /// Helper view for a single step (circle + title)
    @ViewBuilder
    private func StepView(step: UploadStep, isCurrent: Bool, isCompleted: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isCompleted ? activeColor : (isCurrent ? BrandColors.backgroundGradientEnd : BrandColors.background))
                    .frame(width: 30, height: 30)
                
                
                if !isCompleted && !isCurrent {
                    Circle()
                        .stroke(BrandColors.lightGray, lineWidth: 1)
                        .frame(width: 30, height: 30)
                }

                if isCompleted {
                    // Completed Step: Checkmark
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                } else if isCurrent {
                    // Current Step: Outlined circle with number
                    Circle()
                        .stroke(activeColor, lineWidth: 2)
                        .background(Circle().fill(BrandColors.backgroundGradientEnd))
                        .frame(width: 28, height: 28)
                    
                    Text("\(step.rawValue + 1)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(activeColor)
                } else {
                    // Future Step: Number
                     Text("\(step.rawValue + 1)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(inactiveTextColor)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isCompleted)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isCurrent)

            // Step Title
            Text(step.title)
                .font(.system(size: 12, design: .rounded))
                .fontWeight(isCurrent ? .bold : .regular)
                .foregroundColor(isCurrent || isCompleted ? activeTextColor : inactiveTextColor)
        }
        .frame(width: 65) // Give each step a consistent width
    }
}
