import Foundation
import SwiftUI
import DataScience
import Signal

/// Magnitude spectrum of a numeric column via SDSTK's `Signal` module — one of the "beyond
/// Orange" categories (see PLAN.md §2), since Orange has no native signal-processing widgets.
final class FFTWidget: StudioWidget {
    static let typeID = "Signal.FFT"
    static let category = WidgetCategory.signal
    static let displayName = "FFT"
    static let symbolName = "waveform"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "chart", kind: .chart)]

    private struct Params: Codable { var column: String = ""; var sampleRate: Double = 1.0 }
    private var params = Params()
    private(set) var availableColumns: [String] = []

    var column: String {
        get { params.column }
        set { params.column = newValue }
    }
    var sampleRate: Double {
        get { params.sampleRate }
        set { params.sampleRate = newValue }
    }

    var summary: String { params.column.isEmpty ? "Select a column" : "\(params.column) @ \(params.sampleRate) Hz" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder
        guard !params.column.isEmpty else { throw WidgetError.message("Select a column") }
        let signal = df.vector(params.column).filter { $0.isFinite }
        guard signal.count >= 4 else { throw WidgetError.message("Need at least 4 samples") }

        let result = fft(signal, window: Window.hann(signal.count))
        let freqs = result.frequencies(sampleRate: params.sampleRate)
        let points = zip(freqs, result.magnitude).map { ChartData.Point(x: $0, y: $1) }
        return .chart(.points(points: points, xLabel: "Frequency (Hz)", yLabel: "Magnitude",
                               title: "FFT of \(params.column)"))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(FFTInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .chart(let data)? = output else { return AnyView(EmptyView()) }
        return AnyView(ChartView(data: data))
    }
}

private struct FFTInspectorView: View {
    let widget: FFTWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table first.").foregroundStyle(.secondary)
            } else {
                Picker("Column", selection: Binding(get: { widget.column }, set: { widget.column = $0; onChange() })) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                TextField("Sample rate (Hz)", value: Binding(get: { widget.sampleRate }, set: { widget.sampleRate = $0; onChange() }), format: .number)
                #if os(iOS)
                    .keyboardType(.decimalPad)
                #endif
            }
        }
    }
}
