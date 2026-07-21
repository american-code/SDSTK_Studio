import Foundation
import SwiftUI
import DataScience

/// Projects the chosen numeric columns onto their top principal components, appending PC1/PC2/…
/// columns to the table (originals kept, so you can still color/facet by them downstream).
final class PCAWidget: StudioWidget {
    static let typeID = "Unsupervised.PCA"
    static let category = WidgetCategory.unsupervised
    static let displayName = "PCA"
    static let symbolName = "arrow.down.right.and.arrow.up.left"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    private struct Params: Codable { var columns: [String] = []; var nComponents: Int = 2 }
    private var params = Params()
    private(set) var availableColumns: [String] = []

    var columns: [String] {
        get { params.columns }
        set { params.columns = newValue }
    }
    var nComponents: Int {
        get { params.nComponents }
        set { params.nComponents = newValue }
    }

    var summary: String { params.columns.isEmpty ? "Select numeric columns" : "\(params.nComponents) components over \(params.columns.count) columns" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder.filter { df[$0].dtype.isNumeric }
        let cols = params.columns.filter { availableColumns.contains($0) }
        guard cols.count >= 2 else { throw WidgetError.message("Select at least 2 numeric columns") }
        let n = min(params.nComponents, cols.count)
        guard n >= 1 else { throw WidgetError.message("Need at least 1 component") }

        var pca = PCA(nComponents: n)
        let projected = pca.fitTransform(df.matrix(cols))
        var result = df
        for c in 0..<n {
            result = result.withColumn("PC\(c + 1)", Column(projected.column(c)))
        }
        return .table(result)
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(PCAInspectorView(widget: self, onChange: onChange))
    }
}

private struct PCAInspectorView: View {
    let widget: PCAWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table with numeric columns first.").foregroundStyle(.secondary)
            } else {
                Stepper("Components: \(widget.nComponents)",
                         value: Binding(get: { widget.nComponents }, set: { widget.nComponents = $0; onChange() }), in: 1...10)
                Section("Columns") {
                    ForEach(widget.availableColumns, id: \.self) { column in
                        Toggle(column, isOn: Binding(
                            get: { widget.columns.contains(column) },
                            set: { isOn in
                                if isOn { widget.columns.append(column) }
                                else { widget.columns.removeAll { $0 == column } }
                                onChange()
                            }
                        ))
                    }
                }
            }
        }
    }
}
