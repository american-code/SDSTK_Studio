import Foundation
import SwiftUI
import DataScience

/// Scores every other numeric column by |Pearson correlation| against a chosen target and
/// charts them sorted descending — Orange's Rank widget (simplified to one scoring method;
/// Orange itself offers several).
final class RankWidget: StudioWidget {
    static let typeID = "Visualize.Rank"
    static let category = WidgetCategory.visualize
    static let displayName = "Rank"
    static let symbolName = "list.number"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "chart", kind: .chart)]

    private struct Params: Codable { var targetColumn: String = "" }
    private var params = Params()
    private(set) var availableColumns: [String] = []

    var targetColumn: String {
        get { params.targetColumn }
        set { params.targetColumn = newValue }
    }

    var summary: String { params.targetColumn.isEmpty ? "Select a target column" : "rank vs \(params.targetColumn)" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder.filter { df[$0].dtype.isNumeric }
        guard !params.targetColumn.isEmpty, availableColumns.contains(params.targetColumn) else {
            throw WidgetError.message("Select a numeric target column")
        }
        let candidates = availableColumns.filter { $0 != params.targetColumn }
        guard !candidates.isEmpty else { throw WidgetError.message("Need at least one other numeric column") }

        let scored = candidates
            .map { ($0, abs(df.correlation($0, params.targetColumn))) }
            .sorted { $0.1 > $1.1 }

        return .chart(.bars(categories: scored.map(\.0), values: scored.map(\.1),
                             xLabel: "Feature", yLabel: "|correlation|",
                             title: "Rank vs \(params.targetColumn)"))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(RankInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .chart(let data)? = output else { return AnyView(EmptyView()) }
        return AnyView(ChartView(data: data))
    }
}

private struct RankInspectorView: View {
    let widget: RankWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table with numeric columns first.").foregroundStyle(.secondary)
            } else {
                Picker("Target", selection: Binding(get: { widget.targetColumn }, set: { widget.targetColumn = $0; onChange() })) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
            }
        }
    }
}
