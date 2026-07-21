import Foundation
import SwiftUI
import DataScience

/// An unfitted (ridge-capable) linear regression learner.
final class LinearRegressionWidget: StudioWidget {
    static let typeID = "Model.LinearRegression"
    static let category = WidgetCategory.model
    static let displayName = "Linear Regression"
    static let symbolName = "chart.xyaxis.line"
    static let inputPorts: [PortSpec] = []
    static let outputPorts: [PortSpec] = [PortSpec(name: "learner", kind: .regressorLearner)]

    private struct Params: Codable { var l2: Double = 0 }
    private var params = Params()

    var l2: Double {
        get { params.l2 }
        set { params.l2 = newValue }
    }

    var summary: String { params.l2 > 0 ? "ridge, α=\(String(format: "%.2f", params.l2))" : "ordinary least squares" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        .regressorLearner(.linearRegression(l2: params.l2))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(Form {
            Slider(value: Binding(get: { self.l2 }, set: { self.l2 = $0; onChange() }), in: 0...5) {
                Text("Ridge α: \(String(format: "%.2f", l2))")
            }
        })
    }
}
