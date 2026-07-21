import Foundation
import SwiftUI
import DataScience

/// Flags rows whose z-score on any selected numeric column exceeds a threshold — Orange's
/// Outlier widget, simplified to a single univariate z-score rule rather than its full
/// covariance-based method. Appends an `IsOutlier` column rather than dropping rows, so you can
/// route flagged/unflagged rows separately downstream if you want to.
final class OutlierDetectionWidget: StudioWidget {
    static let typeID = "Data.OutlierDetection"
    static let category = WidgetCategory.data
    static let displayName = "Outlier Detection"
    static let symbolName = "exclamationmark.triangle"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    private struct Params: Codable { var columns: [String] = []; var threshold: Double = 3.0 }
    private var params = Params()
    private(set) var availableColumns: [String] = []
    private(set) var outlierCount = 0

    var columns: [String] {
        get { params.columns }
        set { params.columns = newValue }
    }
    var threshold: Double {
        get { params.threshold }
        set { params.threshold = newValue }
    }

    var summary: String {
        params.columns.isEmpty ? "Select numeric columns" : "\(outlierCount) flagged (|z| > \(String(format: "%.1f", params.threshold)))"
    }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder.filter { df[$0].dtype.isNumeric }
        let cols = params.columns.filter { availableColumns.contains($0) }
        guard !cols.isEmpty else { throw WidgetError.message("Select at least 1 numeric column") }

        var isOutlier = [Bool](repeating: false, count: df.rowCount)
        for name in cols {
            let column = df[name]
            guard let mean = column.mean(), let std = column.std(), std > 0,
                  let values = column.asDoubles(dropNulls: false) else { continue }
            for r in 0..<df.rowCount where values[r].isFinite {
                if abs((values[r] - mean) / std) > params.threshold { isOutlier[r] = true }
            }
        }
        outlierCount = isOutlier.filter { $0 }.count
        return .table(df.withColumn("IsOutlier", Column(isOutlier)))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(OutlierDetectionInspectorView(widget: self, onChange: onChange))
    }
}

private struct OutlierDetectionInspectorView: View {
    let widget: OutlierDetectionWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table with numeric columns first.").foregroundStyle(.secondary)
            } else {
                Slider(value: Binding(get: { widget.threshold }, set: { widget.threshold = $0; onChange() }), in: 1...5) {
                    Text("Threshold: |z| > \(String(format: "%.1f", widget.threshold))")
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
