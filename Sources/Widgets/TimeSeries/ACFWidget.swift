import Foundation
import SwiftUI
import DataScience
import TimeSeries

/// Autocorrelation of a numeric column by lag — Orange has no time-series category at all;
/// this is one of the "beyond Orange" showcase widgets (see PLAN.md §2).
final class ACFWidget: StudioWidget {
    static let typeID = "TimeSeries.ACF"
    static let category = WidgetCategory.timeSeries
    static let displayName = "Autocorrelation"
    static let symbolName = "waveform.path.ecg"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "chart", kind: .chart)]

    private struct Params: Codable { var column: String = ""; var maxLag: Int = 20 }
    private var params = Params()
    private(set) var availableColumns: [String] = []

    var column: String {
        get { params.column }
        set { params.column = newValue }
    }
    var maxLag: Int {
        get { params.maxLag }
        set { params.maxLag = newValue }
    }

    var summary: String { params.column.isEmpty ? "Select a column" : "\(params.column), lags 0–\(params.maxLag)" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder
        guard !params.column.isEmpty else { throw WidgetError.message("Select a column") }
        let series = df.vector(params.column)
        let lag = min(params.maxLag, max(1, series.count - 1))
        guard series.count > lag else { throw WidgetError.message("Not enough rows for that many lags") }

        let values = acf(series, maxLag: lag)
        let labels = (0...lag).map(String.init)
        return .chart(.bars(categories: labels, values: values, xLabel: "Lag", yLabel: "ACF",
                             title: "Autocorrelation of \(params.column)"))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(ACFInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .chart(let data)? = output else { return AnyView(EmptyView()) }
        return AnyView(ChartView(data: data))
    }
}

private struct ACFInspectorView: View {
    let widget: ACFWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table first.").foregroundStyle(.secondary)
            } else {
                Picker("Column", selection: Binding(get: { widget.column }, set: { widget.column = $0; onChange() })) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                Stepper("Max lag: \(widget.maxLag)", value: Binding(get: { widget.maxLag }, set: { widget.maxLag = $0; onChange() }), in: 1...100)
            }
        }
    }
}
