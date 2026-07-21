import Foundation
import SwiftUI
import DataScience

/// An unfitted logistic-regression learner. Like Orange's model widgets, this has no data
/// input of its own — it just declares hyperparameters and hands a `LearnerSpec` downstream to
/// `Test & Score`, which does the actual fitting per fold.
final class LogisticRegressionWidget: StudioWidget {
    static let typeID = "Model.LogisticRegression"
    static let category = WidgetCategory.model
    static let displayName = "Logistic Regression"
    static let symbolName = "function"
    static let inputPorts: [PortSpec] = []
    static let outputPorts: [PortSpec] = [PortSpec(name: "learner", kind: .classifierLearner)]

    private struct Params: Codable { var iterations: Int = 200; var fitIntercept: Bool = true }
    private var params = Params()

    var iterations: Int {
        get { params.iterations }
        set { params.iterations = newValue }
    }
    var fitIntercept: Bool {
        get { params.fitIntercept }
        set { params.fitIntercept = newValue }
    }

    var summary: String { "\(params.iterations) iterations" + (params.fitIntercept ? "" : ", no intercept") }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        .classifierLearner(.logisticRegression(iterations: params.iterations, fitIntercept: params.fitIntercept))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(LogisticRegressionInspectorView(widget: self, onChange: onChange))
    }
}

private struct LogisticRegressionInspectorView: View {
    let widget: LogisticRegressionWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            Stepper("Iterations: \(widget.iterations)",
                    value: Binding(get: { widget.iterations }, set: { widget.iterations = $0; onChange() }),
                    in: 10...2000, step: 10)
            Toggle("Fit intercept", isOn: Binding(
                get: { widget.fitIntercept },
                set: { widget.fitIntercept = $0; onChange() }
            ))
        }
    }
}
