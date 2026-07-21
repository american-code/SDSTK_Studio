import Foundation
import SwiftUI
import DataScience

/// An unfitted gradient-boosted-trees regressor learner. `Learn.GradientBoostingRegressor`
/// already existed (used internally by SDSTK's own benchmarks); this is its first canvas widget.
final class GradientBoostingRegressorWidget: StudioWidget {
    static let typeID = "Model.GradientBoostingRegressor"
    static let category = WidgetCategory.model
    static let displayName = "Gradient Boosting (Regressor)"
    static let symbolName = "chart.line.uptrend.xyaxis"
    static let inputPorts: [PortSpec] = []
    static let outputPorts: [PortSpec] = [PortSpec(name: "learner", kind: .regressorLearner)]

    private struct Params: Codable { var numTrees: Int = 100; var learningRate: Double = 0.1; var maxDepth: Int = 3 }
    private var params = Params()

    var numTrees: Int {
        get { params.numTrees }
        set { params.numTrees = newValue }
    }
    var learningRate: Double {
        get { params.learningRate }
        set { params.learningRate = newValue }
    }
    var maxDepth: Int {
        get { params.maxDepth }
        set { params.maxDepth = newValue }
    }

    var summary: String { "\(params.numTrees) trees, lr=\(String(format: "%.2f", params.learningRate)), depth \(params.maxDepth)" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        .regressorLearner(.gradientBoosting(numTrees: params.numTrees, learningRate: params.learningRate, maxDepth: params.maxDepth))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(Form {
            Stepper("Trees: \(numTrees)", value: Binding(get: { self.numTrees }, set: { self.numTrees = $0; onChange() }), in: 10...500, step: 10)
            Slider(value: Binding(get: { self.learningRate }, set: { self.learningRate = $0; onChange() }), in: 0.01...1.0) {
                Text("Learning rate: \(String(format: "%.2f", learningRate))")
            }
            Stepper("Max depth: \(maxDepth)", value: Binding(get: { self.maxDepth }, set: { self.maxDepth = $0; onChange() }), in: 1...10)
        })
    }
}
