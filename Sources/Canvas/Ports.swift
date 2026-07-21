import Foundation
import SwiftUI
import CoreGraphics
import DataScience

/// The category a widget appears under in the palette — mirrors Orange's own tab layout, plus
/// categories Orange has no native equivalent for (see PLAN.md §2).
enum WidgetCategory: String, CaseIterable {
    case data = "Data"
    case visualize = "Visualize"
    case model = "Model"
    case evaluate = "Evaluate"
    case unsupervised = "Unsupervised"
    case signal = "Signal"
    case text = "Text"
    case timeSeries = "Time Series"
    case optimize = "Optimize"
    case formulas = "Formulas"
    case graph = "Graph"
    case experts = "Experts"

    /// One accent color per category, shown on the node icon badge and palette — mirrors
    /// Orange's own color-coded tabs, since that's a big part of what makes its canvas scannable
    /// at a glance instead of a wall of identical gray boxes.
    var color: Color {
        switch self {
        case .data: return Color(red: 0.80, green: 0.62, blue: 0.07)
        case .visualize: return .pink
        case .model: return .green
        case .evaluate: return .orange
        case .unsupervised: return .purple
        case .signal: return .teal
        case .text: return .indigo
        case .timeSeries: return .mint
        case .optimize: return .brown
        case .formulas: return .cyan
        case .graph: return .blue
        case .experts: return .red
        }
    }
}

/// The type of value carried by one input or output port.
enum PortKind: String {
    case table
    case classifierLearner
    case regressorLearner
    case scores
    case chart
    case image
    case prediction
    case text
}

/// A named, typed port on a widget (declared statically per widget type).
struct PortSpec {
    let name: String
    let kind: PortKind
}

/// A value flowing across one link on the canvas. Concrete widgets pattern-match the cases
/// they declared in their `inputPorts`/`outputPorts`.
enum PortValue {
    case table(DataFrame)
    case classifierLearner(ClassifierSpec)
    case regressorLearner(RegressorSpec)
    case scores(CVResult)
    case chart(ChartData)
    case image(CGImage)
    case prediction(ExpertPrediction)
    case text(String)
    /// A multi-output node's results, keyed by output-port name. `WorkflowGraph.gatherInputs`
    /// unwraps this per-link (picking `dict[link.fromPort]`), so downstream widgets never see
    /// the wrapper — they receive the same plain `PortValue` they always did. Single-output
    /// widgets keep returning bare values; nothing about them changed. Added for interactive
    /// selection propagation (`Visualize.ScatterPlot`'s "chart" + "selected" outputs — Orange's
    /// Data/Selected Data pattern).
    case outputs([String: PortValue])
    /// Placeholder for widgets that declare zero output ports (display-only "sink" widgets like
    /// `Graph.ShortestPath`) — never actually consumed by a downstream link.
    case none
}

/// One Core ML expert's output. Scoped to exactly what ModelBuilder's two working on-device
/// trainers produce today — an image classifier's top label + confidence, or a tabular
/// regressor's scalar value — not a speculative generic schema. Add a field only once a third
/// expert shape (e.g. a text classifier) actually needs one.
struct ExpertPrediction {
    var label: String?
    var confidence: Double?
    var value: Double?
    /// The runner-up classification's confidence, when the expert is a classifier and had a
    /// second candidate. Margin (`confidence - runnerUpConfidence`) is a stronger uncertainty
    /// signal than raw confidence alone — a model can be genuinely confident and still wrong,
    /// but a thin margin over the runner-up reliably flags an ambiguous case. Used by
    /// `Experts.MemStacker`; `nil` when there was no second candidate (or the expert is a
    /// regressor, which has no "runner-up" concept at all).
    var runnerUpConfidence: Double?
    /// Which upstream expert produced this — threaded through so a `Coordinator` can label its
    /// combined result and the node face can show something more useful than a bare number.
    var sourceName: String = ""
    /// `true` when the expert ran successfully but produced no usable classification/value (e.g.
    /// Vision returned zero observations) — distinguished from a thrown error specifically so
    /// this flows downstream as *data* a `Coordinator`/`MemStacker` can react to, rather than
    /// halting the graph the way a genuine failure (bad model file, undecodable image) should.
    var isEmpty: Bool { label == nil && value == nil }
}

/// An unfitted classifier + its hyperparameters. `Evaluate.TestAndScore` constructs and fits the
/// concrete model itself so `crossValScore`'s generic signature stays fully typed — no
/// existential `any Classifier` opening required. Add a case per new classifier widget.
enum ClassifierSpec {
    case logisticRegression(iterations: Int, fitIntercept: Bool)
    case decisionTree(maxDepth: Int)
    case randomForest(numTrees: Int, maxDepth: Int)
}

/// An unfitted regressor + its hyperparameters — the regression-side counterpart to
/// `ClassifierSpec`. Add a case per new regressor widget.
enum RegressorSpec {
    case linearRegression(l2: Double)
    case decisionTree(maxDepth: Int)
    case randomForest(numTrees: Int, maxDepth: Int)
    case gradientBoosting(numTrees: Int, learningRate: Double, maxDepth: Int)
}

/// The result of a cross-validated evaluation run.
struct CVResult {
    let foldScores: [Double]
    let metricName: String

    var mean: Double { foldScores.isEmpty ? 0 : foldScores.reduce(0, +) / Double(foldScores.count) }
    var std: Double {
        guard foldScores.count > 1 else { return 0 }
        let m = mean
        let variance = foldScores.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(foldScores.count - 1)
        return variance.squareRoot()
    }
}

/// Chart data native to Swift Charts — the live on-canvas renderer. SDSTK's `Plot` (headless
/// SVG) is reserved for export/report, not this path (see `PLAN.md` §3, "Visualization strategy").
/// One case per chart shape a `Visualize` widget produces.
enum ChartData {
    struct Point: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
    }
    struct BoxStats: Identifiable {
        let id = UUID()
        let category: String
        let min: Double
        let q1: Double
        let median: Double
        let q3: Double
        let max: Double
    }

    case points(points: [Point], xLabel: String, yLabel: String, title: String)
    case bars(categories: [String], values: [Double], xLabel: String, yLabel: String, title: String)
    case heatmap(rowLabels: [String], colLabels: [String], values: [[Double]], title: String)
    case box(stats: [BoxStats], yLabel: String, title: String)

    var title: String {
        switch self {
        case .points(_, _, _, let t), .bars(_, _, _, _, let t), .heatmap(_, _, _, let t), .box(_, _, let t):
            return t
        }
    }
}
