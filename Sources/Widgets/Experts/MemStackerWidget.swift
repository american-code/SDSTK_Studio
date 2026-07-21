import Foundation
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Routes low-confidence / ambiguous / null predictions to a human-review queue, and once a
/// label accumulates enough reviewed examples, automatically retrains a new on-device expert —
/// the "active-learning-driven expert growth" piece of the compound-orchestration design, scoped
/// down to a single trigger→review→promote loop (no autonomous graph rewiring — see PLAN.md).
///
/// Sits downstream of a `CoreMLExpert`, taking both its `image` input (to file away) and its
/// `prediction` (to judge). Passes the prediction through unchanged either way — it's an
/// observer with a side effect, not a gate that blocks the pipeline.
final class MemStackerWidget: StudioWidget {
    static let typeID = "Experts.MemStacker"
    static let category = WidgetCategory.experts
    static let displayName = "Mem Stacker"
    static let symbolName = "tray.2"
    static let inputPorts: [PortSpec] = [PortSpec(name: "image", kind: .image), PortSpec(name: "prediction", kind: .prediction)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "prediction", kind: .prediction)]

    private struct Params: Codable {
        /// Generated once, at first creation, and persisted — the stable per-node storage root.
        /// A fresh `UUID()` on every `entry.make()` call would give a saved workflow a *new*
        /// storage folder on every reopen, silently losing prior review progress.
        var storageID = UUID()
        var confidenceThreshold: Double = 0.6
        var marginThreshold: Double = 0.15
        var promotionCount: Int = 20
        var knownLabels: [String] = []
    }
    private var params = Params()
    /// Transient — resets to "Idle" on reload rather than persisting; there's nothing useful to
    /// resume mid-training across a relaunch anyway (a stale in-flight `Task` doesn't survive it).
    var trainingStatus: String = "Idle"

    var confidenceThreshold: Double {
        get { params.confidenceThreshold }
        set { params.confidenceThreshold = newValue }
    }
    var marginThreshold: Double {
        get { params.marginThreshold }
        set { params.marginThreshold = newValue }
    }
    var promotionCount: Int {
        get { params.promotionCount }
        set { params.promotionCount = newValue }
    }
    var knownLabels: [String] { params.knownLabels }

    var summary: String {
        let pending = pendingUnknownItems.count
        return pending == 0 ? "No unknowns pending" : "\(pending) pending review"
    }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .image(let cgImage) = inputs[0], case .prediction(let prediction) = inputs[1] else {
            throw WidgetError.message("Expected an image and a prediction")
        }
        if shouldFlagAsUnknown(prediction) {
            try? fileToUnknown(cgImage)
        }
        return .prediction(prediction)
    }

    func shouldFlagAsUnknown(_ prediction: ExpertPrediction) -> Bool {
        if prediction.isEmpty { return true } // the null/error case — expert ran, produced nothing usable
        guard let confidence = prediction.confidence else { return false } // a regressor's `.value` has no confidence notion to gate on
        if confidence < params.confidenceThreshold { return true }
        if let runnerUp = prediction.runnerUpConfidence, (confidence - runnerUp) < params.marginThreshold { return true }
        return false
    }

    // MARK: Storage

    private var storageRoot: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("MemStacker", isDirectory: true)
            .appendingPathComponent(params.storageID.uuidString, isDirectory: true)
    }
    private var unknownDir: URL { storageRoot.appendingPathComponent("Unknown", isDirectory: true) }
    private var stagingDir: URL { storageRoot.appendingPathComponent("Staging", isDirectory: true) }
    private var trainedDir: URL { storageRoot.appendingPathComponent("TrainedExperts", isDirectory: true) }

    var pendingUnknownItems: [URL] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: unknownDir, includingPropertiesForKeys: nil)) ?? []
        return items.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    var stagingCounts: [(label: String, count: Int)] {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: nil)) ?? []
        return dirs.map { dir in
            (dir.lastPathComponent, (try? fm.contentsOfDirectory(atPath: dir.path).count) ?? 0)
        }.sorted { $0.label < $1.label }
    }

    private func fileToUnknown(_ cgImage: CGImage) throws {
        try FileManager.default.createDirectory(at: unknownDir, withIntermediateDirectories: true)
        let dest = unknownDir.appendingPathComponent("\(UUID().uuidString).png")
        try Self.writePNG(cgImage, to: dest)
    }

    /// Moves `item` from the Unknown queue into `Staging/<label>/` (created if new). If that
    /// label's folder now has at least `promotionCount` images *and* at least one other label is
    /// also staged (`FullyConnectedNetworkClassifier` needs ≥2 classes to mean anything), kicks
    /// off a background retrain over the *whole* staging root — auto-train once N is hit, not
    /// gated on a further human "train now" click. `onChange` (the same closure every widget's
    /// inspector already receives) is called again when training finishes so the UI reflects it.
    func label(item: URL, as label: String, onChange: @escaping () -> Void) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let labelDir = stagingDir.appendingPathComponent(trimmed, isDirectory: true)
        try? FileManager.default.createDirectory(at: labelDir, withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: item, to: labelDir.appendingPathComponent(item.lastPathComponent))
        if !params.knownLabels.contains(trimmed) { params.knownLabels.append(trimmed) }

        let countInThisLabel = (try? FileManager.default.contentsOfDirectory(atPath: labelDir.path).count) ?? 0
        guard countInThisLabel >= params.promotionCount else { return }
        let allLabelDirs = (try? FileManager.default.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: nil)) ?? []
        guard allLabelDirs.count >= 2 else { return }

        trainingStatus = "Training…"
        let trainedDir = self.trainedDir
        let staging = self.stagingDir
        Task {
            do {
                try FileManager.default.createDirectory(at: trainedDir, withIntermediateDirectories: true)
                let outputURL = trainedDir.appendingPathComponent("expert-\(Int(Date().timeIntervalSince1970)).mlmodel")
                let result = try await OnDeviceExpertTrainer.train(labeledRoot: staging, outputURL: outputURL)
                let accuracyPct = String(format: "%.0f%%", (result.trainingAccuracy ?? 0) * 100)
                trainingStatus = "Trained \(result.perClassCounts.count)-class expert (\(accuracyPct) train accuracy) → \(outputURL.lastPathComponent)"
            } catch {
                trainingStatus = "Training failed: \(error)"
            }
            onChange()
        }
    }

    static func loadPreview(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw WidgetError.message("Couldn't create PNG writer for \(url.lastPathComponent)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw WidgetError.message("Couldn't write \(url.lastPathComponent)")
        }
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(MemStackerInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .prediction(let prediction)? = output else { return AnyView(EmptyView()) }
        return AnyView(PredictionPreviewView(prediction: prediction))
    }
}

private struct MemStackerInspectorView: View {
    let widget: MemStackerWidget
    let onChange: () -> Void
    @State private var labelText: String = ""
    @State private var currentIndex: Int = 0

    var body: some View {
        Form {
            Section("Trigger thresholds") {
                Stepper("Confidence below \(widget.confidenceThreshold, specifier: "%.2f")",
                        value: Binding(get: { widget.confidenceThreshold }, set: { widget.confidenceThreshold = $0; onChange() }),
                        in: 0...1, step: 0.05)
                Stepper("Margin below \(widget.marginThreshold, specifier: "%.2f")",
                        value: Binding(get: { widget.marginThreshold }, set: { widget.marginThreshold = $0; onChange() }),
                        in: 0...1, step: 0.05)
                Stepper("Auto-train at \(widget.promotionCount) per label",
                        value: Binding(get: { widget.promotionCount }, set: { widget.promotionCount = $0; onChange() }),
                        in: 2...500)
            }

            unknownSection

            let staging = widget.stagingCounts
            if !staging.isEmpty {
                Section("Staging") {
                    ForEach(staging, id: \.label) { entry in
                        LabeledContent(entry.label, value: "\(entry.count) / \(widget.promotionCount)")
                    }
                }
            }

            Section("Training") {
                Text(widget.trainingStatus).font(.callout)
            }
        }
    }

    @ViewBuilder
    private var unknownSection: some View {
        let pending = widget.pendingUnknownItems
        Section("Unknown (\(pending.count) pending)") {
            if pending.isEmpty {
                Text("Nothing pending review.").foregroundStyle(.secondary)
            } else {
                let index = min(currentIndex, pending.count - 1)
                let item = pending[index]
                if let cgImage = MemStackerWidget.loadPreview(item) {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                }
                TextField("Label", text: $labelText)
                HStack {
                    Button("Label & File") {
                        widget.label(item: item, as: labelText, onChange: onChange)
                        labelText = ""
                        currentIndex = 0
                        onChange()
                    }
                    .disabled(labelText.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Skip") {
                        currentIndex = pending.count > 1 ? (index + 1) % pending.count : 0
                    }
                }
                if !widget.knownLabels.isEmpty {
                    Text("Known labels: \(widget.knownLabels.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
