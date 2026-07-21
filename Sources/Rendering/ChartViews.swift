import SwiftUI
import Charts

/// Native Swift Charts renderer for every `ChartData` shape — the live on-canvas visualization
/// path (see `PLAN.md` §3). SDSTK's own `Plot` SVG renderer is reserved for export, not this view.
/// Dispatches to a shape-specific view so each widget's `makePreview` only has to build data.
struct ChartView: View {
    let data: ChartData

    var body: some View {
        switch data {
        case .points(let points, let xLabel, let yLabel, _):
            Chart(points) { point in
                PointMark(x: .value(xLabel, point.x), y: .value(yLabel, point.y))
            }
            .chartXAxisLabel(xLabel)
            .chartYAxisLabel(yLabel)

        case .bars(let categories, let values, let xLabel, let yLabel, _):
            Chart(Array(zip(categories, values)), id: \.0) { category, value in
                BarMark(x: .value(xLabel, category), y: .value(yLabel, value))
            }
            .chartXAxisLabel(xLabel)
            .chartYAxisLabel(yLabel)

        case .heatmap(let rowLabels, let colLabels, let values, _):
            Chart {
                ForEach(Array(rowLabels.enumerated()), id: \.offset) { ri, row in
                    ForEach(Array(colLabels.enumerated()), id: \.offset) { ci, col in
                        RectangleMark(x: .value("Column", col), y: .value("Row", row))
                            .foregroundStyle(by: .value("Value", values[ri][ci]))
                    }
                }
            }
            .chartForegroundStyleScale(range: Gradient(colors: [.blue, .white, .red]))

        case .box(let stats, let yLabel, _):
            Chart(stats) { s in
                RuleMark(x: .value("Category", s.category), yStart: .value("Min", s.min), yEnd: .value("Max", s.max))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                RectangleMark(x: .value("Category", s.category), yStart: .value("Q1", s.q1), yEnd: .value("Q3", s.q3))
                    .foregroundStyle(.blue.opacity(0.4))
                RuleMark(x: .value("Category", s.category), yStart: .value("MedianLo", s.median), yEnd: .value("MedianHi", s.median))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(.blue)
            }
            .chartYAxisLabel(yLabel)
        }
    }
}
