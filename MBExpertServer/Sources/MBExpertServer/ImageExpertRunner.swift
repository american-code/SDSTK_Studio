import Foundation
import CoreML
import Vision
import ImageIO

/// Runs a Core ML image classifier/regressor via Vision — a deliberately small, standalone
/// reimplementation of `CoreMLExpertWidget.run()`'s inference logic (not shared code; the app
/// isn't structured as a library, so a few duplicated lines here is the lower-risk choice over
/// restructuring the shipping app to share this one method).
enum ImageExpertRunner {
    struct Result {
        var label: String?
        var confidence: Double?
        var value: Double?
    }

    enum RunError: Error, CustomStringConvertible {
        case imageNotFound(String)
        case undecodableImage(String)
        case noUsableOutput

        var description: String {
            switch self {
            case .imageNotFound(let path): "Image not found at \(path)"
            case .undecodableImage(let path): "Couldn't decode '\(path)' as an image"
            case .noUsableOutput: "Model produced no usable output"
            }
        }
    }

    static func run(modelURL: URL, imagePath: String) throws -> Result {
        let fm = FileManager.default
        guard fm.fileExists(atPath: imagePath) else { throw RunError.imageNotFound(imagePath) }
        let imageURL = URL(fileURLWithPath: imagePath)
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RunError.undecodableImage(imagePath)
        }

        let compiledURL = modelURL.pathExtension == "mlmodelc" ? modelURL : try MLModel.compileModel(at: modelURL)
        let mlModel = try MLModel(contentsOf: compiledURL)
        let visionModel = try VNCoreMLModel(for: mlModel)

        let request = VNCoreMLRequest(model: visionModel)
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        if let classifications = request.results as? [VNClassificationObservation], let top = classifications.first {
            return Result(label: top.identifier, confidence: Double(top.confidence))
        }
        if let features = request.results as? [VNCoreMLFeatureValueObservation], let top = features.first {
            return Result(value: top.featureValue.doubleValue)
        }
        throw RunError.noUsableOutput
    }
}
