//
//  ReportView.swift
//  Haddaf_v1
//
//  Created by Leen Thamer on 07/11/2025.
//

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
                List(viewModel.options, id: \.self, selection: $viewModel.selectedOption) { option in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.title)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                        
                        Text(option.description)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .listStyle(.plain)
                
                // 3. Submit Button
                VStack {
                    Button(action: {
                        viewModel.submitReport {
                            // This completion is now handled by the .alert
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
                    .disabled(viewModel.selectedOption == nil || viewModel.isSubmitting)
                    .opacity(viewModel.selectedOption == nil ? 0.7 : 1.0)
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
