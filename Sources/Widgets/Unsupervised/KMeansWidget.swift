import Foundation
import SwiftUI
import DataScience

/// Runs k-means on the chosen numeric columns and appends a "Cluster" label column — unlike the
/// supervised Model widgets, clustering has no ground truth to defer to a separate evaluate
/// step, so it fits and labels inline (matches Orange's own k-Means widget).
final class KMeansWidget: StudioWidget {
    static let typeID = "Unsupervised.KMeans"
    static let category = WidgetCategory.unsupervised
    static let displayName = "k-Means"
    static let symbolName = "circle.hexagongrid"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    private struct Params: Codable { var columns: [String] = []; var k: Int = 3 }
    private var params = Params()
    private(set) var availableColumns: [String] = []

    var columns: [String] {
        get { params.columns }
        set { params.columns = newValue }
    }
    var k: Int {
        get { params.k }
        set { params.k = newValue }
    }

    var summary: String { params.columns.isEmpty ? "Select numeric columns" : "k=\(params.k) over \(params.columns.count) columns" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder.filter { df[$0].dtype.isNumeric }
        let cols = params.columns.filter { availableColumns.contains($0) }
        guard cols.count >= 1 else { throw WidgetError.message("Select at least 1 numeric column") }
        guard df.rowCount >= params.k else { throw WidgetError.message("Need at least k=\(params.k) rows") }

        var model = KMeans(k: params.k)
        model.fit(df.matrix(cols))
        return .table(df.withColumn("Cluster", Column(model.labels)))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(KMeansInspectorView(widget: self, onChange: onChange))
    }
}

private struct KMeansInspectorView: View {
    let widget: KMeansWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table with numeric columns first.").foregroundStyle(.secondary)
            } else {
                Stepper("k = \(widget.k)", value: Binding(get: { widget.k }, set: { widget.k = $0; onChange() }), in: 2...20)
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
