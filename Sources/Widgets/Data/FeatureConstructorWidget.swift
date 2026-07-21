import Foundation
import SwiftUI
import DataScience

/// Appends a new numeric column computed as `columnA <op> (columnB | constant)` — Orange's
/// Feature Constructor, scoped to simple two-operand arithmetic rather than a full formula
/// language (SDSTK's `Column` already overloads `+ - * /` for column-column and column-scalar,
/// so this widget is a thin UI over that, not a new evaluator).
final class FeatureConstructorWidget: StudioWidget {
    static let typeID = "Data.FeatureConstructor"
    static let category = WidgetCategory.data
    static let displayName = "Feature Constructor"
    static let symbolName = "plusminus.circle"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    enum Operator: String, Codable, CaseIterable { case add = "+", subtract = "−", multiply = "×", divide = "÷" }
    enum OperandMode: String, Codable, CaseIterable { case column = "Column", constant = "Constant" }

    private struct Params: Codable {
        var newColumnName: String = "new_feature"
        var columnA: String = ""
        var op: Operator = .add
        var mode: OperandMode = .constant
        var columnB: String = ""
        var constant: Double = 1
    }
    private var params = Params()
    private(set) var availableColumns: [String] = []

    var newColumnName: String { get { params.newColumnName } set { params.newColumnName = newValue } }
    var columnA: String { get { params.columnA } set { params.columnA = newValue } }
    var op: Operator { get { params.op } set { params.op = newValue } }
    var mode: OperandMode { get { params.mode } set { params.mode = newValue } }
    var columnB: String { get { params.columnB } set { params.columnB = newValue } }
    var constant: Double { get { params.constant } set { params.constant = newValue } }

    var summary: String {
        guard !params.columnA.isEmpty else { return "Select a column" }
        let rhs = params.mode == .column ? (params.columnB.isEmpty ? "?" : params.columnB) : String(format: "%.3g", params.constant)
        return "\(params.newColumnName) = \(params.columnA) \(params.op.rawValue) \(rhs)"
    }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder.filter { df[$0].dtype.isNumeric }
        guard !params.columnA.isEmpty, availableColumns.contains(params.columnA) else {
            throw WidgetError.message("Select column A")
        }
        let name = params.newColumnName.isEmpty ? "new_feature" : params.newColumnName
        let a = df[params.columnA]

        let result: Column
        switch params.mode {
        case .constant:
            switch params.op {
            case .add: result = a + params.constant
            case .subtract: result = a - params.constant
            case .multiply: result = a * params.constant
            case .divide: result = a / params.constant
            }
        case .column:
            guard !params.columnB.isEmpty, availableColumns.contains(params.columnB) else {
                throw WidgetError.message("Select column B")
            }
            let b = df[params.columnB]
            switch params.op {
            case .add: result = a + b
            case .subtract: result = a - b
            case .multiply: result = a * b
            case .divide: result = a / b
            }
        }
        return .table(df.withColumn(name, result))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(FeatureConstructorInspectorView(widget: self, onChange: onChange))
    }
}

private struct FeatureConstructorInspectorView: View {
    let widget: FeatureConstructorWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table with numeric columns first.").foregroundStyle(.secondary)
            } else {
                TextField("New column name", text: Binding(get: { widget.newColumnName }, set: { widget.newColumnName = $0; onChange() }))
                Picker("A", selection: Binding(get: { widget.columnA }, set: { widget.columnA = $0; onChange() })) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                Picker("Operator", selection: Binding(get: { widget.op }, set: { widget.op = $0; onChange() })) {
                    ForEach(FeatureConstructorWidget.Operator.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("B is a", selection: Binding(get: { widget.mode }, set: { widget.mode = $0; onChange() })) {
                    ForEach(FeatureConstructorWidget.OperandMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                if widget.mode == .column {
                    Picker("B", selection: Binding(get: { widget.columnB }, set: { widget.columnB = $0; onChange() })) {
                        ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                    }
                } else {
                    TextField("Constant", value: Binding(get: { widget.constant }, set: { widget.constant = $0; onChange() }), format: .number)
                }
            }
        }
    }
}
