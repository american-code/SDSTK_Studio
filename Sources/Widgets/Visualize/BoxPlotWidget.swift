import Foundation
import SwiftUI
import DataScience

/// Quartile distribution of a numeric column, grouped by a categorical column — with the same
/// category-level selection propagation as Bar Chart: tap a box's category in the inspector and
/// its rows flow out of the `selected` port.
final class BoxPlotWidget: StudioWidget {
    static let typeID = "Visualize.BoxPlot"
    static let category = WidgetCategory.visualize
    static let displayName = "Box Plot"
    static let symbolName = "chart.bar.doc.horizontal"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [
        PortSpec(name: "chart", kind: .chart),
        PortSpec(name: "selected", kind: .table),
    ]

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
    private(set) var lastMedians: [Double] = []
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
        let base = "\(params.valueColumn) by \(params.categoryColumn)"
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

        var byCategory: [String: [Double]] = [:]
        var order: [String] = []
        for (category, value) in zip(categories, values) where value.isFinite {
            if byCategory[category] == nil { order.append(category) }
            byCategory[category, default: []].append(value)
        }
        let stats: [ChartData.BoxStats] = order.compactMap { category in
            guard let vals = byCategory[category], !vals.isEmpty else { return nil }
            return ChartData.BoxStats(category: category,
                                       min: vals.min() ?? 0,
                                       q1: Stats.quantile(vals, 0.25),
                                       median: Stats.quantile(vals, 0.5),
                                       q3: Stats.quantile(vals, 0.75),
                                       max: vals.max() ?? 0)
        }
        guard !stats.isEmpty else { throw WidgetError.message("No numeric data to summarize") }
        lastCategories = stats.map(\.category)
        lastMedians = stats.map(\.median)

        let selectedRows = categories.indices.filter { selectedCategories.contains(categories[$0]) }
        lastSelectedRowCount = selectedRows.count

        let chart = ChartData.box(stats: stats, yLabel: params.valueColumn,
                                   title: "\(params.valueColumn) by \(params.categoryColumn)")
        return .outputs(["chart": .chart(chart), "selected": .table(df.take(selectedRows))])
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(BoxPlotInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .outputs(let byPort)? = output, case .chart(let data)? = byPort["chart"] else {
            return AnyView(EmptyView())
        }
        return AnyView(ChartView(data: data))
    }
}

private struct BoxPlotInspectorView: View {
    let widget: BoxPlotWidget
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
                    // Reuses the shared tap chart with medians as bar heights — the tap target
                    // is the category, which is what selection operates on; the full quartile
                    // rendering stays on the node face.
                    Section("Selection — tap a category, rows flow out the 'selected' port") {
                        CategoryTapChart(
                            categories: widget.lastCategories,
                            values: widget.lastMedians,
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
