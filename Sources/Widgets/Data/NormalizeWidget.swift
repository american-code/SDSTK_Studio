import Foundation
import SwiftUI
import DataScience

/// Rescales the chosen numeric columns in place — Orange's Continuize/Normalize step. Wraps
/// `Learn`'s existing `StandardScaler`/`MinMaxScaler` (`Preprocessing.swift`), which were already
/// built for the `Learn.Pipeline` machinery but had no canvas-facing widget yet.
final class NormalizeWidget: StudioWidget {
    static let typeID = "Data.Normalize"
    static let category = WidgetCategory.data
    static let displayName = "Normalize"
    static let symbolName = "arrow.up.arrow.down.circle"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    enum Method: String, Codable, CaseIterable {
        case standard = "Standardize (mean 0, unit variance)"
        case minMax = "Min-Max (scale to 0–1)"
    }

    private struct Params: Codable { var columns: [String] = []; var method: Method = .standard }
    private var params = Params()
    private(set) var availableColumns: [String] = []

    var columns: [String] {
        get { params.columns }
        set { params.columns = newValue }
    }
    var method: Method {
        get { params.method }
        set { params.method = newValue }
    }

    var summary: String { params.columns.isEmpty ? "Select numeric columns" : "\(params.method.rawValue), \(params.columns.count) columns" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder.filter { df[$0].dtype.isNumeric }
        let cols = params.columns.filter { availableColumns.contains($0) }
        guard !cols.isEmpty else { throw WidgetError.message("Select at least 1 numeric column") }

        let matrix: Matrix
        switch params.method {
        case .standard:
            var scaler = StandardScaler()
            matrix = scaler.fitTransform(df.matrix(cols))
        case .minMax:
            var scaler = MinMaxScaler()
            let X = df.matrix(cols)
            scaler.fit(X)
            matrix = scaler.transform(X)
        }

        var result = df
        for (i, name) in cols.enumerated() {
            result = result.withColumn(name, Column(matrix.column(i)))
        }
        return .table(result)
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(NormalizeInspectorView(widget: self, onChange: onChange))
    }
}

private struct NormalizeInspectorView: View {
    let widget: NormalizeWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table with numeric columns first.").foregroundStyle(.secondary)
            } else {
                Picker("Method", selection: Binding(get: { widget.method }, set: { widget.method = $0; onChange() })) {
                    ForEach(NormalizeWidget.Method.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
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
