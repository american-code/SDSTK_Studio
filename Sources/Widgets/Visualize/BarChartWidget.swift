import Foundation
import SwiftUI
import DataScience

/// Mean of a numeric column, grouped by a categorical column — with category-level selection
/// propagation: tap bars in the inspector to toggle categories, and the rows belonging to the
/// selected categories flow out of the `selected` port.
final class BarChartWidget: StudioWidget {
    static let typeID = "Visualize.BarChart"
    static let category = WidgetCategory.visualize
    static let displayName = "Bar Chart"
    static let symbolName = "chart.bar.xaxis"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [
        PortSpec(name: "chart", kind: .chart),
        PortSpec(name: "selected", kind: .table),
    ]

    /// Selection by category *name*, not bar index — names stay stable when upstream data adds
    /// or reorders groups.
    /// `selectedCategories` is Optional so pre-selection saved params (bundled examples) still
    /// decode — see HistogramWidget.Params for the full reasoning.
    private struct Params: Codable {
        var categoryColumn: String = ""
        var valueColumn: String = ""
        var selectedCategories: Set<String>? = nil
    }
    private var params = Params()
    private(set) var availableColumns: [String] = []
    private(set) var lastCategories: [String] = []
    private(set) var lastMeans: [Double] = []
    private(set) var lastSelectedRowCount: Int = 0

    var categoryColumn: String {
        get { params.categoryColumn }
        set { params.categoryColumn = newValue }
    }
    var valueColumn: String {
        get { params.valueColumn }
        set { params.valueColumn = newValue }
    }
    var selectedCategories: Set<String> { params.selectedCategories ?? [] }

    func toggleCategory(_ name: String) {
        var set = params.selectedCategories ?? []
        if set.contains(name) { set.remove(name) } else { set.insert(name) }
        params.selectedCategories = set
    }
    func clearSelection() { params.selectedCategories = [] }

    var summary: String {
        if params.categoryColumn.isEmpty || params.valueColumn.isEmpty { return "Select category/value columns" }
        let base = "mean(\(params.valueColumn)) by \(params.categoryColumn)"
        return selectedCategories.isEmpty ? base : "\(base) — \(lastSelectedRowCount) selected"
    }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder
        guard !params.categoryColumn.isEmpty, !params.valueColumn.isEmpty else {
            throw WidgetError.message("Select category and value columns")
        }
        let categories = df[params.categoryColumn].stringValues()
        let values = df.vector(params.valueColumn)

        var sums: [String: Double] = [:]
        var counts: [String: Int] = [:]
        var order: [String] = []
        for (category, value) in zip(categories, values) where value.isFinite {
            if sums[category] == nil { order.append(category) }
            sums[category, default: 0] += value
            counts[category, default: 0] += 1
        }
        let means = order.map { sums[$0]! / Double(counts[$0]!) }
        lastCategories = order
        lastMeans = means

        let selectedRows = categories.indices.filter { selectedCategories.contains(categories[$0]) }
        lastSelectedRowCount = selectedRows.count

        let chart = ChartData.bars(categories: order, values: means, xLabel: params.categoryColumn,
                                    yLabel: "mean(\(params.valueColumn))",
                                    title: "\(params.valueColumn) by \(params.categoryColumn)")
        return .outputs(["chart": .chart(chart), "selected": .table(df.take(selectedRows))])
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(BarChartInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .outputs(let byPort)? = output, case .chart(let data)? = byPort["chart"] else {
            return AnyView(EmptyView())
        }
        return AnyView(ChartView(data: data))
    }
}

private struct BarChartInspectorView: View {
    let widget: BarChartWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table first.").foregroundStyle(.secondary)
            } else {
                Picker("Category", selection: Binding(get: { widget.categoryColumn }, set: { widget.categoryColumn = $0; onChange() })) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                Picker("Value", selection: Binding(get: { widget.valueColumn }, set: { widget.valueColumn = $0; onChange() })) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                if !widget.lastCategories.isEmpty {
                    Section("Selection — tap bars, rows flow out the 'selected' port") {
                        CategoryTapChart(
                            categories: widget.lastCategories,
                            values: widget.lastMeans,
                            isSelected: { widget.selectedCategories.contains(widget.lastCategories[$0]) },
                            onTap: { widget.toggleCategory(widget.lastCategories[$0]); onChange() })
                            .frame(height: 200)
                        if !widget.selectedCategories.isEmpty {
                            Button("Clear selection") { widget.clearSelection(); onChange() }
                        }
                    }
                }
            }
        }
    }
}
