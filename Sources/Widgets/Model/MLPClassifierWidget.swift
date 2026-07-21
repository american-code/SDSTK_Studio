import Foundation
import SwiftUI
import DataScience
import Neural
import MLX
import MLXNN
import MLXOptimizers

/// Trains an MLX-backed multi-layer perceptron *classifier* on the incoming table — the
/// classification counterpart to `Model.MLPRegressor`, sharing its shape: self-contained
/// train-and-report (Neural's MLX loop can't ride `Learn`'s `crossValScore`), loss-curve chart
/// out, same Metal-shader-library guard-before-touch (see `BenchmarkWidget.metallibAvailable`).
///
/// The target column's distinct values become integer class labels (sorted for determinism),
/// the output layer is `numClasses` wide, and the loss is softmax cross-entropy on logits
/// (`Neural.Loss.crossEntropy`). Final training accuracy is reported in the summary alongside
/// the loss curve.
final class MLPClassifierWidget: StudioWidget {
    static let typeID = "Model.MLPClassifier"
    static let category = WidgetCategory.model
    static let displayName = "Neural Network Classifier (MLP)"
    static let symbolName = "brain.head.profile"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "loss curve", kind: .chart)]

    private struct Params: Codable {
        var targetColumn: String = ""
        var featureColumns: [String] = []
        var hiddenLayers: String = "32,16"
        var epochs: Int = 50
        var batchSize: Int = 32
        var learningRate: Double = 0.01
    }
    private var params = Params()
    private(set) var availableColumns: [String] = []
    private(set) var finalAccuracy: Double?

    var targetColumn: String {
        get { params.targetColumn }
        set { params.targetColumn = newValue }
    }
    var featureColumns: [String] {
        get { params.featureColumns }
        set { params.featureColumns = newValue }
    }
    var hiddenLayers: String {
        get { params.hiddenLayers }
        set { params.hiddenLayers = newValue }
    }
    var epochs: Int {
        get { params.epochs }
        set { params.epochs = newValue }
    }
    var learningRate: Double {
        get { params.learningRate }
        set { params.learningRate = newValue }
    }

    var summary: String {
        if params.targetColumn.isEmpty { return "Select target + features" }
        let arch = "[\(params.hiddenLayers)]"
        if let finalAccuracy {
            return "classify \(params.targetColumn), \(arch) — \(String(format: "%.0f%%", finalAccuracy * 100)) train acc"
        }
        return "classify \(params.targetColumn), \(arch), \(params.epochs) epochs"
    }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder
        guard !params.targetColumn.isEmpty, !params.featureColumns.isEmpty else {
            throw WidgetError.message("Select a target and at least one feature column")
        }
        guard BenchmarkWidget.metallibAvailable else {
            throw WidgetError.message(
                "No compiled MLX Metal shader library found, so GPU training is unavailable. "
                + "A real Xcode build should produce this automatically with no network access.")
        }

        let hidden = params.hiddenLayers.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !hidden.isEmpty else { throw WidgetError.message("Hidden layers must be a comma-separated list, e.g. 32,16") }

        // Labels come from the target column as strings (works for both text labels and
        // numeric class codes); sorted distinct values → dense 0..<k indices, deterministically.
        let labels = df[params.targetColumn].stringValues()
        let features = params.featureColumns.map { df.vector($0) }
        let keep = labels.indices.filter { i in features.allSatisfy { $0[i].isFinite } }
        guard keep.count >= 4 else { throw WidgetError.message("Not enough complete rows to train") }

        let classes = Array(Set(keep.map { labels[$0] })).sorted()
        guard classes.count >= 2 else { throw WidgetError.message("Target column needs at least two distinct classes") }
        let classIndex = Dictionary(uniqueKeysWithValues: classes.enumerated().map { ($0.element, Int32($0.offset)) })

        let n = keep.count, d = features.count
        var xFlat = [Float](); xFlat.reserveCapacity(n * d)
        var yFlat = [Int32](); yFlat.reserveCapacity(n)
        for i in keep {
            for f in features { xFlat.append(Float(f[i])) }
            yFlat.append(classIndex[labels[i]]!)
        }
        let X = MLXArray(xFlat, [n, d])
        let y = MLXArray(yFlat, [n])

        let model = MLP(layers: [d] + hidden + [classes.count])
        let optimizer = Adam(learningRate: Float(params.learningRate))
        let config = TrainConfig(epochs: max(1, params.epochs), batchSize: max(1, params.batchSize),
                                  validationSplit: 0, printEvery: 0)
        let history = Neural.train(model: model, optimizer: optimizer, loss: Loss.crossEntropy, X: X, y: y, config: config)

        // Training accuracy: argmax over logits vs true class, computed on-GPU then reduced.
        let predicted = argMax(model(X), axis: 1)
        let correct = sum(predicted .== y.asType(predicted.dtype)).item(Int.self)
        finalAccuracy = Double(correct) / Double(n)

        let points = history.trainLoss.enumerated().map { ChartData.Point(x: Double($0.offset + 1), y: Double($0.element)) }
        return .chart(.points(points: points, xLabel: "epoch", yLabel: "cross-entropy loss",
                               title: "MLP classifier loss — \(params.targetColumn) (\(classes.count) classes)"))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(MLPClassifierInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .chart(let data)? = output else { return AnyView(EmptyView()) }
        return AnyView(ChartView(data: data))
    }
}

private struct MLPClassifierInspectorView: View {
    let widget: MLPClassifierWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a Data widget with a table first.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Target (class labels)", selection: Binding(get: { widget.targetColumn }, set: { widget.targetColumn = $0; onChange() })) {
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
                Section("Network") {
                    TextField("Hidden layers (e.g. 32,16)", text: Binding(
                        get: { widget.hiddenLayers }, set: { widget.hiddenLayers = $0; onChange() }))
                    Stepper("Epochs: \(widget.epochs)",
                            value: Binding(get: { widget.epochs }, set: { widget.epochs = $0; onChange() }),
                            in: 1...500, step: 10)
                    Stepper("Learning rate: \(widget.learningRate, specifier: "%.3f")",
                            value: Binding(get: { widget.learningRate }, set: { widget.learningRate = $0; onChange() }),
                            in: 0.001...0.5, step: 0.005)
                }
                if !BenchmarkWidget.metallibAvailable {
                    Text("No compiled MLX Metal shader library found — GPU training is unavailable "
                         + "in this build. A real Xcode build produces one automatically.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
