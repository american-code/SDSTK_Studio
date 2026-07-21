import Foundation
import SwiftUI
import DataScience
import Neural
import MLX
import MLXNN
import MLXOptimizers

/// Trains an MLX-backed multi-layer perceptron regressor on the incoming table and outputs its
/// per-epoch training-loss curve as a chart — the first `Neural`-module widget, closing the
/// "no GPU-trained neural model on the canvas" gap.
///
/// Unlike the other Model-category widgets (unfitted `RegressorSpec`s handed to Test & Score,
/// which fits per fold via `Learn`), this widget trains *itself*: `Neural`'s `train()` loop is
/// MLX-specific and can't ride `Learn`'s `crossValScore` path. Self-contained train-and-report
/// is the honest fit, not a forced abstraction.
///
/// MLX is GPU-only here and hard-exits (not throws) without a compiled Metal shader library
/// available — same guard-before-touch pattern as `Data.Benchmark` (see its doc comment for why
/// `BenchmarkWidget.metallibAvailable` checks Xcode's native resource bundle first).
final class MLPRegressorWidget: StudioWidget {
    static let typeID = "Model.MLPRegressor"
    static let category = WidgetCategory.model
    static let displayName = "Neural Network (MLP)"
    static let symbolName = "brain"
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
    private(set) var finalLoss: Float?

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
        if let finalLoss { return "predict \(params.targetColumn), \(arch) — loss \(String(format: "%.4f", finalLoss))" }
        return "predict \(params.targetColumn), \(arch), \(params.epochs) epochs"
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

        // Drop rows with non-finite target or features — same posture as Test & Score.
        let target = df.vector(params.targetColumn)
        let features = params.featureColumns.map { df.vector($0) }
        let keep = target.indices.filter { i in target[i].isFinite && features.allSatisfy { $0[i].isFinite } }
        guard keep.count >= 4 else { throw WidgetError.message("Not enough complete rows to train") }

        let n = keep.count, d = features.count
        var xFlat = [Float](); xFlat.reserveCapacity(n * d)
        var yFlat = [Float](); yFlat.reserveCapacity(n)
        for i in keep {
            for f in features { xFlat.append(Float(f[i])) }
            yFlat.append(Float(target[i]))
        }
        let X = MLXArray(xFlat, [n, d])
        let y = MLXArray(yFlat, [n, 1])

        let model = MLP(layers: [d] + hidden + [1])
        let optimizer = Adam(learningRate: Float(params.learningRate))
        let config = TrainConfig(epochs: max(1, params.epochs), batchSize: max(1, params.batchSize),
                                  validationSplit: 0, printEvery: 0)
        let history = Neural.train(model: model, optimizer: optimizer, loss: Loss.mse, X: X, y: y, config: config)

        finalLoss = history.trainLoss.last
        let points = history.trainLoss.enumerated().map { ChartData.Point(x: Double($0.offset + 1), y: Double($0.element)) }
        return .chart(.points(points: points, xLabel: "epoch", yLabel: "MSE loss",
                               title: "MLP training loss — \(params.targetColumn)"))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(MLPRegressorInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .chart(let data)? = output else { return AnyView(EmptyView()) }
        return AnyView(ChartView(data: data))
    }
}

private struct MLPRegressorInspectorView: View {
    let widget: MLPRegressorWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a Data widget with a table first.")
                    .foregroundStyle(.secondary)
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
