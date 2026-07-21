import Foundation
import SwiftUI

/// Combines N upstream experts' predictions into one weighted result — the "project manager"
/// node from the compound-orchestration design. Echoes the original Jacobs & Jordan (1991)
/// mixture-of-experts gating network (a combiner over independent experts' outputs), not the
/// routing-inside-one-network kind of MoE transformer LLMs use.
///
/// The first widget to override `dynamicInputPorts`: its port list is generated from
/// `expertCount` in its own params (`expert1...expertN`, each with its own weight), so arity is
/// a per-node setting, not a type-level constant. Shrinking the count prunes now-dangling links
/// via the `onPortsChanged` hook the inspector receives.
final class CoordinatorWidget: StudioWidget {
    static let typeID = "Experts.Coordinator"
    static let category = WidgetCategory.experts
    static let displayName = "Coordinator"
    static let symbolName = "arrow.triangle.merge"
    /// Palette-facing default shape (what a freshly-placed node starts as).
    static let inputPorts: [PortSpec] = [
        PortSpec(name: "expert1", kind: .prediction),
        PortSpec(name: "expert2", kind: .prediction),
    ]
    static let outputPorts: [PortSpec] = [PortSpec(name: "decision", kind: .prediction)]

    enum Strategy: String, Codable, CaseIterable, Identifiable {
        case highestConfidence = "Highest confidence wins"
        case weightedAverage = "Weighted average (numeric value)"
        var id: String { rawValue }
    }

    private struct Params: Codable {
        var strategy: Strategy = .highestConfidence
        var expertCount: Int = 2
        /// One weight per expert slot, index-aligned with `expert1...expertN`. Kept at least
        /// `expertCount` long by `normalizeWeights()`; extra trailing entries from a shrink are
        /// preserved so growing back restores the old weight rather than resetting it.
        var weights: [Double] = [1.0, 1.0]
    }
    private var params = Params()

    var strategy: Strategy {
        get { params.strategy }
        set { params.strategy = newValue }
    }
    var expertCount: Int {
        get { params.expertCount }
        set {
            params.expertCount = max(2, min(newValue, 8))
            normalizeWeights()
        }
    }
    func weight(at index: Int) -> Double {
        index < params.weights.count ? params.weights[index] : 1.0
    }
    func setWeight(_ value: Double, at index: Int) {
        normalizeWeights()
        guard index < params.weights.count else { return }
        params.weights[index] = value
    }
    private func normalizeWeights() {
        while params.weights.count < params.expertCount { params.weights.append(1.0) }
    }

    var dynamicInputPorts: [PortSpec] {
        (1...params.expertCount).map { PortSpec(name: "expert\($0)", kind: .prediction) }
    }

    var summary: String { "\(params.expertCount) experts — \(params.strategy.rawValue)" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws {
        params = try JSONDecoder().decode(Params.self, from: data)
        normalizeWeights()
    }

    func run(inputs: [PortValue]) async throws -> PortValue {
        var experts: [(ExpertPrediction, Double)] = []
        for (index, input) in inputs.enumerated() {
            guard case .prediction(let p) = input else {
                throw WidgetError.message("Input expert\(index + 1) is not a prediction")
            }
            experts.append((p, weight(at: index)))
        }
        guard !experts.isEmpty else { throw WidgetError.message("No experts connected") }

        switch params.strategy {
        case .highestConfidence:
            let winner = experts.max { lhs, rhs in
                (lhs.0.confidence ?? 0) * lhs.1 < (rhs.0.confidence ?? 0) * rhs.1
            }!.0
            return .prediction(winner)

        case .weightedAverage:
            // Only experts carrying a numeric `value` (regressor-shaped output) participate;
            // a classifier-shaped expert (label/confidence, no `value`) is skipped rather than
            // coerced into a number that doesn't mean anything for it.
            let numeric = experts.filter { $0.0.value != nil }
            guard !numeric.isEmpty else {
                throw WidgetError.message("Weighted average needs at least one expert with a numeric value")
            }
            let totalWeight = numeric.reduce(0.0) { $0 + $1.1 }
            let combined = numeric.reduce(0.0) { $0 + ($1.0.value! * $1.1) } / totalWeight
            return .prediction(ExpertPrediction(value: combined, sourceName: "Coordinator"))
        }
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(CoordinatorInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .prediction(let prediction)? = output else { return AnyView(EmptyView()) }
        return AnyView(PredictionPreviewView(prediction: prediction))
    }
}

private struct CoordinatorInspectorView: View {
    let widget: CoordinatorWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            Picker("Strategy", selection: Binding(
                get: { widget.strategy },
                set: { widget.strategy = $0; onChange() }
            )) {
                ForEach(CoordinatorWidget.Strategy.allCases) { Text($0.rawValue).tag($0) }
            }
            Stepper("Experts: \(widget.expertCount)",
                    value: Binding(get: { widget.expertCount }, set: { widget.expertCount = $0; onChange() }),
                    in: 2...8)
            Section("Weights") {
                ForEach(1...widget.expertCount, id: \.self) { slot in
                    Stepper("Expert \(slot): \(widget.weight(at: slot - 1), specifier: "%.1f")",
                            value: Binding(get: { widget.weight(at: slot - 1) },
                                           set: { widget.setWeight($0, at: slot - 1); onChange() }),
                            in: 0...5, step: 0.1)
                }
            }
        }
    }
}
