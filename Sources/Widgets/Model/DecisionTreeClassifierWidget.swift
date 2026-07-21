import Foundation
import SwiftUI
import DataScience

/// An unfitted CART decision-tree classifier learner.
final class DecisionTreeClassifierWidget: StudioWidget {
    static let typeID = "Model.DecisionTreeClassifier"
    static let category = WidgetCategory.model
    static let displayName = "Decision Tree (Classifier)"
    static let symbolName = "arrow.triangle.branch"
    static let inputPorts: [PortSpec] = []
    static let outputPorts: [PortSpec] = [PortSpec(name: "learner", kind: .classifierLearner)]

    private struct Params: Codable { var maxDepth: Int = 6 }
    private var params = Params()

    var maxDepth: Int {
        get { params.maxDepth }
        set { params.maxDepth = newValue }
    }

    var summary: String { "max depth \(params.maxDepth)" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        .classifierLearner(.decisionTree(maxDepth: params.maxDepth))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(Form {
            Stepper("Max depth: \(maxDepth)",
                    value: Binding(get: { self.maxDepth }, set: { self.maxDepth = $0; onChange() }), in: 1...30)
        })
    }
}
