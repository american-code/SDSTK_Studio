import Foundation
import SwiftUI
import DataScience

/// Pearson correlation matrix over the chosen numeric columns.
final class CorrelationHeatmapWidget: StudioWidget {
    static let typeID = "Visualize.CorrelationHeatmap"
    static let category = WidgetCategory.visualize
    static let displayName = "Correlation Heatmap"
    static let symbolName = "grid"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "chart", kind: .chart)]

    private struct Params: Codable { var columns: [String] = [] }
    private var params = Params()
    private(set) var availableColumns: [String] = []

    var columns: [String] {
        get { params.columns }
        set { params.columns = newValue }
    }

    var summary: String { params.columns.isEmpty ? "Select 2+ numeric columns" : "\(params.columns.count) columns" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder.filter { df[$0].dtype.isNumeric }
        let cols = params.columns.filter { availableColumns.contains($0) }
        guard cols.count >= 2 else { throw WidgetError.message("Select at least 2 numeric columns") }

        var grid = [[Double]](repeating: [Double](repeating: 0, count: cols.count), count: cols.count)
        for i in 0..<cols.count {
            for j in 0..<cols.count {
                grid[i][j] = i == j ? 1.0 : df.correlation(cols[i], cols[j])
            }
        }
        return .chart(.heatmap(rowLabels: cols, colLabels: cols, values: grid, title: "Correlation"))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(CorrelationHeatmapInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .chart(let data)? = output else { return AnyView(EmptyView()) }
        return AnyView(ChartView(data: data))
    }
}

private struct CorrelationHeatmapInspectorView: View {
    let widget: CorrelationHeatmapWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table with numeric columns first.").foregroundStyle(.secondary)
            } else {
                ForEach(widget.availableColumns, id: \.self) { column in
                    Toggle(column, isOn: Binding(
                        get: { widget.columns.contains(column) },
                        set: { isOn in
                            if isOn { widget.columns.append(column) }
                            else { widget.columns.removeAll { $0 == column } }
                            onChange()
                        }
                    ))
                }
            }
        }
    }
}
