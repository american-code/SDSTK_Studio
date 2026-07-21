import Foundation
import SwiftUI
import DataScience

/// Fits an incoming `ClassifierSpec` on a held-out train/test split and renders the resulting
/// confusion matrix as a heatmap — Orange's Confusion Matrix widget. Where `Test & Score`
/// reports an aggregate cross-validated score, this shows where a single fit's mistakes land
/// (rows = true class, columns = predicted class).
final class ConfusionMatrixWidget: StudioWidget {
    static let typeID = "Evaluate.ConfusionMatrix"
    static let category = WidgetCategory.evaluate
    static let displayName = "Confusion Matrix"
    static let symbolName = "square.grid.3x3"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table), PortSpec(name: "learner", kind: .classifierLearner)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "chart", kind: .chart)]

    private struct Params: Codable {
        var targetColumn: String = ""
        var featureColumns: [String] = []
        var testFraction: Double = 0.25
    }
    private var params = Params()
    private(set) var availableColumns: [String] = []
    private(set) var accuracyText = ""

    var targetColumn: String {
        get { params.targetColumn }
        set { params.targetColumn = newValue }
    }
    var featureColumns: [String] {
        get { params.featureColumns }
        set { params.featureColumns = newValue }
    }
    var testFraction: Double {
        get { params.testFraction }
        set { params.testFraction = newValue }
    }

    var summary: String {
        params.targetColumn.isEmpty ? "Select target + features" : accuracyText.isEmpty ? "predict \(params.targetColumn)" : accuracyText
    }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        guard case .classifierLearner(let spec) = inputs[1] else { throw WidgetError.message("Expected a learner") }
        availableColumns = df.columnOrder
        guard !params.targetColumn.isEmpty, !params.featureColumns.isEmpty else {
            throw WidgetError.message("Select a target and at least one feature column")
        }

        let rawTarget = df.vector(params.targetColumn)
        let keep = rawTarget.indices.filter { rawTarget[$0].isFinite }
        let clean = keep.count == df.rowCount ? df : df.take(keep)
        guard clean.rowCount >= 4 else { throw WidgetError.message("Not enough labeled rows to evaluate") }

        var rng = SeededGenerator(seed: 42)
        let shuffled = Array(0..<clean.rowCount).shuffled(using: &rng)
        let testCount = max(1, Int(Double(clean.rowCount) * params.testFraction))
        let testIdx = Array(shuffled.prefix(testCount)).sorted()
        let trainIdx = Array(shuffled.dropFirst(testCount)).sorted()
        guard !trainIdx.isEmpty, !testIdx.isEmpty else { throw WidgetError.message("Need rows on both sides of the split") }

        let trainDF = clean.take(trainIdx), testDF = clean.take(testIdx)
        let xTrain = trainDF.matrix(params.featureColumns)
        let yTrain = trainDF.vector(params.targetColumn).map { Int($0) }
        let xTest = testDF.matrix(params.featureColumns)
        let yTest = testDF.vector(params.targetColumn).map { Int($0) }
        let numClasses = (clean.vector(params.targetColumn).map { Int($0) }.max() ?? 0) + 1

        let yPred: [Int]
        switch spec {
        case .logisticRegression(let iterations, let fitIntercept):
            var model = LogisticRegression(iterations: iterations, fitIntercept: fitIntercept)
            model.fit(xTrain, yTrain)
            yPred = model.predict(xTest)
        case .decisionTree(let maxDepth):
            var model = DecisionTreeClassifier(maxDepth: maxDepth)
            model.fit(xTrain, yTrain)
            yPred = model.predict(xTest)
        case .randomForest(let numTrees, let maxDepth):
            var model = RandomForestClassifier(nEstimators: numTrees, maxDepth: maxDepth)
            model.fit(xTrain, yTrain)
            yPred = model.predict(xTest)
        }

        let matrix = Metrics.confusionMatrix(yTest, yPred, labelCount: numClasses)
        let labels = (0..<numClasses).map(String.init)
        accuracyText = "accuracy \(String(format: "%.1f", Metrics.accuracy(yTest, yPred) * 100))% on \(testIdx.count) held-out rows"

        return .chart(.heatmap(rowLabels: labels, colLabels: labels,
                                values: matrix.map { $0.map(Double.init) },
                                title: "Confusion Matrix (rows=true, cols=predicted)"))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(ConfusionMatrixInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .chart(let data)? = output else { return AnyView(EmptyView()) }
        return AnyView(ChartView(data: data))
    }
}

private struct ConfusionMatrixInspectorView: View {
    let widget: ConfusionMatrixWidget
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
                Slider(value: Binding(get: { widget.testFraction }, set: { widget.testFraction = $0; onChange() }), in: 0.1...0.5) {
                    Text("Test fraction: \(Int(widget.testFraction * 100))%")
                }
                if !widget.accuracyText.isEmpty {
                    Text(widget.accuracyText).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
