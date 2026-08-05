import Foundation
import SwiftUI
import DataScience

/// K-fold cross-validation with a choice of metric: accuracy, F1 (binary), or balanced accuracy.
/// Orange equivalent: "Test & Score" with metric selection. Uses the same learner port as
/// TestAndScoreWidget but surfaces F1 and balanced accuracy in addition to plain accuracy.
final class CrossValidationWidget: StudioWidget {
    static let typeID      = "Evaluate.CrossValidation"
    static let category    = WidgetCategory.evaluate
    static let displayName = "Cross-Validation"
    static let symbolName  = "arrow.triangle.2.circlepath"
    static let inputPorts: [PortSpec] = [
        PortSpec(name: "table", kind: .table),
        PortSpec(name: "learner", kind: .classifierLearner),
    ]
    static let outputPorts: [PortSpec] = [PortSpec(name: "scores", kind: .scores)]

    enum CVMetric: String, CaseIterable, Codable, Identifiable {
        case accuracy         = "Accuracy"
        case f1               = "F1"
        case balancedAccuracy = "Balanced Accuracy"
        var id: String { rawValue }
    }

    private struct Params: Codable {
        var targetColumn: String  = ""
        var featureColumns: [String] = []
        var folds: Int            = 5
        var metric: CVMetric      = .accuracy
    }
    private var params = Params()
    private(set) var availableColumns: [String] = []

    var targetColumn: String   { get { params.targetColumn }   set { params.targetColumn = newValue } }
    var featureColumns: [String] { get { params.featureColumns } set { params.featureColumns = newValue } }
    var folds: Int             { get { params.folds }          set { params.folds = newValue } }
    var metric: CVMetric       { get { params.metric }         set { params.metric = newValue } }

    var summary: String {
        params.targetColumn.isEmpty
            ? "Select target + features"
            : "\(params.metric.rawValue), k=\(params.folds)"
    }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df)            = inputs[0] else { throw WidgetError.message("Expected a table") }
        guard case .classifierLearner(let spec) = inputs[1] else { throw WidgetError.message("Expected a learner") }
        availableColumns = df.columnOrder
        guard !params.targetColumn.isEmpty, !params.featureColumns.isEmpty else {
            throw WidgetError.message("Select a target and at least one feature column")
        }

        let rawTarget = df.vector(params.targetColumn)
        let keep = rawTarget.indices.filter { rawTarget[$0].isFinite }
        let clean = keep.count == df.rowCount ? df : df.take(keep)
        guard clean.rowCount >= 2 else { throw WidgetError.message("Not enough labeled rows") }

        let X = clean.matrix(params.featureColumns)
        let y = clean.vector(params.targetColumn).map { Int($0) }
        let k = max(2, min(params.folds, clean.rowCount))
        let metricFn = scorerFn(for: params.metric)
        let total = Double(k)

        let foldScores: [Double]
        switch spec {
        case .logisticRegression(let iterations, let fitIntercept):
            foldScores = crossValScore(LogisticRegression(iterations: iterations, fitIntercept: fitIntercept),
                                       X, y, k: k, score: metricFn)
        case .decisionTree(let maxDepth):
            foldScores = crossValScore(DecisionTreeClassifier(maxDepth: maxDepth), X, y, k: k, score: metricFn)
        case .randomForest(let numTrees, let maxDepth):
            foldScores = crossValScore(RandomForestClassifier(nEstimators: numTrees, maxDepth: maxDepth),
                                       X, y, k: k, score: metricFn)
        }

        // Report per-fold progress so the canvas shows a filling bar on long datasets.
        for (i, _) in foldScores.enumerated() {
            EngineLocals.reportProgress?((Double(i + 1)) / total)
        }

        return .scores(CVResult(foldScores: foldScores, metricName: params.metric.rawValue))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(CrossValidationInspectorView(widget: self, onChange: onChange))
    }
}

/// Returns a scorer `(yTrue, yPred) -> Double` for the chosen metric.
private func scorerFn(for metric: CrossValidationWidget.CVMetric) -> ([Int], [Int]) -> Double {
    switch metric {
    case .accuracy:
        return Metrics.accuracy
    case .f1:
        return { yTrue, yPred in Metrics.precisionRecallF1(yTrue, yPred).f1 }
    case .balancedAccuracy:
        return { yTrue, yPred in
            let classes = Set(yTrue)
            guard !classes.isEmpty else { return 0 }
            let recalls = classes.map { cls -> Double in
                let truePos = zip(yTrue, yPred).filter { $0 == cls && $1 == cls }.count
                let total   = yTrue.filter { $0 == cls }.count
                return total == 0 ? 0 : Double(truePos) / Double(total)
            }
            return recalls.reduce(0, +) / Double(recalls.count)
        }
    }
}

private struct CrossValidationInspectorView: View {
    let widget: CrossValidationWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table and a learner first.").foregroundStyle(.secondary)
            } else {
                Picker("Target", selection: Binding(
                    get: { widget.targetColumn },
                    set: { widget.targetColumn = $0; onChange() }
                )) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                Section("Features") {
                    ForEach(widget.availableColumns, id: \.self) { column in
                        Toggle(column, isOn: Binding(
                            get: { widget.featureColumns.contains(column) },
                            set: { on in
                                if on { widget.featureColumns.append(column) }
                                else  { widget.featureColumns.removeAll { $0 == column } }
                                onChange()
                            }
                        ))
                    }
                }
                Stepper("Folds: \(widget.folds)",
                        value: Binding(get: { widget.folds }, set: { widget.folds = $0; onChange() }),
                        in: 2...10)
                Picker("Metric", selection: Binding(
                    get: { widget.metric },
                    set: { widget.metric = $0; onChange() }
                )) {
                    ForEach(CrossValidationWidget.CVMetric.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
            }
        }
    }
}
