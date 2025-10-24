import SwiftUI

// MARK: - Data Models for Progress View
struct ProgressStat: Identifiable {
    let id = UUID()
    let label: String
    let value: Int
    let maxValue: Int
}

struct TrendDataPoint: Identifiable {
    let id = UUID()
    let month: String
    let score: Double
}

struct TrendDataSet: Identifiable {
    let id = UUID()
    let metricName: String
    let dataPoints: [TrendDataPoint]
    let color: Color
}

// MARK: - Main Progress Tab View
struct ProgressTabView: View {
    // MODIFIED: Use new BrandColors
    let accentColor = BrandColors.darkTeal
    let dataTurquoise = BrandColors.turquoise
    let dataTeal = BrandColors.teal
    let dataGreen = BrandColors.actionGreen

    // --- Dummy Data ---
    let overallScore: Double = 2.4
    
    let averagePerformance: [ProgressStat] = [
        .init(label: "DRIBBLE", value: 2, maxValue: 10),
        .init(label: "PASS", value: 9, maxValue: 15),
        .init(label: "SHOOT", value: 3, maxValue: 10)
    ]

    // MODIFIED: Removed gradients from dummy data
    let trendDataSets: [TrendDataSet] = [
        .init(metricName: "DRIBBLE", dataPoints: [
            .init(month: "Jan", score: 20), .init(month: "Feb", score: 28), .init(month: "Mar", score: 22),
            .init(month: "Apr", score: 35), .init(month: "May", score: 30), .init(month: "Jun", score: 25)
        ], color: BrandColors.turquoise), // Removed gradient

        .init(metricName: "PASS", dataPoints: [
            .init(month: "Jan", score: 10), .init(month: "Feb", score: 15), .init(month: "Mar", score: 42),
            .init(month: "Apr", score: 30), .init(month: "May", score: 25), .init(month: "Jun", score: 18)
        ], color: BrandColors.teal), // Removed gradient

        .init(metricName: "SHOOT", dataPoints: [
            .init(month: "Jan", score: 15), .init(month: "Feb", score: 22), .init(month: "Mar", score: 12),
            .init(month: "Apr", score: 20), .init(month: "May", score: 22), .init(month: "Jun", score: 15)
        ], color: BrandColors.actionGreen) // Removed gradient
    ]
    // --- End Dummy Data ---
    
    @State private var selectedMonth: String?
    @State private var touchLocation: CGPoint?

    var body: some View {
        VStack(spacing: 24) {
            overallScoreView
            averagePerformanceCard
            performanceTrendsCard // This now uses the original chart code
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 20)
    }

    private var overallScoreView: some View {
        HStack(spacing: 16) {
            Text("Overall score")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            Text(String(format: "%.1f", overallScore))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(BrandColors.gold)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(accentColor) // darkTeal
        .cornerRadius(20)
        .shadow(color: accentColor.opacity(0.3), radius: 12, y: 5)
    }

    private var averagePerformanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Average Performance Overtime")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(BrandColors.darkGray)
                .padding(.bottom, 8)
            ForEach(averagePerformance) { stat in
                ProgressBarView(stat: stat, accentColor: accentColor) // Uses new styled ProgressBarView
            }
        }
        .padding(20)
        .background(BrandColors.background)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }
    
    private var performanceTrendsCard: some View {
        VStack(alignment: .leading, spacing: 12) { // <- Original error pointed here, hopefully fixed now
            Text("Performance Trends Over the Year")
                .font(.system(size: 18, weight: .semibold, design: .rounded)) // New font
                .foregroundColor(BrandColors.darkGray) // New color

            ZStack(alignment: .topLeading) {
                // Use the original LineChartView struct
                LineChartView(
                    dataSets: trendDataSets,
                    selectedMonth: $selectedMonth,
                    touchLocation: $touchLocation
                )
                .frame(height: 180)

                // Use the original TooltipView struct
                if let month = selectedMonth, let location = touchLocation {
                    TooltipView(dataSets: trendDataSets, selectedMonth: month, touchLocation: location)
                }
            }

            // Use the original ChartLegendView struct
            ChartLegendView(dataSets: trendDataSets)
                .padding(.top, 8)

        }
        .padding(20)
        .background(BrandColors.background) // New background
        .cornerRadius(20) // New corner radius
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5) // New shadow
    }
    // --- END REVERT ---
}


// MARK: - Helper Views

fileprivate struct ProgressBarView: View {
    let stat: ProgressStat
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stat.label)
                    // MODIFIED: Use new font
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(stat.value)")
                    // MODIFIED: Use new font
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(BrandColors.darkGray)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        // MODIFIED: Use new color
                        .fill(BrandColors.lightGray)
                        .frame(height: 8)
                    
                    Capsule()
                        // MODIFIED: Use gradient for the bar
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.7), accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: (geometry.size.width * CGFloat(stat.value) / CGFloat(stat.maxValue)), height: 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: stat.value)
                }
            }
            .frame(height: 8)
        }
    }
}

// --- REVERTED: Original LineChartView, ChartLegendView, TooltipView ---
// These structs are exactly as provided in your original file upload for ProgressTabView.swift
private struct LineChartView: View {
    let dataSets: [TrendDataSet]
    @Binding var selectedMonth: String?
    @Binding var touchLocation: CGPoint?

    var body: some View {
        let allScores = dataSets.flatMap { $0.dataPoints.map { $0.score } }
        let maxScore = allScores.max() ?? 50
        let minScore = 0.0
        let monthLabels = dataSets.first?.dataPoints.map { $0.month } ?? []

        VStack {
            GeometryReader { geometry in
                ZStack {
                    ForEach(dataSets) { dataSet in
                        Path { path in
                            for (index, point) in dataSet.dataPoints.enumerated() {
                                let xPosition = geometry.size.width / CGFloat(dataSet.dataPoints.count - 1) * CGFloat(index)
                                // Y calculation: 0 is top, 1 is bottom. Invert score percentage.
                                let yPosition = (1 - CGFloat((point.score - minScore) / (maxScore - minScore))) * geometry.size.height

                                if index == 0 {
                                    path.move(to: CGPoint(x: xPosition, y: yPosition))
                                } else {
                                    path.addLine(to: CGPoint(x: xPosition, y: yPosition))
                                }
                            }
                        }
                        .stroke(dataSet.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }

                    // Interactive elements (vertical line, circles on hover)
                    if let location = touchLocation {
                        let index = Int(round((location.x / geometry.size.width) * CGFloat(monthLabels.count - 1)))

                        if index >= 0 && index < monthLabels.count {
                            let xPosition = geometry.size.width / CGFloat(monthLabels.count - 1) * CGFloat(index)

                            // Vertical line
                            Path { path in
                                path.move(to: CGPoint(x: xPosition, y: 0))
                                path.addLine(to: CGPoint(x: xPosition, y: geometry.size.height))
                            }
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)

                            // Circles for each dataset at the intersection
                            ForEach(dataSets) { dataSet in
                                if index < dataSet.dataPoints.count { // Safety check
                                    let score = dataSet.dataPoints[index].score
                                    let yPosition = (1 - CGFloat((score - minScore) / (maxScore - minScore))) * geometry.size.height
                                    Circle()
                                        .fill(dataSet.color)
                                        .frame(width: 8, height: 8)
                                        .position(x: xPosition, y: yPosition)
                                }
                            }
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let location = value.location
                            let clampedX = max(0, min(location.x, geometry.size.width))
                            let clampedLocation = CGPoint(x: clampedX, y: location.y)
                            touchLocation = clampedLocation // Update touch location

                            // Find the closest month index based on touch location
                            let index = Int(round((clampedLocation.x / geometry.size.width) * CGFloat(monthLabels.count - 1)))
                            if index >= 0 && index < monthLabels.count {
                                selectedMonth = monthLabels[index] // Update selected month
                            }
                        }
                        .onEnded { _ in
                            // Reset selection when drag ends
                            selectedMonth = nil
                            touchLocation = nil
                        }
                )
            }

            // X-Axis Labels (Months)
            HStack {
                ForEach(monthLabels, id: \.self) { month in
                    Text(month)
                        .font(.caption) // Original font
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
        }
    }
}


private struct ChartLegendView: View {
    let dataSets: [TrendDataSet]

    var body: some View {
        HStack(spacing: 20) {
            ForEach(dataSets) { dataSet in
                HStack(spacing: 6) {
                    Circle()
                        .fill(dataSet.color)
                        .frame(width: 10, height: 10)
                    Text(dataSet.metricName)
                        .font(.custom("Poppins-Regular", size: 12)) // Original font
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}


private struct TooltipView: View {
    let dataSets: [TrendDataSet]
    let selectedMonth: String
    let touchLocation: CGPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selectedMonth)
                .font(.custom("Poppins-Bold", size: 14)) // Original font
                .foregroundColor(.primary)
                .bold()

            Divider()

            ForEach(dataSets) { dataSet in
                // Find the data point for the selected month in this specific dataset
                if let dataPoint = dataSet.dataPoints.first(where: { $0.month == selectedMonth }) {
                    HStack {
                        Text(dataSet.metricName)
                            .font(.custom("Poppins-Regular", size: 12)) // Original font
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f", dataPoint.score))
                            .font(.custom("Poppins-SemiBold", size: 12)) // Original font
                            .foregroundColor(dataSet.color) // Use the dataset's color
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white) // Original background
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4) // Original shadow
        )
        .frame(width: 120)
        // Position the tooltip relative to the touch location
        .position(x: touchLocation.x, y: touchLocation.y - 60) // Adjust Y offset as needed
    }
}
