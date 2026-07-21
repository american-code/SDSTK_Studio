import Foundation
import SwiftUI
import DataScience
import Text

/// TF-IDF cosine-similarity matrix between the rows of a text column — Orange only gets this
/// via a separate Text Mining add-on; here it's a native category (see PLAN.md §2).
final class TextSimilarityWidget: StudioWidget {
    static let typeID = "Text.Similarity"
    static let category = WidgetCategory.text
    static let displayName = "Text Similarity"
    static let symbolName = "doc.text.magnifyingglass"
    static let inputPorts: [PortSpec] = [PortSpec(name: "table", kind: .table)]
    static let outputPorts: [PortSpec] = [PortSpec(name: "chart", kind: .chart)]

    private struct Params: Codable { var textColumn: String = ""; var labelColumn: String = "" }
    private var params = Params()
    private(set) var availableColumns: [String] = []

    var textColumn: String {
        get { params.textColumn }
        set { params.textColumn = newValue }
    }
    var labelColumn: String {
        get { params.labelColumn }
        set { params.labelColumn = newValue }
    }

    var summary: String { params.textColumn.isEmpty ? "Select a text column" : "similarity over \(params.textColumn)" }

    func encodeParams() throws -> Data { try JSONEncoder().encode(params) }
    func applyParams(from data: Data) throws { params = try JSONDecoder().decode(Params.self, from: data) }

    func run(inputs: [PortValue]) async throws -> PortValue {
        guard case .table(let df) = inputs[0] else { throw WidgetError.message("Expected a table") }
        availableColumns = df.columnOrder
        guard !params.textColumn.isEmpty else { throw WidgetError.message("Select a text column") }
        let docs = df[params.textColumn].stringValues()
        guard docs.count >= 2 else { throw WidgetError.message("Need at least 2 rows") }
        let cappedDocs = Array(docs.prefix(30)) // heatmap readability guard, not a silent data cap on the pipeline output
        let labels = params.labelColumn.isEmpty
            ? (0..<cappedDocs.count).map { "#\($0)" }
            : Array(df[params.labelColumn].stringValues().prefix(cappedDocs.count))

        var vectorizer = TFIDFVectorizer()
        let vectors = vectorizer.fitTransform(cappedDocs, stopWords: StopWords.english)
        let sim = similarityMatrix(vectors)
        return .chart(.heatmap(rowLabels: labels, colLabels: labels, values: sim, title: "Text similarity"))
    }

    func makeInspector(onChange: @escaping () -> Void) -> AnyView {
        AnyView(TextSimilarityInspectorView(widget: self, onChange: onChange))
    }

    func makePreview(output: PortValue?) -> AnyView {
        guard case .chart(let data)? = output else { return AnyView(EmptyView()) }
        return AnyView(ChartView(data: data))
    }
}

private struct TextSimilarityInspectorView: View {
    let widget: TextSimilarityWidget
    let onChange: () -> Void

    var body: some View {
        Form {
            if widget.availableColumns.isEmpty {
                Text("Connect a table first.").foregroundStyle(.secondary)
            } else {
                Picker("Text column", selection: Binding(get: { widget.textColumn }, set: { widget.textColumn = $0; onChange() })) {
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                Picker("Label column (optional)", selection: Binding(get: { widget.labelColumn }, set: { widget.labelColumn = $0; onChange() })) {
                    Text("Row index").tag("")
                    ForEach(widget.availableColumns, id: \.self) { Text($0).tag($0) }
                }
                Text("Capped at 30 rows for heatmap readability.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
