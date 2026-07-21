import Foundation
import SwiftUI
import DataScience

/// Terminal widget (zero output ports, like `Graph.ShortestPath`): writes the incoming table to
/// a temp CSV and offers it via `ShareLink` (Save to Files, AirDrop, etc.) — Orange's Save Data
/// widget. Doesn't need its own file-picker plumbing since `ShareLink`'s system sheet already
/// covers "save to a location," including choosing outside the sandbox.
final class SaveDataWidget: StudioWidget {
    static let typeID = "Data.SaveData"
    static let category = WidgetCategory.data
    static let displayName = "Save Data"
    static let symbolName = "square.and.arrow.down"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = []

    private struct Params: Codable { var fileName: String = "export" }
    private var params = Params()
    private(set) var rowCount = 0
    private(set) var exportURL: URL?

    var fileName: String {
        get { params.fileName }
        set { params.fileName = newValue }
    }

    var summary: String { rowCount > 0 ? "\(rowCount) rows ready to export" : "No data yet" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        rowCount = df.rowCount
        let safeName = params.fileName.isEmpty ? "export" : params.fileName
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName).appendingPathExtension("csv")
        try df.writeCSV(to: url.path)
        exportURL = url
        return .none
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(SaveDataInspectorView(widget: self, onChange: onChange))
    }
}

private struct SaveDataInspectorView: View {
    let widget: SaveDataWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            TextField("File name", text: Binding(get: { widget.fileName }, set: { widget.fileName = $0; onChange() }))
            if let url = widget.exportURL {
                ShareLink(item: url) {
                    Label("Export \(widget.rowCount) rows as CSV", systemImage: "square.and.arrow.up")
                }
            } else {
                Text("Connect a table first.").foregroundStyle(.secondary)
            }
        }
    }
}
