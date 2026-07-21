import Foundation
import SwiftUI
import DataScience
import Graph

/// Reads an edge list (from/to/optional weight columns) into an SDSTK `Graph<String>` and runs
/// Dijkstra between two chosen nodes — a category Orange only gets via its separate Networks
/// add-on (see PLAN.md §2). Display-only: declares zero output ports, so the result only shows
/// in this node's own preview/inspector.
final class ShortestPathWidget: StudioWidget {
    static let typeID = "Graph.ShortestPath"
    static let category = WidgetCategory.graph
    static let displayName = "Shortest Path"
    static let symbolName = "point.topleft.down.curvedto.point.bottomright.up"
    static let inputPorts: [PortSpec] = [PortSpec(name: "edges", kind: .table)]
    static let outputPorts: [PortSpec] = []

    private struct Params: Codable {
        var fromColumn: String = ""
        var toColumn: String = ""
        var weightColumn: String = ""
        var start: String = ""
        var end: String = ""
    }
    private var params = Params()
    private(set) var availableColumns: [String] = []
    private(set) var availableNodes: [String] = []
    private(set) var resultText: String = ""

    var fromColumn: String { get { params.fromColumn } set { params.fromColumn = newValue } }
    var toColumn: String { get { params.toColumn } set { params.toColumn = newValue } }
    var weightColumn: String { get { params.weightColumn } set { params.weightColumn = newValue } }
    var start: String { get { params.start } set { params.start = newValue } }
    var end: String { get { params.end } set { params.end = newValue } }

    var summary: String { resultText.isEmpty ? "Configure edge columns" : resultText }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder
        guard !params.fromColumn.isEmpty, !params.toColumn.isEmpty else {
            throw WidgetError.message("Select the from/to edge columns")
        }
        let froms = df[params.fromColumn].stringValues()
        let tos = df[params.toColumn].stringValues()
        let weights = params.weightColumn.isEmpty ? nil : df.vector(params.weightColumn)

        var graph = Graph<String>(directed: true)
        for i in 0..<df.rowCount {
            graph.addEdge(from: froms[i], to: tos[i], weight: weights.map { $0[i].isFinite ? $0[i] : 1 } ?? 1)
        }
        availableNodes = Array(graph.nodes).sorted()

        guard !params.start.isEmpty, !params.end.isEmpty else {
            resultText = "Pick a start and end node"
            throw WidgetError.message(resultText)
        }
        guard let (path, distance) = graph.shortestPath(from: params.start, to: params.end) else {
            resultText = "No path from \(params.start) to \(params.end)"
            throw WidgetError.message(resultText)
        }
        resultText = "\(path.joined(separator: " → ")) — distance \(String(format: "%.3g", distance))"
        return .none
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(ShortestPathInspectorView(widget: self, onChange: onChange))
    }
}

private struct ShortestPathInspectorView: View {
    let widget: ShortestPathWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect an edge-list table first.").foregroundStyle(.secondary)
            } else {
                Picker("From column", selection: Binding(get: { widget.fromColumn }, set: { widget.fromColumn = $0; onChange() })) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                Picker("To column", selection: Binding(get: { widget.toColumn }, set: { widget.toColumn = $0; onChange() })) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                Picker("Weight column (optional)", selection: Binding(get: { widget.weightColumn }, set: { widget.weightColumn = $0; onChange() })) {
                    Text("Unweighted (1.0)").tag("")
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                if !widget.availableNodes.isEmpty {
                    Picker("Start", selection: Binding(get: { widget.start }, set: { widget.start = $0; onChange() })) {
                        ForEach(widget.availableNodes, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("End", selection: Binding(get: { widget.end }, set: { widget.end = $0; onChange() })) {
                        ForEach(widget.availableNodes, id: \.self) { Text($0).tag($0) }
                    }
                }
                if !widget.resultText.isEmpty {
                    Text(widget.resultText).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
