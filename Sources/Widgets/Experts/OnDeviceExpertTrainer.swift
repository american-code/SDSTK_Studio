import Foundation
import CreateMLComponents
import CoreImage

/// Trains a compact on-device image classifier from a labeled folder (one subfolder per class)
/// via `CreateMLComponents` — works on iPad and Mac, unlike `CreateML` proper (macOS-only). This
/// is a standalone reimplementation of the same pattern ModelBuilder's own `OnDeviceTrainer`
/// uses, not a shared dependency: SDSTK Studio and ModelBuilder are separate Xcode projects with
/// no package relationship, so duplicating this one well-understood, already-proven piece of
/// logic is the lower-risk choice over inventing a cross-project dependency for it.
///
/// `Experts.MemStacker` is the caller: once a staging label folder crosses its promotion
/// threshold, it retrains over the *entire* staging root (every label folder, not just the one
/// that just crossed the threshold) — `FullyConnectedNetworkClassifier` needs at least two
/// classes to mean anything, so the promotion trigger and the training scope are necessarily
/// different things.
enum OnDeviceExpertTrainer {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "bmp", "gif"]

    struct Result: Sendable {
        var modelURL: URL
        var perClassCounts: [String: Int]
        var trainingAccuracy: Double?
    }

    enum TrainingError: LocalizedError {
        case needTwoClasses
        case noImages

        var errorDescription: String? {
            switch self {
            case .needTwoClasses: "Need at least two labeled subfolders (one per class) to train."
            case .noImages: "No readable images were found under the staging folder."
            }
        }
    }

    static func train(labeledRoot: URL, outputURL: URL) async throws -> Result {
        let fm = FileManager.default
        let subdirs = try fm.contentsOfDirectory(at: labeledRoot, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

        var annotated: [AnnotatedFeature<CIImage, String>] = []
        var counts: [String: Int] = [:]
        for dir in subdirs {
            let label = dir.lastPathComponent
            let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            for file in files {
                if let image = try? ImageReader.read(url: file) {
                    annotated.append(AnnotatedFeature(feature: image, annotation: label))
                    counts[label, default: 0] += 1
                }
            }
        }

        guard counts.count >= 2 else { throw TrainingError.needTwoClasses }
        guard !annotated.isEmpty else { throw TrainingError.noImages }

        let estimator = ImageFeaturePrint()
            .appending(FullyConnectedNetworkClassifier<Float, String>(labels: Set(counts.keys)))
        let transformer = try await estimator.fitted(to: annotated)

        var correct = 0
        for sample in annotated {
            let distribution = try await transformer.applied(to: sample.feature)
            if distribution.mostLikelyLabel == sample.annotation { correct += 1 }
        }
        let accuracy = Double(correct) / Double(annotated.count)

        try transformer.export(to: outputURL)
        return Result(modelURL: outputURL, perClassCounts: counts, trainingAccuracy: accuracy)
    }
}
