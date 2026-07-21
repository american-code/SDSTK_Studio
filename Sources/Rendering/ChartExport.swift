import Foundation
import DataScience

/// Bridges a `ChartData` to SDSTK's headless `Plot.Figure` SVG renderer — the export/report
/// path (see `PLAN.md` §3; Swift Charts is the live on-canvas renderer, `Plot` is for portable
/// static output). `Figure` only has line/scatter/bar/histogram marks, so heatmap/box-plot
/// shapes have no equivalent and deliberately return `nil` rather than faking one.
enum ChartExport {
    static func svg(for data: ChartData) -> String? {
        switch data {
        case .points(let points, let xLabel, let yLabel, let title):
            var figure = Figure(title: title)
            figure.xLabel = xLabel
            figure.yLabel = yLabel
            figure.scatter(x: points.map(\.x), y: points.map(\.y))
            return figure.render()
        case .bars(let categories, let values, let xLabel, let yLabel, let title):
            var figure = Figure(title: title)
            figure.xLabel = xLabel
            figure.yLabel = yLabel
            figure.bar(categories: categories, values: values)
            return figure.render()
        case .heatmap, .box:
            return nil
        }
    }
}
