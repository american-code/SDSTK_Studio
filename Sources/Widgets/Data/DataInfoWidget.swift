import Foundation
import SwiftUI
import DataScience

/// Passes a table through unchanged while summarizing its schema — Orange's Data Info widget:
/// row/column counts, each column's dtype, null count, and (for numeric columns) mean/std.
final class DataInfoWidget: StudioWidget {
    static let typeID = "Data.DataInfo"
    static let category = WidgetCategory.data
    static let displayName = "Data Info"
    static let symbolName = "info.circle"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    struct ColumnSummary: Identifiable {
        let id = UUID()
        let name: String
        let dtype: String
        let nullCount: Int
        let detail: String
    }

    private struct Params: Codable {}
    private var params = Params()
    private(set) var rowCount = 0
    private(set) var columnSummaries: [ColumnSummary] = []

    var summary: String { rowCount > 0 ? "\(rowCount) rows × \(columnSummaries.count) cols" : "No data yet" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        rowCount = df.rowCount
        columnSummaries = df.columnOrder.map { name in
            let column = df[name]
            let detail: String
            if column.dtype.isNumeric, let values = column.asDoubles(dropNulls: true), !values.isEmpty {
                let mean = values.reduce(0, +) / Double(values.count)
                let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
                detail = "mean \(String(format: "%.3g", mean)), std \(String(format: "%.3g", variance.squareRoot()))"
            } else {
                detail = "\(Set(column.stringValues()).count) distinct values"
            }
            return ColumnSummary(name: name, dtype: column.dtype.description, nullCount: column.nullCount, detail: detail)
        }
        return .table(df)
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(DataInfoInspectorView(widget: self))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard rowCount > 0 else { return AnyView(EmptyView()) }
        return AnyView(Text("\(rowCount) rows · \(columnSummaries.count) cols")
            .font(.caption2).foregroundStyle(.secondary))
    }
}

private struct DataInfoInspectorView: View {
    let widget: DataInfoWidget

    var body: some View {
        List {
            Section("\(widget.rowCount) rows") {
                ForEach(widget.columnSummaries) { col in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(col.name).font(.caption.weight(.semibold))
                            Text(col.dtype).font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            if col.nullCount > 0 {
                                Text("\(col.nullCount) null").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        Text(col.detail).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
