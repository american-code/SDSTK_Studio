import Foundation
import SwiftUI
import DataScience

/// Loads the classic Iris dataset bundled with the app — a one-tap starting point for trying
/// the canvas without hunting for a CSV first. Unlike `CSVFileWidget`, this reads straight from
/// the app bundle (no file picker, no security-scoped bookmark — it isn't user-selected data).
/// Includes both a string `species` column (for labeling charts) and an integer `species_id`
/// column (for `Model`/`Evaluate` widgets, which need a numeric target).
final class IrisExampleWidget: StudioWidget {
    static let typeID = "Data.IrisExample"
    static let category = WidgetCategory.data
    static let displayName = "Iris Example"
    static let symbolName = "leaf"
    static let inputPorts: [PortSpec] = []
    static let outputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]

    private struct Params: Codable {}
    private var params = Params()

    var summary: String { "150 rows · 4 features · 3 species" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard let url = Bundle.main.url(forResource: "iris", withExtension: "csv", subdirectory: "Examples") ?? Bundle.main.url(forResource: "iris", withExtension: "csv") else {
            throw WidgetError.message("Bundled iris.csv not found")
        }
        return .table(try DataFrame.readCSV(path: url.path))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(Text("The classic Fisher/Anderson Iris dataset: 150 flowers, 3 species, "
                     + "4 measurements each. Wire straight into a Scatter Plot or a Model widget.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding())
    }
}
