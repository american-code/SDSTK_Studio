import SwiftUI
import UniformTypeIdentifiers

/// The trailing detail column: the selected node's parameter form, plus an SVG export action
/// when its current output is a chart Plot's renderer can express (see `ChartExport`).
struct InspectorPanel: View {
    let node: WidgetNode
    let state: NodeState
    let onChange: () -> Void

    /// The chart carried by this node's output, whether it's a single-output chart widget or a
    /// multi-output one (`.outputs` with a "chart" entry — Scatter/Histogram/Bar/Box since
    /// selection propagation).
    private var chartOutput: ChartData? {
        guard case .done(let value) = state else { return nil }
        if case .chart(let data) = value { return data }
        if case .outputs(let byPort) = value, case .chart(let data)? = byPort["chart"] { return data }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let data = chartOutput, let svg = ChartExport.svg(for: data), let url = writeTemp(svg, name: data.title) {
                ShareLink(item: url) {
                    Label("Export as SVG", systemImage: "square.and.arrow.up")
                }
                .padding([.horizontal, .top], 8)
                Divider()
            }
            node.widget.makeInspector(onChange: onChange)
        }
    }

    private func writeTemp(_ svg: String, name: String) -> URL? {
        let safeName = name.isEmpty ? "chart" : name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName).appendingPathExtension("svg")
        return (try? svg.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }
}
