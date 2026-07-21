import Foundation
import SwiftUI
import DataScience

/// Passes a table through unchanged while previewing it — Orange's Data Table widget. Lets you
/// look at what's flowing through the canvas without breaking the chain.
final class DataTableWidget: StudioWidget {
    static let typeID = "Data.DataTable"
    static let category = WidgetCategory.data
    static let displayName = "Data Table"
    static let symbolName = "tablecells"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    private struct Params: Codable {}
    private var params = Params()

    private(set) var previewColumns: [String] = []
    private(set) var previewRows: [[String]] = []
    private(set) var totalRowCount = 0

    var summary: String { totalRowCount > 0 ? "\(totalRowCount) rows × \(previewColumns.count) cols" : "No data yet" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        previewColumns = df.columnOrder
        let head = df.head(50)
        let columnStrings = previewColumns.map { head[$0].stringValues() }
        previewRows = (0..<head.rowCount).map { r in columnStrings.map { $0[r] } }
        totalRowCount = df.rowCount
        return .table(df)
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(DataTableInspectorView(widget: self))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard totalRowCount > 0 else { return AnyView(EmptyView()) }
        return AnyView(TableGridView(columns: previewColumns, rows: Array(previewRows.prefix(4)), cellWidth: 60)
            .font(.system(size: 9)))
    }
}

private struct DataTableInspectorView: View {
    let widget: DataTableWidget

    var body: some View {
        VStack(alignment: .leading) {
            Text("\(widget.totalRowCount) rows total, showing first \(widget.previewRows.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding([.horizontal, .top], 8)
            TableGridView(columns: widget.previewColumns, rows: widget.previewRows)
        }
    }
}
