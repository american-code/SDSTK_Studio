import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CoreML
import Vision

/// Runs an externally-trained Core ML model (e.g. exported from ModelBuilder's Library) as one
/// "expert" node in a compound orchestration graph. Image-in — the `.table`-in counterpart for
/// tabular regressors is `Experts.CoreMLTabularExpert`.
///
/// Model compilation (`MLModel.compileModel(at:)`) is a real, sometimes-slow blocking call, and
/// this widget's `run` — like every `StudioWidget` — executes on the main actor (see
/// `StudioWidget.swift`'s concurrency note). Cached after the first successful load so only a
/// freshly-picked or freshly-changed model pays that cost; re-running the graph afterward only
/// re-pays Vision's (fast) inference cost, not compilation.
final class CoreMLExpertWidget: StudioWidget, ExportsEmbeddedModel {
    static let typeID = "Experts.CoreMLExpert"
    static let category = WidgetCategory.experts
    static let displayName = "Core ML Expert"
    static let symbolName = "cpu"
    static let inputPorts: [PortSpec] = [PortSpec(name: "image", kind: .image)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "prediction", kind: .prediction)]

    private struct Params: Codable {
        var model = ModelFileBookmark()
        var expertName: String = ""
    }
    private var params = Params()
    private var cachedModel: VNCoreMLModel?
    private var cachedModelBookmark: Data?

    var fileName: String? { params.model.fileName }
    var expertName: String {
        get { params.expertName }
        set { params.expertName = newValue }
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

    /// Points this widget at an already-local file (e.g. one just extracted from an `.mbexpert`
    /// bundle on open) without going through the sandboxed file picker — no externally-scoped
    /// resource involved since the app already owns this copy.
    func rebind(toLocalFile url: URL) {
        params.model.rebind(toLocalFile: url)
        cachedModel = nil
    }

    func stageModelFileForExport() throws -> URL? {
        try params.model.stageForExport()
    }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .image(let cgImage) = inputs[0] else { throw WidgetError.message("Expected an image") }

        let visionModel = try loadModel()
        let request = VNCoreMLRequest(model: visionModel)
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let name = params.expertName.isEmpty ? (params.model.fileName ?? "expert") : params.expertName
        if let classifications = request.results as? [VNClassificationObservation], let top = classifications.first {
            let runnerUp = classifications.count > 1 ? Double(classifications[1].confidence) : nil
            return .prediction(ExpertPrediction(label: top.identifier, confidence: Double(top.confidence),
                                                 runnerUpConfidence: runnerUp, sourceName: name))
        }
        if let features = request.results as? [VNCoreMLFeatureValueObservation], let top = features.first {
            return .prediction(ExpertPrediction(value: top.featureValue.doubleValue, sourceName: name))
        }
        // The model ran successfully but produced nothing usable — this is data a downstream
        // `MemStacker` can act on, not a graph-halting failure (see `ExpertPrediction.isEmpty`).
        return .prediction(ExpertPrediction(sourceName: name))
    }

    private func loadModel() throws -> VNCoreMLModel {
        if let cachedModel, cachedModelBookmark == params.model.bookmark { return cachedModel }
        let visionModel = try params.model.withResolvedURL { url -> VNCoreMLModel in
            // Already-compiled models (.mlmodelc) load directly; source .mlmodel/.mlpackage need
            // compiling first — required regardless of whether the source ships in-app or, as
            // here, is picked at runtime from an arbitrary user location.
            let compiledURL = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
            let mlModel = try MLModel(contentsOf: compiledURL)
            return try VNCoreMLModel(for: mlModel)
        }
        cachedModel = visionModel
        cachedModelBookmark = params.model.bookmark
        return visionModel
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(CoreMLExpertInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .prediction(let prediction)? = output else { return AnyView(EmptyView()) }
        return AnyView(PredictionPreviewView(prediction: prediction))
    }
}

/// `.mlmodel`/`.mlpackage`/`.mlmodelc` have no public `UTType` static constants — built from the
/// filename extension instead, same defensive approach as any non-common format.
let coreMLFileTypes: [UTType] = ["mlpackage", "mlmodel", "mlmodelc"].compactMap { UTType(filenameExtension: $0) }

private struct CoreMLExpertInspectorView: View {
    let widget: CoreMLExpertWidget
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
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: coreMLFileTypes) { result in
            guard case .success(let url) = result else { return }
            widget.setFile(url: url)
            onChange()
        }
    }
}

/// Shared preview for any `.prediction` output — used by both `CoreMLExpert` and
/// `CoreMLTabularExpert`.
struct PredictionPreviewView: View {
    let prediction: ExpertPrediction
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label = prediction.label {
                Text(label).font(.headline)
                if let confidence = prediction.confidence {
                    Text(String(format: "%.1f%% confidence", confidence * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let value = prediction.value {
                Text(String(format: "%.4f", value)).font(.headline)
            }
        }
        .padding(.vertical, 4)
    }
}
