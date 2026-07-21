import Foundation
import SwiftUI
import DataScience

/// Keeps only the chosen columns, in the order picked.
final class SelectColumnsWidget: StudioWidget {
    static let typeID = "Data.SelectColumns"
    static let category = WidgetCategory.data
    static let displayName = "Select Columns"
    static let symbolName = "line.3.horizontal.decrease"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    private struct Params: Codable { var selected: [String] = [] }
    private var params = Params()
    private(set) var availableColumns: [String] = []

    var selected: [String] {
        get { params.selected }
        set { params.selected = newValue }
    }

    var summary: String { params.selected.isEmpty ? "All columns" : params.selected.joined(separator: ", ") }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder
        let keep = params.selected.filter { availableColumns.contains($0) }
        return .table(keep.isEmpty ? df : df.select(keep))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(SelectColumnsInspectorView(widget: self, onChange: onChange))
    }
}

private struct SelectColumnsInspectorView: View {
    let widget: SelectColumnsWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table first.").foregroundStyle(.secondary)
            } else {
                Text("Leave all unchecked to pass every column through.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(widget.availableColumns, id: \.self) { column in
                    Toggle(column, isOn: Binding(
                        get: { widget.selected.contains(column) },
                        set: { isOn in
                            if isOn { widget.selected.append(column) }
                            else { widget.selected.removeAll { $0 == column } }
                            onChange()
                        }
                    ))
                }
            }
        }
    }
}
