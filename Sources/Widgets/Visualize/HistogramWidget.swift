import Foundation
import SwiftUI
import Charts
import DataScience

/// Histogram of one numeric column, with bin-level selection propagation: tap bars in the
/// inspector to toggle bins, and the rows falling in the selected bins flow out of the
/// `selected` port as a filtered table (same `.outputs` mechanism as Scatter Plot's marquee).
final class HistogramWidget: StudioWidget {
    static let typeID = "Visualize.Histogram"
    static let category = WidgetCategory.visualize
    static let displayName = "Histogram"
    static let symbolName = "chart.bar"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [
        PortSpec(name: "chart", kind: .chart),
        PortSpec(name: "selected", kind: .table),
    ]

    /// Selection is by bin *index* (with the bin count alongside): bin edges are fully
    /// determined by (data min/max, bins), so indices stay meaningful across re-runs of the
    /// same configuration; changing the bin count invalidates the old indices, so the stored
    /// count acts as a guard that clears stale selections rather than misapplying them.
    /// Selection fields are Optional so params saved *before* selection existed (the bundled
    /// example workflows) still decode — synthesized Codable throws on a missing non-optional
    /// key, and `applyParams` failing would silently drop the column/bins config too.
    private struct Params: Codable {
        var column: String = ""
        var bins: Int = 10
        var selectedBins: Set<Int>? = nil
        var selectionBinCount: Int? = nil
    }
    private var params = Params()
    private(set) var availableColumns: [String] = []
    /// Cached by `run` for the inspector's interactive chart.
    private(set) var lastLabels: [String] = []
    private(set) var lastCounts: [Double] = []
    private(set) var lastSelectedRowCount: Int = 0

    var column: String {
        get { params.column }
        set { params.column = newValue }
    }
    var bins: Int {
        get { params.bins }
        set { params.bins = newValue }
    }
    var selectedBins: Set<Int> { params.selectedBins ?? [] }

    func toggleBin(_ index: Int) {
        if params.selectionBinCount != params.bins {
            params.selectedBins = []
            params.selectionBinCount = params.bins
        }
        var bins = params.selectedBins ?? []
        if bins.contains(index) { bins.remove(index) } else { bins.insert(index) }
        params.selectedBins = bins
    }
    func clearSelection() { params.selectedBins = [] }

    var summary: String {
        if params.column.isEmpty { return "Select a column" }
        let base = "\(params.column), \(params.bins) bins"
        return selectedBins.isEmpty ? base : "\(base) — \(lastSelectedRowCount) selected"
    }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder
        guard !params.column.isEmpty else { throw WidgetError.message("Select a column") }

        let raw = df.vector(params.column)
        let values = raw.filter { $0.isFinite }
        guard let lo = values.min(), let hi = values.max(), hi > lo, bins > 0 else {
            throw WidgetError.message("Not enough spread in this column to bin")
        }
        let width = (hi - lo) / Double(bins)
        func binIndex(_ v: Double) -> Int { min(bins - 1, max(0, Int((v - lo) / width))) }

        var counts = [Int](repeating: 0, count: bins)
        for v in values { counts[binIndex(v)] += 1 }
        let labels = (0..<bins).map { String(format: "%.1f", lo + Double($0) * width) }
        lastLabels = labels
        lastCounts = counts.map(Double.init)

        // A stale selection (made under a different bin count) filters nothing rather than
        // filtering wrongly.
        let selection = params.selectionBinCount == bins ? (params.selectedBins ?? []) : []
        let selectedRows = raw.indices.filter { raw[$0].isFinite && selection.contains(binIndex(raw[$0])) }
        lastSelectedRowCount = selectedRows.count

        let chart = ChartData.bars(categories: labels, values: lastCounts,
                                    xLabel: params.column, yLabel: "Count",
                                    title: "Histogram of \(params.column)")
        return .outputs(["chart": .chart(chart), "selected": .table(df.take(selectedRows))])
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(HistogramInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .outputs(let byPort)? = output, case .chart(let data)? = byPort["chart"] else {
            return AnyView(EmptyView())
        }
        return AnyView(ChartView(data: data))
    }
}

private struct HistogramInspectorView: View {
    let widget: HistogramWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table first.").foregroundStyle(.secondary)
            } else {
                Picker("Column", selection: Binding(get: { widget.column }, set: { widget.column = $0; onChange() })) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                Stepper("Bins: \(widget.bins)", value: Binding(get: { widget.bins }, set: { widget.bins = $0; onChange() }), in: 2...50)
                if !widget.lastLabels.isEmpty {
                    Section("Selection — tap bars, rows flow out the 'selected' port") {
                        CategoryTapChart(
                            categories: widget.lastLabels,
                            values: widget.lastCounts,
                            isSelected: { widget.selectedBins.contains($0) },
                            onTap: { widget.toggleBin($0); onChange() })
                            .frame(height: 200)
                        if !widget.selectedBins.isEmpty {
                            Button("Clear selection") { widget.clearSelection(); onChange() }
                        }
                    }
                }
            }
        }
    }
}

/// Shared tap-to-toggle bar chart used by the Histogram / Bar Chart / Box Plot inspectors —
/// converts a tap's x position to the nearest category via `ChartProxy` and reports its index.
struct CategoryTapChart: View {
    let categories: [String]
    let values: [Double]
    let isSelected: (Int) -> Bool
    let onTap: (Int) -> Void

    var body: some View {
        Chart {
            ForEach(Array(zip(categories.indices, zip(categories, values))), id: \.0) { index, pair in
                BarMark(x: .value("category", pair.0), y: .value("value", pair.1))
                    .foregroundStyle(isSelected(index) ? Color.accentColor : Color.secondary.opacity(0.5))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plotAnchor = proxy.plotFrame else { return }
                        let plotFrame = geo[plotAnchor]
                        let x = location.x - plotFrame.origin.x
                        guard let category: String = proxy.value(atX: x),
                              let index = categories.firstIndex(of: category) else { return }
                        onTap(index)
                    }
            }
        }
    }
}
