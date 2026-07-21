import Foundation
import SwiftUI
import DataScience

/// The regression-side counterpart to `TestAndScoreWidget` — cross-validates an incoming
/// `RegressorSpec` against a table, scoring by R².
final class TestAndScoreRegressorWidget: StudioWidget {
    static let typeID = "Evaluate.TestAndScoreRegressor"
    static let category = WidgetCategory.evaluate
    static let displayName = "Test & Score (Regressor)"
    static let symbolName = "checkmark.seal"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table), PortSpec(name: "learner", kind: .regressorLearner)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "scores", kind: .scores)]

    private struct Params: Codable {
        var targetColumn: String = ""
        var featureColumns: [String] = []
        var folds: Int = 5
    }
    private var params = Params()
    private(set) var availableColumns: [String] = []

    var targetColumn: String {
        get { params.targetColumn }
        set { params.targetColumn = newValue }
    }
    var featureColumns: [String] {
        get { params.featureColumns }
        set { params.featureColumns = newValue }
    }
    var folds: Int {
        get { params.folds }
        set { params.folds = newValue }
    }

    var summary: String {
        params.targetColumn.isEmpty ? "Select target + features" : "predict \(params.targetColumn), k=\(params.folds)"
    }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        guard case .regressorLearner(let spec) = inputs[1] else { throw WidgetError.message("Expected a learner") }
        availableColumns = df.columnOrder
        guard !params.targetColumn.isEmpty, !params.featureColumns.isEmpty else {
            throw WidgetError.message("Select a target and at least one feature column")
        }

        let rawTarget = df.vector(params.targetColumn)
        let keep = rawTarget.indices.filter { rawTarget[$0].isFinite }
        let clean = keep.count == df.rowCount ? df : df.take(keep)
        guard clean.rowCount >= 2 else { throw WidgetError.message("Not enough labeled rows to evaluate") }

        let X = clean.matrix(params.featureColumns)
        let y = clean.vector(params.targetColumn)
        let k = max(2, min(params.folds, clean.rowCount))

        let foldScores: [Double]
        switch spec {
        case .linearRegression(let l2):
            foldScores = crossValScore(LinearRegression(l2: l2), X, y, k: k)
        case .decisionTree(let maxDepth):
            foldScores = crossValScore(DecisionTreeRegressor(maxDepth: maxDepth), X, y, k: k)
        case .randomForest(let numTrees, let maxDepth):
            foldScores = crossValScore(RandomForestRegressor(nEstimators: numTrees, maxDepth: maxDepth), X, y, k: k)
        case .gradientBoosting(let numTrees, let learningRate, let maxDepth):
            foldScores = crossValScore(GradientBoostingRegressor(nEstimators: numTrees, learningRate: learningRate, maxDepth: maxDepth), X, y, k: k)
        }
        return .scores(CVResult(foldScores: foldScores, metricName: "R²"))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(TestAndScoreRegressorInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .scores(let result)? = output else { return AnyView(EmptyView()) }
        return AnyView(VStack(alignment: .leading, spacing: 4) {
            Text("\(result.metricName): \(result.mean, specifier: "%.3f") ± \(result.std, specifier: "%.3f")").font(.headline)
            Text(result.foldScores.map { String(format: "%.3f", $0) }.joined(separator: ", "))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4))
    }
}

private struct TestAndScoreRegressorInspectorView: View {
    let widget: TestAndScoreRegressorWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table and a learner first.").foregroundStyle(.secondary)
            } else {
                Picker("Target", selection: Binding(get: { widget.targetColumn }, set: { widget.targetColumn = $0; onChange() })) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                Section("Features") {
                    ForEach(widget.availableColumns, id: \.self) { column in
                        Toggle(column, isOn: Binding(
                            get: { widget.featureColumns.contains(column) },
                            set: { isOn in
                                if isOn { widget.featureColumns.append(column) }
                                else { widget.featureColumns.removeAll { $0 == column } }
                                onChange()
                            }
                        ))
                    }
                }
                Stepper("Folds: \(widget.folds)", value: Binding(get: { widget.folds }, set: { widget.folds = $0; onChange() }), in: 2...10)
            }
        }
    }
}
