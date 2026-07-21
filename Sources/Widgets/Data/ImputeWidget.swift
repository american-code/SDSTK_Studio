import Foundation
import SwiftUI
import DataScience

/// Handles missing values — either drops rows with any null, or fills numeric nulls with that
/// column's mean (string/bool columns pass through unchanged in fill mode; mean-filling doesn't
/// apply to them).
final class ImputeWidget: StudioWidget {
    static let typeID = "Data.Impute"
    static let category = WidgetCategory.data
    static let displayName = "Impute"
    static let symbolName = "square.and.pencil"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    enum Strategy: String, Codable, CaseIterable {
        case dropRows = "Drop rows with nulls"
        case fillMean = "Fill numeric nulls with mean"
    }

    private struct Params: Codable { var strategy: Strategy = .dropRows }
    private var params = Params()

    var strategy: Strategy {
        get { params.strategy }
        set { params.strategy = newValue }
    }

    var summary: String { params.strategy.rawValue }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(var df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        switch params.strategy {
        case .dropRows:
            var keep = [Int]()
            keep.reserveCapacity(df.rowCount)
            rowLoop: for r in 0..<df.rowCount {
                for name in df.columnOrder where df[name].isNullAt(r) { continue rowLoop }
                keep.append(r)
            }
            df = df.take(keep)
        case .fillMean:
            for name in df.columnOrder {
                let column = df[name]
                guard column.dtype.isNumeric, column.nullCount > 0, let values = column.asDoubles(dropNulls: false) else { continue }
                let mean = column.mean() ?? 0
                df = df.withColumn(name, Column(values.map { $0.isNaN ? mean : $0 }))
            }
        }
        return .table(df)
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(ImputeInspectorView(widget: self, onChange: onChange))
    }
}

private struct ImputeInspectorView: View {
    let widget: ImputeWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            Picker("Strategy", selection: Binding(get: { widget.strategy }, set: { widget.strategy = $0; onChange() })) {
                ForEach(ImputeWidget.Strategy.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
        }
    }
}
