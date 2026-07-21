import Foundation
import SwiftUI
import DataScience

/// Keeps a random fraction of rows — Orange's Data Sampler, simplified to one fixed-fraction mode.
final class SamplerWidget: StudioWidget {
    static let typeID = "Data.Sampler"
    static let category = WidgetCategory.data
    static let displayName = "Data Sampler"
    static let symbolName = "die.face.3"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    private struct Params: Codable { var fraction: Double = 0.5; var seed: UInt64 = 42 }
    private var params = Params()

    var fraction: Double {
        get { params.fraction }
        set { params.fraction = newValue }
    }

    var summary: String { "\(Int(params.fraction * 100))% of rows" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        var rng = SeededGenerator(seed: params.seed)
        let keepCount = max(1, Int((Double(df.rowCount) * params.fraction).rounded()))
        let indices = Array(0..<df.rowCount).shuffled(using: &rng).prefix(keepCount).sorted()
        return .table(df.take(Array(indices)))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(SamplerInspectorView(widget: self, onChange: onChange))
    }
}

/// A tiny deterministic RNG so re-running with unchanged params reproduces the same sample.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private struct SamplerInspectorView: View {
    let widget: SamplerWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            Slider(value: Binding(get: { widget.fraction }, set: { widget.fraction = $0; onChange() }), in: 0.05...1.0) {
                Text("Fraction")
            }
            Text("\(Int(widget.fraction * 100))% of rows").font(.caption).foregroundStyle(.secondary)
        }
    }
}
