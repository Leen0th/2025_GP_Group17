import SwiftUI

/// The sheet view that presents reporting options.
struct ReportView: View {
    @StateObject private var viewModel: ReportViewModel
    @Environment(\.dismiss) private var dismiss

    /// Called with the ID of the reported item when the submission is successful.
    var onReportComplete: (String) -> Void
    private let item: ReportableItem

    init(item: ReportableItem, onReportComplete: @escaping (String) -> Void) {
        self.item = item
        self.onReportComplete = onReportComplete
        _viewModel = StateObject(wrappedValue: ReportViewModel(item: item))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // 1. Content Preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("REPORTING \(item.type.rawValue.uppercased())")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)

                    Text(item.contentPreview)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .lineLimit(2)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BrandColors.lightGray.opacity(0.7))
                        .cornerRadius(12)
                }
                .padding()

                Divider()

                // 2. Options List
                List {
                    ForEach(viewModel.options) { option in
                        Button {
                            withAnimation {
                                viewModel.selectedOption = option
                            }
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title)
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        .foregroundColor(.primary)

                                    Text(option.description)
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if viewModel.selectedOption == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(BrandColors.darkTeal)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }

                    // Custom Text Input for "Other"
                    if viewModel.selectedOption?.title == "Other" {
                        Section {
                            VStack(alignment: .trailing, spacing: 6) {
                                TextField("Please describe the problem...", text: $viewModel.customReason, axis: .vertical)
                                    .lineLimit(3...6)
                                    .padding(12)
                                    .background(BrandColors.lightGray.opacity(0.5))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(BrandColors.darkTeal.opacity(0.3), lineWidth: 1)
                                    )
                                    .onChange(of: viewModel.customReason) { newValue in
                                        if newValue.count > 500 {
                                            viewModel.customReason = String(newValue.prefix(500))
                                        }
                                    }

                                Text("\(viewModel.customReason.count)/500")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundColor(viewModel.customReason.count >= 500 ? .red : .secondary)
                                    .padding(.trailing, 4)
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)

                // 3. Submit Button
                VStack {
                    Button(action: {
                        viewModel.submitReport {
                            // handled by alert
                        }
                    }) {
                        if viewModel.isSubmitting {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity, minHeight: 32)
                        } else {
                            Text("Submit Report")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                    }
                    .padding()
                    .background(BrandColors.darkTeal)
                    .clipShape(Capsule())
                    .disabled(
                        viewModel.selectedOption == nil ||
                        viewModel.isSubmitting ||
                        (viewModel.selectedOption?.title == "Other" &&
                         viewModel.customReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
                    .opacity(
                        (viewModel.selectedOption == nil ||
                         viewModel.isSubmitting ||
                         (viewModel.selectedOption?.title == "Other" &&
                          viewModel.customReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        ? 0.7 : 1.0
                    )
                }
                .padding()

            }
            .navigationTitle("Report Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Report Submitted", isPresented: $viewModel.showSuccessAlert) {
                Button("OK") {
                    onReportComplete(item.id)
                    dismiss()
                }
            } message: {
                Text("Thank you for your report. We will review the content and take appropriate action.")
            }
        }
        .tint(BrandColors.darkTeal)
    }
}
