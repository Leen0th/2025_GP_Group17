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

// A structured way to hold a complete data set for the chart
struct TrendDataSet: Identifiable {
    let id = UUID()
    let metricName: String
    let dataPoints: [TrendDataPoint]
    let color: Color
}


// MARK: - Main Progress Tab View
struct ProgressTabView: View {
    let accentColor = Color(hex: "#36796C")

    // --- Dummy Data ---
    let overallScore: Double = 2.4
    
    let averagePerformance: [ProgressStat] = [
        .init(label: "DRIBBLE", value: 2, maxValue: 10),
        .init(label: "PASS", value: 9, maxValue: 15),
        .init(label: "SHOOT", value: 3, maxValue: 10)
    ]

    let trendDataSets: [TrendDataSet] = [
        .init(metricName: "DRIBBLE", dataPoints: [
            .init(month: "Jan", score: 20), .init(month: "Feb", score: 28), .init(month: "Mar", score: 22),
            .init(month: "Apr", score: 35), .init(month: "May", score: 30), .init(month: "Jun", score: 25)
        ], color: Color(hex: "#36796C")),
        .init(metricName: "PASS", dataPoints: [
            .init(month: "Jan", score: 10), .init(month: "Feb", score: 15), .init(month: "Mar", score: 42),
            .init(month: "Apr", score: 30), .init(month: "May", score: 25), .init(month: "Jun", score: 18)
        ], color: .green.opacity(0.8)),
        .init(metricName: "SHOOT", dataPoints: [
            .init(month: "Jan", score: 15), .init(month: "Feb", score: 22), .init(month: "Mar", score: 12),
            .init(month: "Apr", score: 20), .init(month: "May", score: 22), .init(month: "Jun", score: 15)
        ], color: Color(hex: "#36796C").opacity(0.6))
    ]
    // --- End Dummy Data ---
    
    @State private var selectedMonth: String?
    @State private var touchLocation: CGPoint?

    var body: some View {
        VStack(spacing: 24) {
            overallScoreView
            averagePerformanceCard
            performanceTrendsCard
            Spacer()
        }
        .padding(.top, 20)
    }

    private var overallScoreView: some View {
        HStack(spacing: 16) {
            Text("Overall score")
                .font(.custom("Poppins-SemiBold", size: 22))
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Spacer()
            
            Text(String(format: "%.1f", overallScore))
                .font(.custom("Poppins-Bold", size: 36))
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(accentColor)
        .cornerRadius(20)
        .shadow(color: accentColor.opacity(0.3), radius: 10, y: 5)
    }

    private var averagePerformanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Average Performance Overtime")
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(.primary)
                .padding(.bottom, 8)
            
            ForEach(averagePerformance) { stat in
                ProgressBarView(stat: stat, accentColor: accentColor)
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
    
    private var performanceTrendsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Trends Over the Year")
                .font(.custom("Poppins-SemiBold", size: 18))
                .foregroundColor(.primary)
            
            ZStack(alignment: .topLeading) {
                LineChartView(
                    dataSets: trendDataSets,
                    selectedMonth: $selectedMonth,
                    touchLocation: $touchLocation
                )
                .frame(height: 180)
                
                if let month = selectedMonth, let location = touchLocation {
                    TooltipView(dataSets: trendDataSets, selectedMonth: month, touchLocation: location)
                }
            }
            
            ChartLegendView(dataSets: trendDataSets)
                .padding(.top, 8)
            
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}


// MARK: - Helper Views

fileprivate struct ProgressBarView: View {
    let stat: ProgressStat
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stat.label)
                    .font(.custom("Poppins-Regular", size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(stat.value)")
                    .font(.custom("Poppins-SemiBold", size: 12))
                    .foregroundColor(.primary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 8)
                    
                    Capsule()
                        .fill(accentColor)
                        .frame(width: (geometry.size.width * CGFloat(stat.value) / CGFloat(stat.maxValue)), height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

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
                    
                    if let location = touchLocation {
                        let index = Int(round((location.x / geometry.size.width) * CGFloat(monthLabels.count - 1)))
                        
                        // Safety check for the index before using it
                        if index >= 0 && index < monthLabels.count {
                            let xPosition = geometry.size.width / CGFloat(monthLabels.count - 1) * CGFloat(index)
                            
                            Path { path in
                                path.move(to: CGPoint(x: xPosition, y: 0))
                                path.addLine(to: CGPoint(x: xPosition, y: geometry.size.height))
                            }
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                            
                            ForEach(dataSets) { dataSet in
                                // ✅ THE FIX: Check if the index is valid for THIS specific dataSet before accessing it.
                                if index < dataSet.dataPoints.count {
                                    let yPosition = (1 - CGFloat((dataSet.dataPoints[index].score - minScore) / (maxScore - minScore))) * geometry.size.height
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
                            // Clamp the location to the bounds of the geometry
                            let clampedX = max(0, min(location.x, geometry.size.width))
                            let clampedLocation = CGPoint(x: clampedX, y: location.y)
                            touchLocation = clampedLocation
                            
                            let index = Int(round((clampedLocation.x / geometry.size.width) * CGFloat(monthLabels.count - 1)))
                            if index >= 0 && index < monthLabels.count {
                                selectedMonth = monthLabels[index]
                            }
                        }
                        .onEnded { _ in
                            selectedMonth = nil
                            touchLocation = nil
                        }
                )
            }
            
            HStack {
                ForEach(monthLabels, id: \.self) { month in
                    Text(month)
                        .font(.caption)
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
                        .font(.custom("Poppins-Regular", size: 12))
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
                .font(.custom("Poppins-Bold", size: 14))
                .foregroundColor(.primary)
                .bold()
            
            Divider()
            
            ForEach(dataSets) { dataSet in
                if let dataPoint = dataSet.dataPoints.first(where: { $0.month == selectedMonth }) {
                    HStack {
                        Text(dataSet.metricName)
                            .font(.custom("Poppins-Regular", size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f", dataPoint.score))
                            .font(.custom("Poppins-SemiBold", size: 12))
                            .foregroundColor(dataSet.color)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .frame(width: 120)
        .position(x: touchLocation.x, y: touchLocation.y - 60)
    }
}

