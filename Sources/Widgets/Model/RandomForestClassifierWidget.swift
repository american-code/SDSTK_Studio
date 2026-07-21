import Foundation
import SwiftUI
import DataScience

/// An unfitted random-forest classifier learner.
final class RandomForestClassifierWidget: StudioWidget {
    static let typeID = "Model.RandomForestClassifier"
    static let category = WidgetCategory.model
    static let displayName = "Random Forest (Classifier)"
    static let symbolName = "tree"
    static let inputPorts: [PortSpec] = []
    static let outputPorts: [PortSpec] = [PortSpec(name: "learner", kind: .classifierLearner)]

    private struct Params: Codable { var numTrees: Int = 100; var maxDepth: Int = 8 }
    private var params = Params()

    var numTrees: Int {
        get { params.numTrees }
        set { params.numTrees = newValue }
    }
    var maxDepth: Int {
        get { params.maxDepth }
        set { params.maxDepth = newValue }
    }

    var summary: String { "\(params.numTrees) trees, max depth \(params.maxDepth)" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        .classifierLearner(.randomForest(numTrees: params.numTrees, maxDepth: params.maxDepth))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(Form {
            Stepper("Trees: \(numTrees)", value: Binding(get: { self.numTrees }, set: { self.numTrees = $0; onChange() }), in: 10...500, step: 10)
            Stepper("Max depth: \(maxDepth)", value: Binding(get: { self.maxDepth }, set: { self.maxDepth = $0; onChange() }), in: 1...30)
        })
    }
}
