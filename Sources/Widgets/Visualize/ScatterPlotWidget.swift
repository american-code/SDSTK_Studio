import Foundation
import SwiftUI
import Charts
import DataScience

/// Scatter plot over two numeric columns of an incoming table. First widget with interactive
/// selection propagation (Orange's "Selected Data" pattern): drag a rectangle on the inspector's
/// chart and the rows inside it flow out of the second output port as a filtered table, live,
/// to whatever is wired downstream.
final class ScatterPlotWidget: StudioWidget {
    static let typeID = "Visualize.ScatterPlot"
    static let category = WidgetCategory.visualize
    static let displayName = "Scatter Plot"
    static let symbolName = "chart.dots.scatter"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [
        PortSpec(name: "chart", kind: .chart),
        PortSpec(name: "selected", kind: .table),
    ]

    /// Selection rectangle in *data* coordinates — not screen points and not row indices, so it
    /// stays meaningful when upstream data is resampled/refiltered (rows that move into the
    /// region join the selection; Orange stores indices and silently loses this property).
    struct SelectionRect: Codable, Equatable {
        var xMin: Double, xMax: Double, yMin: Double, yMax: Double
        func contains(x: Double, y: Double) -> Bool {
            x >= xMin && x <= xMax && y >= yMin && y <= yMax
        }
    }

    private struct Params: Codable {
        var xColumn: String = ""
        var yColumn: String = ""
        var selection: SelectionRect?
    }
    private var params = Params()
    /// Populated as a side effect of `run` so the inspector has something to pick from even
    /// before both columns are chosen (see the note in `run`).
    private(set) var availableColumns: [String] = []
    /// Last plotted points + how many fell inside the selection — cached by `run` so the
    /// inspector's interactive chart renders without re-deriving from upstream state it can't see.
    private(set) var lastPoints: [ChartData.Point] = []
    private(set) var lastSelectedCount: Int = 0

    var xColumn: String {
        get { params.xColumn }
        set { params.xColumn = newValue }
    }
    var yColumn: String {
        get { params.yColumn }
        set { params.yColumn = newValue }
    }
    var selection: SelectionRect? {
        get { params.selection }
        set { params.selection = newValue }
    }

    var summary: String {
        if params.xColumn.isEmpty || params.yColumn.isEmpty { return "Select X/Y columns" }
        let base = "\(params.xColumn) vs \(params.yColumn)"
        return params.selection == nil ? base : "\(base) — \(lastSelectedCount) selected"
    }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        // Populate the column list even on the "not configured yet" failure path below, so the
        // inspector's pickers have entries as soon as data first arrives.
        availableColumns = df.columnOrder
        guard !params.xColumn.isEmpty, !params.yColumn.isEmpty else {
            throw WidgetError.message("Select X and Y columns")
        }
        let xs = df.vector(params.xColumn)
        let ys = df.vector(params.yColumn)
        let points = zip(xs, ys)
            .filter { $0.0.isFinite && $0.1.isFinite }
            .map { ChartData.Point(x: $0.0, y: $0.1) }
        lastPoints = points

        // Selection filters the *original rows* (all columns), not the plotted points — that's
        // what makes it composable downstream. No selection → empty table, matching Orange's
        // "Selected Data sends nothing until you select" semantics as closely as a
        // must-produce-a-value engine allows.
        let selectedIndices: [Int]
        if let sel = params.selection {
            selectedIndices = xs.indices.filter { i in
                xs[i].isFinite && ys[i].isFinite && sel.contains(x: xs[i], y: ys[i])
            }
        } else {
            selectedIndices = []
        }
        lastSelectedCount = selectedIndices.count
        let selectedTable = df.take(selectedIndices)

        let chart = ChartData.points(points: points, xLabel: params.xColumn, yLabel: params.yColumn,
                                      title: "\(params.xColumn) vs \(params.yColumn)")
        return .outputs(["chart": .chart(chart), "selected": .table(selectedTable)])
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(ScatterPlotInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        // Multi-output node: the face preview shows the chart half.
        guard case .outputs(let byPort)? = output, case .chart(let data)? = byPort["chart"] else {
            return AnyView(EmptyView())
        }
        return AnyView(ChartView(data: data))
    }
}

private struct ScatterPlotInspectorView: View {
    let widget: ScatterPlotWidget
    let onChange: () -> Void
    /// Screen-space rect while a drag is in flight (drawn as a live marquee); committed to the
    /// widget's data-space selection on gesture end.
    @State private var marquee: CGRect?

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a Data widget with a table first.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("X", selection: Binding(get: { widget.xColumn }, set: { widget.xColumn = $0; onChange() })) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                Picker("Y", selection: Binding(get: { widget.yColumn }, set: { widget.yColumn = $0; onChange() })) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                if !widget.lastPoints.isEmpty {
                    Section("Selection — drag to select, rows flow out the 'selected' port") {
                        selectionChart
                            .frame(height: 240)
                        HStack {
                            Text(widget.selection == nil
                                 ? "No selection"
                                 : "\(widget.lastSelectedCount) row(s) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if widget.selection != nil {
                                Button("Clear") {
                                    widget.selection = nil
                                    onChange()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var selectionChart: some View {
        Chart {
            ForEach(widget.lastPoints) { point in
                PointMark(x: .value(widget.xColumn, point.x), y: .value(widget.yColumn, point.y))
                    .foregroundStyle(selected(point) ? Color.accentColor : Color.secondary.opacity(0.55))
            }
            if let sel = widget.selection {
                RectangleMark(xStart: .value("x0", sel.xMin), xEnd: .value("x1", sel.xMax),
                               yStart: .value("y0", sel.yMin), yEnd: .value("y1", sel.yMax))
                    .foregroundStyle(Color.accentColor.opacity(0.12))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { drag in
                                marquee = CGRect(x: min(drag.startLocation.x, drag.location.x),
                                                 y: min(drag.startLocation.y, drag.location.y),
                                                 width: abs(drag.translation.width),
                                                 height: abs(drag.translation.height))
                            }
                            .onEnded { drag in
                                commit(drag: drag, proxy: proxy, geo: geo)
                                marquee = nil
                            }
                    )
                if let marquee {
                    Rectangle()
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .background(Color.accentColor.opacity(0.08))
                        .frame(width: marquee.width, height: marquee.height)
                        .position(x: marquee.midX, y: marquee.midY)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func selected(_ point: ChartData.Point) -> Bool {
        widget.selection?.contains(x: point.x, y: point.y) ?? false
    }

    /// Converts the drag's screen-space corners to data coordinates via the chart proxy and
    /// commits them as the widget's persistent selection.
    private func commit(drag: DragGesture.Value, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotAnchor = proxy.plotFrame else { return }
        let plotFrame = geo[plotAnchor]
        func dataPoint(_ p: CGPoint) -> (Double, Double)? {
            let local = CGPoint(x: p.x - plotFrame.origin.x, y: p.y - plotFrame.origin.y)
            guard let x: Double = proxy.value(atX: local.x), let y: Double = proxy.value(atY: local.y) else { return nil }
            return (x, y)
        }
        guard let a = dataPoint(drag.startLocation), let b = dataPoint(drag.location) else { return }
        widget.selection = ScatterPlotWidget.SelectionRect(
            xMin: min(a.0, b.0), xMax: max(a.0, b.0),
            yMin: min(a.1, b.1), yMax: max(a.1, b.1))
        onChange()
    }
}
