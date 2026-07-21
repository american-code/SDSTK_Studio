import Foundation
import SwiftUI
import DataScience

/// Generates configurable synthetic (x, y) data — no bundled example dataset is large or
/// shaped right to show off `Signal`/`TimeSeries`/`Optimize` convincingly, so this widget
/// produces exactly what each of those demos needs: a periodic wave for FFT/autocorrelation, or
/// a noisy curve for `Optimize.CurveFit` to recover. Also a real (if secondary) capability demo
/// on its own — generating hundreds of thousands of rows is near-instant, which is the same
/// story `Data.Benchmark` tells more explicitly.
final class SyntheticSignalWidget: StudioWidget {
    static let typeID = "Data.SyntheticSignal"
    static let category = WidgetCategory.data
    static let displayName = "Synthetic Signal"
    static let symbolName = "waveform.path"
    static let inputPorts: [PortSpec] = []
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    enum Kind: String, Codable, CaseIterable {
        case sine = "Sine wave"
        case quadratic = "Quadratic"
        case exponential = "Exponential decay"
    }

    private struct Params: Codable { var kind: Kind = .sine; var rows: Int = 500; var noise: Double = 0.1 }
    private var params = Params()

    var kind: Kind {
        get { params.kind }
        set { params.kind = newValue }
    }
    var rows: Int {
        get { params.rows }
        set { params.rows = newValue }
    }
    var noise: Double {
        get { params.noise }
        set { params.noise = newValue }
    }

    var summary: String { "\(params.kind.rawValue), \(params.rows) rows" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        var rng = SeededGenerator(seed: 7)
        let n = max(2, params.rows)
        var xs = [Double](repeating: 0, count: n)
        var ys = [Double](repeating: 0, count: n)

        for i in 0..<n {
            let noiseTerm = (Double(rng.next() >> 11) * (1.0 / Double(1 << 53)) - 0.5) * 2 * params.noise
            switch params.kind {
            case .sine:
                let x = Double(i)
                xs[i] = x
                ys[i] = sin(2 * .pi * x / 50) + noiseTerm
            case .quadratic:
                let x = Double(i) / Double(n - 1) * 10
                xs[i] = x
                ys[i] = 0.5 * x * x - 3 * x + 2 + noiseTerm * 5
            case .exponential:
                let x = Double(i) / Double(n - 1) * 10
                xs[i] = x
                ys[i] = 5 * exp(-0.3 * x) + noiseTerm
            }
        }
        return .table(DataFrame(["x": Column(xs), "y": Column(ys)]))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(Form {
            Picker("Kind", selection: Binding(get: { self.kind }, set: { self.kind = $0; onChange() })) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Stepper("Rows: \(rows)", value: Binding(get: { self.rows }, set: { self.rows = $0; onChange() }), in: 10...1_000_000, step: rows < 1000 ? 10 : 10_000)
            Slider(value: Binding(get: { self.noise }, set: { self.noise = $0; onChange() }), in: 0...1) {
                Text("Noise: \(String(format: "%.2f", noise))")
            }
        })
    }
}
