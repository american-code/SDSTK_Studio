import Foundation
import SwiftUI
import CoreML
import DataScience

/// Runs an externally-trained Core ML tabular regressor (e.g. ModelBuilder's Create ML
/// regression trainer) as one "expert" node — the `.table`-in counterpart to
/// `Experts.CoreMLExpert` (image-in). Takes exactly one row from the incoming table (the
/// selected `rowIndex`) as one instance's feature values; evaluating a whole dataset is a
/// different job already covered by `Evaluate.TestAndScore`.
///
/// Feature columns are auto-matched to the loaded model's declared input names rather than
/// through a manual mapping UI — Create ML training preserves the original CSV column names
/// through to the model's input schema, so a DataFrame column named the same as a model input
/// is, in practice, that input. A model expecting a column the table doesn't have throws a
/// specific error naming it, rather than silently guessing.
final class CoreMLTabularExpertWidget: StudioWidget, ExportsEmbeddedModel {
    static let typeID = "Experts.CoreMLTabularExpert"
    static let category = WidgetCategory.experts
    static let displayName = "Core ML Expert (Tabular)"
    static let symbolName = "tablecells.badge.ellipsis"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "prediction", kind: .prediction)]

    private struct Params: Codable {
        var model = ModelFileBookmark()
        var expertName: String = ""
        var rowIndex: Int = 0
    }
    private var params = Params()
    private var cachedModel: MLModel?
    private var cachedModelBookmark: Data?

    var fileName: String? { params.model.fileName }
    var expertName: String {
        get { params.expertName }
        set { params.expertName = newValue }
    }
    var rowIndex: Int {
        get { params.rowIndex }
        set { params.rowIndex = newValue }
    }

    var summary: String {
        guard let fileName else { return "No model selected" }
        return params.expertName.isEmpty ? fileName : "\(params.expertName) (\(fileName))"
    }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws {
        params = try JSONDecoder().decode(Params.self, from: data)
        cachedModel = nil
    }

    func setFile(url: URL) {
        params.model.setFile(url)
        if params.expertName.isEmpty {
            params.expertName = url.deletingPathExtension().lastPathComponent
        }
        cachedModel = nil
    }

    func rebind(toLocalFile url: URL) {
        params.model.rebind(toLocalFile: url)
        cachedModel = nil
    }

    func stageModelFileForExport() throws -> URL? {
        try params.model.stageForExport()
    }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        guard df.rowCount > 0 else { throw WidgetError.message("Table has no rows") }
        let row = min(max(params.rowIndex, 0), df.rowCount - 1)

        let mlModel = try loadModel()
        var featureDict: [String: MLFeatureValue] = [:]
        for name in mlModel.modelDescription.inputDescriptionsByName.keys {
            guard df.columnOrder.contains(name) else {
                throw WidgetError.message("Model expects a column named “\(name)”, not found in the table")
            }
            featureDict[name] = MLFeatureValue(double: df.vector(name)[row])
        }
        // On macOS in this SDK, `MLModel.prediction` only exists as the `async` overload (the
        // synchronous `prediction(fromFeatures:options:)` is `@available(macOS, unavailable)`).
        // `mlModel` is non-`Sendable` and lives in `@MainActor`-isolated widget state, so handing
        // it to this nonisolated async API trips Swift's conservative sending-risk check even
        // though nothing else touches it concurrently in practice — this widget's `run()` is the
        // only thing that ever holds a reference to it. `nonisolated(unsafe)` on this one local
        // binding is the sanctioned escape hatch for exactly that situation.
        nonisolated(unsafe) let modelForPrediction = mlModel
        let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
        let output = try await modelForPrediction.prediction(from: provider, options: MLPredictionOptions())

        // Create ML tabular regressors name their single output feature after the training
        // target column — read whichever output the model actually declares rather than
        // guessing a fixed name.
        let name = params.expertName.isEmpty ? (params.model.fileName ?? "expert") : params.expertName
        guard let outputName = mlModel.modelDescription.outputDescriptionsByName.keys.first,
              let outputValue = output.featureValue(for: outputName) else {
            // Same reasoning as `CoreMLExpertWidget`: no usable output is data a downstream
            // `MemStacker` can act on, not a graph-halting failure.
            return .prediction(ExpertPrediction(sourceName: name))
        }
        return .prediction(ExpertPrediction(value: outputValue.doubleValue, sourceName: name))
    }

    private func loadModel() throws -> MLModel {
        if let cachedModel, cachedModelBookmark == params.model.bookmark { return cachedModel }
        let mlModel = try params.model.withResolvedURL { url -> MLModel in
            let compiledURL = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
            return try MLModel(contentsOf: compiledURL)
        }
        cachedModel = mlModel
        cachedModelBookmark = params.model.bookmark
        return mlModel
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(CoreMLTabularExpertInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .prediction(let prediction)? = output else { return AnyView(EmptyView()) }
        return AnyView(PredictionPreviewView(prediction: prediction))
    }
}

private struct CoreMLTabularExpertInspectorView: View {
    let widget: CoreMLTabularExpertWidget
    let onChange: () -> Void
    @State private var showImporter = false

    var body: some View {
        Form {
            Section("Model") {
                Button(widget.fileName ?? "Choose Model…") { showImporter = true }
                TextField("Expert name", text: Binding(
                    get: { widget.expertName },
                    set: { widget.expertName = $0; onChange() }
                ))
                Stepper("Row: \(widget.rowIndex)",
                        value: Binding(get: { widget.rowIndex }, set: { widget.rowIndex = $0; onChange() }),
                        in: 0...9999)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: coreMLFileTypes) { result in
            guard case .success(let url) = result else { return }
            widget.setFile(url: url)
            onChange()
        }
    }
}
