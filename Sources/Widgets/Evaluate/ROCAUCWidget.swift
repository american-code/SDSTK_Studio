import Foundation
import SwiftUI
import DataScience

/// Computes the ROC curve and AUC from a table with a binary-label column and a score column.
/// Equivalent to Orange's "ROC Analysis" widget applied to already-predicted probabilities.
/// Use this after a Model widget that outputs predicted scores (e.g. LogisticRegression probabilities).
final class ROCAUCWidget: StudioWidget {
    static let typeID     = "Evaluate.ROCAUC"
    static let category   = WidgetCategory.evaluate
    static let displayName = "ROC / AUC"
    static let symbolName  = "waveform.path.ecg"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "scores", kind: .scores)]

    private struct Params: Codable {
        var labelColumn: String = ""
        var scoreColumn: String = ""
        var positiveClass: Int  = 1
    }
    private var params = Params()
    private(set) var availableColumns: [String] = []

    var labelColumn: String { get { params.labelColumn } set { params.labelColumn = newValue } }
    var scoreColumn: String { get { params.scoreColumn } set { params.scoreColumn = newValue } }
    var positiveClass: Int  { get { params.positiveClass } set { params.positiveClass = newValue } }

    var summary: String {
        guard !params.labelColumn.isEmpty, !params.scoreColumn.isEmpty else {
            return "Select label + score columns"
        }
        return "AUC of \(params.scoreColumn) → \(params.labelColumn)"
    }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder
        guard !params.labelColumn.isEmpty, !params.scoreColumn.isEmpty else {
            throw WidgetError.message("Select a label column and a score column")
        }
        guard availableColumns.contains(params.labelColumn) else {
            throw WidgetError.message("Column '\(params.labelColumn)' not found")
        }
        guard availableColumns.contains(params.scoreColumn) else {
            throw WidgetError.message("Column '\(params.scoreColumn)' not found")
        }

        let rawLabels = df.vector(params.labelColumn)
        let rawScores = df.vector(params.scoreColumn)
        guard rawLabels.count == rawScores.count, rawLabels.count >= 2 else {
            throw WidgetError.message("Need ≥ 2 rows")
        }

        let labels = rawLabels.map { Int($0) }
        let scores = rawScores
        let positives = labels.filter { $0 == params.positiveClass }.count
        let negatives  = labels.count - positives
        guard positives > 0 else { throw WidgetError.message("No positive-class rows found") }
        guard negatives > 0 else { throw WidgetError.message("No negative-class rows found") }

        let auc = computeAUC(scores: scores, labels: labels, positiveClass: params.positiveClass)
        return .scores(CVResult(foldScores: [auc], metricName: "ROC-AUC"))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(ROCAUCInspectorView(widget: self, onChange: onChange))
    }
}

/// Computes AUC via the trapezoid rule over the empirical ROC curve.
private func computeAUC(scores: [Double], labels: [Int], positiveClass: Int) -> Double {
    let paired = zip(scores, labels).sorted { $0.0 > $1.0 }
    let P = Double(labels.filter { $0 == positiveClass }.count)
    let N = Double(labels.count) - P
    var tp = 0.0, fp = 0.0
    var prevFPR = 0.0, prevTPR = 0.0
    var auc = 0.0
    for (_, label) in paired {
        if label == positiveClass { tp += 1 } else { fp += 1 }
        let fpr = fp / N, tpr = tp / P
        auc += (fpr - prevFPR) * (tpr + prevTPR) / 2
        prevFPR = fpr; prevTPR = tpr
    }
    return auc
}

private struct ROCAUCInspectorView: View {
    let widget: ROCAUCWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table with label and score columns.").foregroundStyle(.secondary)
            } else {
                Picker("Label column", selection: Binding(
                    get: { widget.labelColumn },
                    set: { widget.labelColumn = $0; onChange() }
                )) {
                    Text("—").tag("")
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                Picker("Score column", selection: Binding(
                    get: { widget.scoreColumn },
                    set: { widget.scoreColumn = $0; onChange() }
                )) {
                    Text("—").tag("")
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                Stepper("Positive class = \(widget.positiveClass)",
                        value: Binding(get: { widget.positiveClass }, set: { widget.positiveClass = $0; onChange() }),
                        in: 0...9)
            }
        }
    }
}
