import Foundation
import SwiftUI
import DataScience
import Optimize

/// Fits a chosen closed-form model to (x, y) data via SDSTK's Levenberg-Marquardt `curveFit` —
/// a category Orange has no equivalent for outside ad-hoc scripting (see PLAN.md §2).
final class CurveFitWidget: StudioWidget {
    static let typeID = "Optimize.CurveFit"
    static let category = WidgetCategory.optimize
    static let displayName = "Curve Fit"
    static let symbolName = "function"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "chart", kind: .chart)]

    enum Form: String, Codable, CaseIterable {
        case linear = "Linear (a·x + b)"
        case quadratic = "Quadratic (a·x² + b·x + c)"
        case exponential = "Exponential (a·eᵇˣ)"

        var initialGuess: [Double] {
            switch self {
            case .linear: return [1, 0]
            case .quadratic: return [1, 1, 0]
            case .exponential: return [1, 0.1]
            }
        }
        func evaluate(_ p: [Double], _ x: Double) -> Double {
            switch self {
            case .linear: return p[0] * x + p[1]
            case .quadratic: return p[0] * x * x + p[1] * x + p[2]
            case .exponential: return p[0] * exp(p[1] * x)
            }
        }
    }

    private struct Params: Codable { var xColumn: String = ""; var yColumn: String = ""; var form: Form = .linear }
    private var params = Params()
    private(set) var availableColumns: [String] = []
    private(set) var fitSummary: String = ""

    var xColumn: String {
        get { params.xColumn }
        set { params.xColumn = newValue }
    }
    var yColumn: String {
        get { params.yColumn }
        set { params.yColumn = newValue }
    }
    var form: Form {
        get { params.form }
        set { params.form = newValue }
    }

    var summary: String {
        params.xColumn.isEmpty || params.yColumn.isEmpty ? "Select X/Y columns" : fitSummary.isEmpty ? params.form.rawValue : fitSummary
    }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder
        guard !params.xColumn.isEmpty, !params.yColumn.isEmpty else { throw WidgetError.message("Select X and Y columns") }

        let pairs = zip(df.vector(params.xColumn), df.vector(params.yColumn)).filter { $0.0.isFinite && $0.1.isFinite }
        guard pairs.count >= params.form.initialGuess.count + 1 else {
            throw WidgetError.message("Need more data points than model parameters")
        }
        let xs = pairs.map(\.0), ys = pairs.map(\.1)
        let form = params.form

        let result = curveFit(model: form.evaluate, xData: xs, yData: ys, p0: form.initialGuess)
        let predicted = xs.map { form.evaluate(result.x, $0) }
        let meanY = ys.reduce(0, +) / Double(ys.count)
        let ssRes = zip(ys, predicted).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
        let ssTot = ys.reduce(0) { $0 + ($1 - meanY) * ($1 - meanY) }
        let r2 = ssTot > 0 ? 1 - ssRes / ssTot : 1
        let coeffs = result.x.map { String(format: "%.4g", $0) }.joined(separator: ", ")
        fitSummary = "[\(coeffs)], R²=\(String(format: "%.3f", r2))"

        let points = zip(xs, ys).map { ChartData.Point(x: $0, y: $1) }
        return .chart(.points(points: points, xLabel: params.xColumn, yLabel: params.yColumn,
                               title: "\(form.rawValue): \(fitSummary)"))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(CurveFitInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .chart(let data)? = output else { return AnyView(EmptyView()) }
        return AnyView(VStack(alignment: .leading, spacing: 2) {
            ChartView(data: data)
            Text(fitSummary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        })
    }
}

private struct CurveFitInspectorView: View {
    let widget: CurveFitWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table first.").foregroundStyle(.secondary)
            } else {
                Picker("X", selection: Binding(get: { widget.xColumn }, set: { widget.xColumn = $0; onChange() })) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                Picker("Y", selection: Binding(get: { widget.yColumn }, set: { widget.yColumn = $0; onChange() })) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                Picker("Model", selection: Binding(get: { widget.form }, set: { widget.form = $0; onChange() })) {
                    ForEach(CurveFitWidget.Form.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
        }
    }
}
